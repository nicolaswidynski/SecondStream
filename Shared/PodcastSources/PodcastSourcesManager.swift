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

@MainActor final class PodcastSourcesManager {

	static let shared = PodcastSourcesManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PodcastSources")

	private let apiURL = URL(string: "https://n8n.nwidynski.com/webhook/get-podcast-sources")!

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

		var request = URLRequest(url: apiURL)
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
				   let dataArray = json["data"] as? [[String: Any]] {

					var sources: [PodcastSource] = []
					for item in dataArray {
						if let name = item["name"] as? String,
						   let url = item["url"] as? String {
							sources.append(PodcastSource(name: name, rssURL: url))
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
}
