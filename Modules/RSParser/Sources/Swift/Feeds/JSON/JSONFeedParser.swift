//
//  JSONFeedParser.swift
//  RSParser
//
//  Created by Brent Simmons on 6/25/17.
//  Copyright © 2017 Ranchero Software, LLC. All rights reserved.
//

import Foundation
#if SWIFT_PACKAGE
import RSParserObjC
#endif

// See https://jsonfeed.org/version/1.1

public struct JSONFeedParser {

	struct Key {
		static let version = "version"
		static let items = "items"
		static let entries = "entries"
		static let title = "title"
		static let homePageURL = "home_page_url"
		static let homepage = "homepage"
		static let feedURL = "feed_url"
		static let feedDescription = "description"
		static let nextURL = "next_url"
		static let icon = "icon"
		static let imageLink = "image_link"
		static let favicon = "favicon"
		static let expired = "expired"
		static let author = "author"
		static let authors = "authors"
		static let name = "name"
		static let url = "url"
		static let avatar = "avatar"
		static let hubs = "hubs"
		static let type = "type"
		static let contentHTML = "content_html"
		static let contentText = "content_text"
		static let externalURL = "external_url"
		static let summary = "summary"
		static let image = "image"
		static let bannerImage = "banner_image"
		static let datePublished = "date_published"
		static let dateModified = "date_modified"
		static let tags = "tags"
		static let uniqueID = "id"
		static let attachments = "attachments"
		static let mimeType = "mime_type"
		static let sizeInBytes = "size_in_bytes"
		static let durationInSeconds = "duration_in_seconds"
		static let language = "language"
		static let idFile = "id_file"
		static let idEntry = "id_entry"
		static let mediaLink = "media_link"
		static let airDate = "air_date"
		static let content = "content"
		static let metadata = "metadata"
		static let pubDate = "pubDate"
		static let practicalApplications = "practical_applications"
		static let deepDive = "deep_dive"
	}

	static let jsonFeedVersionMarker = "://jsonfeed.org/version/" // Allow for the mistake of not getting the scheme exactly correct.

	public static func parse(_ parserData: ParserData) throws -> ParsedFeed? {

		guard let d = JSONUtilities.dictionary(with: parserData.data) else {
			throw FeedParserError.invalidJSON
		}

		if let version = d[Key.version] as? String, version.range(of: JSONFeedParser.jsonFeedVersionMarker) != nil {
			return try parseJSONFeed(d, parserData.url)
		}

		if isGeneratedJSONFeed(d) {
			return try parseGeneratedJSONFeed(d, parserData.url)
		}

		throw FeedParserError.jsonFeedVersionNotFound
	}
}

private extension JSONFeedParser {

	static func parseJSONFeed(_ d: JSONDictionary, _ parserURL: String) throws -> ParsedFeed {
		guard let itemsArray = d[Key.items] as? JSONArray else {
			throw FeedParserError.jsonFeedItemsNotFound
		}
		guard let title = d[Key.title] as? String else {
			throw FeedParserError.jsonFeedTitleNotFound
		}

		let authors = parseAuthors(d)
		let homePageURL = d[Key.homePageURL] as? String
		let feedURL = d[Key.feedURL] as? String ?? parserURL
		let feedDescription = d[Key.feedDescription] as? String
		let nextURL = d[Key.nextURL] as? String
		let iconURL = d[Key.icon] as? String
		let faviconURL = d[Key.favicon] as? String
		let expired = d[Key.expired] as? Bool ?? false
		let hubs = parseHubs(d)
		let language = d[Key.language] as? String

		let items = parseItems(itemsArray, parserURL)

		return ParsedFeed(type: .jsonFeed, title: title, homePageURL: homePageURL, feedURL: feedURL, language: language, feedDescription: feedDescription, nextURL: nextURL, iconURL: iconURL, faviconURL: faviconURL, authors: authors, expired: expired, hubs: hubs, items: items)
	}

