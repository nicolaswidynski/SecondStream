//
//  PodcastSourcesManager.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-22.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import os.log

struct PodcastSource: Codable, Hashable {
	let name: String
	let author: String?
	let url: String
	let imageURL: String?

	private enum CodingKeys: String, CodingKey {
		case name
		case author
		case url
		case imageURL
		case legacyRSSURL = "rssURL"
	}

	init(name: String, author: String?, url: String, imageURL: String?) {
		self.name = name
		self.author = author
		self.url = url
		self.imageURL = imageURL
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		name = try container.decode(String.self, forKey: .name)
		author = try container.decodeIfPresent(String.self, forKey: .author)
		url = try container.decodeIfPresent(String.self, forKey: .url)
			?? container.decode(String.self, forKey: .legacyRSSURL)
		imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(name, forKey: .name)
		try container.encodeIfPresent(author, forKey: .author)
		try container.encode(url, forKey: .url)
		try container.encodeIfPresent(imageURL, forKey: .imageURL)
	}
}

enum AddPodcastResult {
	case successExisting(summaryURL: String)  // 201 - Podcast already exists, no wait
	case successNew(summaryURL: String)       // 202 - New podcast, wait ~15 minutes
	case failure(message: String)             // Any error - uses server message
}

@MainActor final class PodcastSourcesManager {

	static let shared = PodcastSourcesManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PodcastSources")

	private let addSourceURL = URL(string: "https://n8n.nwidynski.com/webhook/add-show-source")!

	private static let topFileName = "pod_free.json"
	private static let libraryFileName = "pod_featured.json"

	// MARK: - Server Error

	private(set) var lastServerMessage: String?

	// MARK: - Fetch State

	private(set) var isFetching = false
	private var fetchTask: Task<Void, Never>?

	// MARK: - Stored Podcast Sources

	private let podcastTopSourcesKey = "podcastTopSources"
	private let podcastLibrarySourcesKey = "podcastLibrarySources"

	/// Top Picks sources, used by pickers.
	var podcastSources: [PodcastSource] {
		get {
			guard let data = UserDefaults.standard.data(forKey: podcastTopSourcesKey),
				  let sources = try? JSONDecoder().decode([PodcastSource].self, from: data) else {
				return []
			}
			return sources
		}
		set {
			if let data = try? JSONEncoder().encode(newValue) {
				UserDefaults.standard.set(data, forKey: podcastTopSourcesKey)
			}
		}
	}

	/// Library (non-Top Picks) sources.
	var podcastLibrarySources: [PodcastSource] {
		get {
			guard let data = UserDefaults.standard.data(forKey: podcastLibrarySourcesKey),
				  let sources = try? JSONDecoder().decode([PodcastSource].self, from: data) else {
				return []
			}
			return sources
		}
		set {
			if let data = try? JSONEncoder().encode(newValue) {
				UserDefaults.standard.set(data, forKey: podcastLibrarySourcesKey)
			}
		}
	}

	// MARK: - Token

