//
//  ArticleRenderer.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 9/8/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import Foundation
#if os(iOS)
import UIKit
#endif
import RSCore
import Articles
import Account

@MainActor struct ArticleRenderer {

	typealias Rendering = (style: String, html: String, title: String, baseURL: String)

	struct Page {
		let url: URL
		let baseURL: URL
		let html: String

		init(name: String) {
			url = Bundle.main.url(forResource: name, withExtension: "html")!
			baseURL = url.deletingLastPathComponent()
			html = try! String(contentsOfFile: url.path, encoding: .utf8)
		}
	}

	static var imageIconScheme = "nnwImageIcon"

	static var blank = Page(name: "blank")
	static var page = Page(name: "page")

	private let article: Article?
	private let extractedArticle: ExtractedArticle?
	private let articleTheme: ArticleTheme
	private let title: String
	private let body: String
	private let baseURL: String?

	private static let longDateTimeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .long
		formatter.timeStyle = .medium
		return formatter
	}()

	private static let mediumDateTimeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .short
		return formatter
	}()

	private static let shortDateTimeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .short
		formatter.timeStyle = .short
		return formatter
	}()

	private static let longDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .long
		formatter.timeStyle = .none
		return formatter
	}()

	private static let mediumDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .none
		return formatter
	}()

	private static let shortDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .short
		formatter.timeStyle = .none
		return formatter
	}()

	private static let longTimeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .long
		return formatter
	}()

	private static let mediumTimeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .medium
		return formatter
	}()

	private static let shortTimeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .short
		return formatter
	}()

	private init(article: Article?, extractedArticle: ExtractedArticle?, theme: ArticleTheme) {
		self.article = article
		self.extractedArticle = extractedArticle
		self.articleTheme = theme
		self.title = article?.sanitizedTitle() ?? ""
		if let content = extractedArticle?.content {
			self.body = content
			self.baseURL = extractedArticle?.url
		} else {
			self.body = article?.body ?? ""
			self.baseURL = article?.baseURL?.absoluteString
		}
	}

	// MARK: - API

	static func articleHTML(article: Article, extractedArticle: ExtractedArticle? = nil, theme: ArticleTheme) -> Rendering {
		let renderer = ArticleRenderer(article: article, extractedArticle: extractedArticle, theme: theme)
		return (renderer.articleCSS, renderer.articleHTML, renderer.title, renderer.baseURL ?? "")
	}

	static func multipleSelectionHTML(theme: ArticleTheme) -> Rendering {
		let renderer = ArticleRenderer(article: nil, extractedArticle: nil, theme: theme)
		return (renderer.articleCSS, renderer.multipleSelectionHTML, renderer.title, renderer.baseURL ?? "")
	}

	static func loadingHTML(theme: ArticleTheme) -> Rendering {
		let renderer = ArticleRenderer(article: nil, extractedArticle: nil, theme: theme)
		return (renderer.articleCSS, renderer.loadingHTML, renderer.title, renderer.baseURL ?? "")
	}

	static func noSelectionHTML(theme: ArticleTheme) -> Rendering {
		let renderer = ArticleRenderer(article: nil, extractedArticle: nil, theme: theme)
		return (renderer.articleCSS, renderer.noSelectionHTML, renderer.title, renderer.baseURL ?? "")
	}

	static func noContentHTML(theme: ArticleTheme) -> Rendering {
		let renderer = ArticleRenderer(article: nil, extractedArticle: nil, theme: theme)
		return (renderer.articleCSS, renderer.noContentHTML, renderer.title, renderer.baseURL ?? "")
	}
}

// MARK: - Private

private extension ArticleRenderer {

	private var articleHTML: String {
		return try! MacroProcessor.renderedText(withTemplate: template(), substitutions: articleSubstitutions())
	}

	private var multipleSelectionHTML: String {
		let body = "<h3 class='systemMessage'>Multiple selection</h3>"
		return body
	}