	static func isGeneratedJSONFeed(_ dictionary: JSONDictionary) -> Bool {
		(dictionary[Key.entries] as? JSONArray) != nil &&
		(dictionary[Key.idFile] as? String) != nil &&
		(dictionary[Key.title] as? String) != nil
	}

	static func parseGeneratedJSONFeed(_ dictionary: JSONDictionary, _ parserURL: String) throws -> ParsedFeed {
		guard let entries = dictionary[Key.entries] as? JSONArray else {
			throw FeedParserError.jsonFeedItemsNotFound
		}
		guard let title = dictionary[Key.title] as? String else {
			throw FeedParserError.jsonFeedTitleNotFound
		}

		let authors = parseGeneratedAuthors(dictionary)
		let homePageURL = nonEmptyString(dictionary[Key.homepage]) ?? nonEmptyString(dictionary[Key.homePageURL])
		let iconURL = nonEmptyString(dictionary[Key.imageLink]) ?? nonEmptyString(dictionary[Key.icon])
		let dateModified = parseDate(nonEmptyString(dictionary["updated"]))
		let items = parseGeneratedItems(entries, parserURL, dateModified)

		return ParsedFeed(
			type: .jsonFeed,
			title: title,
			homePageURL: homePageURL,
			feedURL: parserURL,
			language: nil,
			feedDescription: nil,
			nextURL: nil,
			iconURL: iconURL,
			faviconURL: nil,
			authors: authors,
			expired: false,
			hubs: nil,
			items: items
		)
	}

	static func parseAuthors(_ dictionary: JSONDictionary) -> Set<ParsedAuthor>? {

		if let authorsArray = dictionary[Key.authors] as? JSONArray {
			var authors = Set<ParsedAuthor>()
			for author in authorsArray {
				if let parsedAuthor = parseAuthor(author) {
					authors.insert(parsedAuthor)
				}
			}
			return authors
		}

		guard let authorDictionary = dictionary[Key.author] as? JSONDictionary,
			  let parsedAuthor = parseAuthor(authorDictionary) else {
			return nil
		}

		return Set([parsedAuthor])
	}

	static func parseGeneratedAuthors(_ dictionary: JSONDictionary) -> Set<ParsedAuthor>? {
		guard let author = nonEmptyString(dictionary[Key.author]) else {
			return nil
		}
		return Set([ParsedAuthor(name: author, url: nil, avatarURL: nil, emailAddress: nil)])
	}

	static func parseGeneratedItems(_ entries: JSONArray, _ feedURL: String, _ fallbackModifiedDate: Date?) -> Set<ParsedItem> {
		Set(entries.compactMap { parseGeneratedItem($0, feedURL, fallbackModifiedDate) })
	}

	static func parseGeneratedItem(_ itemDictionary: JSONDictionary, _ feedURL: String, _ fallbackModifiedDate: Date?) -> ParsedItem? {
		let uniqueID = nonEmptyString(itemDictionary[Key.idEntry]) ?? {
			guard let title = nonEmptyString(itemDictionary[Key.title]) else { return nil }
			return "\(feedURL)::\(title)"
		}()
		guard let uniqueID else {
			return nil
		}

		let entryContent = itemDictionary[Key.content]
		let contentJSON = jsonString(from: entryContent)
		let contentHTML = generatedHTMLFromContent(entryContent)
		let entryTitle = nonEmptyString(itemDictionary[Key.title])
		let inferredTitle = inferGeneratedTitle(from: entryContent)
		let isTopicsEntry = uniqueID.hasPrefix("topics/")
		let title = entryTitle ?? (isTopicsEntry ? nil : inferredTitle)
		let contentText = contentTextFromGeneratedContent(entryContent)
		let mediaLink = parseGeneratedMediaLink(itemDictionary, entryContent)
		let datePublished = parseDate(nonEmptyString(itemDictionary[Key.airDate])) ?? parseDateFromGeneratedContent(entryContent) ?? fallbackModifiedDate

		if title == nil && contentJSON == nil && contentText == nil {
			return nil
		}

		return ParsedItem(
			syncServiceID: nil,
			uniqueID: uniqueID,
			feedURL: feedURL,
			url: nil,
			externalURL: nil,
			title: title,
			language: nil,
			contentHTML: contentHTML,
			contentText: contentText ?? title,
			markdown: nil,
			contentJSON: contentJSON,
			summary: nil,
			imageURL: nil,
			bannerImageURL: nil,
			datePublished: datePublished,
			dateModified: fallbackModifiedDate,
			authors: nil,
			tags: nil,
			attachments: nil,
			mp3URL: mediaLink
		)
	}