	private var bearerToken: String? {
		guard let tokenURL = Bundle.main.url(forResource: "podcast_token", withExtension: "txt"),
			  let token = try? String(contentsOf: tokenURL, encoding: .utf8) else {
			Self.logger.error("Failed to load podcast token from file")
			return nil
		}
		return token.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: - API

	/// Starts fetching podcast sources in the background. Does nothing if already fetching.
	func startFetching() {
		guard !isFetching else {
			return
		}
		fetchTask = Task {
			await fetchPodcastSources()
		}
	}

	/// Waits for any in-progress fetch to complete, or fetches if not already fetching.
	func waitForFetch() async {
		if let task = fetchTask {
			await task.value
		} else if !isFetching {
			await fetchPodcastSources()
		}
	}

	/// Always fetches fresh sources, regardless of current state.
	func fetchFresh() async {
		// Cancel any existing fetch task
		fetchTask?.cancel()
		fetchTask = nil
		// Fetch fresh
		await fetchPodcastSources()
	}

	private func fetchPodcastSources() async {
		isFetching = true
		defer {
			isFetching = false
			fetchTask = nil
		}

		async let topEntries = SourceFileFetcher.fetchIfModified(fileName: Self.topFileName)
		async let libraryEntries = SourceFileFetcher.fetchIfModified(fileName: Self.libraryFileName)

		if let entries = await topEntries {
			let sources = entries.map { PodcastSource(name: $0.name, author: $0.author, url: $0.feedURL, imageURL: $0.imageURL) }
			let oldURLs = Set(self.podcastSources.compactMap(\.imageURL))
			let newURLs = Set(sources.compactMap(\.imageURL))
			let libraryURLs = Set(self.podcastLibrarySources.compactMap(\.imageURL))
			let removed = Array(oldURLs.subtracting(newURLs).subtracting(libraryURLs))
			let added = Array(newURLs.subtracting(oldURLs))
			SourceImageCache.shared.removeImages(for: removed)
			SourceImageCache.shared.prefetchImages(for: added)
			self.podcastSources = sources
			Self.logger.info("Fetched \(sources.count) top podcast sources")
		}

		if let entries = await libraryEntries {
			let sources = entries.map { PodcastSource(name: $0.name, author: $0.author, url: $0.feedURL, imageURL: $0.imageURL) }
			let oldURLs = Set(self.podcastLibrarySources.compactMap(\.imageURL))
			let newURLs = Set(sources.compactMap(\.imageURL))
			let topURLs = Set(self.podcastSources.compactMap(\.imageURL))
			let removed = Array(oldURLs.subtracting(newURLs).subtracting(topURLs))
			let added = Array(newURLs.subtracting(oldURLs))
			SourceImageCache.shared.removeImages(for: removed)
			SourceImageCache.shared.prefetchImages(for: added)
			self.podcastLibrarySources = sources
			Self.logger.info("Fetched \(sources.count) library podcast sources")
		}
	}

	/// Adds a podcast source by sending the podcast name and author to the webhook.
	/// Returns the summary feed URL on success.
	func addPodcast(name: String, author: String? = nil) async -> AddPodcastResult {
		return await sendAddPodcastRequest(show: name, author: author ?? "")
	}

	private func sendAddPodcastRequest(show: String, author: String) async -> AddPodcastResult {
		guard let token = bearerToken else {
			Self.logger.error("No bearer token available")
			return .failure(message: "No authentication token")
		}

		var request = URLRequest(url: addSourceURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

		let body: [String: String] = [
			"type": "pod",
			"show": show,
			"author": author,
			"apple_user_id": AuthManager.shared.appleUserID ?? ""
		]

		do {
			request.httpBody = try JSONSerialization.data(withJSONObject: body)
		} catch {
			Self.logger.error("Failed to encode request body")
			return .failure(message: "Failed to encode request")
		}

		do {
			let (data, response) = try await URLSession.shared.data(for: request)

			guard let httpResponse = response as? HTTPURLResponse else {
				Self.logger.error("Invalid response type")
				return .failure(message: "Invalid response")
			}

			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
			let serverMessage = json?["message"] as? String
			lastServerMessage = serverMessage
			let statusCode = httpResponse.statusCode

			switch statusCode {
			case 201:
				if let json,
				   let status = json["status"] as? String,
				   status == "success",
				   let summaryURL = json["summary_url"] as? String {
					Self.logger.info("Podcast already exists")
					return .successExisting(summaryURL: summaryURL)
				}
				Self.logger.error("Failed to parse 201 response")
				return .failure(message: "Failed to parse response")

			case 202:
				if let json,
				   let status = json["status"] as? String,
				   status == "success",
				   let summaryURL = json["summary_url"] as? String {
					Self.logger.info("New podcast added, processing required")
					return .successNew(summaryURL: summaryURL)
				}
				Self.logger.error("Failed to parse 202 response")
				return .failure(message: "Failed to parse response")

			default:
				let message = serverMessage ?? "Unknown error"
				Self.logger.error("[\(statusCode)] \(message)")
				return .failure(message: "[\(statusCode)] \(message)")
			}
		} catch {
			Self.logger.error("Failed to add podcast source: \(error.localizedDescription)")
			return .failure(message: error.localizedDescription)
		}
	}
}
