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
/// For additions the gate function must succeed (200) before the actual add proceeds.
/// For deletions events are queued in a UserDefaults outbox and drained when network is available.
@MainActor final class FeedStatsManager {

	static let shared = FeedStatsManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedStats")

	private let statsURL = URL(string: "https://n8n.nwidynski.com/webhook/feeds-stats")!
	private let outboxKey = "feedStats_deletionOutbox"

	// MARK: - Outbox record

	struct OutboxRecord: Codable {
		let appleUserID: String
		let type: String
		let operation: String
		let show: String
		let author: String
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

	// MARK: - Pre-add gate

	/// Calls feeds-stats before an add operation. Throws if the server does not return 200.
	func gateAdd(type: FeedCategory, name: String, author: String?) async throws {
		guard let token = bearerToken else {
			throw FeedStatsError.missingToken
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
		request.httpBody = try JSONSerialization.data(withJSONObject: body)

		let (data, response) = try await URLSession.shared.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse else {
			throw FeedStatsError.invalidResponse
		}

		guard (200...299).contains(httpResponse.statusCode) else {
			let rawBody = String(data: data, encoding: .utf8) ?? "(empty)"
			Self.logger.error("feeds-stats gate rejected add [\(httpResponse.statusCode)]: \(rawBody)")
			throw FeedStatsError.serverError(statusCode: httpResponse.statusCode, body: Self.webhookMessage(from: data))
		}

		Self.logger.info("feeds-stats gate approved add: \(name) type=\(self.typeString(for: type))")
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
			author: author ?? ""
		)

		var outbox = loadOutbox()
		outbox.append(record)
		saveOutbox(outbox)

		Self.logger.info("Queued delete for \(name)")
		Task { await self.drainOutbox() }
	}

	/// Attempts to send all queued delete events to the server.
	func drainOutbox() async {
		let outbox = loadOutbox()
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

		var remaining = [OutboxRecord]()
		for record in outbox {
			do {
				try await send(record: record, token: token)
				Self.logger.info("Drained delete: \(record.show)")
			} catch {
				Self.logger.error("Failed to drain delete for \(record.show): \(error.localizedDescription)")
				remaining.append(record)
			}
		}
		saveOutbox(remaining)
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
			Self.logger.error("feeds-stats drain failed [\((response as? HTTPURLResponse)?.statusCode ?? 0)]: \(rawBody)")
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
		return records
	}

	private func saveOutbox(_ records: [OutboxRecord]) {
		guard let data = try? JSONEncoder().encode(records) else {
			return
		}
		UserDefaults.standard.set(data, forKey: outboxKey)
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
