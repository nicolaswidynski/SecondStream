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

	private static let noText = NSLocalizedString("(No Text)", comment: "No Text")

	let title: String
	let attributedTitle: NSAttributedString
	let summary: String
	let dateString: String
	let inlineDateString: String
	let feedName: String
	let byline: String
	let showFeedName: ShowFeedName
	let iconImage: IconImage? // feed icon, user avatar, or favicon
	let showIcon: Bool // Make space even when icon is nil
	let read: Bool
	let starred: Bool
	let numberOfLines: Int
	let iconSize: IconSize
	let readingTimeMinutes: Int?

	init(article: Article, showFeedName: ShowFeedName, feedName: String?, byline: String?, iconImage: IconImage?, showIcon: Bool, numberOfLines: Int, iconSize: IconSize, includeListingSummary: Bool = true, dateStringOverride: String? = nil, overrideStarred: Bool? = nil) {

		self.title = ArticleStringFormatter.truncatedTitle(article)
		self.attributedTitle = ArticleStringFormatter.attributedTruncatedTitle(article)

		if includeListingSummary {
			let truncatedSummary = ArticleStringFormatter.truncatedSummary(article)
			if self.title.isEmpty && truncatedSummary.isEmpty {
				self.summary = Self.noText
			} else {
				self.summary = truncatedSummary
			}
		} else {
			self.summary = ""
		}

		self.dateString = dateStringOverride ?? ArticleStringFormatter.dateString(article.logicalDatePublished)
		self.inlineDateString = ArticleStringFormatter.inlineDateString(article.logicalDatePublished)

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
		self.starred = overrideStarred ?? article.status.starred
		self.numberOfLines = numberOfLines
		self.iconSize = iconSize
		if !article.status.read, let wc = article.wordCount, wc > 0 {
			self.readingTimeMinutes = max(1, wc / 200)
		} else {
			self.readingTimeMinutes = nil
		}

	}

	init() { // Empty
		self.title = ""
		self.attributedTitle = NSAttributedString()
		self.summary = ""
		self.dateString = ""
		self.inlineDateString = ""
		self.feedName = ""
		self.byline = ""
		self.showFeedName = .none
		self.showIcon = false
		self.iconImage = nil
		self.read = true
		self.starred = false
		self.numberOfLines = 0
		self.iconSize = .medium
		self.readingTimeMinutes = nil
	}

}
