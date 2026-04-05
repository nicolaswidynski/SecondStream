//
//  FeedStatsManager.swift
//  NetNewsWire
//
//  Created by Claude on 2026-03-14.
//  Copyright © 2026 STDN. All rights reserved.
//

import Foundation
import Account
import RSWeb
import os.log

/// Tracks feed add/delete events and reports them to the backend via a single
/// unified endpoint (`all-feed-requests`).
///
/// Every call to that endpoint includes a `feeds_for_update` snapshot of the
/// user's current subscriptions, and every successful response returns
/// `nb_credits` so credits are always kept in sync without a separate fetch.
@MainActor final class FeedStatsManager {

	static let shared = FeedStatsManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedStats")

	private let allFeedRequestsURL = URL(string: "https://n8n.nwidynski.com/webhook/all-feed-requests")!
	private let outboxKey = "feedStats_deletionOutbox"
	private let creditsKey = "feedStats_cachedCredits"
	private var isDrainingOutbox = false
	/// Set by `queueDelete` so that `childrenDidChange` only drains after an actual delete,
	/// not after every structural change (e.g. feed adds).
	private var pendingDrain = false

	/// Minimum time between foreground-triggered credit refreshes.
	private let foregroundFetchInterval: TimeInterval = 60
	private var lastForegroundFetchDate: Date?

