//
//  YoutubeSourcesManager.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-31.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import os.log

struct YoutubeSource: Codable, Hashable {
	let name: String
	let url: String
	let imageURL: String?
}

enum AddYoutubeResult {
	case successExisting(summaryURL: String)  // 201 - Channel already exists, no wait
	case successNew(summaryURL: String)       // 202 - New channel, wait for processing
	case unauthorized                         // 401
	case badRSS                               // 551
	case wrongFormat                          // 552
	case maxChannels                          // 553
	case badMessage                           // 554 - Neither channel nor url set
	case badChannel                           // 555 - Channel not found
	case youtubeRSSNotFound                   // 556 - YouTube channel RSS not found
	case illegalName                          // 557 - Illegal show name
	case unknownTopic                         // 558 - Unknown topic
	case missingInput                         // 559 - No name or URL provided
	case error(String)
}

@MainActor final class YoutubeSourcesManager {

	static let shared = YoutubeSourcesManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "YoutubeSources")

	// Use the same endpoints as podcasts
	private let getSourcesURL = URL(string: "https://n8n.nwidynski.com/webhook/get-show-sources")!
	private let addSourceURL = URL(string: "https://n8n.nwidynski.com/webhook/add-show-source")!

	// MARK: - Fetch State

	private(set) var isFetching = false
	private var fetchTask: Task<Void, Never>?

	// MARK: - Stored YouTube Sources

	private let youtubeSourcesKey = "youtubeSources"

	var youtubeSources: [YoutubeSource] {
		get {
			guard let data = UserDefaults.standard.data(forKey: youtubeSourcesKey),
				  let sources = try? JSONDecoder().decode([YoutubeSource].self, from: data) else {
				return []
			}
			return sources
		}
		set {
			if let data = try? JSONEncoder().encode(newValue) {
				UserDefaults.standard.set(data, forKey: youtubeSourcesKey)
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

	/// Starts fetching youtube sources in the background. Does nothing if already fetching.
	func startFetching() {
		guard !isFetching else {
			return
		}
		fetchTask = Task {
			await fetchYoutubeSources()
		}
	}

	/// Waits for any in-progress fetch to complete, or fetches if not already fetching.
	func waitForFetch() async {
		if let task = fetchTask {
			await task.value
		} else if !isFetching {
			await fetchYoutubeSources()
		}
	}

	/// Always fetches fresh sources, regardless of current state.
	func fetchFresh() async {
		// Cancel any existing fetch task
		fetchTask?.cancel()
		fetchTask = nil
		// Fetch fresh
		await fetchYoutubeSources()
	}

	private func fetchYoutubeSources() async {
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

		// Add type in body
		let body: [String: String] = [
			"type": "yt"
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

					var sources: [YoutubeSource] = []
					for (index, name) in names.enumerated() {
						if index < urls.count {
							let imageURL = (imageRefs != nil && index < imageRefs!.count) ? imageRefs![index] : nil
							sources.append(YoutubeSource(name: name, url: urls[index], imageURL: imageURL))
						}
					}

					self.youtubeSources = sources
					Self.logger.info("Fetched \(sources.count) YouTube sources")
				} else {
					Self.logger.error("Failed to parse success response")
				}
			} else {
				Self.logger.error("Unexpected status code: \(httpResponse.statusCode)")
			}
		} catch {
			Self.logger.error("Failed to fetch YouTube sources: \(error.localizedDescription)")
		}
	}

	/// Adds a YouTube channel by extracting the channel name from a URL.
	/// Returns the summary feed URL on success.
	func addYoutubeByURL(_ youtubeURL: String) async -> AddYoutubeResult {
		let channelName = extractChannelName(from: youtubeURL)
		return await sendAddYoutubeRequest(show: channelName)
	}

	/// Adds a YouTube channel by sending the channel name to the webhook.
	/// Returns the summary feed URL on success.
	func addYoutubeByChannelName(_ channelName: String) async -> AddYoutubeResult {
		let name = channelName.replacingOccurrences(of: "@", with: "")
		return await sendAddYoutubeRequest(show: name)
	}

	/// Extracts the channel name from a YouTube URL, stripping any leading @.
	private func extractChannelName(from urlString: String) -> String {
		guard let url = URL(string: urlString),
			  let lastComponent = url.pathComponents.last,
			  lastComponent != "/" else {
			return urlString.replacingOccurrences(of: "@", with: "")
		}
		return lastComponent.replacingOccurrences(of: "@", with: "")
	}

	private func sendAddYoutubeRequest(show: String) async -> AddYoutubeResult {
		guard let token = bearerToken else {
			Self.logger.error("No bearer token available")
			return .error("No authentication token")
		}

		var request = URLRequest(url: addSourceURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

		let body: [String: String] = [
			"type": "yt",
			"show": show,
			"link": ""
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
				// Success - channel already exists, no wait needed
				if let json,
				   let status = json["status"] as? String,
				   status == "success",
				   let summaryURL = json["summary_url"] as? String {
					Self.logger.info("YouTube channel already exists")
					return .successExisting(summaryURL: summaryURL)
				}
				Self.logger.error("Failed to parse 201 response")
				return .error("Failed to parse response")

			case 202:
				// Success - new channel, wait for processing
				if let json,
				   let status = json["status"] as? String,
				   status == "success",
				   let summaryURL = json["summary_url"] as? String {
					Self.logger.info("New YouTube channel added, processing required")
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
				Self.logger.error("Maximum number of channels reached")
				return .maxChannels

			case 554:
				Self.logger.error("Bad request - neither channel nor url set")
				return .badMessage

			case 555:
				Self.logger.error("Channel not found")
				return .badChannel

			case 556:
				Self.logger.error("YouTube channel RSS not found")
				return .youtubeRSSNotFound

			case 557:
				Self.logger.error("Illegal show name")
				return .illegalName

			case 558:
				Self.logger.error("Unknown topic")
				return .unknownTopic

			case 559:
				Self.logger.error("No name or URL provided")
				return .missingInput

			default:
				Self.logger.error("Unexpected status code: \(httpResponse.statusCode)")
				return .error("Unexpected error")
			}
		} catch {
			Self.logger.error("Failed to add YouTube channel: \(error.localizedDescription)")
			return .error(error.localizedDescription)
		}
	}
}
