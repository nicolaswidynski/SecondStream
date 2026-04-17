//
//  SecondStreamAPIClient.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-11.
//  Copyright © 2026 STDN. All rights reserved.
//

import Foundation
import os.log

// MARK: - APIError

enum APIError: LocalizedError {
	case missingToken
	case serverError(statusCode: Int, message: String)
	/// The request was intentionally dropped (e.g. a stats update while adds are queued).
	case skipped

	var errorDescription: String? {
		switch self {
		case .missingToken:
			return "Authentication token not found."
		case .serverError(_, let message):
			return message
		case .skipped:
			return "Request skipped."
		}
	}
}

private let apiClientLogger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "APIClient")

// MARK: - SecondStreamAPIClient

/// The single class responsible for all HTTP communication with the backend.
///
/// Every manager that needs to reach n8n calls `SecondStreamAPIClient.shared.post(to:body:)`.
/// Token loading, header setup, and `URLSession` are owned here and nowhere else.
@MainActor final class SecondStreamAPIClient {

	static let shared = SecondStreamAPIClient()

	private init() {}

	// MARK: - Endpoints

	enum Endpoint {
		case manageUser
		case allFeedRequests
		case findShow
		case queryBootstrapProgress

		var url: URL {
			switch self {
			case .manageUser:
				return URL(string: "https://n8n.nwidynski.com/webhook/manage-user")!
			case .allFeedRequests:
				return URL(string: "https://n8n.nwidynski.com/webhook/all-feed-requests")!
			case .findShow:
				return URL(string: "https://n8n.nwidynski.com/webhook/find-show")!
			case .queryBootstrapProgress:
				return URL(string: "https://n8n.nwidynski.com/webhook/query-bootstrap-progress")!
			}
		}
	}

	// MARK: - Core request

	/// POSTs `body` as JSON to `endpoint`.
	///
	/// Calls to `.allFeedRequests` are automatically serialized: concurrent callers
	/// queue behind each other and execute one at a time.
	///
	/// - Returns: The raw response `Data` and HTTP status code.
	/// - Throws: `APIError.missingToken` if the bearer token is unavailable,
	///   or a `URLError` / other `Error` on network failure.
	func post(
		to endpoint: Endpoint,
		body: [String: Any],
		timeout: TimeInterval = 60
	) async throws -> (data: Data, statusCode: Int) {
		if endpoint == .allFeedRequests {
			return try await enqueueAllFeedRequest(body: body, timeout: timeout)
		}
		return try await performPost(to: endpoint, body: body, timeout: timeout)
	}

	// MARK: - all-feed-requests queue

	/// Number of `add-show` operations that are currently queued or in-flight.
	private var pendingAddCount = 0

	/// Tail of the serial chain for `add-show` operations.
	///
	/// Each new `add-show` call captures the current tail, chains off it (waiting
	/// for it to finish — success or failure — before sending), then becomes the
	/// new tail. This guarantees at most one `add-show` is in-flight at a time.
	private var allFeedRequestsTail: Task<(data: Data, statusCode: Int), Error>?

	private func enqueueAllFeedRequest(body: [String: Any], timeout: TimeInterval) async throws -> (data: Data, statusCode: Int) {
		let operation = body["operation"] as? String

		// update-user-stats: drop immediately if any add-show is pending.
		// The stats it would report are stale — the in-flight/queued add will
		// change the server state before this response would be acted upon.
		if operation == "update-user-stats" {
			guard pendingAddCount == 0 else {
				apiClientLogger.info("update-user-stats skipped — \(self.pendingAddCount) add(s) pending")
				throw APIError.skipped
			}
			return try await performPost(to: .allFeedRequests, body: body, timeout: timeout)
		}

		// del-show: fire immediately, independent of the add-show queue.
		if operation == "del-show" {
			return try await performPost(to: .allFeedRequests, body: body, timeout: timeout)
		}

		// add-show: serialize behind any currently queued add.
		pendingAddCount += 1
		let previous = allFeedRequestsTail
		let task = Task<(data: Data, statusCode: Int), Error> {
			defer { self.pendingAddCount -= 1 }
			_ = try? await previous?.value
			return try await self.performPost(to: .allFeedRequests, body: body, timeout: timeout)
		}
		allFeedRequestsTail = task
		return try await task.value
	}

