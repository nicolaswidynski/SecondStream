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

	private static let fileName = "rss.json"

	// MARK: - Server Error

	private(set) var lastServerMessage: String?

	private static func extractMessage(from data: Data) -> String {
		if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
		   let msg = arr.first?["message"] as? String { return msg }
		if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		   let msg = obj["message"] as? String { return msg }
		return String(data: data, encoding: .utf8) ?? "Unknown error"
	}

	// MARK: - Fetch State

	private(set) var isFetching = false
	private var fetchTask: Task<Void, Never>?

	// MARK: - Stored RSS Sources

	private let rssSourcesKey = "rssSources"

	/// All RSS sources, used by pickers.
	var rssSources: [RSSSource] {
		get {
			guard let data = UserDefaults.standard.data(forKey: rssSourcesKey),
				  let sources = try? JSONDecoder().decode([RSSSource].self, from: data) else {
				return []
			}
			return sources
		}
		set {
			if let data = try? JSONEncoder().encode(newValue) {
				UserDefaults.standard.set(data, forKey: rssSourcesKey)
			}
		}
	}

	// MARK: - Lookup

	/// Returns the configured image URL for a subscribed RSS feed URL (or its homepage URL), if present in rss.json.
	func imageURL(forFeedURL feedURL: String, homePageURL: String?) -> String? {
		let normalizedFeedURL = normalizedURLKey(feedURL)
		let normalizedHomePageURL = normalizedURLKey(homePageURL)

		for source in rssSources {
			let sourceURL = normalizedURLKey(source.url)
			guard !sourceURL.isEmpty else {
				continue
			}
			let matchesFeed = !normalizedFeedURL.isEmpty && sourceURL == normalizedFeedURL
			let matchesHome = !normalizedHomePageURL.isEmpty && sourceURL == normalizedHomePageURL
			guard matchesFeed || matchesHome else {
				continue
			}
			guard let imageURL = source.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
				  !imageURL.isEmpty else {
				continue
			}
			return imageURL
		}

		return nil
	}

	func matches(imageURL candidateImageURL: String, feedURL: String, homePageURL: String?) -> Bool {
		guard let matched = imageURL(forFeedURL: feedURL, homePageURL: homePageURL) else {
			return false
		}
		return normalizedURLKey(matched) == normalizedURLKey(candidateImageURL)
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

		guard let entries = await SourceFileFetcher.fetchIfModified(fileName: Self.fileName) else {
			return
		}

		let sources = entries.map { RSSSource(name: $0.name, author: $0.author, url: $0.feedURL, imageURL: $0.imageURL) }
		let oldURLs = Set(self.rssSources.compactMap(\.imageURL))
		let newURLs = Set(sources.compactMap(\.imageURL))
		let removed = Array(oldURLs.subtracting(newURLs))
		let added = Array(newURLs.subtracting(oldURLs))
		SourceImageCache.shared.removeImages(for: removed)
		SourceImageCache.shared.prefetchImages(for: added)
		self.rssSources = sources
		Self.logger.info("Fetched \(sources.count) RSS sources")
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

	private func normalizedURLKey(_ rawURL: String?) -> String {
		guard let rawURL else {
			return ""
		}
		let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			return ""
		}
		guard let components = URLComponents(string: trimmed.lowercased()) else {
			return trimmed.lowercased()
		}
		let host = components.host ?? ""
		let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
		return path.isEmpty ? "\(host)\(query)" : "\(host)/\(path)\(query)"
	}
}
