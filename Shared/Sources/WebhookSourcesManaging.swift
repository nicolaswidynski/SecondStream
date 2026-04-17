//
//  WebhookSourcesManaging.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-10.
//  Copyright © 2026 STDN. All rights reserved.
//

import Foundation

/// Unified result type for webhook-based source additions.
/// Replaces the per-manager result enums (AddPodcastResult, AddYoutubeResult, AddNewsResult)
/// at the call site, collapsing the three parallel branches into one.
enum AddSourceResult {
	/// HTTP 200/201 — source already exists on the server; subscribe immediately.
	case existsOnServer(summaryURL: String)
	/// HTTP 202 — source is new and being processed; start bootstrap polling.
	/// `message` is the server-supplied user-facing string (may be empty for some source types).
	case newOnServer(summaryURL: String, message: String)
	/// Any error — `message` is suitable for display to the user.
	case failure(message: String)
}

/// Common interface for managers that add sources via a server-side webhook.
///
/// Conformers: `MediaSourcesManager` (.podcast and .youtube), `NewsSourcesManager`.
/// `RSSSourcesManager` is excluded because RSS subscriptions use a direct URL and never
/// call a webhook.
@MainActor protocol WebhookSourcesManaging: AnyObject {
	/// Calls the server webhook to add a source by name.
	/// Returns when the network request completes; never throws.
	func add(name: String, author: String?) async -> AddSourceResult

	/// Discards cached results and re-fetches the source list from the server.
	func fetchFresh() async
}
