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

		// Add title as H1
		let title = article.title ?? "Untitled"
		markdown += "# \(escapeMarkdown(title))\n\n"

		// Add article body
		if let body = getBodyContent(from: article) {
			markdown += body
		}

		return markdown
	}

	// MARK: - Frontmatter

	@MainActor private static func generateFrontmatter(article: Article, feed: Feed) -> String {
		var frontmatter = "---\n"

		// Title
		let title = article.title ?? "Untitled"
		frontmatter += "title: \"\(escapeYAMLString(title))\"\n"

		// Author
		if let authors = article.authors, let firstAuthor = authors.first {
			let authorName = firstAuthor.name ?? firstAuthor.emailAddress ?? "Unknown"
			frontmatter += "author: \"\(escapeYAMLString(authorName))\"\n"
		}

		// Date
		let dateFormatter = ISO8601DateFormatter()
		dateFormatter.formatOptions = [.withFullDate]
		if let datePublished = article.datePublished {
			frontmatter += "date: \(dateFormatter.string(from: datePublished))\n"
		}

		// Source URL
		if let url = article.rawLink {
			frontmatter += "source: \(url)\n"
		} else if let externalURL = article.rawExternalLink {
			frontmatter += "source: \(externalURL)\n"
		}

		// Feed name
		frontmatter += "feed: \"\(escapeYAMLString(feed.nameForDisplay))\"\n"

		// Tags (optional - for Obsidian)
		frontmatter += "tags:\n"
		frontmatter += "  - rss\n"
		frontmatter += "  - starred\n"

		frontmatter += "---\n"

		return frontmatter
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

		// Bold and italic
		result = result.replacingOccurrences(of: "<strong[^>]*>|<b[^>]*>", with: "**", options: .regularExpression)
		result = result.replacingOccurrences(of: "</strong>|</b>", with: "**", options: .regularExpression)
		result = result.replacingOccurrences(of: "<em[^>]*>|<i[^>]*>", with: "*", options: .regularExpression)
		result = result.replacingOccurrences(of: "</em>|</i>", with: "*", options: .regularExpression)

		// Code
		result = result.replacingOccurrences(of: "<code[^>]*>", with: "`", options: .regularExpression)
		result = result.replacingOccurrences(of: "</code>", with: "`")

		// Pre/code blocks
		result = result.replacingOccurrences(of: "<pre[^>]*>", with: "```\n", options: .regularExpression)
		result = result.replacingOccurrences(of: "</pre>", with: "\n```")

		// Blockquotes
		result = result.replacingOccurrences(of: "<blockquote[^>]*>", with: "> ", options: .regularExpression)
		result = result.replacingOccurrences(of: "</blockquote>", with: "\n")

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

		// Lists
		result = result.replacingOccurrences(of: "<ul[^>]*>", with: "", options: .regularExpression)
		result = result.replacingOccurrences(of: "</ul>", with: "\n")
		result = result.replacingOccurrences(of: "<ol[^>]*>", with: "", options: .regularExpression)
		result = result.replacingOccurrences(of: "</ol>", with: "\n")
		result = result.replacingOccurrences(of: "<li[^>]*>", with: "- ", options: .regularExpression)
		result = result.replacingOccurrences(of: "</li>", with: "\n")

		// Horizontal rule
		result = result.replacingOccurrences(of: "<hr[^>]*/??>", with: "---\n", options: .regularExpression)

		// Use RSCore's convertingToPlainText() to handle remaining HTML tags and spacing
		result = result.convertingToPlainText()

		// Clean up excessive newlines
		result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

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
