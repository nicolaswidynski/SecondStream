//
//  SubscriptionSyncManager.swift
//  NetNewsWire
//
//  Created by Nicolas Widynski on 2026-04-11.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import Account
import RSCore
import os.log

/// A server-side subscription that is absent from local storage.
///
/// Produced by `SubscriptionSyncManager.detectMissingFeeds()` and consumed by
/// `restore(_:onProgress:)` or `SourceRestoreViewController`.
struct MissingFeed {
	let urlString: String
	let category: FeedCategory
}

/// Restores a user's server-side subscriptions to the local account.
///
/// **Normal launch:** call `sync()` — it silently restores any missing feeds.
/// **Recovery UI:** call `detectMissingFeeds()` first; if non-empty, present
/// `SourceRestoreViewController`, which calls `restore(_:onProgress:)` with a
/// progress callback to drive the UI.
///
/// RSS feeds are intentionally excluded: they are local-only by design.
@MainActor final class SubscriptionSyncManager {

	static let shared = SubscriptionSyncManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SubscriptionSync")

	// MARK: - Public API

	/// Fetches the user's subscription list from the server and returns any feeds that
	/// are present on the server but absent from the local account.
	///
	/// Safe to call at any time — does not modify local state.
	/// - Throws: `FeedStatsError` on network / server failure.
	func detectMissingFeeds() async throws -> [MissingFeed] {
		guard let account = AccountManager.shared.activeAccounts.first else {
			Self.logger.info("detectMissingFeeds: no active account")
			return []
		}

		Self.logger.info("detectMissingFeeds: fetching server subscriptions")
		let categorizedURLs = try await FeedStatsManager.shared.getUserFeeds()

		var categoryForURL: [String: FeedCategory] = [:]
		for (category, urls) in categorizedURLs {
			for url in urls { categoryForURL[url] = category }
		}

		let allURLs = categorizedURLs.flatMap { $0.value }
		let missing = allURLs.filter { urlString in
			let normalized = urlString.normalizedURL
			return !normalized.isEmpty && !account.hasFeed(withURL: normalized)
		}

		Self.logger.info("detectMissingFeeds: \(missing.count) missing out of \(allURLs.count) server feeds")
		return missing.map { MissingFeed(urlString: $0, category: categoryForURL[$0] ?? .rss) }
	}

	/// Creates local feeds for every entry in `feeds`, fetching summary metadata for each.
	///
	/// `onProgress` is called on the main actor before each feed is created.
	/// Parameters: `(displayName, zeroBasedIndex, total)`.
	func restore(_ feeds: [MissingFeed], onProgress: ((String, Int, Int) -> Void)? = nil) async {
		guard let account = AccountManager.shared.activeAccounts.first else { return }

		BatchUpdate.shared.start()
		for (index, feed) in feeds.enumerated() {
			guard let meta = await fetchSummaryMeta(urlString: feed.urlString) else {
				Self.logger.warning("restore: no metadata for \(feed.urlString, privacy: .public)")
				continue
			}
			let normalized = feed.urlString.normalizedURL
			guard !normalized.isEmpty, let feedURL = URL(string: normalized) else { continue }

			onProgress?(meta.title ?? feed.urlString, index, feeds.count)

			await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
				account.createFeed(
					url: feedURL.absoluteString,
					name: meta.title,
					container: account,
					validateFeed: false
				) { result in
					if case .success(let created) = result {
						created.feedCategory = feed.category
						if let imageURL = meta.imageLink { created.iconURL = imageURL }
						NotificationCenter.default.post(name: .ChildrenDidChange, object: account)
						Self.logger.info("restore: created \(meta.title ?? feed.urlString, privacy: .public)")
					}
					continuation.resume()
				}
			}
		}
		BatchUpdate.shared.end()

		Self.logger.info("restore: finished \(feeds.count) feed(s), triggering refresh")
		try? await account.refreshAll()
	}

	/// Convenience: detects missing feeds and restores them silently (no progress UI).
	///
	/// Called on normal cold launch when no recovery UI is needed. If you need to show
	/// progress, call `detectMissingFeeds()` + `restore(_:onProgress:)` directly.
	/// - Throws: `FeedStatsError` on network / server failure.
	func sync() async throws {
		let missing = try await detectMissingFeeds()
		guard !missing.isEmpty else {
			Self.logger.info("sync: all feeds present, nothing to do")
			return
		}
		Self.logger.info("sync: restoring \(missing.count) feed(s)")
		await restore(missing)
		Self.logger.info("sync: complete")
	}

	// MARK: - Private

	private func fetchSummaryMeta(urlString: String) async -> SummaryFileMeta? {
		guard let url = URL(string: urlString) else { return nil }
		guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
		return try? JSONDecoder().decode(SummaryFileMeta.self, from: data)
	}
}

// MARK: - Summary file model

private struct SummaryFileMeta: Decodable {
	let title: String?
	let author: String?
	let imageLink: String?

	enum CodingKeys: String, CodingKey {
		case title
		case author
		case imageLink = "image_link"
	}
}