	// MARK: - Underlying POST

	private func performPost(
		to endpoint: Endpoint,
		body: [String: Any],
		timeout: TimeInterval
	) async throws -> (data: Data, statusCode: Int) {
		var request = URLRequest(url: endpoint.url)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.timeoutInterval = timeout
		request.httpBody = try JSONSerialization.data(withJSONObject: body)

		if endpoint == .manageUser {
			// Account creation and reconnect use the shared bootstrap token.
			guard let bootstrap = bootstrapToken else { throw APIError.missingToken }
			request.setValue("Bearer \(bootstrap)", forHTTPHeaderField: "Authorization")
			// Also send session token if available — server requires it on reconnect for users who already have one.
			if let sessionToken = AuthManager.shared.sessionToken {
				request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "authorization_uuid")
			}
		} else {
			// All other webhooks use the per-user session token.
			guard let sessionToken = AuthManager.shared.sessionToken else { throw APIError.missingToken }
			request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "authorization_uuid")
		}

		let (data, response) = try await URLSession.shared.data(for: request)
		let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
		apiClientLogger.debug("\(endpoint.url.lastPathComponent, privacy: .public) → HTTP \(statusCode, privacy: .public)")
		return (data, statusCode)
	}

	// MARK: - Unauthenticated requests

	/// Sends a HEAD request to `url`.
	///
	/// - Returns: HTTP status code and response headers (string-keyed).
	nonisolated func head(_ url: URL, timeout: TimeInterval = 30) async throws -> (statusCode: Int, headers: [String: String]) {
		var request = URLRequest(url: url)
		request.httpMethod = "HEAD"
		request.timeoutInterval = timeout
		let (_, response) = try await URLSession.shared.data(for: request)
		let http = response as? HTTPURLResponse
		let statusCode = http?.statusCode ?? 0
		let headers = http?.allHeaderFields.reduce(into: [String: String]()) { acc, pair in
			if let key = pair.key as? String, let value = pair.value as? String { acc[key] = value }
		} ?? [:]
		apiClientLogger.debug("HEAD \(url.absoluteString, privacy: .public) → HTTP \(statusCode, privacy: .public)")
		return (statusCode, headers)
	}

	/// Sends a GET request to `url`.
	///
	/// - Returns: Raw response data, HTTP status code, and response headers (string-keyed).
	nonisolated func get(from url: URL, timeout: TimeInterval = 60) async throws -> (data: Data, statusCode: Int, headers: [String: String]) {
		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		request.timeoutInterval = timeout
		let (data, response) = try await URLSession.shared.data(for: request)
		let http = response as? HTTPURLResponse
		let statusCode = http?.statusCode ?? 0
		let headers = http?.allHeaderFields.reduce(into: [String: String]()) { acc, pair in
			if let key = pair.key as? String, let value = pair.value as? String { acc[key] = value }
		} ?? [:]
		apiClientLogger.debug("GET \(url.absoluteString, privacy: .public) → HTTP \(statusCode, privacy: .public)")
		return (data, statusCode, headers)
	}

	// MARK: - Token

	/// Shared API key bundled with the app. Used only for `.manageUser` (account creation/reconnect).
	private var bootstrapToken: String? {
		guard let url = Bundle.main.url(forResource: "podcast_token", withExtension: "txt"),
			  let token = try? String(contentsOf: url, encoding: .utf8) else {
			apiClientLogger.error("Failed to load bootstrap token from podcast_token.txt")
			return nil
		}
		return token.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}
