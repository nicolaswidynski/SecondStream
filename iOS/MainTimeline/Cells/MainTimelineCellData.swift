//
//  MainTimelineCellData.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 2/6/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//

import UIKit
import Articles

@MainActor struct MainTimelineCellData {

	let title: String
	let attributedTitle: NSAttributedString
	let summary: String
	let dateString: String
	let feedName: String
	let byline: String
	let showFeedName: ShowFeedName
	let iconImage: IconImage? // feed icon, user avatar, or favicon
	let showIcon: Bool // Make space even when icon is nil
	let read: Bool
	let starred: Bool
	let numberOfLines: Int
	let iconSize: IconSize

	init(article: Article, showFeedName: ShowFeedName, feedName: String?, byline: String?, iconImage: IconImage?, showIcon: Bool, numberOfLines: Int, iconSize: IconSize) {

		self.title = ArticleStringFormatter.truncatedTitle(article)
		self.attributedTitle = ArticleStringFormatter.attributedTruncatedTitle(article)

		self.summary = MainTimelineCellData.listingSummary(for: article)

		self.dateString = ArticleStringFormatter.dateString(article.logicalDatePublished)

		if let feedName = feedName {
			self.feedName = ArticleStringFormatter.truncatedFeedName(feedName)
		} else {
			self.feedName = ""
		}

		if let byline = byline {
			self.byline = byline
		} else {
			self.byline = ""
		}

		self.showFeedName = showFeedName

		self.showIcon = showIcon
		self.iconImage = iconImage

		self.read = article.status.read
		self.starred = article.status.starred
		self.numberOfLines = numberOfLines
		self.iconSize = iconSize

	}

	private static func listingSummary(for article: Article) -> String {
		guard let category = article.feed?.feedCategory else {
			return ""
		}

		switch category {
		case .podcast, .youtube:
			return firstSummaryContentLine(from: article.contentJSON)
		case .news:
			return firstNewsTitle(from: article.contentJSON)
		default:
			return ""
		}
	}

	private static func firstSummaryContentLine(from contentJSONString: String?) -> String {
		guard let contentJSONString,
			  let data = contentJSONString.data(using: .utf8),
			  let root = try? JSONSerialization.jsonObject(with: data),
			  let dictionary = root as? [String: Any] else {
			return ""
		}

		if let summaryItems = dictionary["summary"] as? [[String: Any]] {
			for item in summaryItems {
				if let content = normalizedLine(item["content"]) {
					return content
				}
			}
		}

		// Backward compatibility with older generated format where summary contains thesis/practical.
		if let summaryDictionary = dictionary["summary"] as? [String: Any],
		   let thesisItems = summaryDictionary["thesis"] as? [[String: Any]] {
			for item in thesisItems {
				if let content = normalizedLine(item["content"]) {
					return content
				}
			}
		}

		if let practicalItems = dictionary["practical_applications"] as? [[String: Any]] {
			for item in practicalItems {
				if let content = normalizedLine(item["content"]) {
					return content
				}
			}
		}

		return ""
	}

	private static func firstNewsTitle(from contentJSONString: String?) -> String {
		guard let contentJSONString,
			  let data = contentJSONString.data(using: .utf8),
			  let root = try? JSONSerialization.jsonObject(with: data) else {
			return ""
		}

		if let items = root as? [[String: Any]] {
			for item in items {
				if let title = normalizedLine(item["title"]) {
					return title
				}
			}
		}

		if let dictionary = root as? [String: Any],
		   let items = dictionary["data"] as? [[String: Any]] {
			for item in items {
				if let title = normalizedLine(item["title"]) {
					return title
				}
			}
		}

		return ""
	}

	private static func normalizedLine(_ value: Any?) -> String? {
		guard let raw = value as? String else {
			return nil
		}
		let cleaned = raw
			.replacingOccurrences(of: "\n", with: " ")
			.replacingOccurrences(of: "\r", with: " ")
			.trimmingCharacters(in: .whitespacesAndNewlines)
		return cleaned.isEmpty ? nil : cleaned
	}

	init() { // Empty
		self.title = ""
		self.attributedTitle = NSAttributedString()
		self.summary = ""
		self.dateString = ""
		self.feedName = ""
		self.byline = ""
		self.showFeedName = .none
		self.showIcon = false
		self.iconImage = nil
		self.read = true
		self.starred = false
		self.numberOfLines = 0
		self.iconSize = .medium
	}

}