	/// Returns the topics articles array from content, whether it is a bare JSONArray
	/// (old format) or a JSONDictionary with an "articles" key (new format).
	static func topicsArray(from content: Any?) -> JSONArray? {
		if let array = content as? JSONArray {
			return array
		}
		if let dictionary = content as? JSONDictionary,
		   let articles = dictionary["articles"] as? JSONArray {
			return articles
		}
		return nil
	}

	static func generatedHTMLFromContent(_ content: Any?) -> String? {
		if let articles = topicsArray(from: content) {
			return generatedTopicsHTML(from: articles)
		}
		if let dictionary = content as? JSONDictionary {
			return generatedShowHTML(from: dictionary)
		}
		return nil
	}

	// MARK: - Section icons (inline SVG, currentColor → inherits header blue)

	private static let iconSummary = "<svg width=\"16\" height=\"16\" viewBox=\"0 0 12 12\" fill=\"currentColor\" style=\"vertical-align:middle;margin-right:5px\"><rect x=\"1\" y=\"1.5\" width=\"10\" height=\"1.5\" rx=\"0.75\"/><rect x=\"1\" y=\"5\" width=\"10\" height=\"1.5\" rx=\"0.75\"/><rect x=\"1\" y=\"8.5\" width=\"7\" height=\"1.5\" rx=\"0.75\"/></svg>"

	private static let iconPractical = "<svg width=\"16\" height=\"16\" viewBox=\"0 0 12 12\" fill=\"currentColor\" style=\"vertical-align:middle;margin-right:5px\"><path d=\"M6 0.5a3 3 0 0 0-1.8 5.4V8h3.6V5.9A3 3 0 0 0 6 0.5zm-1 8.5h2v.4a1 1 0 0 1-2 0V9z\"/></svg>"

	private static let iconDeepDive = "<svg width=\"16\" height=\"16\" viewBox=\"0 0 12 12\" fill=\"currentColor\" style=\"vertical-align:middle;margin-right:5px\"><circle cx=\"9\" cy=\"2\" r=\"1.2\"/><path d=\"M1.5 5.5 5 3.5l1.5 2.5-2.5 1.5 1 2H3.5L1.5 7z\"/><path d=\"M1 9.5 Q3 8 5 9.5 Q7 11 9 9.5 Q11 8 11 8\" stroke=\"currentColor\" stroke-width=\"1.1\" fill=\"none\" stroke-linecap=\"round\"/></svg>"

	static func generatedShowHTML(from dictionary: JSONDictionary) -> String? {
		var blocks = [String]()

		let timestampLines = dictionary["timestamps"].flatMap { timestampLinesHTML(from: $0) } ?? []
		if !timestampLines.isEmpty {
			blocks.append("<hr><details><summary><strong>Timestamps</strong></summary><ul class=\"nnw-generated-bullet-list nnw-generated-timestamps-list\">\(timestampLines.joined())</ul></details><hr>")
		}

		let summaryBlocks = titledContentLinesHTML(from: dictionary[Key.summary])
		if !summaryBlocks.isEmpty {
			blocks.append("<h2>\(iconSummary)Summary</h2><ul class=\"nnw-generated-bullet-list\">\(summaryBlocks.joined())</ul>")
		}

		let practicalBlocks = titledContentLinesHTML(from: dictionary[Key.practicalApplications])
		if !practicalBlocks.isEmpty {
			blocks.append("<h2>\(iconPractical)Practical Applications</h2><ul class=\"nnw-generated-bullet-list\">\(practicalBlocks.joined())</ul>")
		}

		let inDepthParagraphs = titledContentParagraphsHTML(from: dictionary[Key.deepDive])
		if !inDepthParagraphs.isEmpty {
			blocks.append("<h2>\(iconDeepDive)Deep Dive</h2>\(inDepthParagraphs.joined())")
		}

		let html = blocks.joined(separator: "\n")
		return html.isEmpty ? nil : html
	}

