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
	let url: String
	let imageURL: String?
}

enum AddNewsResult {
	case successExisting(summaryURL: String)  // 201 - Topic already exists, no wait
	case successNew(summaryURL: String)       // 202 - New topic, wait for processing
	case unauthorized                         // 401
	case badRSS                               // 551
	case wrongFormat                          // 552
	case maxTopics                            // 553
	case badMessage                           // 554 - Neither topic nor url set
	case badTopic                             // 555 - Topic not found
	case error(String)
}

@MainActor final class NewsSourcesManager {

	static let shared = NewsSourcesManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NewsSources")

	private let getSourcesURL = URL(string: "https://n8n.nwidynski.com/webhook/get-show-sources")!
	private let addSourceURL = URL(string: "https://n8n.nwidynski.com/webhook/add-show-source")!

	// MARK: - Server Error

	private(set) var lastServerMessage: String?

	// MARK: - Fetch State

	private(set) var isFetching = false
	private var fetchTask: Task<Void, Never>?

	// MARK: - Stored News Sources

	private let newsSourcesKey = "newsSources"

	var newsSources: [NewsSource] {
		get {
			guard let data = UserDefaults.standard.data(forKey: newsSourcesKey),
				  let sources = try? JSONDecoder().decode([NewsSource].self, from: data) else {
				return []
			}
			return sources
		}
		set {
			if let data = try? JSONEncoder().encode(newValue) {
				UserDefaults.standard.set(data, forKey: newsSourcesKey)
			}
		}
	}

	// MARK: - Token

	private var bearerToken: String? {
		// Use the same token as podcasts
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
		await fetchNewsSources()
	}

	private func fetchNewsSources() async {
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

		// Use type "topics" for news
		let body: [String: String] = [
			"type": "topics"
		]
		request.httpBody = try? JSONSerialization.data(withJSONObject: body)

		do {
			let (data, response) = try await URLSession.shared.data(for: request)

			guard let httpResponse = response as? HTTPURLResponse else {
				Self.logger.error("Invalid response type")
				return
			}

			if httpResponse.statusCode == 200 {
				// Success
				if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
				   let status = json["status"] as? String,
				   status == "success",
				   let dataArray = json["data"] as? [[String: Any]],
				   let firstItem = dataArray.first,
				   let names = firstItem["name"] as? [String],
				   let urls = firstItem["url"] as? [String] {

					let imageRefs = firstItem["image"] as? [String]

					var sources: [NewsSource] = []
					for (index, name) in names.enumerated() {
						if index < urls.count {
							let imageURL = (imageRefs != nil && index < imageRefs!.count) ? imageRefs![index] : nil
							sources.append(NewsSource(name: name, url: urls[index], imageURL: imageURL))
						}
					}

					self.newsSources = sources
					Self.logger.info("Fetched \(sources.count) news sources")
				} else {
					Self.logger.error("Failed to parse success response")
				}
			} else {
				Self.logger.error("Unexpected status code: \(httpResponse.statusCode)")
			}
		} catch {
			Self.logger.error("Failed to fetch news sources: \(error.localizedDescription)")
		}
	}

	/// Adds a news topic by sending the topic name to the webhook.
	/// Returns the summary feed URL on success.
	func addNewsByTopicName(_ topicName: String) async -> AddNewsResult {
		return await sendAddNewsRequest(link: nil, show: topicName)
	}

	/// Adds a news source by sending the URL to the webhook.
	/// Returns the summary feed URL on success.
	func addNewsByURL(_ newsURL: String) async -> AddNewsResult {
		return await sendAddNewsRequest(link: newsURL, show: nil)
	}

	private func sendAddNewsRequest(link: String?, show: String?) async -> AddNewsResult {
		guard let token = bearerToken else {
			Self.logger.error("No bearer token available")
			return .error("No authentication token")
		}

		var request = URLRequest(url: addSourceURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

		// Build body with type "topics", show, and link (use empty strings for nil values)
		let body: [String: String] = [
			"type": "topics",
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
			lastServerMessage = json?["message"] as? String

			switch httpResponse.statusCode {
			case 201:
				// Success - topic already exists, no wait needed
				if let json,
				   let status = json["status"] as? String,
				   status == "success",
				   let summaryURL = json["summary_url"] as? String {
					Self.logger.info("News topic already exists")
					return .successExisting(summaryURL: summaryURL)
				}
				Self.logger.error("Failed to parse 201 response")
				return .error("Failed to parse response")

			case 202:
				// Success - new topic, wait for processing
				if let json,
				   let status = json["status"] as? String,
				   status == "success",
				   let summaryURL = json["summary_url"] as? String {
					Self.logger.info("New news topic added, processing required")
					return .successNew(summaryURL: summaryURL)
				}
				Self.logger.error("Failed to parse 202 response")
				return .error("Failed to parse response")

			case 401:
				Self.logger.error("Unauthorized - wrong credentials")
				return .unauthorized

			case 551:
				Self.logger.error("RSS not found")
				return .badRSS

			case 552:
				Self.logger.error("RSS format not supported")
				return .wrongFormat

			case 553:
				Self.logger.error("Maximum number of topics reached")
				return .maxTopics

			case 554:
				Self.logger.error("Bad request - neither topic nor url set")
				return .badMessage

			case 555:
				Self.logger.error("Topic not found")
				return .badTopic

			default:
				Self.logger.error("Unexpected status code: \(httpResponse.statusCode)")
				return .error("Unexpected error")
			}
		} catch {
			Self.logger.error("Failed to add news topic: \(error.localizedDescription)")
			return .error(error.localizedDescription)
		}
	}
}
