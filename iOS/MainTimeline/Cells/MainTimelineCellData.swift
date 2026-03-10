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
	let showIndicator: Bool
	let isGeneratedSummaryRow: Bool
	let numberOfLines: Int
	let iconSize: IconSize

	init(article: Article, showFeedName: ShowFeedName, feedName: String?, byline: String?, iconImage: IconImage?, showIcon: Bool, numberOfLines: Int, iconSize: IconSize, includeListingSummary: Bool = true, dateStringOverride: String? = nil) {

		self.title = ArticleStringFormatter.truncatedTitle(article)
		self.attributedTitle = ArticleStringFormatter.attributedTruncatedTitle(article)

		self.summary = includeListingSummary ? MainTimelineCellData.listingSummary(for: article) : ""

		self.dateString = dateStringOverride ?? ArticleStringFormatter.dateString(article.logicalDatePublished)

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
		self.showIndicator = true
		self.isGeneratedSummaryRow = false
		self.numberOfLines = numberOfLines
		self.iconSize = iconSize

	}

	static func listingSummaryText(for article: Article) -> String {
		listingSummary(for: article)
	}

	static func summaryRow(text: String, numberOfLines: Int, iconSize: IconSize) -> MainTimelineCellData {
		let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
		let summaryText = normalizedText.isEmpty ? " " : normalizedText
		return MainTimelineCellData(
			title: summaryText,
			summary: "",
			dateString: "",
			feedName: "",
			byline: "",
			showFeedName: .none,
			iconImage: nil,
			showIcon: false,
			read: false,
			starred: false,
			showIndicator: false,
			isGeneratedSummaryRow: true,
			numberOfLines: 0,
			iconSize: iconSize
		)
	}

	private static func listingSummary(for article: Article) -> String {
		if let category = article.feed?.feedCategory {
			switch category {
			case .podcast, .youtube:
				let content = firstSummaryContentLine(from: article.contentJSON)
				if !content.isEmpty {
					return firstLine(in: content)
				}
			case .news:
				let title = firstNewsTitle(from: article.contentJSON)
				if !title.isEmpty {
					return title
				}
			default:
				break
			}
		}

		let fallback = article.summary ?? article.contentText ?? ""
		return firstLine(in: fallback)
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

	private static func firstLine(in text: String) -> String {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			return ""
		}

		for line in trimmed.components(separatedBy: .newlines) {
			let candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
			if !candidate.isEmpty {
				return candidate
			}
		}
		return trimmed
	}

	private init(title: String, summary: String, dateString: String, feedName: String, byline: String, showFeedName: ShowFeedName, iconImage: IconImage?, showIcon: Bool, read: Bool, starred: Bool, showIndicator: Bool, isGeneratedSummaryRow: Bool, numberOfLines: Int, iconSize: IconSize) {
		self.title = title
		self.attributedTitle = NSAttributedString(string: title)
		self.summary = summary
		self.dateString = dateString
		self.feedName = feedName
		self.byline = byline
		self.showFeedName = showFeedName
		self.iconImage = iconImage
		self.showIcon = showIcon
		self.read = read
		self.starred = starred
		self.showIndicator = showIndicator
		self.isGeneratedSummaryRow = isGeneratedSummaryRow
		self.numberOfLines = numberOfLines
		self.iconSize = iconSize
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
		self.showIndicator = false
		self.isGeneratedSummaryRow = false
		self.numberOfLines = 0
		self.iconSize = .medium
	}

}
