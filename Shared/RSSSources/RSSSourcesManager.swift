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
	let url: String
	let imageURL: String?
}

enum AddRSSResult {
	case successExisting(summaryURL: String)  // 201 - Feed already exists
	case successNew(summaryURL: String)       // 202 - Feed accepted for processing
	case unauthorized                         // 401
	case badRSS                               // 551
	case wrongFormat                          // 552
	case maxFeeds                             // 553
	case badMessage                           // 554
	case badFeed                              // 555
	case error(String)
}

@MainActor final class RSSSourcesManager {

	static let shared = RSSSourcesManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "RSSSources")

	private let getSourcesURL = URL(string: "https://n8n.nwidynski.com/webhook/get-show-sources")!
	private let addSourceURL = URL(string: "https://n8n.nwidynski.com/webhook/add-show-source")!

	// MARK: - Fetch State

	private(set) var isFetching = false
	private var fetchTask: Task<Void, Never>?

	// MARK: - Stored RSS Sources

	private let rssSourcesKey = "rssSources"

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

		guard let token = bearerToken else {
			Self.logger.error("No bearer token available")
			return
		}

		var request = URLRequest(url: getSourcesURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.httpBody = try? JSONSerialization.data(withJSONObject: ["type": "rss"])

		do {
			let (data, response) = try await URLSession.shared.data(for: request)

			guard let httpResponse = response as? HTTPURLResponse else {
				Self.logger.error("Invalid response type")
				return
			}

			guard httpResponse.statusCode == 200 else {
				Self.logger.error("Unexpected status code: \(httpResponse.statusCode)")
				return
			}

			guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
				  let status = json["status"] as? String,
				  status == "success",
				  let dataArray = json["data"] as? [[String: Any]],
				  let firstItem = dataArray.first,
				  let names = firstItem["name"] as? [String],
				  let urls = firstItem["url"] as? [String] else {
				Self.logger.error("Failed to parse success response")
				return
			}

			let imageRefs = firstItem["image"] as? [String]
			var sources: [RSSSource] = []
			for (index, name) in names.enumerated() where index < urls.count {
				let imageURL = (imageRefs != nil && index < imageRefs!.count) ? imageRefs![index] : nil
				sources.append(RSSSource(name: name, url: urls[index], imageURL: imageURL))
			}

			self.rssSources = sources
			Self.logger.info("Fetched \(sources.count) RSS sources")
		} catch {
			Self.logger.error("Failed to fetch RSS sources: \(error.localizedDescription)")
		}
	}

	func addRSSByName(_ feedName: String) async -> AddRSSResult {
		return await sendAddRSSRequest(link: nil, show: feedName)
	}

	func addRSSByURL(_ rssURL: String) async -> AddRSSResult {
		return await sendAddRSSRequest(link: rssURL, show: nil)
	}

	private func sendAddRSSRequest(link: String?, show: String?) async -> AddRSSResult {
		guard let token = bearerToken else {
			Self.logger.error("No bearer token available")
			return .error("No authentication token")
		}

		var request = URLRequest(url: addSourceURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

		let body: [String: String] = [
			"type": "rss",
			"show": show ?? "",
			"link": link ?? ""
		]

		do {
			request.httpBody = try JSONSerialization.data(withJSONObject: body)
		} catch {
			Self.logger.error("Failed to encode request body")
			return .error("Failed to encode request")
		}

		do {
			let (data, response) = try await URLSession.shared.data(for: request)

			guard let httpResponse = response as? HTTPURLResponse else {
				Self.logger.error("Invalid response type")
				return .error("Invalid response")
			}

			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

			switch httpResponse.statusCode {
			case 201:
				if let json,
				   let status = json["status"] as? String,
				   status == "success",
				   let summaryURL = json["summary_url"] as? String {
					return .successExisting(summaryURL: summaryURL)
				}
				return .error("Failed to parse response")

			case 202:
				if let json,
				   let status = json["status"] as? String,
				   status == "success",
				   let summaryURL = json["summary_url"] as? String {
					return .successNew(summaryURL: summaryURL)
				}
				return .error("Failed to parse response")

			case 401:
				return .unauthorized
			case 551:
				return .badRSS
			case 552:
				return .wrongFormat
			case 553:
				return .maxFeeds
			case 554:
				return .badMessage
			case 555:
				return .badFeed
			default:
				Self.logger.error("Unexpected status code: \(httpResponse.statusCode)")
				return .error("Unexpected error")
			}
		} catch {
			Self.logger.error("Failed to add RSS source: \(error.localizedDescription)")
			return .error(error.localizedDescription)
		}
	}
}