	private init() {
		// Drain the outbox whenever the account structure changes (feeds added/removed).
		// Account posts .ChildrenDidChange after removeFeed/addFeed completes, so
		// flattenedFeeds() is already up-to-date when we read it in buildFeedsForUpdate.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(childrenDidChange(_:)),
			name: .ChildrenDidChange,
			object: nil
		)
	}

	@objc private nonisolated func childrenDidChange(_ note: Notification) {
		Task { @MainActor in
			guard FeedStatsManager.shared.pendingDrain else { return }
			FeedStatsManager.shared.pendingDrain = false
			await FeedStatsManager.shared.drainOutbox()
		}
	}

	// MARK: - Outbox record

	struct OutboxRecord: Codable, Equatable {
		let appleUserID: String
		let type: String
		let operation: String
		let show: String
		let author: String
		let queuedAt: Date?
	}

	// MARK: - Error helpers

	/// Extracts `nb_credits` from a parsed JSON dictionary, accepting both
	/// a JSON string (`"42"`) and a JSON integer (`42`).
	static func parseCredits(_ json: [String: Any]) -> Int? {
		if let intValue = json["nb_credits"] as? Int {
			return intValue
		}
		if let strValue = json["nb_credits"] as? String {
			return Int(strValue)
		}
		return nil
	}

	/// Extracts the `"message"` field from a JSON webhook error body.
	/// Falls back to the raw UTF-8 body if the field is absent or unparseable.
	static func webhookMessage(from data: Data) -> String {
		if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		   let message = json["message"] as? String {
			return message
		}
		return String(data: data, encoding: .utf8) ?? "Unknown error"
	}

	// MARK: - Bearer token

	private var bearerToken: String? {
		guard let tokenURL = Bundle.main.url(forResource: "podcast_token", withExtension: "txt"),
			  let token = try? String(contentsOf: tokenURL, encoding: .utf8) else {
			Self.logger.error("Failed to load bearer token from file")
			return nil
		}
		return token.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: - Type mapping

	private func typeString(for category: FeedCategory) -> String {
		switch category {
		case .podcast: return "pod"
		case .youtube: return "yt"
		case .rss: return "rss"
		case .news: return "topics"
		}
	}

	// MARK: - Credits

	/// Cached credit count. Nil means never fetched. Observers watch `.creditsDidUpdate`.
	var cachedCredits: Int? {
		get { UserDefaults.standard.object(forKey: creditsKey) as? Int }
		set {
			if let v = newValue {
				Self.logger.info("cachedCredits → \(v, privacy: .public)")
				UserDefaults.standard.set(v, forKey: creditsKey)
			} else {
				Self.logger.info("cachedCredits → nil (cleared)")
				UserDefaults.standard.removeObject(forKey: creditsKey)
			}
			NotificationCenter.default.post(name: .creditsDidUpdate, object: nil)
		}
	}

	// MARK: - Feeds payload

	/// Builds the `feeds_for_update` dictionary that must accompany every request
	/// to `all-feed-requests`. Uses already-cached free source lists from the
	/// source managers — no extra network calls needed.
	func buildFeedsForUpdate() -> [String: Any] {
		guard let account = AccountManager.shared.activeAccounts.first else {
			return [:]
		}

		let allFeeds = account.flattenedFeeds()

		var podSources: [String] = []
		var ytSources: [String] = []
		var topicSources: [String] = []
		var rssCount = 0

		for feed in allFeeds {
			switch feed.feedCategory {
			case .podcast: podSources.append(feed.nameForDisplay)
			case .youtube: ytSources.append(feed.nameForDisplay)
			case .news:    topicSources.append(feed.nameForDisplay)
			case .rss:     rssCount += 1
			}
		}

		// Use the already-cached free source lists — no network call needed
		let podFreeNames = Set(PodcastSourcesManager.shared.podcastSources.map { $0.name.lowercased() })
		let ytFreeNames  = Set(YoutubeSourcesManager.shared.youtubeSources.map { $0.name.lowercased() })

		let podFreeCount = podSources.filter { podFreeNames.contains($0.lowercased()) }.count
		let ytFreeCount  = ytSources.filter  { ytFreeNames.contains($0.lowercased()) }.count

		return [
			"pod": [
				"count":      String(podSources.count),
				"count_free": String(podFreeCount),
				"sources":    podSources
			],
			"yt": [
				"count":      String(ytSources.count),
				"count_free": String(ytFreeCount),
				"sources":    ytSources
			],
			"topics": [
				"count":      String(topicSources.count),
				"count_free": String(topicSources.count),
				"sources":    topicSources
			],
			"rss": [
				"count":      String(rssCount),
				"count_free": String(rssCount)
			]
		]
	}

	// MARK: - Core request

	/// POSTs to `all-feed-requests` and returns the `nb_credits` value from the
	/// response, or `nil` on any failure.
	///
	/// Always includes `feeds_for_update` as required by the API contract.
	/// Pass `type`, `show`, and `author` for `add-show` operations.
	func sendRequest(
		operation: String,
		type: String? = nil,
		show: String? = nil,
		author: String? = nil
	) async -> Int? {
		guard let token = bearerToken else {
			Self.logger.error("sendRequest: no bearer token")
			return nil
		}
		let appleUserID = AuthManager.shared.appleUserID ?? ""
		guard !appleUserID.isEmpty else {
			return nil
		}

		let feedsForUpdate = buildFeedsForUpdate()
		let requestID = UUID().uuidString

		var body: [String: Any] = [
			"apple_user_id":    appleUserID,
			"request_id":       requestID,
			"operation":        operation,
			"feeds_for_update": feedsForUpdate
		]
		if let type   { body["type"]   = type }
		if let show   { body["show"]   = show }
		if let author { body["author"] = author }

		var request = URLRequest(url: allFeedRequestsURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

		do {
			request.httpBody = try JSONSerialization.data(withJSONObject: body)
			let (data, response) = try await URLSession.shared.data(for: request)

			guard let httpResponse = response as? HTTPURLResponse else {
				Self.logger.error("all-feed-requests \(operation) — non-HTTP response")
				return nil
			}
			guard (200...299).contains(httpResponse.statusCode) else {
				let rawBody = String(data: data, encoding: .utf8) ?? "(empty)"
				Self.logger.error("all-feed-requests \(operation) failed [\(httpResponse.statusCode, privacy: .public)]: \(rawBody, privacy: .public)")
				return nil
			}

			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
			if let echoed = json?["request_id"] as? String, echoed != requestID {
				Self.logger.warning("request_id mismatch: sent \(requestID), received \(echoed)")
			}
			if let credits = json.flatMap({ Self.parseCredits($0) }) {
				Self.logger.info("all-feed-requests \(operation) ok — nb_credits: \(credits, privacy: .public)")
				return credits
			}
			let rawForLog = String(data: data, encoding: .utf8) ?? "(empty)"
			Self.logger.info("all-feed-requests \(operation) ok (no nb_credits) body: \(rawForLog, privacy: .public)")
			return nil
		} catch {
			Self.logger.error("all-feed-requests \(operation) error: \(error.localizedDescription)")
			return nil
		}
	}

	// MARK: - Credits

	/// Sends `update-user-stats` and caches the returned credit count.
	/// Best-effort — errors are only logged.
	func fetchCredits() async {
		if let credits = await sendRequest(operation: "update-user-stats") {
			cachedCredits = credits
		}
	}

	/// Sends `update-user-stats` only if at least `foregroundFetchInterval` seconds
	/// have elapsed since the last foreground fetch. Call on every app-foreground event.
	func fetchCreditsIfNeeded() async {
		let now = Date()
		if let last = lastForegroundFetchDate, now.timeIntervalSince(last) < foregroundFetchInterval {
			return
		}
		lastForegroundFetchDate = now
		await fetchCredits()
	}

	// MARK: - Update stats

	/// Sends a full subscription snapshot via `update-user-stats` and caches the
	/// returned credit count. Returns `true` on success.
	@discardableResult
	func reportUpdate() async -> Bool {
		if let credits = await sendRequest(operation: "update-user-stats") {
			cachedCredits = credits
			return true
		}
		return false
	}

	// MARK: - Delete outbox

	/// Queues a delete event and attempts to drain the outbox immediately.
	/// The outbox record acts as a "pending update" marker; when drained, the
	/// current subscription state is sent rather than a per-feed delete operation.
	func queueDelete(type: FeedCategory, name: String, author: String?) {
		let appleUserID = AuthManager.shared.appleUserID ?? ""
		let record = OutboxRecord(
			appleUserID: appleUserID,
			type: typeString(for: type),
			operation: "del",
			show: name,
			author: author ?? "",
			queuedAt: Date()
		)

		var outbox = loadOutbox()
		outbox.append(record)
		saveOutbox(outbox)
		pendingDrain = true

		Self.logger.info("Queued delete for \(name) — will drain on next ChildrenDidChange")
	}

	/// Attempts to send a stats update for all queued delete events.
	/// Sends a single `update-user-stats` call (current subscription snapshot)
	/// and clears all pending records on success.
	func drainOutbox() async {
		guard !isDrainingOutbox else {
			return
		}
		isDrainingOutbox = true
		defer { isDrainingOutbox = false }

		let outbox = pruneStaleOutboxRecords()
		guard !outbox.isEmpty else {
			return
		}
		guard NetworkMonitor.shared.isConnected else {
			Self.logger.info("Outbox drain skipped — no network (\(outbox.count) pending)")
			return
		}

		if let credits = await sendRequest(operation: "update-user-stats") {
			cachedCredits = credits
			saveOutbox([])
			Self.logger.info("Drained \(outbox.count) pending delete(s)")
		}
	}

	// MARK: - UserDefaults persistence

	private func loadOutbox() -> [OutboxRecord] {
		guard let data = UserDefaults.standard.data(forKey: outboxKey),
			  let records = try? JSONDecoder().decode([OutboxRecord].self, from: data) else {
			return []
		}
		let now = Date()
		let migratedRecords = records.map { record in
			guard record.queuedAt == nil else {
				return record
			}
			return OutboxRecord(
				appleUserID: record.appleUserID,
				type: record.type,
				operation: record.operation,
				show: record.show,
				author: record.author,
				queuedAt: now
			)
		}
		if migratedRecords != records {
			saveOutbox(migratedRecords)
		}
		return migratedRecords
	}

	private func saveOutbox(_ records: [OutboxRecord]) {
		guard let data = try? JSONEncoder().encode(records) else {
			return
		}
		UserDefaults.standard.set(data, forKey: outboxKey)
	}

	private func pruneStaleOutboxRecords() -> [OutboxRecord] {
		let oneWeekInterval: TimeInterval = 7 * 24 * 60 * 60
		let records = loadOutbox()
		let now = Date()
		let freshRecords = records.filter { record in
			guard let queuedAt = record.queuedAt else {
				return true
			}
			return now.timeIntervalSince(queuedAt) <= oneWeekInterval
		}
		let staleCount = records.count - freshRecords.count
		if staleCount > 0 {
			Self.logger.info("Dropped \(staleCount) stale feed stats delete events from outbox")
			saveOutbox(freshRecords)
		}
		return freshRecords
	}
}

// MARK: - FeedStatsError

enum FeedStatsError: LocalizedError {
	case missingToken
	case invalidResponse
	case serverError(statusCode: Int, body: String)

	var errorDescription: String? {
		switch self {
		case .missingToken:
			return "Authentication token not found."
		case .invalidResponse:
			return "Received an invalid response from the server."
		case .serverError(_, let body):
			return body
		}
	}
}

// MARK: - Notification names

extension Notification.Name {
	static let creditsDidUpdate = Notification.Name("com.secondstream.creditsDidUpdate")
}
