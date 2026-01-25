//
//  PodcastSourcesManager.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-22.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import os.log

struct PodcastSource: Codable {
	let name: String
	let rssURL: String
}

enum AddPodcastResult {
	case successExisting(summaryURL: String)  // 201 - Podcast already exists, no wait
	case successNew(summaryURL: String)       // 202 - New podcast, wait ~15 minutes
	case unauthorized                         // 401
	case badRSS                               // 551
	case wrongFormat                          // 552
	case maxPodcasts                          // 553
	case badMessage                           // 554 - Neither podcast nor rss_url set
	case badPodcast                           // 555 - Podcast not found
	case error(String)
}

@MainActor final class PodcastSourcesManager {

	static let shared = PodcastSourcesManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PodcastSources")

	private let getSourcesURL = URL(string: "https://n8n.nwidynski.com/webhook/get-podcast-sources")!
	private let addSourceURL = URL(string: "https://n8n.nwidynski.com/webhook/add-podcast-source")!

	// MARK: - Fetch State

	private(set) var isFetching = false
	private var fetchTask: Task<Void, Never>?

	// MARK: - Stored Podcast Sources

	private let podcastSourcesKey = "podcastSources"

	var podcastSources: [PodcastSource] {
		get {
			guard let data = UserDefaults.standard.data(forKey: podcastSourcesKey),
				  let sources = try? JSONDecoder().decode([PodcastSource].self, from: data) else {
				return []
			}
			return sources
		}
		set {
			if let data = try? JSONEncoder().encode(newValue) {
				UserDefaults.standard.set(data, forKey: podcastSourcesKey)
			}
		}
	}

	// MARK: - Token

	private var bearerToken: String? {
		guard let tokenURL = Bundle.main.url(forResource: "podcast_token", withExtension: "txt"),
			  let token = try? String(contentsOf: tokenURL, encoding: .utf8) else {
			Self.logger.error("Failed to load podcast token from file")
			return nil
		}
		return token.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: - API

	/// Starts fetching podcast sources in the background. Does nothing if already fetching.
	func startFetching() {
		guard !isFetching else {
			return
		}
		fetchTask = Task {
			await fetchPodcastSources()
		}
	}

	/// Waits for any in-progress fetch to complete, or fetches if not already fetching.
	func waitForFetch() async {
		if let task = fetchTask {
			await task.value
		} else if !isFetching {
			await fetchPodcastSources()
		}
	}

	private func fetchPodcastSources() async {
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
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")

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

					var sources: [PodcastSource] = []
					for (index, name) in names.enumerated() {
						if index < urls.count {
							sources.append(PodcastSource(name: name, rssURL: urls[index]))
						}
					}

					self.podcastSources = sources
					Self.logger.info("Fetched \(sources.count) podcast sources")
				} else {
					Self.logger.error("Failed to parse success response")
				}
			} else if httpResponse.statusCode == 422 {
				// Bad RSS error
				if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
				   let status = json["status"] as? String,
				   let message = json["message"] as? String {
					Self.logger.error("API error: status=\(status), message=\(message)")
				} else {
					Self.logger.error("API returned 422 but could not parse error response")
				}
			} else {
				Self.logger.error("Unexpected status code: \(httpResponse.statusCode)")
			}
		} catch {
			Self.logger.error("Failed to fetch podcast sources: \(error.localizedDescription)")
		}
	}

	/// Adds a podcast source by sending the RSS URL to the webhook.
	/// Returns the summary feed URL on success.
	func addPodcastSource(rssURL: String) async -> AddPodcastResult {
		return await sendAddPodcastRequest(body: ["rss_url": rssURL])
	}

	/// Adds a podcast source by sending the podcast name to the webhook.
	/// Returns the summary feed URL on success.
	func addPodcastByName(_ podcastName: String) async -> AddPodcastResult {
		return await sendAddPodcastRequest(body: ["podcast": podcastName])
	}

	private func sendAddPodcastRequest(body: [String: String]) async -> AddPodcastResult {
		guard let token = bearerToken else {
			Self.logger.error("No bearer token available")
			return .error("No authentication token")
		}

		var request = URLRequest(url: addSourceURL)
		request.httpMethod = "POST"
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")

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
				// Success - podcast already exists, no wait needed
				if let json,
				   let status = json["status"] as? String,
				   status == "success",
				   let summaryURL = json["summary_url"] as? String {
					Self.logger.info("Podcast already exists")
					return .successExisting(summaryURL: summaryURL)
				}
				Self.logger.error("Failed to parse 201 response")
				return .error("Failed to parse response")

			case 202:
				// Success - new podcast, wait ~15 minutes
				if let json,
				   let status = json["status"] as? String,
				   status == "success",
				   let summaryURL = json["summary_url"] as? String {
					Self.logger.info("New podcast added, processing required")
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
				Self.logger.error("Maximum number of podcasts reached")
				return .maxPodcasts

			case 554:
				Self.logger.error("Bad request - neither podcast nor rss_url set")
				return .badMessage

			case 555:
				Self.logger.error("Podcast not found")
				return .badPodcast

			default:
				Self.logger.error("Unexpected status code: \(httpResponse.statusCode)")
				return .error("Unexpected error")
			}
		} catch {
			Self.logger.error("Failed to add podcast source: \(error.localizedDescription)")
			return .error(error.localizedDescription)
		}
	}
}
