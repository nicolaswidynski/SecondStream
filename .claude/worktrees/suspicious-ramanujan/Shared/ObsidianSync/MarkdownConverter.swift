//
//  MarkdownConverter.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-19.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import Account
import Articles
import RSCore
import os.log

struct MarkdownConverter {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "MarkdownConverter")

	/// Convert an article to markdown format for Obsidian
	@MainActor static func convert(article: Article, feed: Feed) -> String {
		var markdown = ""

		// Generate YAML frontmatter
		markdown += generateFrontmatter(article: article, feed: feed)

		// Add article body only (no H1 title - it's already in frontmatter)
		if let body = getBodyContent(from: article, category: feed.feedCategory) {
			markdown += body
		}

		return markdown
	}

	// MARK: - Frontmatter

	@MainActor static func generateFrontmatter(article: Article, feed: Feed) -> String {
		var frontmatter = "---\n"

		// Title - strip HTML tags to get plain text
		let rawTitle = article.title ?? "Untitled"
		let title = stripHTMLTags(rawTitle)
		frontmatter += "title: \"\(escapeYAMLString(title))\"\n"

		// Author
		if let authors = article.authors, let firstAuthor = authors.first {
			let authorName = firstAuthor.name ?? firstAuthor.emailAddress ?? "Unknown"
			frontmatter += "author: \"\(escapeYAMLString(authorName))\"\n"
		}

		// Date - topics titles already embed the date, so skip the field for them
		if feed.feedCategory != .news {
			let dateString = extractDateForFrontmatter(from: article)
			if let dateString {
				frontmatter += "date: \(dateString)\n"
			}
		}

		// Source URL: only for RSS feeds (for pod/yt/topics the URL is our own server, not a meaningful source)
		if feed.feedCategory == .rss {
			frontmatter += "source: \(feed.url)\n"
		}

		// Feed name
		frontmatter += "feed: \"\(escapeYAMLString(feed.nameForDisplay))\"\n"

		// Timestamps in frontmatter for pod/yt (preferred over a body section)
		let category = feed.feedCategory
		if (category == .podcast || category == .youtube),
		   let json = article.contentJSON,
		   !json.isEmpty,
		   let data = json.data(using: .utf8),
		   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
			let timestamps = (parsed["timestamps"] as? [[String: Any]]) ?? []
			if !timestamps.isEmpty {
				let lines = timestamps.compactMap { item -> String? in
					let ts = (item["timestamp"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
					let content = (item["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
					guard !ts.isEmpty || !content.isEmpty else {
						return nil
					}
					let entry = [ts, content].filter { !$0.isEmpty }.joined(separator: " - ")
					return "  - \"\(escapeYAMLString(entry))\""
				}
				if !lines.isEmpty {
					frontmatter += "timestamps:\n"
					frontmatter += lines.joined(separator: "\n") + "\n"
				}
			}
		}

		frontmatter += "---\n"

		return frontmatter
	}

	/// Extract date from article URL or use datePublished
	private static func extractDateForFrontmatter(from article: Article) -> String? {
		// Try to extract date from URL first
		if let rawLink = article.rawLink {
			let pattern = #"(\d{4}-\d{2}-\d{2})"#
			if let regex = try? NSRegularExpression(pattern: pattern),
			   let match = regex.firstMatch(in: rawLink, range: NSRange(rawLink.startIndex..., in: rawLink)),
			   let range = Range(match.range(at: 1), in: rawLink) {
				return String(rawLink[range])
			}
		}

		// Fall back to datePublished
		if let datePublished = article.datePublished {
			let dateFormatter = DateFormatter()
			dateFormatter.dateFormat = "yyyy-MM-dd"
			return dateFormatter.string(from: datePublished)
		}

		return nil
	}

	/// Strip HTML tags from a string
	private static func stripHTMLTags(_ text: String) -> String {
		// Remove HTML tags
		var result = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
		// Decode common HTML entities
		result = decodeHTMLEntities(result)
		return result.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: - Body Content

	private static func getBodyContent(from article: Article, category: FeedCategory) -> String? {
		var body: String?

		if let json = article.contentJSON,
		   !json.isEmpty,
		   let jsonMarkdown = convertContentJSONToMarkdown(json, category: category) {
			logger.debug("Using contentJSON for body")
			body = jsonMarkdown
		}

		// Prefer contentHTML, then contentText, then summary
		if body == nil, let html = article.contentHTML, !html.isEmpty {
			logger.debug("Using contentHTML for body")
			body = convertHTMLToMarkdown(html)
		} else if body == nil, let text = article.contentText, !text.isEmpty {
			logger.debug("Using contentText for body (not HTML)")
			body = text
		} else if body == nil, let summary = article.summary, !summary.isEmpty {
			logger.debug("Using summary for body")
			body = convertHTMLToMarkdown(summary)
		} else {
			logger.debug("No body content found")
		}

		// Apply H1 removal to all content types (in case content is already markdown-formatted)
		if let content = body {
			let result = removeSingleH1IfNeeded(content)
			logger.debug("Body content processed, final length: \(result.count)")
			return result
		}
		return nil
	}

	private static func convertContentJSONToMarkdown(_ jsonString: String, category: FeedCategory) -> String? {
		switch category {
		case .podcast, .youtube:
			return convertShowJSONToMarkdown(jsonString)
		case .news:
			return convertTopicsJSONToMarkdown(jsonString)
		case .rss:
			return nil
		}
	}

	private static func convertShowJSONToMarkdown(_ jsonString: String) -> String? {
		guard let data = jsonString.data(using: .utf8),
			  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			return nil
		}

		var sections = [String]()

		let guests = (json["guests"] as? [[String: Any]]) ?? []
		var guestsLines = [String]()
		for guest in guests {
			let name = (guest["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			guard !name.isEmpty else {
				continue
			}
			let description = (guest["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			if description.isEmpty {
				guestsLines.append("- \(name)")
			} else {
				guestsLines.append("- \(name): \(description)")
			}
		}
		if !guestsLines.isEmpty {
			sections.append("## Guest(s)\n" + guestsLines.joined(separator: "\n"))
		}

		if let summary = json["summary"] as? [String: Any] {
			var summaryParts = [String]()
			let thesis = (summary["thesis"] as? [[String: Any]]) ?? []
			if !thesis.isEmpty {
				let lines = thesis.compactMap { item -> String? in
					let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
					let content = (item["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
					guard !title.isEmpty || !content.isEmpty else { return nil }
					if !title.isEmpty && !content.isEmpty {
						return "- **\(title)**: \(content)"
					}
					return "- \(title)\(content)"
				}
				if !lines.isEmpty {
					summaryParts.append("### Core Thesis\n" + lines.joined(separator: "\n"))
				}
			}

			let practical = (summary["practical"] as? [[String: Any]]) ?? []
			if !practical.isEmpty {
				let lines = practical.compactMap { item -> String? in
					let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
					let content = (item["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
					guard !title.isEmpty || !content.isEmpty else { return nil }
					if !title.isEmpty && !content.isEmpty {
						return "- **\(title)**: \(content)"
					}
					return "- \(title)\(content)"
				}
				if !lines.isEmpty {
					summaryParts.append("### Practical Applications\n" + lines.joined(separator: "\n"))
				}
			}

			if !summaryParts.isEmpty {
				sections.append("## Summary\n" + summaryParts.joined(separator: "\n\n"))
			}
		}

		let inDepth = (json["in_depth_analysis"] as? [[String: Any]]) ?? []
		if !inDepth.isEmpty {
			let blocks = inDepth.compactMap { item -> String? in
				let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
				let content = (item["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
				guard !title.isEmpty || !content.isEmpty else { return nil }
				if !title.isEmpty && !content.isEmpty {
					return "**\(title)**: \(content)"
				}
				return "\(title)\(content)"
			}
			if !blocks.isEmpty {
				sections.append("## In-Depth Analysis\n" + blocks.joined(separator: "\n\n"))
			}
		}

		// Timestamps are written to YAML frontmatter instead of the body.

		guard !sections.isEmpty else {
			return nil
		}
		return sections.joined(separator: "\n\n")
	}

	private static func convertTopicsJSONToMarkdown(_ jsonString: String) -> String? {
		guard let data = jsonString.data(using: .utf8),
			  let object = try? JSONSerialization.jsonObject(with: data) else {
			return nil
		}

		var entries = [[String: Any]]()
		if let topLevelArray = object as? [[String: Any]] {
			if topLevelArray.first?["title"] != nil || topLevelArray.first?["summary"] != nil {
				entries = topLevelArray
			} else {
				for element in topLevelArray {
					if let dataArray = element["data"] as? [[String: Any]] {
						entries.append(contentsOf: dataArray)
					}
				}
			}
		} else if let dict = object as? [String: Any] {
			if let dataArray = dict["data"] as? [[String: Any]] {
				entries = dataArray
			} else if dict["title"] != nil || dict["summary"] != nil {
				entries = [dict]
			}
		}

		guard !entries.isEmpty else {
			return nil
		}

		let blocks = entries.compactMap { entry -> String? in
			let title = (entry["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			let summary = (entry["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			let metadata = entry["metadata"] as? [String: Any]
			let author = (metadata?["author"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			let pubDate = (metadata?["pubDate"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			let link = (metadata?["link"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

			var lines = [String]()
			lines.append("## \(title.isEmpty ? "Untitled" : title)")

			var metadataLines = [String]()
			if !author.isEmpty {
				metadataLines.append("- **Author**: \(author)")
			}
			if !pubDate.isEmpty {
				metadataLines.append("- **Published**: \(pubDate)")
			}
			if !link.isEmpty {
				metadataLines.append("- **Link**: \(link)")
			}
			if !metadataLines.isEmpty {
				lines.append(metadataLines.joined(separator: "\n"))
			}

			if !summary.isEmpty {
				lines.append(summary)
			}

			return lines.joined(separator: "\n\n")
		}

		guard !blocks.isEmpty else {
			return nil
		}
		return blocks.joined(separator: "\n\n---\n\n")
	}

	/// Convert HTML to a basic markdown-like format
	private static func convertHTMLToMarkdown(_ html: String) -> String {
		var result = html

		logger.debug("convertHTMLToMarkdown called, HTML length: \(html.count)")

		// Remove any "This summary..." boilerplate text that some feeds add
		result = result.replacingOccurrences(of: "This summary of the[^.]*is formatted for seamless export to Obsidian[^.]*\\.", with: "", options: .regularExpression)

		// STEP 1: Normalize HTML - remove whitespace between tags for predictable processing
		result = result.replacingOccurrences(of: ">\\s+<", with: "><", options: .regularExpression)

		// Count H1 tags - if there's only one, remove it entirely (title is in frontmatter)
		let h1Pattern = "<h1[^>]*>[\\s\\S]*?</h1>"
		if let h1Regex = try? NSRegularExpression(pattern: h1Pattern, options: .caseInsensitive) {
			let range = NSRange(result.startIndex..., in: result)
			let h1Count = h1Regex.numberOfMatches(in: result, options: [], range: range)
			logger.debug("Found \(h1Count) H1 tags in HTML")
			if h1Count == 1 {
				logger.debug("Removing single H1 from HTML")
				result = h1Regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
			}
		} else {
			logger.error("Failed to create H1 regex")
		}

		// STEP 2: Convert inline elements first (bold, italic, links, etc.)

		// Bold - use proper regex to capture content
		let boldPattern = "<(strong|b)[^>]*>([^<]*)</(strong|b)>"
		if let regex = try? NSRegularExpression(pattern: boldPattern, options: .caseInsensitive) {
			let range = NSRange(result.startIndex..., in: result)
			result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "**$2**")
		}

		// Italic - use proper regex to capture content
		let italicPattern = "<(em|i)[^>]*>([^<]*)</(em|i)>"
		if let regex = try? NSRegularExpression(pattern: italicPattern, options: .caseInsensitive) {
			let range = NSRange(result.startIndex..., in: result)
			result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "*$2*")
		}

		// Code
		result = result.replacingOccurrences(of: "<code[^>]*>", with: "`", options: .regularExpression)
		result = result.replacingOccurrences(of: "</code>", with: "`")

		// Pre/code blocks
		result = result.replacingOccurrences(of: "<pre[^>]*>", with: "```\n", options: .regularExpression)
		result = result.replacingOccurrences(of: "</pre>", with: "\n```")

		// Links - extract href and text
		let linkPattern = "<a[^>]+href=[\"']([^\"']+)[\"'][^>]*>([^<]*)</a>"
		if let regex = try? NSRegularExpression(pattern: linkPattern, options: .caseInsensitive) {
			let range = NSRange(result.startIndex..., in: result)
			result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "[$2]($1)")
		}

		// Images - extract src and alt
		let imgPattern = "<img[^>]+src=[\"']([^\"']+)[\"'][^>]*(?:alt=[\"']([^\"']*)[\"'])?[^>]*/?>"
		if let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) {
			let range = NSRange(result.startIndex..., in: result)
			result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "![$2]($1)")
		}

		// Blockquotes - capture content and format properly
		let blockquotePattern = "<blockquote[^>]*>([\\s\\S]*?)</blockquote>"
		if let regex = try? NSRegularExpression(pattern: blockquotePattern, options: .caseInsensitive) {
			let range = NSRange(result.startIndex..., in: result)
			let matches = regex.matches(in: result, options: [], range: range)
			for match in matches.reversed() {
				if let contentRange = Range(match.range(at: 1), in: result),
				   let fullRange = Range(match.range, in: result) {
					let content = String(result[contentRange])
						.trimmingCharacters(in: .whitespacesAndNewlines)
						.components(separatedBy: .newlines)
						.map { "> \($0.trimmingCharacters(in: .whitespaces))" }
						.joined(separator: "\n")
					result.replaceSubrange(fullRange, with: "\n\(content)\n")
				}
			}
		}

		// STEP 3: Convert block elements

		// Headers - blank line BEFORE, single newline after
		result = result.replacingOccurrences(of: "<h1[^>]*>", with: "\n\n# ", options: .regularExpression)
		result = result.replacingOccurrences(of: "</h1>", with: "\n")
		result = result.replacingOccurrences(of: "<h2[^>]*>", with: "\n\n## ", options: .regularExpression)
		result = result.replacingOccurrences(of: "</h2>", with: "\n")
		result = result.replacingOccurrences(of: "<h3[^>]*>", with: "\n\n### ", options: .regularExpression)
		result = result.replacingOccurrences(of: "</h3>", with: "\n")
		result = result.replacingOccurrences(of: "<h4[^>]*>", with: "\n\n#### ", options: .regularExpression)
		result = result.replacingOccurrences(of: "</h4>", with: "\n")
		result = result.replacingOccurrences(of: "<h5[^>]*>", with: "\n\n##### ", options: .regularExpression)
		result = result.replacingOccurrences(of: "</h5>", with: "\n")
		result = result.replacingOccurrences(of: "<h6[^>]*>", with: "\n\n###### ", options: .regularExpression)
		result = result.replacingOccurrences(of: "</h6>", with: "\n")

		// Paragraphs - single newline after (headers/hr provide the blank lines before next content)
		result = result.replacingOccurrences(of: "<p[^>]*>", with: "", options: .regularExpression)
		result = result.replacingOccurrences(of: "</p>", with: "\n")

		// Line breaks
		result = result.replacingOccurrences(of: "<br[^>]*/?>", with: "\n", options: .regularExpression)

		// Lists - tight formatting, no blank lines
		result = result.replacingOccurrences(of: "<ul[^>]*>", with: "", options: .regularExpression)
		result = result.replacingOccurrences(of: "</ul>", with: "")
		result = result.replacingOccurrences(of: "<ol[^>]*>", with: "", options: .regularExpression)
		result = result.replacingOccurrences(of: "</ol>", with: "")
		result = result.replacingOccurrences(of: "<li[^>]*>", with: "- ", options: .regularExpression)
		result = result.replacingOccurrences(of: "</li>", with: "\n")

		// Horizontal rule - blank lines around it
		result = result.replacingOccurrences(of: "<hr[^>]*/?>", with: "\n\n---\n\n", options: .regularExpression)

		// Remove any remaining HTML tags
		result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

		// STEP 4: Clean up whitespace

		// Normalize whitespace-only lines to empty lines
		result = result.replacingOccurrences(of: "\\n[ \\t]+\\n", with: "\n\n", options: .regularExpression)

		// Clean up excessive newlines (3+ becomes 2)
		result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

		// Clean up leading spaces on lines (except list items and code)
		result = result.replacingOccurrences(of: "\\n +([^-`])", with: "\n$1", options: .regularExpression)

		// Clean up multiple spaces
		result = result.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)

		// Decode common HTML entities
		result = decodeHTMLEntities(result)

		return result.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// Remove the H1 heading if there's only one in the content
	private static func removeSingleH1IfNeeded(_ markdown: String) -> String {
		// Use regex to find H1 headings: lines starting with "# " (exactly one #)
		// Pattern: start of line, optional whitespace, single #, space, then content
		let h1Pattern = "(?m)^\\s*# [^\n]+"

		guard let regex = try? NSRegularExpression(pattern: h1Pattern) else {
			return markdown
		}

		let range = NSRange(markdown.startIndex..., in: markdown)
		let matches = regex.matches(in: markdown, options: [], range: range)

		// Only remove if there's exactly one H1
		guard matches.count == 1, let match = matches.first, let matchRange = Range(match.range, in: markdown) else {
			return markdown
		}

		var result = markdown
		result.replaceSubrange(matchRange, with: "")

		// Clean up any resulting excessive newlines at the start
		result = result.replacingOccurrences(of: "^\\s*\\n+", with: "", options: .regularExpression)
		// Clean up excessive newlines in general
		result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

		return result
	}

	// MARK: - String Escaping

	/// Escape special markdown characters
	private static func escapeMarkdown(_ text: String) -> String {
		// For titles, we mainly need to escape characters that would break the header
		var escaped = text
		escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
		escaped = escaped.replacingOccurrences(of: "[", with: "\\[")
		escaped = escaped.replacingOccurrences(of: "]", with: "\\]")
		return escaped
	}

	/// Escape string for YAML frontmatter (double quotes)
	private static func escapeYAMLString(_ text: String) -> String {
		var escaped = text
		escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
		escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
		escaped = escaped.replacingOccurrences(of: "\n", with: " ")
		escaped = escaped.replacingOccurrences(of: "\r", with: "")
		return escaped
	}

	/// Decode common HTML entities
	private static func decodeHTMLEntities(_ text: String) -> String {
		var result = text
		let entities: [String: String] = [
			"&amp;": "&",
			"&lt;": "<",
			"&gt;": ">",
			"&quot;": "\"",
			"&#39;": "'",
			"&apos;": "'",
			"&nbsp;": " ",
			"&ndash;": "-",
			"&mdash;": "-",
			"&lsquo;": "'",
			"&rsquo;": "'",
			"&ldquo;": "\"",
			"&rdquo;": "\"",
			"&hellip;": "...",
			"&copy;": "(c)",
			"&reg;": "(R)",
			"&trade;": "(TM)"
		]

		for (entity, replacement) in entities {
			result = result.replacingOccurrences(of: entity, with: replacement)
		}

		// Handle numeric entities
		let numericPattern = "&#(\\d+);"
		if let regex = try? NSRegularExpression(pattern: numericPattern) {
			let range = NSRange(result.startIndex..., in: result)
			var offset = 0

			regex.enumerateMatches(in: result, options: [], range: range) { match, _, _ in
				guard let match else {
					return
				}
				guard let codeRange = Range(match.range(at: 1), in: result) else {
					return
				}
				let codeString = String(result[codeRange])
				guard let code = UInt32(codeString), let scalar = Unicode.Scalar(code) else {
					return
				}

				let adjustedRange = NSRange(location: match.range.location + offset, length: match.range.length)
				guard let swiftRange = Range(adjustedRange, in: result) else {
					return
				}

				let character = String(Character(scalar))
				result.replaceSubrange(swiftRange, with: character)
				offset += character.count - match.range.length
			}
		}

		return result
	}
}
