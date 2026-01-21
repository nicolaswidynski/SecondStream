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

struct MarkdownConverter {

	/// Convert an article to markdown format for Obsidian
	@MainActor static func convert(article: Article, feed: Feed) -> String {
		var markdown = ""

		// Generate YAML frontmatter
		markdown += generateFrontmatter(article: article, feed: feed)
		markdown += "\n"

		// Add article body only (no H1 title - it's already in frontmatter)
		if let body = getBodyContent(from: article) {
			markdown += body
		}

		return markdown
	}

	// MARK: - Frontmatter

	@MainActor private static func generateFrontmatter(article: Article, feed: Feed) -> String {
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

		// Date - try to extract from URL first, then use datePublished
		let dateString = extractDateForFrontmatter(from: article)
		if let dateString {
			frontmatter += "date: \(dateString)\n"
		}

		// Source URL
		if let url = article.rawLink {
			frontmatter += "source: \(url)\n"
		} else if let externalURL = article.rawExternalLink {
			frontmatter += "source: \(externalURL)\n"
		}

		// Feed name
		frontmatter += "feed: \"\(escapeYAMLString(feed.nameForDisplay))\"\n"

		// Tags (only rss tag, no starred)
		frontmatter += "tags:\n"
		frontmatter += "  - rss\n"

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

	private static func getBodyContent(from article: Article) -> String? {
		// Prefer contentHTML, then contentText, then summary
		if let html = article.contentHTML, !html.isEmpty {
			return convertHTMLToMarkdown(html)
		}
		if let text = article.contentText, !text.isEmpty {
			return text
		}
		if let summary = article.summary, !summary.isEmpty {
			return convertHTMLToMarkdown(summary)
		}
		return nil
	}

	/// Convert HTML to a basic markdown-like format
	private static func convertHTMLToMarkdown(_ html: String) -> String {
		var result = html

		// Remove any "This summary..." boilerplate text that some feeds add
		result = result.replacingOccurrences(of: "This summary of the[^.]*is formatted for seamless export to Obsidian[^.]*\\.", with: "", options: .regularExpression)

		// Convert common HTML elements to markdown equivalents
		// Headers
		result = result.replacingOccurrences(of: "<h1[^>]*>", with: "# ", options: .regularExpression)
		result = result.replacingOccurrences(of: "</h1>", with: "\n")
		result = result.replacingOccurrences(of: "<h2[^>]*>", with: "## ", options: .regularExpression)
		result = result.replacingOccurrences(of: "</h2>", with: "\n")
		result = result.replacingOccurrences(of: "<h3[^>]*>", with: "### ", options: .regularExpression)
		result = result.replacingOccurrences(of: "</h3>", with: "\n")
		result = result.replacingOccurrences(of: "<h4[^>]*>", with: "#### ", options: .regularExpression)
		result = result.replacingOccurrences(of: "</h4>", with: "\n")
		result = result.replacingOccurrences(of: "<h5[^>]*>", with: "##### ", options: .regularExpression)
		result = result.replacingOccurrences(of: "</h5>", with: "\n")
		result = result.replacingOccurrences(of: "<h6[^>]*>", with: "###### ", options: .regularExpression)
		result = result.replacingOccurrences(of: "</h6>", with: "\n")

		// Bold - use proper regex to capture content and avoid trailing issues
		// Match <strong>content</strong> or <b>content</b> and replace with **content**
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

		// Blockquotes - capture content and format properly
		let blockquotePattern = "<blockquote[^>]*>([\\s\\S]*?)</blockquote>"
		if let regex = try? NSRegularExpression(pattern: blockquotePattern, options: .caseInsensitive) {
			let range = NSRange(result.startIndex..., in: result)
			let matches = regex.matches(in: result, options: [], range: range)
			// Process in reverse to preserve indices
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

		// Paragraphs - add proper spacing
		result = result.replacingOccurrences(of: "<p[^>]*>", with: "", options: .regularExpression)
		result = result.replacingOccurrences(of: "</p>", with: "\n\n")

		// Line breaks
		result = result.replacingOccurrences(of: "<br[^>]*/?>", with: "\n", options: .regularExpression)

		// Lists
		result = result.replacingOccurrences(of: "<ul[^>]*>", with: "", options: .regularExpression)
		result = result.replacingOccurrences(of: "</ul>", with: "\n")
		result = result.replacingOccurrences(of: "<ol[^>]*>", with: "", options: .regularExpression)
		result = result.replacingOccurrences(of: "</ol>", with: "\n")
		result = result.replacingOccurrences(of: "<li[^>]*>", with: "- ", options: .regularExpression)
		result = result.replacingOccurrences(of: "</li>", with: "\n")

		// Horizontal rule
		result = result.replacingOccurrences(of: "<hr[^>]*/??>", with: "---\n", options: .regularExpression)

		// Remove any remaining HTML tags
		result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

		// Clean up excessive newlines
		result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

		// Clean up excessive spaces
		result = result.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)

		// Decode common HTML entities
		result = decodeHTMLEntities(result)

		return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
