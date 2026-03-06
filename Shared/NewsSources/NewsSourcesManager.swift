//
//  NewsSourcesManager.swift
//  NetNewsWire
//
//  Created by Claude on 2026-02-10.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import os.log

struct NewsSource: Codable, Hashable {
	let name: String
	let author: String?
	let url: String
	let imageURL: String?
}

enum AddNewsResult {
	case successExisting(summaryURL: String)  // 201 - Topic already exists, no wait
	case successNew(summaryURL: String)       // 202 - New topic, wait for processing
	case failure(message: String)             // Any error - uses server message
}

@MainActor final class NewsSourcesManager {

	static let shared = NewsSourcesManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NewsSources")

	private let addSourceURL = URL(string: "https://n8n.nwidynski.com/webhook/add-show-source")!

	private static let topFileNames = ["topic_top.json", "topics_top.json"]
	private static let libraryFileNames = ["topic.json", "topics.json"]

	// MARK: - Server Error

	private(set) var lastServerMessage: String?

	// MARK: - Fetch State

	private(set) var isFetching = false
	private var fetchTask: Task<Void, Never>?

	// MARK: - Stored News Sources

	private let newsTopSourcesKey = "newsTopSources"
	private let newsLibrarySourcesKey = "newsLibrarySources"

	/// Top Picks sources, used by pickers.
	var newsSources: [NewsSource] {
		get {
			guard let data = UserDefaults.standard.data(forKey: newsTopSourcesKey),
				  let sources = try? JSONDecoder().decode([NewsSource].self, from: data) else {
				return []
			}
			return sources
		}
		set {
			if let data = try? JSONEncoder().encode(newValue) {
				UserDefaults.standard.set(data, forKey: newsTopSourcesKey)
			}
		}
	}

