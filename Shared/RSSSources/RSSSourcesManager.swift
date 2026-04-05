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
	let imageURLLight: String?
}

@MainActor final class RSSSourcesManager {

	static let shared = RSSSourcesManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "RSSSources")

	private static let fileName = "rss.json"

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

	/// Returns the light-mode image URL for a subscribed RSS feed URL, if present.
	func lightImageURL(forFeedURL feedURL: String, homePageURL: String?) -> String? {
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
			guard let lightURL = source.imageURLLight?.trimmingCharacters(in: .whitespacesAndNewlines),
				  !lightURL.isEmpty else {
				continue
			}
			return lightURL
		}

		return nil
	}

	func matches(imageURL candidateImageURL: String, feedURL: String, homePageURL: String?) -> Bool {
		guard let matched = imageURL(forFeedURL: feedURL, homePageURL: homePageURL) else {
			return false
		}
		return normalizedURLKey(matched) == normalizedURLKey(candidateImageURL)
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

		let sources = entries.map { RSSSource(name: $0.name, author: $0.author, url: $0.feedURL, imageURL: $0.imageURL, imageURLLight: $0.imageURLLight) }
		let oldURLs = Set(self.rssSources.compactMap(\.imageURL))
		let newURLs = Set(sources.compactMap(\.imageURL))
		let removed = Array(oldURLs.subtracting(newURLs))
		let added = Array(newURLs.subtracting(oldURLs))
		SourceImageCache.shared.removeImages(for: removed)
		SourceImageCache.shared.prefetchImages(for: added)
		SourceImageCache.shared.prefetchImages(for: sources.compactMap(\.imageURLLight))
		self.rssSources = sources
		sources.forEach { LightFeedIconStore.shared.setLightIconURL($0.imageURLLight, for: $0.url) }
		Self.logger.info("Fetched \(sources.count) RSS sources")
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
