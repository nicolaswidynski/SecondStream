//
//  ObsidianFileManager.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-19.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import Account
import Articles
import os.log

enum ObsidianFileManagerError: LocalizedError {
	case noVaultConfigured
	case bookmarkStale
	case accessDenied
	case invalidURL
	case fileCoordinationFailed(Error)
	case iCloudDownloadFailed

	var errorDescription: String? {
		switch self {
		case .noVaultConfigured:
			return "No Obsidian vault configured"
		case .bookmarkStale:
			return "Obsidian vault bookmark is stale"
		case .accessDenied:
			return "Access to Obsidian vault denied"
		case .invalidURL:
			return "Invalid Obsidian vault URL"
		case .fileCoordinationFailed(let error):
			return "File coordination failed: \(error.localizedDescription)"
		case .iCloudDownloadFailed:
			return "Failed to download file from iCloud"
		}
	}
}

@MainActor struct ObsidianFileManager {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ObsidianFileManager")

	// MARK: - Date Extraction

	/// Extract date from article URL or use datePublished
	static func extractDateForFilename(from article: Article) -> String {
		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "yyyy-MM-dd"

		// Try to extract date from URL first
		if let rawLink = article.rawLink {
			let pattern = #"\/(\d{4}-\d{2}-\d{2})"#
			if let regex = try? NSRegularExpression(pattern: pattern),
			   let match = regex.firstMatch(in: rawLink, range: NSRange(rawLink.startIndex..., in: rawLink)),
			   let range = Range(match.range(at: 1), in: rawLink) {
				return String(rawLink[range])
			}
		}

		// Fall back to datePublished or current date
		let date = article.datePublished ?? Date()
		return dateFormatter.string(from: date)
	}

	// MARK: - Filename Generation

