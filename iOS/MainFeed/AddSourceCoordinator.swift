//
//  AddSourceCoordinator.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-10.
//  Copyright © 2026 STDN. All rights reserved.
//

import Account

/// Coordinates the webhook→subscribe pipeline for a single source-add operation.
///
/// Business logic lives here; `MainFeedCollectionViewController` observes `state` and
/// handles all UIKit presentation (loading alerts, success/error alerts, section expansion).
///
/// Usage:
/// ```swift
/// let coordinator = AddSourceCoordinator(manager: MediaSourcesManager.podcast, category: .podcast)
/// await coordinator.add(name: name, author: author)
/// // read coordinator.state for the outcome
/// ```
@MainActor final class AddSourceCoordinator {

	// MARK: - State

	enum State: Equatable {
		/// Initial state — no operation in flight.
		case idle
		/// Webhook request has been dispatched; awaiting response.
		case webhookPending
		/// HTTP 200/201 — source already exists on the server.
		case existsOnServer(summaryURL: String)
		/// HTTP 202 — source is new and being processed server-side.
		/// `message` is the server-supplied user-facing string; may be empty (e.g. for news topics).
		case newOnServer(summaryURL: String, message: String)
		/// Network or server error. `message` is suitable for display.
		case failed(message: String)
	}

	// MARK: - Properties

	/// The manager that will be called to add the source.
	let manager: any WebhookSourcesManaging

	/// Feed category associated with this add operation.
	let category: FeedCategory

	/// Bootstrap type string sent to `BootstrapProgressManager` on a 202 response.
	/// Empty string for source types that don't use bootstrap polling (e.g. news).
	var bootstrapType: String {
		switch category {
		case .podcast: return "pod"
		case .youtube: return "yt"
		default: return ""
		}
	}

	/// Current state of the add operation. Updated on `@MainActor` before returning from `add`.
	private(set) var state: State = .idle

	/// Called after each state transition. Useful for lightweight observers that don't
	/// need Combine (e.g. updating a loading indicator).
	var onStateChange: ((State) -> Void)?

	// MARK: - Init

	init(manager: any WebhookSourcesManaging, category: FeedCategory) {
		self.manager = manager
		self.category = category
	}

	// MARK: - API

	/// Calls the webhook and transitions `state` to the result.
	/// Returns when the network request completes. Read `state` for the outcome.
	func add(name: String, author: String?) async {
		transition(to: .webhookPending)
		let result = await manager.add(name: name, author: author)
		switch result {
		case .existsOnServer(let url):
			transition(to: .existsOnServer(summaryURL: url))
		case .newOnServer(let url, let msg):
			transition(to: .newOnServer(summaryURL: url, message: msg))
		case .failure(let msg):
			transition(to: .failed(message: msg))
		}
	}

	// MARK: - Private

	private func transition(to newState: State) {
		state = newState
		onStateChange?(newState)
	}
}
