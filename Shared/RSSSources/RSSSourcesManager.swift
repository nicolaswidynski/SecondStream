//
//  RSSSourcesManager.swift
//  NetNewsWire
//
//  Created by Codex on 2026-02-17.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import os.log

struct RSSSource: Codable, Hashable {
	let name: String
	let author: String?
	let url: String
	let myFeedURL: String?
	let imageURL: String?
}

enum AddRSSResult {
	case successExisting(summaryURL: String)  // 201 - Feed already exists
	case successNew(summaryURL: String)       // 202 - Feed accepted for processing
	case failure(message: String)             // Any error - uses server message
}

@MainActor final class RSSSourcesManager {

	static let shared = RSSSourcesManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "RSSSources")

	private let addSourceURL = URL(string: "https://n8n.nwidynski.com/webhook/add-show-source")!

	private static let topFileName = "rss_top.txt"
	private static let libraryFileName = "rss.txt"

	// MARK: - Server Error

	private(set) var lastServerMessage: String?

	// MARK: - Fetch State

	private(set) var isFetching = false
	private var fetchTask: Task<Void, Never>?

	// MARK: - Stored RSS Sources

	private let rssTopSourcesKey = "rssTopSources"
	private let rssLibrarySourcesKey = "rssLibrarySources"

	/// Top Picks sources, used by pickers.
	var rssSources: [RSSSource] {
		get {
			guard let data = UserDefaults.standard.data(forKey: rssTopSourcesKey),
				  let sources = try? JSONDecoder().decode([RSSSource].self, from: data) else {
				return []
			}
			return sources
		}
		set {
			if let data = try? JSONEncoder().encode(newValue) {
				UserDefaults.standard.set(data, forKey: rssTopSourcesKey)
			}
		}
	}

	/// Library (non-Top Picks) sources.
	var rssLibrarySources: [RSSSource] {
		get {
			guard let data = UserDefaults.standard.data(forKey: rssLibrarySourcesKey),
				  let sources = try? JSONDecoder().decode([RSSSource].self, from: data) else {
				return []
			}
			return sources
		}
		set {
			if let data = try? JSONEncoder().encode(newValue) {
				UserDefaults.standard.set(data, forKey: rssLibrarySourcesKey)
			}
		}
	}

	// MARK: - Token

	private var bearerToken: String? {
		guard let tokenURL = Bundle.main.url(forResource: "podcast_token", withExtension: "txt"),
			  let token = try? String(contentsOf: tokenURL, encoding: .utf8) else {
			Self.logger.error("Failed to load token from file")
			return nil
		}
		return token.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: - API

	func startFetching() {
		guard !isFetching else {
			return
		}
		fetchTask = Task {
			await fetchRSSSources()
		}
	}

	func waitForFetch() async {
		if let task = fetchTask {
			await task.value
		} else if !isFetching {
			await fetchRSSSources()
		}
	}

	func fetchFresh() async {
		fetchTask?.cancel()
		fetchTask = nil
		await fetchRSSSources()
	}

	private func fetchRSSSources() async {
		isFetching = true
		defer {
			isFetching = false
			fetchTask = nil
		}

		async let topEntries = SourceFileFetcher.fetchIfModified(fileName: Self.topFileName)
		async let libraryEntries = SourceFileFetcher.fetchIfModified(fileName: Self.libraryFileName)

		if let entries = await topEntries {
			let sources = entries.map { RSSSource(name: $0.name, author: $0.author, url: $0.rssURL, myFeedURL: $0.myFeedURL, imageURL: $0.imageURL) }
			let oldURLs = Set(self.rssSources.compactMap(\.imageURL))
			let newURLs = Set(sources.compactMap(\.imageURL))
			let libraryURLs = Set(self.rssLibrarySources.compactMap(\.imageURL))
			let removed = Array(oldURLs.subtracting(newURLs).subtracting(libraryURLs))
			let added = Array(newURLs.subtracting(oldURLs))
			SourceImageCache.shared.removeImages(for: removed)
			SourceImageCache.shared.prefetchImages(for: added)
			self.rssSources = sources
			Self.logger.info("Fetched \(sources.count) top RSS sources")
		}

		if let entries = await libraryEntries {
			let sources = entries.map { RSSSource(name: $0.name, author: $0.author, url: $0.rssURL, myFeedURL: $0.myFeedURL, imageURL: $0.imageURL) }
			let oldURLs = Set(self.rssLibrarySources.compactMap(\.imageURL))
			let newURLs = Set(sources.compactMap(\.imageURL))
			let topURLs = Set(self.rssSources.compactMap(\.imageURL))
			let removed = Array(oldURLs.subtracting(newURLs).subtracting(topURLs))
			let added = Array(newURLs.subtracting(oldURLs))
			SourceImageCache.shared.removeImages(for: removed)
			SourceImageCache.shared.prefetchImages(for: added)
			self.rssLibrarySources = sources
			Self.logger.info("Fetched \(sources.count) library RSS sources")
		}
	}

	/// Adds an RSS source by sending the name and author to the webhook.
	func addRSS(name: String, author: String? = nil) async -> AddRSSResult {
		return await sendAddRSSRequest(show: name, author: author ?? "")
	}

	private func sendAddRSSRequest(show: String, author: String) async -> AddRSSResult {
		guard let token = bearerToken else {
			Self.logger.error("No bearer token available")
			return .failure(message: "No authentication token")
		}

		var request = URLRequest(url: addSourceURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

		let body: [String: String] = [
			"type": "rss",
			"show": show,
			"author": author,
			"authorize_unknown_sources": "YES"
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
					Self.logger.info("RSS feed already exists")
					return .successExisting(summaryURL: summaryURL)
				}
				Self.logger.error("Failed to parse 201 response")
				return .failure(message: "Failed to parse response")

			case 202:
				if let json,
				   let status = json["status"] as? String,
				   status == "success",
				   let summaryURL = json["summary_url"] as? String {
					Self.logger.info("New RSS feed added, processing required")
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
			Self.logger.error("Failed to add RSS source: \(error.localizedDescription)")
			return .failure(message: error.localizedDescription)
		}
	}
}