	static func timestampLinesHTML(from value: Any?) -> [String] {
		guard let timestamps = value as? JSONArray else {
			return []
		}
		return timestamps.compactMap { item -> String? in
			let timestamp = nonEmptyString(item["timestamp"]) ?? ""
			let content = nonEmptyString(item[Key.content]) ?? ""
			guard !timestamp.isEmpty || !content.isEmpty else { return nil }
			if !timestamp.isEmpty && !content.isEmpty {
				return "<li class=\"nnw-generated-bullet-item\"><strong>\(htmlEscaped(timestamp))</strong> - \(htmlEscaped(content))</li>"
			}
			if !timestamp.isEmpty {
				return "<li class=\"nnw-generated-bullet-item\"><strong>\(htmlEscaped(timestamp))</strong></li>"
			}
			return "<li class=\"nnw-generated-bullet-item\">\(htmlEscaped(content))</li>"
		}
	}

	static func titledContentLinesHTML(from value: Any?) -> [String] {
		guard let items = value as? JSONArray else {
			return []
		}
		return items.compactMap { item -> String? in
			let title = nonEmptyString(item[Key.title]) ?? ""
			let content = nonEmptyString(item[Key.content]) ?? ""
			guard !title.isEmpty || !content.isEmpty else { return nil }
			if !title.isEmpty && !content.isEmpty {
				return "<li class=\"nnw-generated-bullet-item\"><strong>\(htmlEscaped(title))</strong>: \(htmlEscaped(content))</li>"
			}
			return "<li class=\"nnw-generated-bullet-item\">\(htmlEscaped(title + content))</li>"
		}
	}

	static func titledContentParagraphsHTML(from value: Any?) -> [String] {
		guard let items = value as? JSONArray else {
			return []
		}
		return items.compactMap { item -> String? in
			let title = nonEmptyString(item[Key.title]) ?? ""
			let content = nonEmptyString(item[Key.content]) ?? ""
			guard !title.isEmpty || !content.isEmpty else { return nil }
			if !title.isEmpty && !content.isEmpty {
				return "<p><strong>\(htmlEscaped(title))</strong>: \(htmlEscaped(content))</p>"
			}
			return "<p>\(htmlEscaped(title + content))</p>"
		}
	}

	static func generatedTopicsHTML(from items: JSONArray) -> String? {
		let sections = items.compactMap { item -> String? in
			let title = nonEmptyString(item[Key.title]) ?? "Untitled"
			let metadata = item[Key.metadata] as? JSONDictionary
			let link = nonEmptyString(metadata?["link"])
			let author = nonEmptyString(metadata?["author"])
			let pubDate = nonEmptyString(metadata?[Key.pubDate])

			let iconNews = "<svg width=\"16\" height=\"16\" viewBox=\"0 0 12 12\" fill=\"currentColor\" style=\"vertical-align:middle;margin-right:5px\"><rect x=\"1\" y=\"1\" width=\"10\" height=\"10\" rx=\"1.5\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.2\"/><rect x=\"2.5\" y=\"2.5\" width=\"7\" height=\"1.5\" rx=\"0.5\"/><rect x=\"2.5\" y=\"5\" width=\"7\" height=\"1\" rx=\"0.5\"/><rect x=\"2.5\" y=\"7\" width=\"4.5\" height=\"1\" rx=\"0.5\"/></svg>"
			let titleHTML: String
			if let link {
				titleHTML = "<h3>\(iconNews)<a href=\"\(htmlEscaped(link))\">\(htmlEscaped(title))</a></h3>"
			} else {
				titleHTML = "<h3>\(iconNews)\(htmlEscaped(title))</h3>"
			}

			var metadataLines = [String]()
			if let author {
				metadataLines.append("<li><strong>Author</strong>: \(htmlEscaped(author))</li>")
			}
			if let pubDate {
				metadataLines.append("<li><strong>Published</strong>: \(htmlEscaped(pubDate))</li>")
			}
			let metadataHTML = metadataLines.isEmpty ? "" : "<ul class=\"nnw-topics-metadata\">\(metadataLines.joined())</ul>"

			let summaryHTML = generatedTopicsSummaryHTML(item[Key.summary])

			return "\(titleHTML)\(metadataHTML)\(summaryHTML)"
		}

		guard !sections.isEmpty else {
			return nil
		}
		return sections.joined(separator: "\n")
	}