	/// Library (non-Top Picks) sources.
	var newsLibrarySources: [NewsSource] {
		get {
			guard let data = UserDefaults.standard.data(forKey: newsLibrarySourcesKey),
				  let sources = try? JSONDecoder().decode([NewsSource].self, from: data) else {
				return []
			}
			return sources
		}
		set {
			if let data = try? JSONEncoder().encode(newValue) {
				UserDefaults.standard.set(data, forKey: newsLibrarySourcesKey)
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

	/// Starts fetching news sources in the background. Does nothing if already fetching.
	func startFetching() {
		guard !isFetching else {
			return
		}
		fetchTask = Task {
			await fetchNewsSources()
		}
	}

	/// Waits for any in-progress fetch to complete, or fetches if not already fetching.
	func waitForFetch() async {
		if let task = fetchTask {
			await task.value
		} else if !isFetching {
			await fetchNewsSources()
		}
	}

	/// Always fetches fresh sources, regardless of current state.
	func fetchFresh() async {
		// Cancel any existing fetch task
		fetchTask?.cancel()
		fetchTask = nil
		// Fetch fresh
		await fetchNewsSources(forceRefresh: true)
	}

	private func fetchNewsSources(forceRefresh: Bool = false) async {
		isFetching = true
		defer {
			isFetching = false
			fetchTask = nil
		}

		async let topEntries = fetchEntries(fileNames: Self.topFileNames, forceRefresh: forceRefresh)
		async let libraryEntries = fetchEntries(fileNames: Self.libraryFileNames, forceRefresh: forceRefresh)

		if let entries = await topEntries {
			let mappedSources = entries.map { NewsSource(name: $0.name, author: $0.author, url: $0.feedURL, imageURL: $0.imageURL) }
			let sources = await hydrateMissingImageURLs(in: mappedSources)
			let oldURLs = Set(self.newsSources.compactMap(\.imageURL))
			let newURLs = Set(sources.compactMap(\.imageURL))
			let libraryURLs = Set(self.newsLibrarySources.compactMap(\.imageURL))
			let removed = Array(oldURLs.subtracting(newURLs).subtracting(libraryURLs))
			let added = Array(newURLs.subtracting(oldURLs))
			SourceImageCache.shared.removeImages(for: removed)
			SourceImageCache.shared.prefetchImages(for: added)
			self.newsSources = sources
			Self.logger.info("Fetched \(sources.count) top news sources")
		}

		if let entries = await libraryEntries {
			let mappedSources = entries.map { NewsSource(name: $0.name, author: $0.author, url: $0.feedURL, imageURL: $0.imageURL) }
			let sources = await hydrateMissingImageURLs(in: mappedSources)
			let oldURLs = Set(self.newsLibrarySources.compactMap(\.imageURL))
			let newURLs = Set(sources.compactMap(\.imageURL))
			let topURLs = Set(self.newsSources.compactMap(\.imageURL))
			let removed = Array(oldURLs.subtracting(newURLs).subtracting(topURLs))
			let added = Array(newURLs.subtracting(oldURLs))
			SourceImageCache.shared.removeImages(for: removed)
			SourceImageCache.shared.prefetchImages(for: added)
			self.newsLibrarySources = sources
			Self.logger.info("Fetched \(sources.count) library news sources")
		}
	}

	private func fetchEntries(fileNames: [String], forceRefresh: Bool) async -> [SourceFileEntry]? {
		for fileName in fileNames {
			if forceRefresh {
				if let entries = await SourceFileFetcher.fetch(fileName: fileName) {
					return entries
				}
			} else {
				if let entries = await SourceFileFetcher.fetchIfModified(fileName: fileName) {
					return entries
				}
			}
		}
		return nil
	}

	private func hydrateMissingImageURLs(in sources: [NewsSource]) async -> [NewsSource] {
		var hydrated = sources

		for index in hydrated.indices {
			let currentImageURL = hydrated[index].imageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			guard currentImageURL.isEmpty else {
				continue
			}
			guard let imageRef = await Self.fetchImageURLFromSource(feedURLString: hydrated[index].url) else {
				continue
			}

			hydrated[index] = NewsSource(
				name: hydrated[index].name,
				author: hydrated[index].author,
				url: hydrated[index].url,
				imageURL: imageRef
			)
		}

		return hydrated
	}

	private static func fetchImageURLFromSource(feedURLString: String) async -> String? {
		let trimmed = feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let url = URL(string: trimmed) else {
			return nil
		}

		do {
			let (data, response) = try await URLSession.shared.data(from: url)
			guard let httpResponse = response as? HTTPURLResponse,
				  (200...299).contains(httpResponse.statusCode) else {
				return nil
			}

			if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
				let imageKeys = ["image_link", "imageURL", "image_url", "icon", "icon_url", "image_ref"]
				for key in imageKeys {
					if let value = json[key] as? String {
						let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
						if !trimmedValue.isEmpty {
							return trimmedValue
						}
					}
				}
			}

			guard let xml = String(data: data, encoding: .utf8) else {
				return nil
			}
			return parseImageRef(fromXML: xml)
		} catch {
			return nil
		}
	}

	private static func parseImageRef(fromXML xml: String) -> String? {
		let patterns = [
			#"<image_ref[^>]*>\s*<!\[CDATA\[(.*?)\]\]>\s*</image_ref>"#,
			#"<image_ref[^>]*>\s*([^<]+?)\s*</image_ref>"#
		]

		for pattern in patterns {
			guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
				continue
			}
			let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
			guard let match = regex.firstMatch(in: xml, options: [], range: range),
				  match.numberOfRanges > 1,
				  let captureRange = Range(match.range(at: 1), in: xml) else {
				continue
			}
			let value = String(xml[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
			if !value.isEmpty {
				return value
			}
		}

		return nil
	}

	/// Adds a news source by sending the name and author to the webhook.
	/// Returns the summary feed URL on success.
	func addNews(name: String, author: String? = nil) async -> AddNewsResult {
		return await sendAddNewsRequest(show: name, author: author ?? "")
	}

	private func sendAddNewsRequest(show: String, author: String) async -> AddNewsResult {
		guard let token = bearerToken else {
			Self.logger.error("No bearer token available")
			return .failure(message: "No authentication token")
		}

		var request = URLRequest(url: addSourceURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

		let body: [String: String] = [
			"type": "topics",
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
					Self.logger.info("News topic already exists")
					return .successExisting(summaryURL: summaryURL)
				}
				Self.logger.error("Failed to parse 201 response")
				return .failure(message: "Failed to parse response")

			case 202:
				if let json,
				   let status = json["status"] as? String,
				   status == "success",
				   let summaryURL = json["summary_url"] as? String {
					Self.logger.info("New news topic added, processing required")
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
			Self.logger.error("Failed to add news topic: \(error.localizedDescription)")
			return .failure(message: error.localizedDescription)
		}
	}
}
