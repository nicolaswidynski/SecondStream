//
//  SubscriptionSyncManager.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-11.
//  Copyright © 2026 STDN. All rights reserved.
//

import Foundation
import Account
import Articles
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
@MainActor final class SubscriptionSyncManager {

	static let shared = SubscriptionSyncManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SubscriptionSync")

	// MARK: - Public API

	/// Fetches the user's subscription list from the server and returns any feeds that
	/// are present on the server but absent from the local account.
	///
	/// Safe to call at any time — does not modify local state.
	/// - Throws: `FeedStatsError` on network / server failure.
	func detectMissingFeeds() async throws -> (feeds: [MissingFeed], bookmarkKeys: [String]) {
		guard let account = AccountManager.shared.activeAccounts.first else {
			Self.logger.info("detectMissingFeeds: no active account")
			return ([], [])
		}

		Self.logger.info("detectMissingFeeds: fetching server subscriptions")
		let (categorizedURLs, bookmarkKeys) = try await FeedStatsManager.shared.getUserFeeds()

		var categoryForURL: [String: FeedCategory] = [:]
		for (category, urls) in categorizedURLs {
			for url in urls { categoryForURL[url] = category }
		}

		let allURLs = categorizedURLs.flatMap { $0.value }
		let missing = allURLs.filter { urlString in
			let normalized = urlString.normalizedURL
			return !normalized.isEmpty && !account.hasFeed(withURL: normalized)
		}

		Self.logger.info("detectMissingFeeds: \(missing.count) missing out of \(allURLs.count) server feeds, \(bookmarkKeys.count) server bookmarks")
		return (missing.map { MissingFeed(urlString: $0, category: categoryForURL[$0] ?? .rss) }, bookmarkKeys)
	}

	/// Creates local feeds for every entry in `feeds`, fetching summary metadata for each.
	/// After feeds are restored, re-stars articles whose `uniqueID` matches a key in
	/// `bookmarkKeys`, waiting for `AccountDidDownloadArticles` so articles are in the DB.
	///
	/// `onProgress` is called on the main actor before each feed is created.
	/// Parameters: `(displayName, zeroBasedIndex, total)`.
	func restore(_ feeds: [MissingFeed], bookmarkKeys: [String] = [], onProgress: ((String, Int, Int) -> Void)? = nil) async {
		guard let account = AccountManager.shared.activeAccounts.first else { return }

		BatchUpdate.shared.start()
		for (index, feed) in feeds.enumerated() {
			let normalized = feed.urlString.normalizedURL
			guard !normalized.isEmpty, let feedURL = URL(string: normalized) else { continue }

			if feed.category == .rss || !feed.urlString.hasSuffix(".json") {
				// Direct feed URL: either an explicit RSS feed or a non-JSON URL that was
				// miscategorized as pod/yt/topics on the server (e.g. old RSS feeds stored
				// under the pod type before the rss category was introduced).
				onProgress?(feedURL.host ?? feed.urlString, index, feeds.count)
				await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
					account.createFeed(
						url: feedURL.absoluteString,
						name: nil,
						container: account,
						validateFeed: false
					) { result in
						if case .success(let created) = result {
							created.feedCategory = .rss
							NotificationCenter.default.post(name: .ChildrenDidChange, object: account)
							Self.logger.info("restore: created RSS feed \(feedURL.absoluteString, privacy: .public)")
						}
						continuation.resume()
					}
				}
			} else {
				guard let meta = await fetchSummaryMeta(urlString: feed.urlString) else {
					Self.logger.warning("restore: no metadata for \(feed.urlString, privacy: .public)")
					continue
				}
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
		}
		BatchUpdate.shared.end()

		Self.logger.info("restore: finished \(feeds.count) feed(s), triggering refresh")
		try? await account.refreshAll()

		// Article-write Tasks spawned during refreshAll run before the completion
		// continuation fires, so articles are in the DB by the time we reach here.
		if !bookmarkKeys.isEmpty {
			await restoreBookmarks(bookmarkKeys: bookmarkKeys, account: account)
		}
	}

	private func restoreBookmarks(bookmarkKeys: [String], account: Account) async {
		let keySet = Set(bookmarkKeys)

		Self.logger.info("restoreBookmarks: looking for \(keySet.count, privacy: .public) keys: \(bookmarkKeys, privacy: .public)")

		// Search ALL feeds in the account — bookmarks may be in feeds that were already
		// present before this restore session, not just the ones we just added.
		// Using .feed() returns every article regardless of read/starred status.
		let allFeeds = account.flattenedFeeds()
		Self.logger.info("restoreBookmarks: searching \(allFeeds.count, privacy: .public) feeds: \(allFeeds.map(\.feedID), privacy: .public)")

		var candidates: Set<Article> = []
		for feed in allFeeds {
			if let articles = try? account.fetchArticles(.feed(feed)) {
				Self.logger.debug("restoreBookmarks: feed \(feed.feedID, privacy: .public) has \(articles.count, privacy: .public) articles")
				candidates.formUnion(articles)
			} else {
				Self.logger.warning("restoreBookmarks: fetchArticles failed for feed \(feed.feedID, privacy: .public)")
			}
		}

		Self.logger.info("restoreBookmarks: \(candidates.count, privacy: .public) total articles across \(allFeeds.count, privacy: .public) feeds")

		// Log which keys were found vs missing
		let foundKeys = keySet.filter { key in candidates.contains { $0.uniqueID == key } }
		let missingKeys = keySet.subtracting(foundKeys)
		Self.logger.info("restoreBookmarks: found \(foundKeys.count, privacy: .public) keys, missing \(missingKeys.count, privacy: .public) keys")
		if !missingKeys.isEmpty {
			Self.logger.warning("restoreBookmarks: missing keys: \(missingKeys, privacy: .public)")
		}

		let toStar = candidates.filter { keySet.contains($0.uniqueID) && !$0.status.starred }
		let alreadyStarred = candidates.filter { keySet.contains($0.uniqueID) && $0.status.starred }
		if !alreadyStarred.isEmpty {
			Self.logger.info("restoreBookmarks: \(alreadyStarred.count, privacy: .public) already starred — skipping")
		}
		guard !toStar.isEmpty else {
			Self.logger.warning("restoreBookmarks: nothing to star")
			return
		}
		account.markArticles(Set(toStar), statusKey: .starred, flag: true) { _ in }
		Self.logger.info("restoreBookmarks: starred \(toStar.count, privacy: .public) article(s): \(toStar.map(\.uniqueID), privacy: .public)")
	}

	/// Convenience: detects missing feeds and restores them silently (no progress UI).
	///
	/// Called on normal cold launch when no recovery UI is needed. If you need to show
	/// progress, call `detectMissingFeeds()` + `restore(_:onProgress:)` directly.
	/// - Throws: `FeedStatsError` on network / server failure.
	func sync() async throws {
		let (missing, bookmarkKeys) = try await detectMissingFeeds()
		guard !missing.isEmpty || !bookmarkKeys.isEmpty else {
			Self.logger.info("sync: all feeds present, nothing to do")
			return
		}
		Self.logger.info("sync: restoring \(missing.count) feed(s), \(bookmarkKeys.count) bookmarks")
		await restore(missing, bookmarkKeys: bookmarkKeys)
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

