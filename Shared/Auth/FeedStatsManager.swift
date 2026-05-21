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

	private let client = SecondStreamAPIClient.shared
	private let outboxKey = "feedStats_deletionOutbox"
	private let creditsKey = "feedStats_cachedCredits"
	/// Stable serialization of the last `feeds_for_update` payload that received HTTP 2xx.
	/// Used to skip redundant `update-user-stats` calls when nothing has changed.
	private var lastSentFeedsPayload: Data?
	private var isDrainingOutbox = false
	/// Set by `queueDelete` so that `childrenDidChange` only drains after an actual delete,
	/// not after every structural change (e.g. feed adds).
	private var pendingDrain = false

	/// Minimum time between foreground-triggered credit refreshes.
	private let foregroundFetchInterval: TimeInterval = 60
	private var lastForegroundFetchDate: Date?

	/// Podcast feed names (lowercased) the server classified as paid.
	/// Non-nil only after a response that included `stats_pod.sub_list`.
	private(set) var cachedPaidPodNames: Set<String>? = nil
	/// YouTube feed names (lowercased) the server classified as paid.
	/// Non-nil only after a response that included `stats_yt.sub_list`.
	private(set) var cachedPaidYTNames: Set<String>? = nil

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

	// MARK: - Type mapping

	private func typeString(for category: FeedCategory) -> String {
		switch category {
		case .podcast: return "pod"
		case .youtube: return "yt"
		case .rss: return "rss"
		case .news: return "topics"
		}
	}

	// MARK: - Get user feeds

	/// POSTs `get-user-feeds` and returns the user's server-side subscriptions grouped by category,
	/// plus bookmark `uniqueID`s to restore after feeds are re-added.
	///
	/// - Returns: `(feeds: [FeedCategory: [String]], bookmarkKeys: [String])`
	///   where feeds maps each category to its list of URLs (pod/yt/topics use summary URLs,
	///   rss uses direct feed URLs) and bookmarkKeys are the `id_entry` values to re-star.
	/// - Throws: `FeedStatsError` on network failure, bad status, or a server-level error.
	func getUserFeeds() async throws -> (feeds: [FeedCategory: [String]], bookmarkKeys: [String]) {
		let appleUserID = AuthManager.shared.appleUserID ?? ""
		guard !appleUserID.isEmpty else {
			throw FeedStatsError.invalidResponse
		}

		let (data, statusCode): (Data, Int)
		do {
			(data, statusCode) = try await client.post(to: .allFeedRequests, body: [
				"operation":     "get-user-feeds",
				"apple_user_id": appleUserID,
				"request_id":    UUID().uuidString
			])
		} catch {
			throw FeedStatsError.serverError(statusCode: 0, body: error.localizedDescription)
		}
		let rawResponse = String(data: data, encoding: .utf8) ?? "<binary>"
		Self.logger.debug("get-user-feeds HTTP \(statusCode, privacy: .public) — \(rawResponse, privacy: .public)")

		let decoded = try JSONDecoder().decode(GetUserFeedsResponse.self, from: data)

		guard statusCode == 200 else {
			let message = decoded.message ?? "An unknown server error occurred (HTTP \(statusCode))."
			Self.logger.error("get-user-feeds failed: \(message, privacy: .public)")
			throw FeedStatsError.serverError(statusCode: statusCode, body: message)
		}

		func parseList(_ raw: String?) -> [String] {
			guard let raw, !raw.isEmpty else { return [] }
			return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
		}

		let feeds: [FeedCategory: [String]] = [
			.podcast: parseList(decoded.summaryURLsPod),
			.youtube:  parseList(decoded.summaryURLsYT),
			.news:     parseList(decoded.summaryURLsTopics),
			.rss:      parseList(decoded.summaryURLsRSS),
		]
		let bookmarkKeys = parseList(decoded.bookmarks)
		Self.logger.debug("get-user-feeds parsed — pod: \(feeds[.podcast]?.count ?? 0, privacy: .public), yt: \(feeds[.youtube]?.count ?? 0, privacy: .public), topics: \(feeds[.news]?.count ?? 0, privacy: .public), rss: \(feeds[.rss]?.count ?? 0, privacy: .public), bookmarks: \(bookmarkKeys.count, privacy: .public)")
		return (feeds, bookmarkKeys)
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

	// MARK: - Paid feed classification

	/// Parses paid feed names from `stats_pod.sub_list` and `stats_yt.sub_list`
	/// in a server response dictionary, caching names where `is_free == "NO"`.
	private func parsePaidFeedNames(from json: [String: Any]?) {
		guard let json else { return }
		for (key, category) in [("stats_pod", "pod"), ("stats_yt", "yt")] {
			guard let section = json[key] as? [String: Any],
				  let subList = section["sub_list"] as? [[String: Any]] else { continue }
			var paid = Set<String>()
			for entry in subList {
				if let name = entry["name"] as? String, (entry["is_free"] as? String) == "NO" {
					paid.insert(name.lowercased())
				}
			}
			if category == "pod" {
				Self.logger.info("cachedPaidPodNames updated: \(paid, privacy: .public)")
				cachedPaidPodNames = paid
			} else {
				Self.logger.info("cachedPaidYTNames updated: \(paid, privacy: .public)")
				cachedPaidYTNames = paid
			}
		}
	}

	/// Returns Feed objects the server (or local catalog as fallback) has classified as paid.
	/// Server classification is used per-category when available; falls back to local catalog
	/// for categories not yet represented in a server response.
	func paidFeeds() -> [Feed] {
		let podFreeNames = Set(MediaSourcesManager.podcast.topSources.map { $0.name.lowercased() })
		let ytFreeNames  = Set(MediaSourcesManager.youtube.topSources.map { $0.name.lowercased() })

		var result: [Feed] = []
		for account in AccountManager.shared.activeAccounts {
			for feed in account.flattenedFeeds() {
				let nameLower = feed.nameForDisplay.lowercased()
				let isPaid: Bool
				switch feed.feedCategory {
				case .podcast:
					if let serverNames = cachedPaidPodNames {
						isPaid = serverNames.contains(nameLower)
					} else {
						isPaid = !podFreeNames.contains(nameLower)
					}
				case .youtube:
					if let serverNames = cachedPaidYTNames {
						isPaid = serverNames.contains(nameLower)
					} else {
						isPaid = !ytFreeNames.contains(nameLower)
					}
				default:
					continue
				}
				if isPaid { result.append(feed) }
			}
		}
		return result.sorted { $0.nameForDisplay < $1.nameForDisplay }
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
		var rssSources: [String] = []

		for feed in allFeeds {
			switch feed.feedCategory {
			case .podcast: podSources.append(feed.nameForDisplay)
			case .youtube: ytSources.append(feed.nameForDisplay)
			case .news:    topicSources.append(feed.nameForDisplay)
			case .rss:     rssSources.append(feed.url)
			}
		}

		// Use the already-cached free source lists — no network call needed
		let podFreeNames = Set(MediaSourcesManager.podcast.topSources.map { $0.name.lowercased() })
		let ytFreeNames  = Set(MediaSourcesManager.youtube.topSources.map { $0.name.lowercased() })

		let podFreeCount = podSources.filter { podFreeNames.contains($0.lowercased()) }.count
		let ytFreeCount  = ytSources.filter  { ytFreeNames.contains($0.lowercased()) }.count

		// Collect uniqueIDs (id_entry) of starred non-RSS articles for bookmark sync
		let rssFeedIDs = Set(allFeeds.filter { $0.feedCategory == .rss }.map { $0.feedID })
		let starredArticles = (try? account.fetchArticles(.starred(nil))) ?? []
		let bookmarkKeys = starredArticles
			.filter { !rssFeedIDs.contains($0.feedID) }
			.map { $0.uniqueID }

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
				"count":      String(rssSources.count),
				"count_free": String(rssSources.count),
				"sources":    rssSources
			],
			"bookmarks": bookmarkKeys
		]
	}

	// MARK: - Core request

	/// POSTs to `all-feed-requests` and returns the `nb_credits` value from the
	/// response, or `nil` on any failure.
	///
	/// Includes `feeds_for_update` only for `update-user-stats`.
	/// Pass `type`, `show`, and `author` for `del-show` operations.
	func sendRequest(
		operation: String,
		type: String? = nil,
		show: String? = nil,
		author: String? = nil
	) async -> Int? {
		let appleUserID = AuthManager.shared.appleUserID ?? ""
		guard !appleUserID.isEmpty else { return nil }

		let requestID = UUID().uuidString
		var body: [String: Any] = [
			"apple_user_id": appleUserID,
			"request_id":    requestID,
			"operation":     operation,
		]
		var feedsPayloadData: Data?
		if operation == "update-user-stats" {
			let feeds = buildFeedsForUpdate()
			let data = try? JSONSerialization.data(withJSONObject: feeds, options: .sortedKeys)
			if let data, data == lastSentFeedsPayload {
				Self.logger.info("update-user-stats skipped — payload unchanged since last successful call")
				return cachedCredits
			}
			feedsPayloadData = data
			body["feeds_for_update"] = feeds
		}
		if let type   { body["type"]   = type }
		if let show   { body["show"]   = show }
		if let author { body["author"] = author }

		do {
			let (data, statusCode) = try await client.post(to: .allFeedRequests, body: body)
			guard (200...299).contains(statusCode) else {
				let rawBody = String(data: data, encoding: .utf8) ?? "(empty)"
				Self.logger.error("all-feed-requests \(operation) failed [\(statusCode, privacy: .public)]: \(rawBody, privacy: .public)")
				return nil
			}
			if let feedsPayloadData {
				lastSentFeedsPayload = feedsPayloadData
			}
			let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
				?? (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first
			if let echoed = json?["request_id"] as? String, echoed != requestID {
				Self.logger.warning("request_id mismatch: sent \(requestID), received \(echoed)")
			}
			if let credits = json.flatMap({ Self.parseCredits($0) }) {
				Self.logger.info("all-feed-requests \(operation) ok — nb_credits: \(credits, privacy: .public)")
				parsePaidFeedNames(from: json)
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

	/// Suspends until the next `creditsDidUpdate` notification fires, or `timeout` seconds elapse.
	/// Use this after triggering a server operation that will update credits asynchronously.
	func waitForNextCreditsUpdate(timeout: TimeInterval = 3) async {
		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			let box = ContinuationBox(continuation)
			let observer = NotificationCenter.default.addObserver(
				forName: .creditsDidUpdate,
				object: nil,
				queue: .main
			) { _ in box.resume() }
			Task { @MainActor in
				try? await Task.sleep(for: .seconds(timeout))
				NotificationCenter.default.removeObserver(observer)
				box.resume()
			}
		}
	}

	/// Sends `update-user-stats` and caches the returned credit count.
	/// Best-effort — errors are only logged.
	func fetchCredits() async {
		if let credits = await sendRequest(operation: "update-user-stats") {
			cachedCredits = credits
		}
	}

	/// Sends `update-user-stats` only if at least `foregroundFetchInterval` seconds
	/// have elapsed since the last foreground fetch. Call on every app-foreground event.
	///
	/// Ordering guarantee: `lastForegroundFetchDate` is set before the async network
	/// call so that a concurrent invocation (e.g. a background→foreground transition
	/// while an existing call is in-flight) returns early instead of making a second
	/// redundant request.
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

	/// Attempts to send a `del-show` for each queued delete event.
	/// Clears each record from the outbox on success.
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

		var remaining = outbox
		for record in outbox {
			let credits = await sendRequest(
				operation: "del-show",
				type: record.type,
				show: record.show,
				author: record.author.isEmpty ? nil : record.author
			)
			if let credits { cachedCredits = credits }
			remaining.removeFirst()
			saveOutbox(remaining)
			Self.logger.info("del-show sent for \(record.show) — \(remaining.count) remaining")
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

// MARK: - ContinuationBox

/// A reference-type wrapper around a `CheckedContinuation` so it can be
/// shared across closures without Sendable complaints. `resume()` is
/// idempotent — only the first call has any effect.
private final class ContinuationBox: @unchecked Sendable {
	private var continuation: CheckedContinuation<Void, Never>?
	init(_ continuation: CheckedContinuation<Void, Never>) {
		self.continuation = continuation
	}
	func resume() {
		continuation?.resume()
		continuation = nil
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

// MARK: - Response models

private struct GetUserFeedsResponse: Decodable {
	let status: String
	let message: String?
	let summaryURLsPod: String?
	let summaryURLsYT: String?
	let summaryURLsTopics: String?
	let summaryURLsRSS: String?
	let bookmarks: String?

	enum CodingKeys: String, CodingKey {
		case status
		case message
		case summaryURLsPod    = "summary_urls_pod"
		case summaryURLsYT     = "summary_urls_yt"
		case summaryURLsTopics = "summary_urls_topics"
		case summaryURLsRSS    = "summary_urls_rss"
		case bookmarks
	}
}

// MARK: - Notification names

extension Notification.Name {
	static let creditsDidUpdate = Notification.Name("com.secondstream.creditsDidUpdate")
}
