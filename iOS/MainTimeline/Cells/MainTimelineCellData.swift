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

		// Listing view is title-only: suppress content snippets.
		self.summary = ""

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