	private var loadingHTML: String {
		let body = "<h3 class='systemMessage'>Loading...</h3>"
		return body
	}

	private var noSelectionHTML: String {
		let body = "<h3 class='systemMessage'>No selection</h3>"
		return body
	}

	private var noContentHTML: String {
		return ""
	}

	private var articleCSS: String {
		return try! MacroProcessor.renderedText(withTemplate: styleString(), substitutions: styleSubstitutions())
	}

	static var defaultStyleSheet: String = {
		let path = Bundle.main.path(forResource: "stylesheet", ofType: "css")!
		let s = try! String(contentsOfFile: path, encoding: .utf8)
		return "\n\(s)\n"
	}()

	static let defaultTemplate: String = {
		let path = Bundle.main.path(forResource: "template", ofType: "html")!
		let s = try! String(contentsOfFile: path, encoding: .utf8)
		return s as String
	}()

	func styleString() -> String {
		return articleTheme.css ?? ArticleRenderer.defaultStyleSheet
	}

	func template() -> String {
		return articleTheme.template ?? ArticleRenderer.defaultTemplate
	}

	func articleSubstitutions() -> [String: String] {
		var d = [String: String]()

		guard let article = article else {
			assertionFailure("Article should have been set before calling this function.")
			return d
		}

		d["title"] = title

		// Custom source categories:
		// - YouTube/Podcast titles get a dedicated media icon link beside the title.
		// - News titles are not linked.
		let feedCategory = article.feed?.feedCategory ?? .rss
		if feedCategory == .youtube {
			let mediaLink = topTitleMediaLink(for: article, feedCategory: .youtube)
			let preferredLink = mediaLink ?? article.preferredLink ?? ""
			d["preferred_link"] = preferredLink
			d["title_html"] = renderedTitleHTML(title: title, mediaLink: mediaLink, feedCategory: .youtube)
		} else if feedCategory == .podcast {
			let mediaLink = topTitleMediaLink(for: article, feedCategory: .podcast)
			d["preferred_link"] = ""
			d["title_html"] = renderedTitleHTML(title: title, mediaLink: mediaLink, feedCategory: .podcast)
		} else if feedCategory == .news {
			d["preferred_link"] = ""
			d["title_html"] = title.escapingSpecialXMLCharacters
		} else {
			let preferredLink = article.preferredLink ?? ""
			d["preferred_link"] = preferredLink
			if preferredLink.isEmpty {
				d["title_html"] = title.escapingSpecialXMLCharacters
			} else {
				d["title_html"] = "<a href=\"\(preferredLink.escapingSpecialXMLCharacters)\">\(title.escapingSpecialXMLCharacters)</a>"
			}
		}

		if let externalLink = article.externalLink, externalLink != article.preferredLink {
			d["external_link_label"] = NSLocalizedString("Link:", comment: "Link")
			d["external_link_stripped"] = externalLink.strippingHTTPOrHTTPSScheme
			d["external_link"] = externalLink
		} else {
			d["external_link_label"] = ""
			d["external_link_stripped"] = ""
			d["external_link"] = ""
		}

		d["body"] = body

		#if os(macOS)
		d["text_size_class"] = AppDefaults.shared.articleTextSize.cssClass
		#endif

		var components = URLComponents()
		components.scheme = Self.imageIconScheme
		components.path = article.articleID
		if let imageIconURLString = components.string {
			d["avatar_src"] = imageIconURLString
		} else {
			d["avatar_src"] = ""
		}

		if self.title.isEmpty {
			d["dateline_style"] = "articleDatelineTitle"
		} else {
			d["dateline_style"] = "articleDateline"
		}

		let feedName = article.feed?.nameForDisplay ?? ""
		let feedLink = article.feed?.homePageURL ?? ""
		d["feed_link_title"] = feedName

		// News feeds: no clickable link on the feed title
		if article.feed?.feedCategory == .news || feedLink.isEmpty {
			d["feed_link"] = ""
		} else {
			d["feed_link"] = feedLink
		}

		// Provide pre-rendered feed link HTML: linked or plain text
		if !feedLink.isEmpty && article.feed?.feedCategory != .news {
			d["feed_link_html"] = "<a class=\"feedlink\" href=\"\(feedLink.escapingSpecialXMLCharacters)\">\(feedName.escapingSpecialXMLCharacters)</a>"
		} else {
			d["feed_link_html"] = "<span class=\"feedlink\">\(feedName.escapingSpecialXMLCharacters)</span>"
		}

		d["byline"] = byline()

		// Only show a timestamp when the feed actually supplied a date.
		// logicalDatePublished falls back to dateArrived, which is meaningless to display.
		guard let datePublished = article.datePublished ?? article.dateModified else {
			d["datetime_long"] = ""
			d["datetime_medium"] = ""
			d["datetime_short"] = ""
			d["datetime_html"] = ""
			d["date_long"] = ""
			d["date_medium"] = ""
			d["date_short"] = ""
			d["time_long"] = ""
			d["time_medium"] = ""
			d["time_short"] = ""
			return d
		}

		d["datetime_long"] = Self.longDateTimeFormatter.string(from: datePublished)
		let datetimeMedium = Self.mediumDateTimeFormatter.string(from: datePublished)
		d["datetime_medium"] = datetimeMedium
		d["datetime_short"] = Self.shortDateTimeFormatter.string(from: datePublished)

		// Add datetime_html that conditionally includes the link
		let preferredLink = d["preferred_link"] ?? ""
		if preferredLink.isEmpty {
			d["datetime_html"] = datetimeMedium.escapingSpecialXMLCharacters
		} else {
			d["datetime_html"] = "<a href=\"\(preferredLink.escapingSpecialXMLCharacters)\">\(datetimeMedium.escapingSpecialXMLCharacters)</a>"
		}
		d["date_long"] = Self.longDateFormatter.string(from: datePublished)
		d["date_medium"] = Self.mediumDateFormatter.string(from: datePublished)
		d["date_short"] = Self.shortDateFormatter.string(from: datePublished)
		d["time_long"] = Self.longTimeFormatter.string(from: datePublished)
		d["time_medium"] = Self.mediumTimeFormatter.string(from: datePublished)
		d["time_short"] = Self.shortTimeFormatter.string(from: datePublished)

		return d
	}

