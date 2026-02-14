//
//  SourcesRefreshManager.swift
//  NetNewsWire
//
//  Created by Claude on 2026-02-13.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import os.log

@MainActor final class SourcesRefreshManager {

	static let shared = SourcesRefreshManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SourcesRefresh")

	private let minimumRefreshInterval: TimeInterval = 5 * 60 // 5 minutes
	private var lastRefreshDate: Date?
	private var refreshTask: Task<Void, Never>?

	/// Refreshes all sources if at least 5 minutes have passed since the last refresh.
	/// Safe to call frequently — duplicates and too-frequent calls are ignored.
	func refreshIfNeeded() {
		if let lastRefresh = lastRefreshDate, Date().timeIntervalSince(lastRefresh) < minimumRefreshInterval {
			Self.logger.info("Skipping sources refresh, last refresh was less than 5 minutes ago")
			return
		}
		refreshNow()
	}

	/// Forces a refresh regardless of the 5-minute throttle.
	func forceRefresh() {
		refreshNow()
	}

	private func refreshNow() {
		guard refreshTask == nil else {
			Self.logger.info("Sources refresh already in progress")
			return
		}

		refreshTask = Task {
			Self.logger.info("Starting sources refresh")

			async let podcastFetch: () = PodcastSourcesManager.shared.fetchFresh()
			async let youtubeFetch: () = YoutubeSourcesManager.shared.fetchFresh()
			async let newsFetch: () = NewsSourcesManager.shared.fetchFresh()

			_ = await (podcastFetch, youtubeFetch, newsFetch)

			lastRefreshDate = Date()
			refreshTask = nil
			Self.logger.info("Sources refresh complete")
		}
	}
}
