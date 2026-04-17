//
//  MediaSource.swift + MediaSourcesManager.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-11.
//  Copyright © 2026 STDN. All rights reserved.
//

import Foundation
import os.log
import Account

// MARK: - MediaSource

/// Unified source model for podcast and YouTube entries.
///
/// Replaces the formerly separate `PodcastSource` and `YoutubeSource` structs.
/// The legacy `rssURL` Codable key is retained for backwards-compatible decoding
/// of podcast entries stored before this unification.
struct MediaSource: Codable, Hashable {
	let name: String
	let author: String?
	let url: String
	let imageURL: String?
	let imageURLLight: String?

	private enum CodingKeys: String, CodingKey {
		case name
		case author
		case url
		case imageURL
		case imageURLLight
		case legacyRSSURL = "rssURL"
	}

	init(name: String, author: String?, url: String, imageURL: String?, imageURLLight: String? = nil) {
		self.name = name
		self.author = author
		self.url = url
		self.imageURL = imageURL
		self.imageURLLight = imageURLLight
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		name = try container.decode(String.self, forKey: .name)
		author = try container.decodeIfPresent(String.self, forKey: .author)
		url = try container.decodeIfPresent(String.self, forKey: .url)
			?? container.decode(String.self, forKey: .legacyRSSURL)
		imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
		imageURLLight = try container.decodeIfPresent(String.self, forKey: .imageURLLight)
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(name, forKey: .name)
		try container.encodeIfPresent(author, forKey: .author)
		try container.encode(url, forKey: .url)
		try container.encodeIfPresent(imageURL, forKey: .imageURL)
		try container.encodeIfPresent(imageURLLight, forKey: .imageURLLight)
	}
}

// MARK: - Find types

struct FindShowCandidate: Hashable {
	let name: String
	let author: String?
	let artworkUrl: String?
}

enum FindShowResult {
	case success([FindShowCandidate])
	case failure(message: String)
}

// MARK: - MediaSourcesManager

/// Unified manager for podcast and YouTube sources.
///
/// Replaces `PodcastSourcesManager` and `YoutubeSourcesManager`. Use the
/// `.podcast` and `.youtube` static instances in place of the old `.shared` singletons.
@MainActor final class MediaSourcesManager {

	static let podcast = MediaSourcesManager(
		category: .podcast,
		typeString: "pod",
		topFileName: "pod_free.json",
		libraryFileName: "pod_featured.json",
		topSourcesKey: "podcastTopSources",
		librarySourcesKey: "podcastLibrarySources",
		supportsAtHandles: false
	)

