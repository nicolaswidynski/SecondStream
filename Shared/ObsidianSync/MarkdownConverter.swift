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

		// Date
		let dateString = extractDateForFrontmatter(from: article)
		if let dateString {
			frontmatter += "date: \(dateString)\n"
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

		// For structured JSON feeds, convert directly from JSON — no HTML intermediate.
		if (category == .podcast || category == .youtube),
		   let json = article.contentJSON, !json.isEmpty,
		   let data = json.data(using: .utf8),
		   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
			logger.debug("Using contentJSON directly for show body")
			body = convertShowJSONToMarkdown(parsed)
		} else if category == .news,
				  let json = article.contentJSON, !json.isEmpty,
				  let data = json.data(using: .utf8),
				  let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
			logger.debug("Using contentJSON directly for topics body")
			body = convertTopicsJSONToMarkdown(items)
		} else if let html = article.contentHTML, !html.isEmpty {
			// RSS: HTML is the native format, convert to markdown.
			logger.debug("Using contentHTML for body")
			body = convertHTMLToMarkdown(html)
		} else if let text = article.contentText, !text.isEmpty {
			logger.debug("Using contentText for body")
			body = text
		} else if let summary = article.summary, !summary.isEmpty {
			logger.debug("Using summary for body")
			body = convertHTMLToMarkdown(summary)
		} else {
			logger.debug("No body content found")
		}
 
		if let content = body {
			let result = removeSingleH1IfNeeded(content)
			logger.debug("Body content processed, final length: \(result.count)")
			return result
		}
		return nil
	}
 
	// MARK: - Direct JSON → Markdown (Podcast / YouTube)
 
	/// Converts structured show JSON directly to markdown, skipping the HTML intermediate.
	/// Sections: Summary (bullets), Practical Applications (bullets), Deep Dive (paragraphs).
	/// Timestamps are handled separately in YAML frontmatter.
	private static func convertShowJSONToMarkdown(_ json: [String: Any]) -> String {
		var sections = [String]()
 
		if let items = json["summary"] as? [[String: Any]] {
			let bullets = items.compactMap { bulletLine(from: $0) }
			if !bullets.isEmpty {
				sections.append("## Summary\n\n" + bullets.joined(separator: "\n"))
			}
		}
 
		if let items = json["practical_applications"] as? [[String: Any]] {
			let bullets = items.compactMap { bulletLine(from: $0) }
			if !bullets.isEmpty {
				sections.append("## Practical Applications\n\n" + bullets.joined(separator: "\n"))
			}
		}
 
		if let items = json["deep_dive"] as? [[String: Any]] {
			let paragraphs = items.compactMap { paragraphLine(from: $0) }
			if !paragraphs.isEmpty {
				sections.append("## Deep Dive\n\n" + paragraphs.joined(separator: "\n\n"))
			}
		}
 
		return sections.isEmpty ? "" : sections.joined(separator: "\n\n") + "\n"
	}
 
	// MARK: - Direct JSON → Markdown (Topics / News)
 
	/// Converts a topics JSON array directly to markdown, skipping the HTML intermediate.
	/// Each item becomes a ### heading with optional metadata and summary bullets.
	private static func convertTopicsJSONToMarkdown(_ items: [[String: Any]]) -> String {
		let sections = items.compactMap { item -> String? in
			let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled"
			let metadata = item["metadata"] as? [String: Any]
			let link = (metadata?["link"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
			let author = (metadata?["author"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
			let pubDate = (metadata?["pubDate"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

			var block = link.map { "### [\(title)](\($0))" } ?? "### \(title)"

			var meta = [String]()
			if let author, !author.isEmpty { meta.append("- **Author**: \(author)") }
			if let pubDate, !pubDate.isEmpty { meta.append("- **Published**: \(pubDate)") }
			if !meta.isEmpty { block += "\n\n" + meta.joined(separator: "\n") }

			let summary = item["summary"]
			let bullets: [String]
			if let list = summary as? [String] {
				bullets = list
					.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
					.filter { !$0.isEmpty }
					.map { line -> String in
						if line.hasPrefix("- ") { return "- \(line.dropFirst(2))" }
						if line.hasPrefix("• ") { return "- \(line.dropFirst(2))" }
						return "- \(line)"
					}
			} else if let str = summary as? String, !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				bullets = str
					.components(separatedBy: .newlines)
					.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
					.filter { !$0.isEmpty }
					.map { line -> String in
						if line.hasPrefix("- ") { return "- \(line.dropFirst(2))" }
						if line.hasPrefix("• ") { return "- \(line.dropFirst(2))" }
						return "- \(line)"
					}
			} else {
				bullets = []
			}
			if !bullets.isEmpty { block += "\n\n" + bullets.joined(separator: "\n") }
 
			return block
		}
 
		return sections.isEmpty ? "" : sections.joined(separator: "\n\n") + "\n"
	}
 
	// MARK: - JSON formatting helpers
 
	private static func bulletLine(from item: [String: Any]) -> String? {
		let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		let content = (item["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		guard !title.isEmpty || !content.isEmpty else { return nil }
		if !title.isEmpty && !content.isEmpty { return "- **\(title)**: \(content)" }
		return "- \(title + content)"
	}
 
	private static func paragraphLine(from item: [String: Any]) -> String? {
		let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		let content = (item["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		guard !title.isEmpty || !content.isEmpty else { return nil }
		if !title.isEmpty && !content.isEmpty { return "**\(title)**: \(content)" }
		return title + content
	}

	/// Convert HTML to a basic markdown-like format (used for RSS feeds)
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

		// Strip <strong> from metadata labels (Author, Published) so they render as plain text.
		// These are fixed labels inside <ul class="nnw-topics-metadata"> — bolding them adds noise.
		let metadataPattern = "(<ul class=\"nnw-topics-metadata\">(?:(?!</ul>)[\\s\\S])*?)</ul>"
		if let regex = try? NSRegularExpression(pattern: metadataPattern, options: .caseInsensitive) {
			let range = NSRange(result.startIndex..., in: result)
			let matches = regex.matches(in: result, options: [], range: range)
			var output = ""
			var lastEnd = result.startIndex
			for match in matches {
				guard let fullRange = Range(match.range, in: result) else { continue }
				output.append(contentsOf: result[lastEnd..<fullRange.lowerBound])
				var block = String(result[fullRange])
				block = block.replacingOccurrences(of: "<strong>", with: "", options: .caseInsensitive)
				block = block.replacingOccurrences(of: "</strong>", with: "", options: .caseInsensitive)
				output.append(block)
				lastEnd = fullRange.upperBound
			}
			output.append(contentsOf: result[lastEnd...])
			result = output
		}

		// Bold - use proper regex to capture content
		let boldPattern = "<(strong|b)[^>]*>([^<]*)</(strong|b)>"
		if let regex = try? NSRegularExpression(pattern: boldPattern, options: .caseInsensitive) {
			let nsRange = NSRange(result.startIndex..., in: result)
			let matches = regex.matches(in: result, options: [], range: nsRange)
			var output = ""
			var lastEnd = result.startIndex
			for match in matches {
				guard let contentRange = Range(match.range(at: 2), in: result),
					  let fullRange = Range(match.range, in: result) else {
					continue
				}
				output.append(contentsOf: result[lastEnd..<fullRange.lowerBound])
				var content = String(result[contentRange])
				// Strip existing ** to prevent doubling when server sends bold markers inside <strong>
				if content.hasPrefix("**") && content.hasSuffix("**") && content.count > 4 {
					content = String(content.dropFirst(2).dropLast(2))
				}
				output.append("**\(content)**")
				lastEnd = fullRange.upperBound
			}
			output.append(contentsOf: result[lastEnd...])
			result = output
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
					var inner = String(result[contentRange])
					// Convert block elements inside the blockquote before prefixing lines with "> "
					inner = inner.replacingOccurrences(of: "<ul[^>]*>", with: "", options: .regularExpression)
					inner = inner.replacingOccurrences(of: "</ul>", with: "")
					inner = inner.replacingOccurrences(of: "<ol[^>]*>", with: "", options: .regularExpression)
					inner = inner.replacingOccurrences(of: "</ol>", with: "")
					inner = inner.replacingOccurrences(of: "<li[^>]*>", with: "- ", options: .regularExpression)
					inner = inner.replacingOccurrences(of: "</li>", with: "\n")
					inner = inner.replacingOccurrences(of: "<p[^>]*>", with: "", options: .regularExpression)
					inner = inner.replacingOccurrences(of: "</p>", with: "\n")
					inner = inner.replacingOccurrences(of: "<br[^>]*/?>", with: "\n", options: .regularExpression)
					// Strip any remaining tags (bold, links, etc. have already been converted above)
					inner = inner.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
					let content = inner
						.trimmingCharacters(in: .whitespacesAndNewlines)
						.components(separatedBy: .newlines)
						.map { line in
							let trimmed = line.trimmingCharacters(in: .whitespaces)
							return trimmed.isEmpty ? ">" : "> \(trimmed)"
						}
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

		// Paragraphs
		result = result.replacingOccurrences(of: "<p[^>]*>", with: "", options: .regularExpression)
		result = result.replacingOccurrences(of: "</p>", with: "\n\n")
		// Line breaks
		result = result.replacingOccurrences(of: "<br[^>]*/?>", with: "\n", options: .regularExpression)

		// Lists
		// standalone summary list (topics): prefix with a "Summary:" bullet and indent items.
//		result = result.replacingOccurrences(of: "<ul class=\"nnw-generated-bullet-list nnw-generated-standalone-summary\">", with: "- **Summary**:\n")
//		// summary list nested under metadata item (topics): keep summary label on its own line.
//		result = result.replacingOccurrences(of: "<li>\\s*<strong>Summary</strong>:\\s*<ul class=\"nnw-generated-bullet-list\">", with: "- **Summary**:\n", options: .regularExpression)
		// headed bullet lists (podcast/yt summary, practical applications): items are already under an h2, just indent.
		result = result.replacingOccurrences(of: "<ul class=\"nnw-generated-bullet-list\">", with: "")
		result = result.replacingOccurrences(of: "<li class=\"nnw-generated-bullet-item\">", with: "- ")
		// Generic lists (must come after the specific class handlers above)
		result = result.replacingOccurrences(of: "<ul[^>]*>", with: "", options: .regularExpression)
		result = result.replacingOccurrences(of: "</ul>", with: "")
		result = result.replacingOccurrences(of: "<ol[^>]*>", with: "", options: .regularExpression)
		result = result.replacingOccurrences(of: "</ol>", with: "")
//		result = result.replacingOccurrences(of: "<li[^>]**Author**: *>", with: " \t- Author: ", options: .regularExpression)
//		result = result.replacingOccurrences(of: "<li[^>]<strong>Published</strong>: *>", with: " \t- Published: ", options: .regularExpression)
		result = result.replacingOccurrences(of: "<li[^>]*>", with: " \t- ", options: .regularExpression)
		result = result.replacingOccurrences(of: "</li>", with: "\n")
		// If a summary line still ends up with the first bullet inline, force it onto the next line.
		result = result.replacingOccurrences(of: "(?m)^(- \\*\\*Summary\\*\\*:)[ \t]+- ", with: "$1\n\t- ", options: .regularExpression)

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

		// Clean up multiple spaces (only inline, not leading indentation)
		result = result.replacingOccurrences(of: "(?<=\\S)[ \\t]{2,}", with: " ", options: .regularExpression)

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
			"&ndash;": "–",
			"&mdash;": "—",
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

		// Handle decimal numeric entities: &#39; &#8217; etc.
		result = decodeNumericEntities(in: result, pattern: "&#(\\d+);") { UInt32($0) }

		// Handle hex numeric entities: &#x27; &#x2019; etc.
		result = decodeNumericEntities(in: result, pattern: "&#x([0-9a-fA-F]+);") { UInt32($0, radix: 16) }

		return result
	}

	private static func decodeNumericEntities(in text: String, pattern: String, decode: (String) -> UInt32?) -> String {
		guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
			return text
		}
		// Enumerate matches against the original (immutable) string so all NSRanges are valid.
		// Collect (fullMatchRange, replacement) pairs, then apply in reverse so earlier indices
		// are never invalidated by a later replacement.
		let nsRange = NSRange(text.startIndex..., in: text)
		var replacements: [(NSRange, String)] = []
		regex.enumerateMatches(in: text, options: [], range: nsRange) { match, _, _ in
			guard let match,
				  let captureRange = Range(match.range(at: 1), in: text),
				  let code = decode(String(text[captureRange])),
				  let scalar = Unicode.Scalar(code) else {
				return
			}
			replacements.append((match.range, String(Character(scalar))))
		}
		var result = text
		for (range, replacement) in replacements.reversed() {
			guard let swiftRange = Range(range, in: result) else {
				continue
			}
			result.replaceSubrange(swiftRange, with: replacement)
		}
		return result
	}
}
