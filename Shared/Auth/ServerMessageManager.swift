//
//  ServerMessageManager.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-23.
//  Copyright © 2026 STDN. All rights reserved.
//

import Foundation
import os.log

/// Fetches server-side messages once per calendar day and surfaces any that
/// haven't been shown yet (determined by the date of the last displayed message).
@MainActor final class ServerMessageManager {

	static let shared = ServerMessageManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ServerMessages")

	private let client = SecondStreamAPIClient.shared
	/// Calendar date string (yyyy-MM-dd) of the last message the user was shown.
	private let lastShownDateKey = "serverMessages_lastShownDate"
	/// Calendar date string of when we last successfully queried the endpoint.
	private let lastFetchDateKey  = "serverMessages_lastFetchDate"

	private static let dateFormatter: DateFormatter = {
		let f = DateFormatter()
		f.dateFormat = "yyyy-MM-dd"
		f.locale = Locale(identifier: "en_US_POSIX")
		f.timeZone = TimeZone.current
		return f
	}()

	private init() {}

	// MARK: - Public API

	/// Call on every foreground event. Fetches and presents messages at most once per calendar day.
	func fetchAndPresentIfNeeded(presentingViewController: UIViewController) {
		let today = Self.dateFormatter.string(from: Date())
		let lastFetch = UserDefaults.standard.string(forKey: lastFetchDateKey)
		guard lastFetch != today else {
			return
		}
		Task {
			await fetchAndPresent(today: today, presentingViewController: presentingViewController)
		}
	}

	// MARK: - Private

	private func fetchAndPresent(today: String, presentingViewController: UIViewController) async {
		guard let appleUserID = AuthManager.shared.appleUserID, !appleUserID.isEmpty else {
			return
		}

		let body: [String: Any] = [
			"apple_user_id": appleUserID,
			"request_id": UUID().uuidString
		]

		do {
			let (data, statusCode) = try await client.post(to: .queryMessages, body: body)
			guard statusCode == 200 else {
				Self.logger.error("query-messages HTTP \(statusCode, privacy: .public)")
				return
			}

			// Mark as fetched today regardless of content, so we don't retry on error.
			UserDefaults.standard.set(today, forKey: lastFetchDateKey)

			let messages = parseMessages(from: data)
			let lastShown = UserDefaults.standard.string(forKey: lastShownDateKey)
			let pending = messages.filter { msg in
				guard let lastShown else { return true }
				return msg.date > lastShown
			}.sorted { $0.date < $1.date }

			guard !pending.isEmpty else {
				Self.logger.debug("query-messages: no new messages to show")
				return
			}

			Self.logger.info("query-messages: \(pending.count, privacy: .public) new message(s)")
			await presentMessages(pending, presentingViewController: presentingViewController)
		} catch {
			Self.logger.error("query-messages error: \(error.localizedDescription)")
		}
	}

	/// Presents each message sequentially as a UIAlertController.
	private func presentMessages(_ messages: [ServerMessage], presentingViewController: UIViewController) async {
		for message in messages {
			await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
				let alert = UIAlertController(title: nil, message: message.text, preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default) { _ in
					continuation.resume()
				})
				// Find the topmost presented VC to avoid "already presenting" errors.
				var presenter = presentingViewController
				while let p = presenter.presentedViewController { presenter = p }
				presenter.present(alert, animated: true)
			}
			// Persist after each message so a crash mid-sequence doesn't re-show already-seen ones.
			UserDefaults.standard.set(message.date, forKey: lastShownDateKey)
		}
	}

	// MARK: - Parsing

	private struct ServerMessage {
		let date: String  // "yyyy-MM-dd"
		let text: String
	}

	private func parseMessages(from data: Data) -> [ServerMessage] {
		// Response may be an object {"messages":[...]} or a bare array.
		let root = try? JSONSerialization.jsonObject(with: data)
		let rawArray: [[String: Any]]?
		if let obj = root as? [String: Any] {
			rawArray = obj["messages"] as? [[String: Any]]
		} else {
			rawArray = root as? [[String: Any]]
		}
		guard let items = rawArray else { return [] }
		return items.compactMap { item in
			guard let date = item["date"] as? String,
				  let text = item["message"] as? String else { return nil }
			return ServerMessage(date: date, text: text)
		}
	}
}
