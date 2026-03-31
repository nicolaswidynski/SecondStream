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

	/// Returns the user-defined feed URL order for the given container, or nil if none saved.
	func order(for containerID: ContainerIdentifier) -> [String]? {
		let stored = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: [String]] ?? [:]
		return stored[key(for: containerID)]
	}

	/// Saves the given feed URL order for the container.
	func saveOrder(_ feedURLs: [String], for containerID: ContainerIdentifier) {
		var stored = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: [String]] ?? [:]
		stored[key(for: containerID)] = feedURLs
		UserDefaults.standard.set(stored, forKey: userDefaultsKey)
	}

	/// Applies the saved order to nodes, falling back to alphabetical if no order is stored.
	/// New feeds not in the saved order are appended alphabetically at the end (before folders).
	func applyOrder(to nodes: [Node], containerID: ContainerIdentifier) -> [Node] {
		guard let savedURLs = order(for: containerID) else {
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

	private func key(for containerID: ContainerIdentifier) -> String {
		switch containerID {
		case .smartFeedController:
			return "smartFeedController"
		case .account(let accountID):
			return "account:\(accountID)"
		case .folder(let accountID, let folderName):
			return "folder:\(accountID):\(folderName)"
		}
	}
}
