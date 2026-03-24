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

/// Tracks feed add/delete events and reports them to the backend.
///
/// `reportAdd` is called after a successful add.
/// For deletions events are queued in a UserDefaults outbox and drained when network is available.
@MainActor final class FeedStatsManager {

	static let shared = FeedStatsManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedStats")

	private let statsURL = URL(string: "https://n8n.nwidynski.com/webhook/update-user-stats")!
	private let creditsURL = URL(string: "https://n8n.nwidynski.com/webhook/get-number-of-credits")!
	private let outboxKey = "feedStats_deletionOutbox"
	private let creditsKey = "feedStats_cachedCredits"
	private let weeklyUpdateLastSentAtKey = "feedStats_weeklyUpdateLastSentAt"
	private let oneWeekInterval: TimeInterval = 7 * 24 * 60 * 60
	private var isDrainingOutbox = false

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

	/// Extracts the `"message"` field from a JSON webhook error body.
	/// Falls back to the raw UTF-8 body if the field is absent or unparseable.
	private static func webhookMessage(from data: Data) -> String {
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
				UserDefaults.standard.set(v, forKey: creditsKey)
			} else {
				UserDefaults.standard.removeObject(forKey: creditsKey)
			}
			NotificationCenter.default.post(name: .creditsDidUpdate, object: nil)
		}
	}

	/// Fetches the current credit count from the server. Best-effort — errors are only logged.
	func fetchCredits() async {
		guard let token = bearerToken else {
			return
		}
		let appleUserID = AuthManager.shared.appleUserID ?? ""
		guard !appleUserID.isEmpty else {
			return
		}

		let body: [String: Any] = ["apple_user_id": appleUserID]

		var request = URLRequest(url: creditsURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

		do {
			request.httpBody = try JSONSerialization.data(withJSONObject: body)
			let (data, response) = try await URLSession.shared.data(for: request)
			guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
				return
			}
			if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			   let message = json["message"] as? String,
			   let credits = Int(message) {
				cachedCredits = credits
				Self.logger.info("Credits fetched: \(credits)")
			}
		} catch {
			Self.logger.error("fetchCredits error: \(error.localizedDescription)")
		}
	}

	// MARK: - Post-add reporting

	/// Reports a successful add to update-feed-stats. Best-effort — errors are only logged.
	func reportAdd(type: FeedCategory, name: String, author: String?) async {
		guard let token = bearerToken else {
			Self.logger.error("reportAdd: no bearer token")
			return
		}

		let appleUserID = AuthManager.shared.appleUserID ?? ""

		let body: [String: Any] = [
			"apple_user_id": appleUserID,
			"type": typeString(for: type),
			"operation": "add",
			"show": name,
			"author": author ?? ""
		]

		var request = URLRequest(url: statsURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

		do {
			request.httpBody = try JSONSerialization.data(withJSONObject: body)
			let (data, response) = try await URLSession.shared.data(for: request)
			if let httpResponse = response as? HTTPURLResponse,
			   !(200...299).contains(httpResponse.statusCode) {
				let rawBody = String(data: data, encoding: .utf8) ?? "(empty)"
				Self.logger.error("update-feed-stats add failed [\(httpResponse.statusCode)]: \(rawBody)")
			} else {
				Self.logger.info("update-feed-stats add reported: \(name)")
				await fetchCredits()
			}
		} catch {
			Self.logger.error("update-feed-stats add error: \(error.localizedDescription)")
		}
	}

	// MARK: - Subscription snapshot (update operation)

	/// Sends a snapshot of all current subscriptions to `update-user-stats`.
	/// `count_free` for pod/yt is resolved at send time by fetching the live free-lib files.
	/// rss and topics are always considered free.
	/// Non-blocking: errors are only logged.
	@discardableResult
	func reportUpdate() async -> Bool {

		guard let token = bearerToken else {
			Self.logger.error("reportUpdate: no bearer token")
			return false
		}
		let appleUserID = AuthManager.shared.appleUserID ?? ""
		guard !appleUserID.isEmpty else {
			return false
		}

		// Collect feeds from the first active account
		guard let account = AccountManager.shared.activeAccounts.first else {
			return false
		}

		let allFeeds = account.flattenedFeeds()

		var podSources: [String] = []
		var ytSources: [String] = []
		var topicSources: [String] = []
		var rssCount = 0

		for feed in allFeeds {
			switch feed.feedCategory {
			case .podcast:
				podSources.append(feed.nameForDisplay)
			case .youtube:
				ytSources.append(feed.nameForDisplay)
			case .news:
				topicSources.append(feed.nameForDisplay)
			case .rss:
				rssCount += 1
			}
		}

		// Resolve count_free at send time by fetching the live free-lib files.
		async let podFreeEntries = SourceFileFetcher.fetch(fileName: "pod_free.json")
		async let ytFreeEntries = SourceFileFetcher.fetch(fileName: "yt_free.json")

		let podFreeNames = Set((await podFreeEntries ?? []).map { $0.name.lowercased() })
		let ytFreeNames = Set((await ytFreeEntries ?? []).map { $0.name.lowercased() })

		let podFreeCount = podSources.filter { podFreeNames.contains($0.lowercased()) }.count
		let ytFreeCount = ytSources.filter { ytFreeNames.contains($0.lowercased()) }.count

		let body: [String: Any] = [
			"apple_user_id": appleUserID,
			"operation": "update",
			"pod": [
				"count": String(podSources.count),
				"count_free": String(podFreeCount),
				"sources": podSources
			],
			"yt": [
				"count": String(ytSources.count),
				"count_free": String(ytFreeCount),
				"sources": ytSources
			],
			"topics": [
				"count": String(topicSources.count),
				"count_free": String(topicSources.count),
				"sources": topicSources
			],
			"rss": [
				"count": String(rssCount),
				"count_free": String(rssCount)
			]
		]

		var request = URLRequest(url: statsURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

		do {
			request.httpBody = try JSONSerialization.data(withJSONObject: body)
			let (data, response) = try await URLSession.shared.data(for: request)
			if let httpResponse = response as? HTTPURLResponse,
			   !(200...299).contains(httpResponse.statusCode) {
				let rawBody = String(data: data, encoding: .utf8) ?? "(empty)"
				Self.logger.error("update-user-stats failed [\(httpResponse.statusCode)]: \(rawBody)")
				return false
			} else {
				Self.logger.info("update-user-stats sent: pod=\(podSources.count) free=\(podFreeCount) yt=\(ytSources.count) free=\(ytFreeCount) topics=\(topicSources.count) rss=\(rssCount)")
				return true
			}
		} catch {
			Self.logger.error("update-user-stats error: \(error.localizedDescription)")
			return false
		}
	}

	/// Sends `operation: "update"` at most once per week.
	func reportWeeklyUpdateIfNeeded() async {
		let now = Date()
		if let lastSentAt = UserDefaults.standard.object(forKey: weeklyUpdateLastSentAtKey) as? Date,
		   now.timeIntervalSince(lastSentAt) < oneWeekInterval {
			return
		}
		if await reportUpdate() {
			UserDefaults.standard.set(now, forKey: weeklyUpdateLastSentAtKey)
		}
	}

	// MARK: - Delete outbox

	/// Queues a delete event and attempts to drain the outbox immediately.
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

		Self.logger.info("Queued delete for \(name)")
		Task { await self.drainOutbox() }
	}

	/// Attempts to send all queued delete events to the server.
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
		guard let token = bearerToken else {
			return
		}

		var drainedAny = false
		for record in outbox {
			do {
				try await send(record: record, token: token)
				Self.logger.info("Drained delete: \(record.show)")
				removeFromOutbox(record)
				drainedAny = true
			} catch {
				Self.logger.error("Failed to drain delete for \(record.show): \(error.localizedDescription)")
			}
		}
		if drainedAny {
			await fetchCredits()
		}
	}

	private func send(record: OutboxRecord, token: String) async throws {
		let body: [String: Any] = [
			"apple_user_id": record.appleUserID,
			"type": record.type,
			"operation": record.operation,
			"show": record.show,
			"author": record.author
		]

		var request = URLRequest(url: statsURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.httpBody = try JSONSerialization.data(withJSONObject: body)

		let (data, response) = try await URLSession.shared.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse,
			  (200...299).contains(httpResponse.statusCode) else {
			let rawBody = String(data: data, encoding: .utf8) ?? "(empty)"
			Self.logger.error("update-feed-stats drain failed [\((response as? HTTPURLResponse)?.statusCode ?? 0)]: \(rawBody)")
			throw FeedStatsError.serverError(
				statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
				body: Self.webhookMessage(from: data)
			)
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

	private func removeFromOutbox(_ record: OutboxRecord) {
		var records = loadOutbox()
		guard let index = records.firstIndex(of: record) else {
			return
		}
		records.remove(at: index)
		saveOutbox(records)
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
