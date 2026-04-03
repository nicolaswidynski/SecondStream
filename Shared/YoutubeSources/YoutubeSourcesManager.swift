//
//  YoutubeSourcesManager.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-31.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import os.log

struct YoutubeSource: Codable, Hashable {
	let name: String
	let author: String?
	let url: String
	let imageURL: String?
	let imageURLLight: String?
}

enum AddYoutubeResult {
	case successExisting(summaryURL: String)  // 201 - Channel already exists, no wait
	case successNew(summaryURL: String, message: String)  // 202 - New channel, wait for processing
	case failure(message: String)             // Any error - uses server message
}

@MainActor final class YoutubeSourcesManager {

	static let shared = YoutubeSourcesManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "YoutubeSources")

	private let allFeedRequestsURL = URL(string: "https://n8n.nwidynski.com/webhook/all-feed-requests")!
	private let findShowURL = URL(string: "https://n8n.nwidynski.com/webhook/find-show")!

	private static let topFileName = "yt_free.json"
	private static let libraryFileName = "yt_featured.json"

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

	// MARK: - Stored YouTube Sources

	private let youtubeTopSourcesKey = "youtubeTopSources"
	private let youtubeLibrarySourcesKey = "youtubeLibrarySources"

	/// Returns the light image URL for the YouTube source whose dark `imageURL` matches `iconURL`.
	func lightImageURL(forIconURL iconURL: String) -> String? {
		(youtubeSources + youtubeLibrarySources).first(where: { $0.imageURL == iconURL })?.imageURLLight
	}

	/// Returns the dark image URL for the YouTube source whose `imageURLLight` matches `lightURL`.
	func iconURL(forLightImageURL lightURL: String) -> String? {
		(youtubeSources + youtubeLibrarySources).first(where: { $0.imageURLLight == lightURL })?.imageURL
	}

	/// Top Picks sources, used by pickers.
	var youtubeSources: [YoutubeSource] {
		get {
			guard let data = UserDefaults.standard.data(forKey: youtubeTopSourcesKey),
				  let sources = try? JSONDecoder().decode([YoutubeSource].self, from: data) else {
				return []
			}
			return sources
		}
		set {
			if let data = try? JSONEncoder().encode(newValue) {
				UserDefaults.standard.set(data, forKey: youtubeTopSourcesKey)
			}
		}
	}

	/// Library (non-Top Picks) sources.
	var youtubeLibrarySources: [YoutubeSource] {
		get {
			guard let data = UserDefaults.standard.data(forKey: youtubeLibrarySourcesKey),
				  let sources = try? JSONDecoder().decode([YoutubeSource].self, from: data) else {
				return []
			}
			return sources
		}
		set {
			if let data = try? JSONEncoder().encode(newValue) {
				UserDefaults.standard.set(data, forKey: youtubeLibrarySourcesKey)
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

	/// Starts fetching youtube sources in the background. Does nothing if already fetching.
	func startFetching() {
		guard !isFetching else {
			return
		}
		fetchTask = Task {
			await fetchYoutubeSources()
		}
	}

	/// Waits for any in-progress fetch to complete, or fetches if not already fetching.
	func waitForFetch() async {
		if let task = fetchTask {
			await task.value
		} else if !isFetching {
			await fetchYoutubeSources()
		}
	}

	/// Always fetches fresh sources, regardless of current state.
	func fetchFresh() async {
		// Cancel any existing fetch task
		fetchTask?.cancel()
		fetchTask = nil
		// Fetch fresh
		await fetchYoutubeSources()
	}

	private func fetchYoutubeSources() async {
		isFetching = true
		defer {
			isFetching = false
			fetchTask = nil
		}

		async let topEntries = SourceFileFetcher.fetchIfModified(fileName: Self.topFileName)
		async let libraryEntries = SourceFileFetcher.fetchIfModified(fileName: Self.libraryFileName)

		if let entries = await topEntries {
			let sources = entries.map { YoutubeSource(name: $0.name, author: $0.author, url: $0.feedURL, imageURL: $0.imageURL, imageURLLight: $0.imageURLLight) }
			let oldURLs = Set(self.youtubeSources.compactMap(\.imageURL))
			let newURLs = Set(sources.compactMap(\.imageURL))
			let libraryURLs = Set(self.youtubeLibrarySources.compactMap(\.imageURL))
			let removed = Array(oldURLs.subtracting(newURLs).subtracting(libraryURLs))
			let added = Array(newURLs.subtracting(oldURLs))
			SourceImageCache.shared.removeImages(for: removed)
			SourceImageCache.shared.prefetchImages(for: added)
			SourceImageCache.shared.prefetchImages(for: sources.compactMap(\.imageURLLight))
			self.youtubeSources = sources
			sources.forEach { LightFeedIconStore.shared.setLightIconURL($0.imageURLLight, for: $0.url) }
			Self.logger.info("Fetched \(sources.count) top YouTube sources")
		}

		if let entries = await libraryEntries {
			let sources = entries.map { YoutubeSource(name: $0.name, author: $0.author, url: $0.feedURL, imageURL: $0.imageURL, imageURLLight: $0.imageURLLight) }
			let oldURLs = Set(self.youtubeLibrarySources.compactMap(\.imageURL))
			let newURLs = Set(sources.compactMap(\.imageURL))
			let topURLs = Set(self.youtubeSources.compactMap(\.imageURL))
			let removed = Array(oldURLs.subtracting(newURLs).subtracting(topURLs))
			let added = Array(newURLs.subtracting(oldURLs))
			SourceImageCache.shared.removeImages(for: removed)
			SourceImageCache.shared.prefetchImages(for: added)
			SourceImageCache.shared.prefetchImages(for: sources.compactMap(\.imageURLLight))
			self.youtubeLibrarySources = sources
			sources.forEach { LightFeedIconStore.shared.setLightIconURL($0.imageURLLight, for: $0.url) }
			Self.logger.info("Fetched \(sources.count) library YouTube sources")
		}
	}

	/// Searches for YouTube channel candidates via the find-show webhook.
	func findYoutube(name channelName: String, author: String? = nil) async -> FindShowResult {
		if channelName.hasPrefix("@") {
			return await sendFindRequest(type: "yt", show: "", author: channelName)
		} else {
			return await sendFindRequest(type: "yt", show: channelName, author: author ?? "")
		}
	}

	private func sendFindRequest(type: String, show: String, author: String) async -> FindShowResult {
		guard let token = bearerToken else {
			Self.logger.error("No bearer token available")
			return .failure(message: "No authentication token")
		}

		var request = URLRequest(url: findShowURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

		let requestID = UUID().uuidString
		let body: [String: String] = [
			"type": type,
			"show": show,
			"author": author,
			"apple_user_id": AuthManager.shared.appleUserID ?? "",
			"request_id": requestID
		]

		do {
			request.httpBody = try JSONSerialization.data(withJSONObject: body)
		} catch {
			Self.logger.error("Failed to encode find request body")
			return .failure(message: "Failed to encode request")
		}

		do {
			let (data, response) = try await URLSession.shared.data(for: request)
			guard let httpResponse = response as? HTTPURLResponse else {
				Self.logger.error("Invalid response type")
				return .failure(message: "Invalid response")
			}
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
			if let echoed = json?["request_id"] as? String, echoed != requestID {
				Self.logger.warning("request_id mismatch: sent \(requestID), received \(echoed)")
			}
			if httpResponse.statusCode == 200,
			   let json,
			   let status = json["status"] as? String,
			   status == "success",
			   let listData = json["list"] as? [[String: Any]] {
				let candidates = listData.compactMap { dict -> FindShowCandidate? in
					guard let name = dict["name"] as? String else {
						return nil
					}
					return FindShowCandidate(name: name, author: dict["author"] as? String, artworkUrl: dict["artworkUrl"] as? String)
				}
				Self.logger.info("Found \(candidates.count) candidates")
				return .success(Array(candidates.prefix(10)))
			}
			let message = Self.extractMessage(from: data)
			Self.logger.error("[\(httpResponse.statusCode)] \(message)")
			return .failure(message: "[\(httpResponse.statusCode)] \(message)")
		} catch {
			Self.logger.error("Failed to find show: \(error.localizedDescription)")
			return .failure(message: error.localizedDescription)
		}
	}

	/// Adds a YouTube channel by sending the channel name and author to the webhook.
	/// When the input starts with `@` it is a channel handle — sent as `author` with an empty `show`.
	/// The `@` prefix is preserved so the webhook always receives the full handle (e.g. `@channel`).
	/// Returns the summary feed URL on success.
	func addYoutube(name channelName: String, author: String? = nil) async -> AddYoutubeResult {
		if channelName.hasPrefix("@") {
			// @handle entered — send as-is (with @) as author, empty show
			return await sendAddYoutubeRequest(show: "", author: channelName)
		} else {
			return await sendAddYoutubeRequest(show: channelName, author: author ?? "")
		}
	}

	private func sendAddYoutubeRequest(show: String, author: String) async -> AddYoutubeResult {
		guard let token = bearerToken else {
			Self.logger.error("No bearer token available")
			return .failure(message: "No authentication token")
		}

		var request = URLRequest(url: allFeedRequestsURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

		let requestID = UUID().uuidString
		let feedsForUpdate = await FeedStatsManager.shared.buildFeedsForUpdate()
		let body: [String: Any] = [
			"operation":        "add-show",
			"type":             "yt",
			"show":             show,
			"author":           author,
			"apple_user_id":    AuthManager.shared.appleUserID ?? "",
			"request_id":       requestID,
			"feeds_for_update": feedsForUpdate
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
			if let echoed = json?["request_id"] as? String, echoed != requestID {
				Self.logger.warning("request_id mismatch: sent \(requestID), received \(echoed)")
			}
			let statusCode = httpResponse.statusCode

			if let nbCreditsStr = json?["nb_credits"] as? String,
			   let credits = Int(nbCreditsStr) {
				FeedStatsManager.shared.cachedCredits = credits
			}

			switch statusCode {
			case 200, 201:
				if let json,
				   let status = json["status"] as? String,
				   status == "success",
				   let summaryURL = json["summary_url"] as? String {
					Self.logger.info("YouTube channel added or already exists")
					return .successExisting(summaryURL: summaryURL)
				}
				Self.logger.error("Failed to parse \(statusCode) response")
				return .failure(message: "Failed to parse response")

			case 202:
				if let json,
				   let status = json["status"] as? String,
				   status == "success",
				   let summaryURL = json["summary_url"] as? String {
					Self.logger.info("New YouTube channel added, processing required")
					return .successNew(summaryURL: summaryURL, message: serverMessage ?? "")
				}
				Self.logger.error("Failed to parse 202 response")
				return .failure(message: "Failed to parse response")

			default:
				let message = serverMessage ?? "Unknown error"
				Self.logger.error("[\(statusCode)] \(message)")
				return .failure(message: "[\(statusCode)] \(message)")
			}
		} catch {
			Self.logger.error("Failed to add YouTube channel: \(error.localizedDescription)")
			return .failure(message: error.localizedDescription)
		}
	}
}
