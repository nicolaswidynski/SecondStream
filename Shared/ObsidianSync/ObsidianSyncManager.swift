//
//  ObsidianSyncManager.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-19.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import Account
import Articles
import os.log

@MainActor final class ObsidianSyncManager {

	static let shared = ObsidianSyncManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ObsidianSync")

	private var isActive = false

	func start() {
		guard !isActive else {
			assertionFailure("start called when already active")
			return
		}

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(statusesDidChange(_:)),
			name: .StatusesDidChange,
			object: nil
		)

		isActive = true
		Self.logger.info("ObsidianSyncManager started")
	}

	@objc func statusesDidChange(_ note: Notification) {
		guard AppDefaults.shared.isObsidianSyncEnabled else {
			return
		}

		// Handle the newer notification format with articleIDs, statusKey, and flag
		if let articleIDs = note.userInfo?[Account.UserInfoKey.articleIDs] as? Set<String>,
		   let statusKey = note.userInfo?[Account.UserInfoKey.statusKey] as? ArticleStatus.Key,
		   statusKey == .starred,
		   let flag = note.userInfo?[Account.UserInfoKey.statusFlag] as? Bool,
		   let account = note.object as? Account {

			Task {
				await handleStarredStatusChange(articleIDs: articleIDs, starred: flag, account: account)
			}
			return
		}

		// Handle the older notification format with statuses and articles
		if let statuses = note.userInfo?[Account.UserInfoKey.statuses] as? Set<ArticleStatus>,
		   let articles = note.userInfo?[Account.UserInfoKey.articles] as? Set<Article> {

			// Filter for starred status changes
			let starredStatuses = statuses.filter { $0.starred }
			let unstarredArticleIDs = statuses.filter { !$0.starred }.map { $0.articleID }

			// Sync starred articles
			for status in starredStatuses {
				if let article = articles.first(where: { $0.articleID == status.articleID }) {
					Task {
						await syncArticle(article)
					}
				}
			}

			// Remove unstarred articles
			for articleID in unstarredArticleIDs {
				if let article = articles.first(where: { $0.articleID == articleID }) {
					Task {
						await removeArticle(article)
					}
				}
			}
		}
	}

	private func handleStarredStatusChange(articleIDs: Set<String>, starred: Bool, account: Account) async {
		do {
			let articles = try await account.fetchArticlesAsync(.articleIDs(articleIDs))

			for article in articles {
				if starred {
					await syncArticle(article)
				} else {
					await removeArticle(article)
				}
			}
		} catch {
			Self.logger.error("Failed to fetch articles for starred status change: \(error.localizedDescription)")
		}
	}

	private func syncArticle(_ article: Article) async {
		guard let account = AccountManager.shared.existingAccount(accountID: article.accountID) else {
			Self.logger.warning("Cannot sync article without account: \(article.articleID)")
			return
		}

		guard let feed = account.existingFeed(withFeedID: article.feedID) else {
			Self.logger.warning("Cannot sync article without feed: \(article.articleID), feedID: \(article.feedID)")
			return
		}

		do {
			let markdown: String

			// Check if the article link is a markdown file - if so, fetch it directly
			if let rawLink = article.rawLink,
			   rawLink.lowercased().hasSuffix(".md"),
			   let url = URL(string: rawLink) {
				Self.logger.info("Article link is markdown file, fetching directly: \(rawLink)")
				markdown = await fetchMarkdownWithFrontmatter(from: url, article: article, feed: feed)
			} else {
				markdown = MarkdownConverter.convert(article: article, feed: feed)
			}

			try ObsidianFileManager.writeArticle(article, feed: feed, content: markdown)
			Self.logger.info("Synced article to Obsidian: \(article.title ?? "Untitled")")
		} catch {
			Self.logger.error("Failed to sync article to Obsidian: \(error.localizedDescription)")
		}
	}

	/// Fetches a markdown file from URL and adds frontmatter
	private func fetchMarkdownWithFrontmatter(from url: URL, article: Article, feed: Feed) async -> String {
		do {
			let (data, _) = try await URLSession.shared.data(from: url)
			if let remoteMarkdown = String(data: data, encoding: .utf8) {
				// Add frontmatter to the remote markdown content
				let frontmatter = MarkdownConverter.generateFrontmatter(article: article, feed: feed)
				return frontmatter + remoteMarkdown
			}
		} catch {
			Self.logger.error("Failed to fetch markdown file: \(error.localizedDescription)")
		}

		// Fall back to conversion if fetch fails
		Self.logger.info("Falling back to HTML conversion")
		return MarkdownConverter.convert(article: article, feed: feed)
	}

	private func removeArticle(_ article: Article) async {
		guard let account = AccountManager.shared.existingAccount(accountID: article.accountID) else {
			Self.logger.warning("Cannot remove article without account: \(article.articleID)")
			return
		}

		guard let feed = account.existingFeed(withFeedID: article.feedID) else {
			Self.logger.warning("Cannot remove article without feed: \(article.articleID), feedID: \(article.feedID)")
			return
		}

		do {
			try ObsidianFileManager.removeArticle(article, feed: feed)
			Self.logger.info("Removed article from Obsidian: \(article.title ?? "Untitled")")
		} catch {
			Self.logger.error("Failed to remove article from Obsidian: \(error.localizedDescription)")
		}
	}
}