	func topTitleMediaLink(for article: Article, feedCategory: FeedCategory) -> String? {
		if let mediaLink = article.mp3URL?.trimmingCharacters(in: .whitespacesAndNewlines), !mediaLink.isEmpty {
			return mediaLink
		}

		guard feedCategory == .youtube else {
			return nil
		}

		let candidates = [article.preferredLink, article.externalLink, article.link]
		for candidate in candidates {
			if let resolved = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !resolved.isEmpty {
				return resolved
			}
		}
		return nil
	}

	func renderedTitleHTML(title: String, mediaLink: String?, feedCategory: FeedCategory) -> String {
		let escapedTitle = title.escapingSpecialXMLCharacters
		let titleSpan = "<span class=\"nnw-title-text\">\(escapedTitle)</span>"
		guard let mediaLink, !mediaLink.isEmpty else {
			return titleSpan
		}

		let accessibilityLabel: String
		switch feedCategory {
		case .youtube:
			accessibilityLabel = NSLocalizedString("Watch Video", comment: "Watch Video")
		default:
			accessibilityLabel = NSLocalizedString("Listen", comment: "Listen")
		}

		let escapedURL = mediaLink.escapingSpecialXMLCharacters
		let escapedLabel = accessibilityLabel.escapingSpecialXMLCharacters
		let mediaType: String = (feedCategory == .youtube) ? "youtube" : "podcast"
		let mediaIconHTML = "<a class=\"nnw-top-media-link\" href=\"#\" data-media-url=\"\(escapedURL)\" data-media-type=\"\(mediaType)\" title=\"\(escapedLabel)\" aria-label=\"\(escapedLabel)\">&#9654;</a>"
		return "\(titleSpan) \(mediaIconHTML)"
	}

