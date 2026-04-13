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
	private var adaptiveCache = [String: UIImage]()
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

	/// Returns an adaptive UIImage that automatically switches between dark and light variants.
	/// If no lightURL is provided, behaves like `image(for:)`.
	func adaptiveImage(darkURL: String, lightURL: String?) -> UIImage? {
		guard let lightURL else {
			return image(for: darkURL)
		}

		let key = darkURL + "|" + lightURL
		if let cached = adaptiveCache[key] {
			return cached
		}

		let darkImage = image(for: darkURL)
		let lightImage = image(for: lightURL)

		guard let darkImage, let lightImage else {
			return darkImage ?? lightImage
		}

		let asset = UIImageAsset()
		asset.register(darkImage, with: UITraitCollection(userInterfaceStyle: .dark))
		asset.register(lightImage, with: UITraitCollection(userInterfaceStyle: .light))
		// darkImage is now backed by the asset and will resolve the correct variant automatically
		adaptiveCache[key] = darkImage
		return darkImage
	}

	private func startDownload(_ urlString: String) {
		guard !urlsInProgress.contains(urlString) else {
			return
		}
		guard let url = downloadURL(for: urlString) else {
			Self.logger.error("Invalid source image URL: \(urlString)")
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
					try? jpegData.write(to : fileURL)
				}

				// Save to memory
				memoryCache[urlString] = image
				urlsInProgress.remove(urlString)

				// Invalidate adaptive cache entries that used this URL
				adaptiveCache = adaptiveCache.filter { key, _ in
					let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
					return !parts.contains(urlString)
				}

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
			adaptiveCache = adaptiveCache.filter { key, _ in
				let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
				return !parts.contains(urlString)
			}
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

	/// Starts downloads for any uncached URLs and suspends until all are available
	/// or `timeout` seconds have elapsed, whichever comes first.
	func prefetchAndWait(for urlStrings: [String], timeout: TimeInterval) async {
		let needed = urlStrings.filter {
			memoryCache[$0] == nil && !FileManager.default.fileExists(atPath: diskURL(for: $0).path)
		}
		guard !needed.isEmpty else { return }

		var remaining = Set(needed)
		for url in needed { startDownload(url) }

		let (stream, continuation) = AsyncStream.makeStream(of: String.self)

		let observer = NotificationCenter.default.addObserver(
			forName: .sourceImageDidBecomeAvailable,
			object: nil,
			queue: .main
		) { notification in
			if let url = notification.userInfo?["url"] as? String {
				continuation.yield(url)
			}
		}
		defer { NotificationCenter.default.removeObserver(observer) }

		let timeoutTask = Task {
			try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
			continuation.finish()
		}
		defer { timeoutTask.cancel() }

		for await url in stream {
			remaining.remove(url)
			if remaining.isEmpty { break }
		}
	}

	private func resizedImage(_ image: UIImage, to targetSize: CGSize) -> UIImage {
		let renderer = UIGraphicsImageRenderer(size: targetSize)
		return renderer.image { _ in
			image.draw(in: CGRect(origin: .zero, size: targetSize))
		}
	}

	private func downloadURL(for rawURLString: String) -> URL? {
		let trimmed = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			return nil
		}

		if let url = URL(string: trimmed), url.scheme != nil {
			return url
		}

		if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
		   let url = URL(string: encoded),
		   url.scheme != nil {
			return url
		}

		return nil
	}

	func clearCache() {
		memoryCache.removeAll()
		adaptiveCache.removeAll()
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