	static func generatedTopicsSummaryHTML(_ value: Any?) -> String {
		if let list = value as? [String] {
			let items = list
				.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
				.filter { !$0.isEmpty }
				.map { "<li class=\"nnw-generated-bullet-item\">\(htmlEscaped($0))</li>" }
			guard !items.isEmpty else { return "<p>No summary available.</p>" }
			return "<ul class=\"nnw-generated-bullet-list\">\(items.joined())</ul>"
		}

		guard let text = nonEmptyString(value) else {
			return "<p>No summary available.</p>"
		}

		let lines = text
			.components(separatedBy: .newlines)
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
		if !lines.isEmpty && lines.allSatisfy({ $0.hasPrefix("- ") || $0.hasPrefix("• ") }) {
			let items = lines.map { line -> String in
				let content = line.hasPrefix("• ") ? String(line.dropFirst(2)) : String(line.dropFirst(2))
				return "<li class=\"nnw-generated-bullet-item\">\(htmlEscaped(content))</li>"
			}
			return "<ul class=\"nnw-generated-bullet-list\">\(items.joined())</ul>"
		}

		return "<p>\(htmlEscaped(text))</p>"
	}

	static func htmlEscaped(_ string: String) -> String {
		string
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
			.replacingOccurrences(of: "'", with: "&#39;")
	}

	static func inferGeneratedTitle(from content: Any?) -> String? {
		guard let articles = topicsArray(from: content) else {
			return nil
		}
		for item in articles {
			if let title = nonEmptyString(item[Key.title]) {
				return title
			}
		}
		return nil
	}

	static func parseDateFromGeneratedContent(_ content: Any?) -> Date? {
		guard let articles = topicsArray(from: content) else {
			return nil
		}

		for item in articles {
			guard let metadata = item[Key.metadata] as? JSONDictionary,
				  let pubDate = nonEmptyString(metadata[Key.pubDate]),
				  let parsedDate = parseDate(pubDate) else {
				continue
			}
			return parsedDate
		}

		return nil
	}

	static func parseGeneratedMediaLink(_ itemDictionary: JSONDictionary, _ content: Any?) -> String? {
		if let mediaLink = nonEmptyString(itemDictionary[Key.mediaLink]) {
			return mediaLink
		}

		guard let dictionary = content as? JSONDictionary else {
			return nil
		}

		if let metadata = dictionary[Key.metadata] as? JSONDictionary,
		   let media = nonEmptyString(metadata["media"]) {
			return media
		}

		return nil
	}