	func byline() -> String {
		guard let authors = article?.authors ?? article?.feed?.authors, !authors.isEmpty else {
			return ""
		}

		// If the author's name is the same as the feed, then we don't want to display it.
		// This code assumes that multiple authors would never match the feed name so that
		// if there feed owner has an article co-author all authors are given the byline.
		if authors.count == 1, let author = authors.first {
			if author.name == article?.feed?.nameForDisplay {
				return ""
			}
		}

		var byline = ""
		var isFirstAuthor = true

		for author in authors {
			if !isFirstAuthor {
				byline += ", "
			}
			isFirstAuthor = false

			var authorEmailAddress: String?
			if let emailAddress = author.emailAddress, !(emailAddress.contains("noreply@") || emailAddress.contains("no-reply@")) {
				authorEmailAddress = emailAddress
			}

			if let emailAddress = authorEmailAddress, emailAddress.contains(" ") {
				byline += emailAddress // probably name plus email address
			} else if let name = author.name, let url = author.url {
				byline += name.htmlByAddingLink(url)
			} else if let name = author.name, let emailAddress = authorEmailAddress {
				byline += "\(name) &lt;\(emailAddress)&gt;"
			} else if let name = author.name {
				byline += name
			} else if let emailAddress = authorEmailAddress {
				byline += "&lt;\(emailAddress)&gt;" // TODO: mailto link
			} else if let url = author.url {
				byline += String.htmlWithLink(url)
			}
		}

		return byline
	}

	#if os(iOS)
	func styleSubstitutions() -> [String: String] {
		var d = [String: String]()
		let bodyFont = UIFont.preferredFont(forTextStyle: .body)
		d["font-size"] = String(describing: bodyFont.pointSize)
		d["color-page-bg-light"]      = Assets.Colors.background.hexString(forStyle: .light)
		d["color-page-bg-dark"]       = Assets.Colors.background.hexString(forStyle: .dark)
		d["color-groupbox-bg-light"]  = Assets.Colors.foreground.hexString(forStyle: .light)
		d["color-groupbox-bg-dark"]   = Assets.Colors.foreground.hexString(forStyle: .dark)
		d["color-accent-light"]       = Assets.Colors.primaryAccent.hexString(forStyle: .light)
		d["color-accent-dark"]        = Assets.Colors.primaryAccent.hexString(forStyle: .dark)
		d["color-accent2-dark"]       = Assets.Colors.secondaryAccent.hexString(forStyle: .dark)
		d["groupbox-box-shadow"]      = Assets.Colors.groupboxBoxShadow
		d["groupbox-box-shadow-dark"] = Assets.Colors.groupboxBoxShadowDark
		d["groupbox-border-radius"]   = "\(Int(Assets.Colors.boxCornerRadius))px"
		return d
	}
	#else
	func styleSubstitutions() -> [String: String] {
		return [String: String]()
	}
	#endif

}

// MARK: - Article extension

@MainActor private extension Article {

	var baseURL: URL? {
		var s = link
		if s == nil {
			s = feed?.homePageURL
		}
		if s == nil {
			s = feed?.url
		}

		guard let urlString = s else {
			return nil
		}
		var urlComponents = URLComponents(string: urlString)
		if urlComponents == nil {
			return nil
		}

		// Can’t use url-with-fragment as base URL. The webview won’t load. See scripting.com/rss.xml for example.
		urlComponents!.fragment = nil
		guard let url = urlComponents!.url, url.scheme == "http" || url.scheme == "https" else {
			return nil
		}
		return url
	}
}
