//
//  SourceFileFetcher.swift
//  NetNewsWire
//
//  Created by Claude on 2026-02-21.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import os.log

enum AppURLs {
	static let filesBase = "https://files.nwidynski.com/"
}

struct SourceFileEntry {
	let name: String
	let author: String?
	let feedURL: String
	let imageURL: String?
	let imageURLLight: String?
}

enum SourceFileFetcher {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SourceFileFetcher")

	private static let baseURL = AppURLs.filesBase + "lib/"
	private static let lastModifiedCache = LastModifiedCache()

	private actor LastModifiedCache {
		private var values = [String: String]()

		func value(for fileName: String) -> String? {
			values[fileName]
		}

		func set(_ value: String, for fileName: String) {
			values[fileName] = value
		}

		func clear() -> Int {
			let count = values.count
			values.removeAll(keepingCapacity: false)
			return count
		}
	}

	/// Fetches entries from a static file, using Last-Modified to avoid redundant downloads.
	/// Returns nil if the file has not changed since the last fetch.
	@MainActor static func fetchIfModified(fileName: String) async -> [SourceFileEntry]? {
		guard let url = URL(string: baseURL + fileName) else {
			logger.error("Invalid file URL for \(fileName)")
			return nil
		}

		let storedLastModified = await lastModifiedCache.value(for: fileName)
		let client = SecondStreamAPIClient.shared

		do {
			// HEAD request to check Last-Modified
			let (headStatus, headHeaders) = try await client.head(url)
			guard headStatus == 200 else {
				logger.error("HEAD request failed for \(fileName)")
				return nil
			}

			let serverLastModified = headHeaders["Last-Modified"]
			if let storedLastModified, let serverLastModified, storedLastModified == serverLastModified {
				logger.info("File \(fileName) not modified, skipping download")
				return nil
			}

			let (data, getStatus, getHeaders) = try await client.get(from: url)
			guard getStatus == 200 else {
				logger.error("GET request failed for \(fileName)")
				return nil
			}

			if let newLastModified = getHeaders["Last-Modified"] {
				await lastModifiedCache.set(newLastModified, for: fileName)
			}

			return parseEntries(from: data, fileName: fileName)
		} catch {
			logger.error("Failed to fetch \(fileName): \(error.localizedDescription)")
			return nil
		}
	}

	/// Force-fetches entries from a static file, ignoring Last-Modified cache.
	@MainActor static func fetch(fileName: String) async -> [SourceFileEntry]? {
		guard let url = URL(string: baseURL + fileName) else {
			logger.error("Invalid file URL for \(fileName)")
			return nil
		}

		do {
			let (data, statusCode, headers) = try await SecondStreamAPIClient.shared.get(from: url)
			guard statusCode == 200 else {
				logger.error("GET request failed for \(fileName)")
				return nil
			}

			if let newLastModified = headers["Last-Modified"] {
				await lastModifiedCache.set(newLastModified, for: fileName)
			}

			return parseEntries(from: data, fileName: fileName)
		} catch {
			logger.error("Failed to fetch \(fileName): \(error.localizedDescription)")
			return nil
		}
	}

	private static func parseEntries(from data: Data, fileName: String) -> [SourceFileEntry]? {
		guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
			  let firstItem = jsonArray.first,
			  let dataArray = firstItem["data"] as? [[String: Any]] else {
			logger.error("Failed to parse JSON from \(fileName)")
			return nil
		}

		var entries: [SourceFileEntry] = []
		for item in dataArray {
			guard let name = firstNonEmptyString(in: item, keys: ["Name", "name", "title"]) else {
				continue
			}
			let feedURL = firstNonEmptyString(in: item, keys: ["RSS URL", "My Feed URL", "my_feed_url", "myFeedURL"]) ?? ""
			let author = firstNonEmptyString(in: item, keys: ["Author", "author"])
			let imageURL = firstNonEmptyString(in: item, keys: ["Image URL", "image_url", "imageURL", "image_ref", "icon_url", "icon"])
			let imageURLLight = firstNonEmptyString(in: item, keys: ["Image URL Light", "image_url_light", "imageURLLight"])
			entries.append(SourceFileEntry(name: name, author: author, feedURL: feedURL, imageURL: imageURL, imageURLLight: imageURLLight))
		}

		logger.info("Parsed \(entries.count) entries from \(fileName)")
		return entries
	}

	private static func firstNonEmptyString(in item: [String: Any], keys: [String]) -> String? {
		for key in keys {
			guard let value = item[key] else {
				continue
			}
			if let string = value as? String {
				let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
				if !trimmed.isEmpty {
					return trimmed
				}
			}
		}
		return nil
	}

	@MainActor static func clearLastModifiedCache() async {
		let count = await lastModifiedCache.clear()
		logger.info("Cleared \(count) SourceFileFetcher Last-Modified cache entries")
	}
}