	/// Sanitize a string to be safe for use as a filename
	static func sanitizeFilename(_ title: String) -> String {
		// Characters that are invalid in filenames on most systems
		let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
		var sanitized = title.components(separatedBy: invalidCharacters).joined(separator: "-")

		// Remove leading/trailing whitespace and dots
		sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
		sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "."))

		// Limit length to avoid filesystem issues (keeping room for date prefix and extension)
		let maxLength = 180
		if sanitized.count > maxLength {
			sanitized = String(sanitized.prefix(maxLength))
		}

		// If completely empty after sanitization, use a default name
		if sanitized.isEmpty {
			sanitized = "Untitled"
		}

		return sanitized
	}

	/// Generate a filename for an article: "YYYY-MM-DD - Title.md"
	static func generateFilename(for article: Article) -> String {
		let date = extractDateForFilename(from: article)
		let title = sanitizeFilename(article.title ?? "Untitled")
		return "\(date) - \(title).md"
	}

	// MARK: - Path Generation

	/// Sanitize a path component (single folder name, not a full path)
	private static func sanitizePathComponent(_ name: String) -> String {
		// Characters that are invalid in folder names (excluding / which is handled separately)
		let invalidCharacters = CharacterSet(charactersIn: "\\:*?\"<>|")
		var sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "-")
		sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
		sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "."))
		if sanitized.isEmpty {
			sanitized = "Untitled"
		}
		return sanitized
	}

	/// Get the default subfolder prefix based on feed category
	static func getDefaultSubfolderPrefix(for feed: Feed) -> String {
		switch feed.feedCategory {
		case .rss:
			return "RSS Feeds"
		case .podcast:
			return "Podcasts"
		case .youtube:
			return "YouTube"
		case .news:
			return "News"
		}
	}

	/// Build subfolder path components based on global settings
	static func getSubfolderPath(for feed: Feed) -> [String] {
		var components = [String]()

		if AppDefaults.shared.obsidianSubfolderFeedType {
			components.append(getDefaultSubfolderPrefix(for: feed))
		}

		if AppDefaults.shared.obsidianSubfolderFeedName {
			components.append(sanitizePathComponent(feed.nameForDisplay))
		}

		return components
	}

	/// Get the full file path for an article within the vault
	static func getFilePath(for article: Article, feed: Feed, vaultURL: URL) -> URL {
		var url = vaultURL

		for component in getSubfolderPath(for: feed) {
			url = url.appendingPathComponent(component)
		}

		let filename = generateFilename(for: article)
		url = url.appendingPathComponent(filename)

		return url
	}

	/// Get a display-friendly preview of the subfolder path based on current settings
	static func subfolderPreview(for feedName: String = "FeedName", feedType: String = "FeedType") -> String {
		var components = [String]()

		if AppDefaults.shared.obsidianSubfolderFeedType {
			components.append(feedType)
		}

		if AppDefaults.shared.obsidianSubfolderFeedName {
			components.append(feedName)
		}

		if components.isEmpty {
			return "(vault root)"
		}

		return components.joined(separator: "/") + "/"
	}

	// MARK: - Security-Scoped Bookmark Handling

	/// Resolve the security-scoped bookmark and return the vault URL
	static func resolveVaultURL() throws -> URL {
		guard let bookmarkData = AppDefaults.shared.obsidianVaultBookmark else {
			throw ObsidianFileManagerError.noVaultConfigured
		}

		var isStale = false
		let url: URL
		do {
			url = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
		} catch {
			logger.error("Failed to resolve bookmark: \(error.localizedDescription)")
			throw ObsidianFileManagerError.invalidURL
		}

		if isStale {
			logger.warning("Obsidian vault bookmark is stale - attempting to refresh")
			// Try to refresh the bookmark if we can still access it
			if url.startAccessingSecurityScopedResource() {
				defer { url.stopAccessingSecurityScopedResource() }
				do {
					try storeVaultBookmark(for: url)
					logger.info("Successfully refreshed stale bookmark")
				} catch {
					logger.error("Failed to refresh stale bookmark: \(error.localizedDescription)")
					throw ObsidianFileManagerError.bookmarkStale
				}
			} else {
				throw ObsidianFileManagerError.bookmarkStale
			}
		}

		return url
	}

	/// Execute a block with security-scoped access to the vault
	static func withVaultAccess<T>(_ block: (URL) throws -> T) throws -> T {
		let vaultURL = try resolveVaultURL()

		guard vaultURL.startAccessingSecurityScopedResource() else {
			logger.error("startAccessingSecurityScopedResource returned false for: \(vaultURL.path)")
			throw ObsidianFileManagerError.accessDenied
		}
		defer {
			vaultURL.stopAccessingSecurityScopedResource()
		}

		// Ensure iCloud directory is available (triggers download if needed)
		try ensureLocalAvailability(of: vaultURL)

		return try block(vaultURL)
	}

	// MARK: - iCloud Support

	/// Check if a URL is in iCloud Drive (ubiquitous)
	private static func isUbiquitousItem(at url: URL) -> Bool {
		return FileManager.default.isUbiquitousItem(at: url)
	}

	/// Ensure a file/directory is downloaded locally from iCloud if needed
	private static func ensureLocalAvailability(of url: URL) throws {
		guard isUbiquitousItem(at: url) else {
			// Not in iCloud, nothing to do
			return
		}

		// Check if already downloaded
		var isDownloaded: AnyObject?
		do {
			try (url as NSURL).getResourceValue(&isDownloaded, forKey: .ubiquitousItemDownloadingStatusKey)
		} catch {
			logger.warning("Could not check iCloud download status: \(error.localizedDescription)")
			return
		}

		if let status = isDownloaded as? URLUbiquitousItemDownloadingStatus, status == .current {
			// Already downloaded
			return
		}

		// Trigger download
		logger.info("Triggering iCloud download for: \(url.path)")
		do {
			try FileManager.default.startDownloadingUbiquitousItem(at: url)
		} catch {
			logger.error("Failed to start iCloud download: \(error.localizedDescription)")
			throw ObsidianFileManagerError.iCloudDownloadFailed
		}
	}

	/// Perform a coordinated write operation (required for iCloud Drive)
	private static func coordinatedWrite(to url: URL, content: String) throws {
		var coordinatorError: NSError?
		var writeError: Error?

		let coordinator = NSFileCoordinator(filePresenter: nil)
		coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { coordinatedURL in
			do {
				try content.write(to: coordinatedURL, atomically: true, encoding: .utf8)
			} catch {
				writeError = error
			}
		}

		if let error = coordinatorError {
			throw ObsidianFileManagerError.fileCoordinationFailed(error)
		}
		if let error = writeError {
			throw error
		}
	}

	/// Perform a coordinated delete operation (required for iCloud Drive)
	private static func coordinatedDelete(at url: URL) throws {
		var coordinatorError: NSError?
		var deleteError: Error?

		let coordinator = NSFileCoordinator(filePresenter: nil)
		coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinatorError) { coordinatedURL in
			do {
				try FileManager.default.removeItem(at: coordinatedURL)
			} catch {
				deleteError = error
			}
		}

		if let error = coordinatorError {
			throw ObsidianFileManagerError.fileCoordinationFailed(error)
		}
		if let error = deleteError {
			throw error
		}
	}

	// MARK: - File Operations

	/// Write an article to the Obsidian vault
	static func writeArticle(_ article: Article, feed: Feed, content: String) throws {
		try withVaultAccess { vaultURL in
			let filePath = getFilePath(for: article, feed: feed, vaultURL: vaultURL)

			// Create subfolder if it doesn't exist (use coordinated access for iCloud)
			let subfolderURL = filePath.deletingLastPathComponent()
			if !FileManager.default.fileExists(atPath: subfolderURL.path) {
				var coordinatorError: NSError?
				var createError: Error?

				let coordinator = NSFileCoordinator(filePresenter: nil)
				coordinator.coordinate(writingItemAt: subfolderURL, options: [], error: &coordinatorError) { coordinatedURL in
					do {
						try FileManager.default.createDirectory(at: coordinatedURL, withIntermediateDirectories: true)
					} catch {
						createError = error
					}
				}

				if let error = coordinatorError {
					throw ObsidianFileManagerError.fileCoordinationFailed(error)
				}
				if let error = createError {
					throw error
				}
			}

			// Write the file with coordination
			try coordinatedWrite(to: filePath, content: content)

			logger.debug("Wrote article to: \(filePath.path)")
		}
	}

	/// Remove an article from the Obsidian vault
	static func removeArticle(_ article: Article, feed: Feed) throws {
		try withVaultAccess { vaultURL in
			let filePath = getFilePath(for: article, feed: feed, vaultURL: vaultURL)

			// Only remove if file exists
			if FileManager.default.fileExists(atPath: filePath.path) {
				try coordinatedDelete(at: filePath)
				logger.debug("Removed article from: \(filePath.path)")
			}
		}
	}

	// MARK: - Bookmark Creation

	/// Create and store a security-scoped bookmark for a selected vault URL
	static func storeVaultBookmark(for url: URL) throws {
		// Must access the security-scoped resource before creating bookmark
		guard url.startAccessingSecurityScopedResource() else {
			logger.error("Cannot access security-scoped resource for bookmark creation")
			throw ObsidianFileManagerError.accessDenied
		}
		defer {
			url.stopAccessingSecurityScopedResource()
		}

		// Create bookmark without .minimalBookmark to preserve security scope
		let bookmarkData = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
		AppDefaults.shared.obsidianVaultBookmark = bookmarkData
		logger.info("Stored bookmark for vault: \(url.path)")
	}

	// MARK: - Utility

	/// Get a display-friendly path for the configured vault
	static func vaultDisplayPath() -> String? {
		guard let url = try? resolveVaultURL() else {
			return nil
		}
		return url.lastPathComponent
	}
}