	static let youtube = MediaSourcesManager(
		category: .youtube,
		typeString: "yt",
		topFileName: "yt_free.json",
		libraryFileName: "yt_featured.json",
		topSourcesKey: "youtubeTopSources",
		librarySourcesKey: "youtubeLibrarySources",
		supportsAtHandles: true
	)

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "MediaSources")

	private let client = SecondStreamAPIClient.shared

	/// Feed category this manager handles (.podcast or .youtube).
	let category: FeedCategory
	private let typeString: String
	private let topFileName: String
	private let libraryFileName: String
	private let topSourcesKey: String
	private let librarySourcesKey: String
	/// Whether `@handle` entries should be routed as `author` rather than `show`.
	private let supportsAtHandles: Bool

	private(set) var lastServerMessage: String?
	private(set) var isFetching = false
	private var fetchTask: Task<Void, Never>?

	private init(
		category: FeedCategory,
		typeString: String,
		topFileName: String,
		libraryFileName: String,
		topSourcesKey: String,
		librarySourcesKey: String,
		supportsAtHandles: Bool
	) {
		self.category = category
		self.typeString = typeString
		self.topFileName = topFileName
		self.libraryFileName = libraryFileName
		self.topSourcesKey = topSourcesKey
		self.librarySourcesKey = librarySourcesKey
		self.supportsAtHandles = supportsAtHandles
	}

	// MARK: - Image URL helpers

	/// Returns the light image URL for the source whose dark `imageURL` matches `iconURL`.
	func lightImageURL(forIconURL iconURL: String) -> String? {
		(topSources + librarySources).first(where: { $0.imageURL == iconURL })?.imageURLLight
	}

	/// Returns the dark image URL for the source whose `imageURLLight` matches `lightURL`.
	func iconURL(forLightImageURL lightURL: String) -> String? {
		(topSources + librarySources).first(where: { $0.imageURLLight == lightURL })?.imageURL
	}

	// MARK: - Stored Sources

	/// Top Picks (free) sources.
	var topSources: [MediaSource] {
		get {
			guard let data = UserDefaults.standard.data(forKey: topSourcesKey),
				  let sources = try? JSONDecoder().decode([MediaSource].self, from: data) else {
				return []
			}
			return sources
		}
		set {
			if let data = try? JSONEncoder().encode(newValue) {
				UserDefaults.standard.set(data, forKey: topSourcesKey)
			}
		}
	}

	/// Library (paid) sources.
	var librarySources: [MediaSource] {
		get {
			guard let data = UserDefaults.standard.data(forKey: librarySourcesKey),
				  let sources = try? JSONDecoder().decode([MediaSource].self, from: data) else {
				return []
			}
			return sources
		}
		set {
			if let data = try? JSONEncoder().encode(newValue) {
				UserDefaults.standard.set(data, forKey: librarySourcesKey)
			}
		}
	}

	// MARK: - API

	/// Starts fetching sources in the background. Does nothing if already fetching.
	func startFetching() {
		guard !isFetching else {
			return
		}
		fetchTask = Task {
			await fetchSources()
		}
	}

	/// Waits for any in-progress fetch to complete, or fetches if not already fetching.
	func waitForFetch() async {
		if let task = fetchTask {
			await task.value
		} else if !isFetching {
			await fetchSources()
		}
	}

	/// Always fetches fresh sources, regardless of current state.
	func fetchFresh() async {
		fetchTask?.cancel()
		fetchTask = nil
		await fetchSources()
	}

	private func fetchSources() async {
		isFetching = true
		defer {
			isFetching = false
			fetchTask = nil
		}

		async let topEntries = SourceFileFetcher.fetchIfModified(fileName: topFileName)
		async let libraryEntries = SourceFileFetcher.fetchIfModified(fileName: libraryFileName)

		if let entries = await topEntries {
			let sources = entries.map { MediaSource(name: $0.name, author: $0.author, url: $0.feedURL, imageURL: $0.imageURL, imageURLLight: $0.imageURLLight) }
			let oldURLs = Set(self.topSources.compactMap(\.imageURL))
			let newURLs = Set(sources.compactMap(\.imageURL))
			let libraryURLs = Set(self.librarySources.compactMap(\.imageURL))
			let removed = Array(oldURLs.subtracting(newURLs).subtracting(libraryURLs))
			let added = Array(newURLs.subtracting(oldURLs))
			SourceImageCache.shared.removeImages(for: removed)
			SourceImageCache.shared.prefetchImages(for: added)
			SourceImageCache.shared.prefetchImages(for: sources.compactMap(\.imageURLLight))
			self.topSources = sources
			sources.forEach { LightFeedIconStore.shared.setLightIconURL($0.imageURLLight, for: $0.url) }
			Self.logger.info("Fetched \(sources.count) top \(self.typeString) sources")
		}

		if let entries = await libraryEntries {
			let sources = entries.map { MediaSource(name: $0.name, author: $0.author, url: $0.feedURL, imageURL: $0.imageURL, imageURLLight: $0.imageURLLight) }
			let oldURLs = Set(self.librarySources.compactMap(\.imageURL))
			let newURLs = Set(sources.compactMap(\.imageURL))
			let topURLs = Set(self.topSources.compactMap(\.imageURL))
			let removed = Array(oldURLs.subtracting(newURLs).subtracting(topURLs))
			let added = Array(newURLs.subtracting(oldURLs))
			SourceImageCache.shared.removeImages(for: removed)
			SourceImageCache.shared.prefetchImages(for: added)
			SourceImageCache.shared.prefetchImages(for: sources.compactMap(\.imageURLLight))
			self.librarySources = sources
			sources.forEach { LightFeedIconStore.shared.setLightIconURL($0.imageURLLight, for: $0.url) }
			Self.logger.info("Fetched \(sources.count) library \(self.typeString) sources")
		}
	}

	// MARK: - Find

	/// Searches for source candidates via the find-show webhook.
	func find(name: String, author: String? = nil) async -> FindShowResult {
		if supportsAtHandles && name.hasPrefix("@") {
			return await sendFindRequest(show: "", author: name)
		}
		return await sendFindRequest(show: name, author: author ?? "")
	}

	private func sendFindRequest(show: String, author: String) async -> FindShowResult {
		let requestID = UUID().uuidString
		let body: [String: String] = [
			"type":          typeString,
			"show":          show,
			"author":        author,
			"apple_user_id": AuthManager.shared.appleUserID ?? "",
			"request_id":    requestID
		]
		do {
			let (data, statusCode) = try await client.post(to: .findShow, body: body)
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
			if let echoed = json?["request_id"] as? String, echoed != requestID {
				Self.logger.warning("request_id mismatch: sent \(requestID), received \(echoed)")
			}
			if statusCode == 200,
			   let json,
			   let status = json["status"] as? String,
			   status == "success",
			   let listData = json["list"] as? [[String: Any]] {
				let candidates = listData.compactMap { dict -> FindShowCandidate? in
					guard let name = dict["name"] as? String else { return nil }
					return FindShowCandidate(name: name, author: dict["author"] as? String, artworkUrl: dict["artworkUrl"] as? String)
				}
				Self.logger.info("Found \(candidates.count) candidates")
				return .success(Array(candidates.prefix(10)))
			}
			let message = FeedStatsManager.webhookMessage(from: data)
			Self.logger.error("[\(statusCode)] \(message)")
			return .failure(message: "[\(statusCode)] \(message)")
		} catch {
			Self.logger.error("Failed to find show: \(error.localizedDescription)")
			return .failure(message: error.localizedDescription)
		}
	}
}

