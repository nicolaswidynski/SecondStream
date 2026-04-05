//
//  FeedOrderStore.swift
//  NetNewsWire
//
//  Created by Claude on 2026-03-31.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import Account
import RSTree

/// Persists user-defined feed ordering per container in UserDefaults.
@MainActor final class FeedOrderStore {

	static let shared = FeedOrderStore()

	private let userDefaultsKey = "feedOrderStore"

	/// Returns the user-defined feed URL order for the given section key, or nil if none saved.
	func order(forKey key: String) -> [String]? {
		let stored = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: [String]] ?? [:]
		return stored[key]
	}

	/// Removes any saved order for the given section key, reverting to alphabetical.
	func clearOrder(forKey key: String) {
		var stored = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: [String]] ?? [:]
		stored.removeValue(forKey: key)
		UserDefaults.standard.set(stored, forKey: userDefaultsKey)
	}

	/// Saves the given feed URL order for the section key.
	func saveOrder(_ feedURLs: [String], forKey key: String) {
		var stored = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: [String]] ?? [:]
		stored[key] = feedURLs
		UserDefaults.standard.set(stored, forKey: userDefaultsKey)
	}

	/// Applies the saved order to nodes, falling back to alphabetical if no order is stored.
	/// New feeds not in the saved order are appended alphabetically at the end (before folders).
	func applyOrder(to nodes: [Node], key: String) -> [Node] {
		guard let savedURLs = order(forKey: key) else {
			return nodes.sortedAlphabeticallyWithFoldersAtEnd()
		}

		let feedNodes = nodes.filter { $0.representedObject is Feed }
		let folderNodes = nodes.filter { !($0.representedObject is Feed) }

		let knownURLs = Set(savedURLs)
		let orderedFeeds = savedURLs.compactMap { url in
			feedNodes.first { ($0.representedObject as? Feed)?.url == url }
		}
		let newFeeds = feedNodes
			.filter { node in
				guard let url = (node.representedObject as? Feed)?.url else { return false }
				return !knownURLs.contains(url)
			}
			.sortedAlphabetically()

		return orderedFeeds + newFeeds + folderNodes.sortedAlphabetically()
	}
}
