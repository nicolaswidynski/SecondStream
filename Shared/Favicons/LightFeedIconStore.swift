//
//  LightFeedIconStore.swift
//  NetNewsWire
//
//  Created by Claude on 2026-03-22.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation

/// Stores light-mode icon URLs for feeds, keyed by feed URL.
@MainActor final class LightFeedIconStore {

	static let shared = LightFeedIconStore()

	private let key = "lightFeedIconURLs"

	private var store: [String: String] {
		get {
			UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
		}
		set {
			UserDefaults.standard.set(newValue, forKey: key)
		}
	}

	func lightIconURL(for feedURL: String) -> String? {
		store[feedURL]
	}

	func setLightIconURL(_ lightURL: String?, for feedURL: String) {
		var current = store
		if let lightURL, !lightURL.isEmpty {
			current[feedURL] = lightURL
		} else {
			current.removeValue(forKey: feedURL)
		}
		store = current
	}
}