	static func contentTextFromGeneratedContent(_ content: Any?) -> String? {
		if let articles = topicsArray(from: content) {
			var chunks = [String]()
			for item in articles {
				if let title = nonEmptyString(item[Key.title]) {
					chunks.append(title)
				}
				if let summaryList = item[Key.summary] as? [String] {
					chunks.append(contentsOf: summaryList.compactMap { nonEmptyString($0) })
				} else if let summary = nonEmptyString(item[Key.summary]) {
					chunks.append(summary)
				}
			}
			let joined = chunks.joined(separator: "\n\n")
			return joined.isEmpty ? nil : joined
		}

		if let dictionary = content as? JSONDictionary {
			let candidates = [dictionary[Key.title], dictionary[Key.contentText], dictionary[Key.summary]]
			for candidate in candidates {
				if let text = nonEmptyString(candidate) {
					return text
				}
			}
			var generatedChunks = [String]()
			let summaryValue = dictionary[Key.summary]
			generatedChunks.append(contentsOf: titledContentPlainText(from: summaryValue))
			if generatedChunks.isEmpty, let summaryDictionary = summaryValue as? JSONDictionary {
				generatedChunks.append(contentsOf: titledContentPlainText(from: summaryDictionary["thesis"]))
			}
			generatedChunks.append(contentsOf: titledContentPlainText(from: dictionary[Key.practicalApplications]))
			if let summaryDictionary = summaryValue as? JSONDictionary {
				generatedChunks.append(contentsOf: titledContentPlainText(from: summaryDictionary["practical"]))
			}
			generatedChunks.append(contentsOf: titledContentPlainText(from: dictionary[Key.deepDive]))
			generatedChunks.append(contentsOf: titledContentPlainText(from: dictionary["in_depth_analysis"]))
			generatedChunks.append(contentsOf: timestampPlainText(from: dictionary["timestamps"]))
			let joined = generatedChunks.filter { !$0.isEmpty }.joined(separator: "\n\n")
			if !joined.isEmpty {
				return joined
			}
		}

		return nil
	}

	static func titledContentPlainText(from value: Any?) -> [String] {
		guard let items = value as? JSONArray else {
			return []
		}
		return items.compactMap { item -> String? in
			let title = nonEmptyString(item[Key.title]) ?? ""
			let content = nonEmptyString(item[Key.content]) ?? ""
			guard !title.isEmpty || !content.isEmpty else { return nil }
			return title.isEmpty ? content : (content.isEmpty ? title : "\(title): \(content)")
		}
	}

	static func timestampPlainText(from value: Any?) -> [String] {
		guard let items = value as? JSONArray else {
			return []
		}
		return items.compactMap { item -> String? in
			let timestamp = nonEmptyString(item["timestamp"]) ?? ""
			let content = nonEmptyString(item[Key.content]) ?? ""
			guard !timestamp.isEmpty || !content.isEmpty else { return nil }
			return timestamp.isEmpty ? content : (content.isEmpty ? timestamp : "\(timestamp) - \(content)")
		}
	}

	static func nonEmptyString(_ value: Any?) -> String? {
		guard let string = value as? String else {
			return nil
		}
		let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}

	static func jsonString(from value: Any?) -> String? {
		guard let value,
			  JSONSerialization.isValidJSONObject(value),
			  let data = try? JSONSerialization.data(withJSONObject: value, options: []),
			  let jsonString = String(data: data, encoding: .utf8) else {
			return nil
		}
		return jsonString
	}

	static func parseAuthor(_ dictionary: JSONDictionary) -> ParsedAuthor? {
		let name = dictionary[Key.name] as? String
		let url = dictionary[Key.url] as? String
		let avatar = dictionary[Key.avatar] as? String
		if name == nil && url == nil && avatar == nil {
			return nil
		}
		return ParsedAuthor(name: name, url: url, avatarURL: avatar, emailAddress: nil)
	}

	static func parseHubs(_ dictionary: JSONDictionary) -> Set<ParsedHub>? {

		guard let hubsArray = dictionary[Key.hubs] as? JSONArray else {
			return nil
		}

		let hubs = hubsArray.compactMap { (hubDictionary) -> ParsedHub? in
			guard let hubURL = hubDictionary[Key.url] as? String, let hubType = hubDictionary[Key.type] as? String else {
				return nil
			}
			return ParsedHub(type: hubType, url: hubURL)
		}
		return hubs.isEmpty ? nil : Set(hubs)
	}

	static func parseItems(_ itemsArray: JSONArray, _ feedURL: String) -> Set<ParsedItem> {

		return Set(itemsArray.compactMap { (oneItemDictionary) -> ParsedItem? in
			return parseItem(oneItemDictionary, feedURL)
		})
	}

