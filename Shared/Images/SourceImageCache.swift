//
//  SourceImageCache.swift
//  NetNewsWire
//
//  Created by Claude on 2026-02-13.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import UIKit
import os.log

extension Notification.Name {
	static let sourceImageDidBecomeAvailable = Notification.Name("SourceImageDidBecomeAvailableNotification")
}

@MainActor final class SourceImageCache {

	static let shared = SourceImageCache()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SourceImageCache")

	private var memoryCache = [String: UIImage]()
	private var urlsInProgress = Set<String>()
	private let cacheDirectory: URL

	init() {
		let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("SourceImages", isDirectory: true)
		try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		self.cacheDirectory = tmp
	}

	/// Returns a cached image synchronously if available, otherwise starts an async download.
	/// Listen for `.sourceImageDidBecomeAvailable` with userInfo key "url" to know when it's ready.
	func image(for urlString: String) -> UIImage? {
		if let cached = memoryCache[urlString] {
			return cached
		}

		// Check disk
		let fileURL = diskURL(for: urlString)
		if FileManager.default.fileExists(atPath: fileURL.path),
		   let data = try? Data(contentsOf: fileURL),
		   let image = UIImage(data: data) {
			memoryCache[urlString] = image
			return image
		}

		// Download async
		startDownload(urlString)
		return nil
	}

	private func startDownload(_ urlString: String) {
		guard !urlsInProgress.contains(urlString) else {
			return
		}
		guard let url = URL(string: urlString) else {
			return
		}

		urlsInProgress.insert(urlString)

		Task {
			do {
				let (data, response) = try await URLSession.shared.data(from: url)

				guard let httpResponse = response as? HTTPURLResponse,
					  (200...299).contains(httpResponse.statusCode),
					  let original = UIImage(data: data) else {
					Self.logger.error("Failed to download source image: \(urlString)")
					urlsInProgress.remove(urlString)
					return
				}

				let image = resizedImage(original, to: CGSize(width: 400, height: 400))

				// Save resized JPEG to disk
				let fileURL = diskURL(for: urlString)
				if let jpegData = image.jpegData(compressionQuality: 0.8) {
					try? jpegData.write(to: fileURL)
				}

				// Save to memory
				memoryCache[urlString] = image
				urlsInProgress.remove(urlString)

				NotificationCenter.default.post(
					name: .sourceImageDidBecomeAvailable,
					object: self,
					userInfo: ["url": urlString]
				)
			} catch {
				Self.logger.error("Error downloading source image: \(error.localizedDescription)")
				urlsInProgress.remove(urlString)
			}
		}
	}

	/// Removes cached images (memory + disk) for the given URLs.
	func removeImages(for urlStrings: [String]) {
		for urlString in urlStrings {
			memoryCache.removeValue(forKey: urlString)
			let fileURL = diskURL(for: urlString)
			try? FileManager.default.removeItem(at: fileURL)
		}
		if !urlStrings.isEmpty {
			Self.logger.info("Removed \(urlStrings.count) stale source images")
		}
	}

	/// Starts downloads for image URLs not already cached on disk.
	func prefetchImages(for urlStrings: [String]) {
		for urlString in urlStrings {
			let fileURL = diskURL(for: urlString)
			if !FileManager.default.fileExists(atPath: fileURL.path) {
				startDownload(urlString)
			}
		}
	}

	private func resizedImage(_ image: UIImage, to targetSize: CGSize) -> UIImage {
		let renderer = UIGraphicsImageRenderer(size: targetSize)
		return renderer.image { _ in
			image.draw(in: CGRect(origin: .zero, size: targetSize))
		}
	}

	func clearCache() {
		memoryCache.removeAll()
		urlsInProgress.removeAll()
		try? FileManager.default.removeItem(at: cacheDirectory)
		try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
		Self.logger.info("Source image cache cleared")
	}

	private func diskURL(for urlString: String) -> URL {
		let filename = urlString.data(using: .utf8)!.base64EncodedString()
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "+", with: "-")
			.prefix(128)
		return cacheDirectory.appendingPathComponent(String(filename))
	}
}
