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
	private static let headersCache = HeadersCache()

	private actor HeadersCache {
		private struct Entry: Codable {
			var lastModified: String?
			var contentLength: String?
		}

		private var values = [String: Entry]()
		private let defaultsKey = "SourceFileFetcherHeadersCache"

		init() {
			if let data = UserDefaults.standard.data(forKey: defaultsKey),
			   let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
				values = decoded
			}
		}

		/// Returns `true` when the server headers indicate the file has changed.
		func isModified(fileName: String, serverLastModified: String?, serverContentLength: String?) -> Bool {
			guard let entry = values[fileName] else { return true }
			if let serverLM = serverLastModified, let storedLM = entry.lastModified, serverLM != storedLM { return true }
			if let serverCL = serverContentLength, let storedCL = entry.contentLength, serverCL != storedCL { return true }
			// No stored baseline yet — treat as modified.
			if serverLastModified != nil && entry.lastModified == nil { return true }
			return false
		}

		func update(fileName: String, lastModified: String?, contentLength: String?) {
			values[fileName] = Entry(lastModified: lastModified, contentLength: contentLength)
			persist()
		}

		func clear() -> Int {
			let count = values.count
			values.removeAll(keepingCapacity: false)
			persist()
			return count
		}

		private func persist() {
			if let data = try? JSONEncoder().encode(values) {
				UserDefaults.standard.set(data, forKey: defaultsKey)
			}
		}
	}

	/// Fetches entries from a static file, skipping the download when neither
	/// `Last-Modified` nor `Content-Length` have changed since the last fetch.
	/// The comparison values are persisted across launches so a cold start is
	/// also fast when the server files haven't changed.
	/// Returns nil if the file has not changed since the last fetch.
	@MainActor static func fetchIfModified(fileName: String) async -> [SourceFileEntry]? {
		guard let url = URL(string: baseURL + fileName) else {
			logger.error("Invalid file URL for \(fileName)")
			return nil
		}

		let client = SecondStreamAPIClient.shared

		do {
			let (headStatus, headHeaders) = try await client.head(url)
			guard headStatus == 200 else {
				logger.error("HEAD request failed for \(fileName)")
				return nil
			}

			let serverLastModified = headHeaders["Last-Modified"]
			let serverContentLength = headHeaders["Content-Length"]

			let modified = await headersCache.isModified(
				fileName: fileName,
				serverLastModified: serverLastModified,
				serverContentLength: serverContentLength
			)
			guard modified else {
				logger.info("File \(fileName) unchanged (Last-Modified + Content-Length match), skipping download")
				return nil
			}

			let (data, getStatus, getHeaders) = try await client.get(from: url)
			guard getStatus == 200 else {
				logger.error("GET request failed for \(fileName)")
				return nil
			}

			await headersCache.update(
				fileName: fileName,
				lastModified: getHeaders["Last-Modified"] ?? serverLastModified,
				contentLength: getHeaders["Content-Length"] ?? serverContentLength
			)

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

			await headersCache.update(
				fileName: fileName,
				lastModified: headers["Last-Modified"],
				contentLength: headers["Content-Length"]
			)

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

	@MainActor static func clearHeadersCache() async {
		let count = await headersCache.clear()
		logger.info("Cleared \(count) SourceFileFetcher headers cache entries")
	}
}
