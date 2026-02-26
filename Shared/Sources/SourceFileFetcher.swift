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
	let rssURL: String
	let myFeedURL: String?
	let imageURL: String?
}

enum SourceFileFetcher {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SourceFileFetcher")

	private static let baseURL = AppURLs.filesBase + "lib/"

	/// Fetches entries from a static file, using Last-Modified to avoid redundant downloads.
	/// Returns nil if the file has not changed since the last fetch.
	static func fetchIfModified(fileName: String) async -> [SourceFileEntry]? {
		guard let url = URL(string: baseURL + fileName) else {
			logger.error("Invalid file URL for \(fileName)")
			return nil
		}

		let lastModifiedKey = "SourceFileFetcher.lastModified.\(fileName)"
		let storedLastModified = UserDefaults.standard.string(forKey: lastModifiedKey)

		// HEAD request to check Last-Modified
		var headRequest = URLRequest(url: url)
		headRequest.httpMethod = "HEAD"

		do {
			let (_, headResponse) = try await URLSession.shared.data(for: headRequest)

			guard let httpResponse = headResponse as? HTTPURLResponse,
				  httpResponse.statusCode == 200 else {
				logger.error("HEAD request failed for \(fileName)")
				return nil
			}

			let serverLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")

			if let storedLastModified, let serverLastModified, storedLastModified == serverLastModified {
				logger.info("File \(fileName) not modified, skipping download")
				return nil
			}

			// Download the file
			let (data, getResponse) = try await URLSession.shared.data(from: url)

			guard let getHTTPResponse = getResponse as? HTTPURLResponse,
				  getHTTPResponse.statusCode == 200 else {
				logger.error("GET request failed for \(fileName)")
				return nil
			}

			// Store the Last-Modified header
			if let newLastModified = getHTTPResponse.value(forHTTPHeaderField: "Last-Modified") {
				UserDefaults.standard.set(newLastModified, forKey: lastModifiedKey)
			}

			return parseEntries(from: data, fileName: fileName)
		} catch {
			logger.error("Failed to fetch \(fileName): \(error.localizedDescription)")
			return nil
		}
	}

	/// Force-fetches entries from a static file, ignoring Last-Modified cache.
	static func fetch(fileName: String) async -> [SourceFileEntry]? {
		guard let url = URL(string: baseURL + fileName) else {
			logger.error("Invalid file URL for \(fileName)")
			return nil
		}

		let lastModifiedKey = "SourceFileFetcher.lastModified.\(fileName)"

		do {
			let (data, response) = try await URLSession.shared.data(from: url)

			guard let httpResponse = response as? HTTPURLResponse,
				  httpResponse.statusCode == 200 else {
				logger.error("GET request failed for \(fileName)")
				return nil
			}

			if let newLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified") {
				UserDefaults.standard.set(newLastModified, forKey: lastModifiedKey)
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
			guard let name = item["Name"] as? String,
				  let rssURL = item["RSS URL"] as? String else {
				continue
			}
			let author = item["Author"] as? String
			let myFeedURL = item["My Feed URL"] as? String
			let imageURL = item["Image URL"] as? String
			entries.append(SourceFileEntry(name: name, author: author, rssURL: rssURL, myFeedURL: myFeedURL, imageURL: imageURL))
		}

		logger.info("Parsed \(entries.count) entries from \(fileName)")
		return entries
	}
}