	static func parseItem(_ itemDictionary: JSONDictionary, _ feedURL: String) -> ParsedItem? {

		guard let uniqueID = parseUniqueID(itemDictionary) else {
			return nil
		}

		let contentHTML = itemDictionary[Key.contentHTML] as? String
		let contentText = itemDictionary[Key.contentText] as? String
		if contentHTML == nil && contentText == nil {
			return nil
		}

		let url = itemDictionary[Key.url] as? String
		let externalURL = itemDictionary[Key.externalURL] as? String
		let title = parseTitle(itemDictionary, feedURL)
		let language = itemDictionary[Key.language] as? String
		let summary = itemDictionary[Key.summary] as? String
		let imageURL = itemDictionary[Key.image] as? String
		let bannerImageURL = itemDictionary[Key.bannerImage] as? String

		let datePublished = parseDate(itemDictionary[Key.datePublished] as? String)
		let dateModified = parseDate(itemDictionary[Key.dateModified] as? String)

		let authors = parseAuthors(itemDictionary)
		var tags: Set<String>?
		if let tagsArray = itemDictionary[Key.tags] as? [String] {
			tags = Set(tagsArray)
		}
		let attachments = parseAttachments(itemDictionary)

		return ParsedItem(syncServiceID: nil, uniqueID: uniqueID, feedURL: feedURL, url: url, externalURL: externalURL, title: title, language: language, contentHTML: contentHTML, contentText: contentText, markdown: nil, summary: summary, imageURL: imageURL, bannerImageURL: bannerImageURL, datePublished: datePublished, dateModified: dateModified, authors: authors, tags: tags, attachments: attachments)
	}

	static func parseTitle(_ itemDictionary: JSONDictionary, _ feedURL: String) -> String? {

		guard let title = itemDictionary[Key.title] as? String else {
			return nil
		}

		if isSpecialCaseTitleWithEntitiesFeed(feedURL) {
			return (title as NSString).rsparser_stringByDecodingHTMLEntities()
		}

		return title
	}

	static func isSpecialCaseTitleWithEntitiesFeed(_ feedURL: String) -> Bool {

		// As of 16 Feb. 2018, Kottke’s and Heer’s feeds includes HTML entities in the title elements.
		// If we find more feeds like this, we’ll add them here. If these feeds get fixed, we’ll remove them.

		let lowerFeedURL = feedURL.lowercased()
		let matchStrings = ["kottke.org", "pxlnv.com", "macstories.net", "macobserver.com"]
		for matchString in matchStrings {
			if lowerFeedURL.contains(matchString) {
				return true
			}
		}

		return false
	}

	static func parseUniqueID(_ itemDictionary: JSONDictionary) -> String? {

		if let uniqueID = itemDictionary[Key.uniqueID] as? String {
			return uniqueID // Spec says it must be a string
		}
		// Version 1 spec also says that if it’s a number, even though that’s incorrect, it should be coerced to a string.
		if let uniqueID = itemDictionary[Key.uniqueID] as? Int {
			return "\(uniqueID)"
		}
		if let uniqueID = itemDictionary[Key.uniqueID] as? Double {
			return "\(uniqueID)"
		}
		return nil
	}

	static func parseDate(_ dateString: String?) -> Date? {

		guard let dateString = dateString, !dateString.isEmpty else {
			return nil
		}
		return RSDateWithString(dateString)
	}

	static func parseAttachments(_ itemDictionary: JSONDictionary) -> Set<ParsedAttachment>? {

		guard let attachmentsArray = itemDictionary[Key.attachments] as? JSONArray else {
			return nil
		}
		return Set(attachmentsArray.compactMap { parseAttachment($0) })
	}

	static func parseAttachment(_ attachmentObject: JSONDictionary) -> ParsedAttachment? {

		guard let url = attachmentObject[Key.url] as? String else {
			return nil
		}
		guard let mimeType = attachmentObject[Key.mimeType] as? String else {
			return nil
		}

		let title = attachmentObject[Key.title] as? String
		let sizeInBytes = attachmentObject[Key.sizeInBytes] as? Int
		let durationInSeconds = attachmentObject[Key.durationInSeconds] as? Int

		return ParsedAttachment(url: url, mimeType: mimeType, title: title, sizeInBytes: sizeInBytes, durationInSeconds: durationInSeconds)
	}
}
