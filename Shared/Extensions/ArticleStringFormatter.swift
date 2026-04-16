//
//  ArticleStringFormatter.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 8/31/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import Articles
import RSParser

@MainActor struct ArticleStringFormatter {
	private static var feedNameCache = [String: String]()
	private static var titleCache = [String: String]()
	private static var summaryCache = [String: String]()

	private static let dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .none
		return formatter
	}()

	private static let timeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .short
		return formatter
	}()

	private static let inlineDayFormatter: DateFormatter = {
		let f = DateFormatter()
		f.dateFormat = "MMM d"
		return f
	}()

	private static let inlineYearFormatter: DateFormatter = {
		let f = DateFormatter()
		f.dateFormat = "yyyy"
		return f
	}()

	static func emptyCaches() {
		feedNameCache = [String: String]()
		titleCache = [String: String]()
		summaryCache = [String: String]()
	}

	static func truncatedFeedName(_ feedName: String) -> String {
		if let cachedFeedName = feedNameCache[feedName] {
			return cachedFeedName
		}

		let maxFeedNameLength = 100
		if feedName.count < maxFeedNameLength {
			feedNameCache[feedName] = feedName
			return feedName
		}

		let s = (feedName as NSString).substring(to: maxFeedNameLength)
		feedNameCache[feedName] = s
		return s
	}

	static func truncatedTitle(_ article: Article, forHTML: Bool = false) -> String {
		guard let title = article.sanitizedTitle(forHTML: forHTML) else {
			return ""
		}

		if let cachedTitle = titleCache[title] {
			return cachedTitle
		}

		var s = title.replacingOccurrences(of: "\n", with: "")
		s = s.replacingOccurrences(of: "\r", with: "")
		s = s.replacingOccurrences(of: "\t", with: "")

		if !forHTML {
			s = s.rsparser_stringByDecodingHTMLEntities()
		}

		s = s.trimmingWhitespace
		s = s.collapsingWhitespace

		let maxLength = 1000
		if s.count < maxLength {
			titleCache[title] = s
			return s
		}

		s = (s as NSString).substring(to: maxLength)
		titleCache[title] = s
		return s
	}

	static func attributedTruncatedTitle(_ article: Article) -> NSAttributedString {
		let title = truncatedTitle(article, forHTML: true)
		let attributed = NSAttributedString(html: title)
		return attributed
	}

	static func truncatedSummary(_ article: Article) -> String {
		guard let body = article.body else {
			return ""
		}

		let key = article.articleID + article.accountID
		if let cachedBody = summaryCache[key] {
			return cachedBody
		}
		var s = body.rsparser_stringByDecodingHTMLEntities()
		s = s.strippingHTML(maxCharacters: 300)
		if s == "Comments" { // Hacker News.
			s = ""
		}
		summaryCache[key] = s
		return s
	}

	static func dateString(_ date: Date) -> String {
		if Calendar.dateIsToday(date) {
			return timeFormatter.string(from: date)
		}
		return dateFormatter.string(from: date)
	}

	/// Two-line date for the left-column date label in the article listing.
	/// Today → "Today\n3:45 PM"; other days → "April 7\n2026".
	static func inlineDateString(_ date: Date) -> String {
		if Calendar.dateIsToday(date) {
			return NSLocalizedString("Today", comment: "Today date label") + "\n" + timeFormatter.string(from: date)
		}
		return inlineDayFormatter.string(from: date) + "\n" + inlineYearFormatter.string(from: date)
	}
}