// MARK: - WebhookSourcesManaging

extension MediaSourcesManager: WebhookSourcesManaging {

	func add(name: String, author: String?) async -> AddSourceResult {
		let effectiveShow: String
		let effectiveAuthor: String
		if supportsAtHandles && name.hasPrefix("@") {
			effectiveShow = ""
			effectiveAuthor = name
		} else {
			effectiveShow = name
			effectiveAuthor = author ?? ""
		}

		let requestID = UUID().uuidString
		let body: [String: Any] = [
			"operation":     "add-show",
			"type":          typeString,
			"show":          effectiveShow,
			"author":        effectiveAuthor,
			"apple_user_id": AuthManager.shared.appleUserID ?? "",
			"request_id":    requestID
		]

		do {
			let (data, statusCode) = try await client.post(to: .allFeedRequests, body: body)
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
			let serverMessage = json?["message"] as? String
			lastServerMessage = serverMessage
			if let echoed = json?["request_id"] as? String, echoed != requestID {
				Self.logger.warning("request_id mismatch: sent \(requestID), received \(echoed)")
			}
			if let json, let credits = FeedStatsManager.parseCredits(json) {
				FeedStatsManager.shared.cachedCredits = credits
			}

			switch statusCode {
			case 200, 201:
				if let json,
				   let status = json["status"] as? String,
				   status == "success",
				   let summaryURL = json["summary_url"] as? String {
					Self.logger.info("\(self.typeString) source added or already exists")
					return .existsOnServer(summaryURL: summaryURL)
				}
				Self.logger.error("Failed to parse \(statusCode) response")
				return .failure(message: "Failed to parse response")
			case 202:
				if let json,
				   let status = json["status"] as? String,
				   status == "success",
				   let summaryURL = json["summary_url"] as? String {
					Self.logger.info("New \(self.typeString) source added, processing required")
					return .newOnServer(summaryURL: summaryURL, message: serverMessage ?? "")
				}
				Self.logger.error("Failed to parse 202 response")
				return .failure(message: "Failed to parse response")
			default:
				let message = serverMessage ?? "Unknown error"
				Self.logger.error("[\(statusCode)] \(message)")
				return .failure(message: "[\(statusCode)] \(message)")
			}
		} catch {
			Self.logger.error("Failed to add \(self.typeString) source: \(error.localizedDescription)")
			return .failure(message: error.localizedDescription)
		}
	}
}
