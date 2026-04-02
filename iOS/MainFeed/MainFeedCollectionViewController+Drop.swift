//
//  MainFeedCollectionViewController+Drop.swift
//  NetNewsWire-iOS
//
//  Created by Stuart Breckenridge on 14/07/2025.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import UIKit
import WebKit
import Account
import Articles
import RSCore
import RSTree
import RSWeb
import SafariServices
import UniformTypeIdentifiers

extension MainFeedCollectionViewController: UICollectionViewDropDelegate {

	func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: any UICollectionViewDropCoordinator) {
		guard let dragItem = coordinator.items.first?.dragItem,
			  let dragNode = dragItem.localObject as? Node,
			  let source = dragNode.parent?.representedObject as? Container,
			  let destIndexPath = coordinator.destinationIndexPath else {
				  return
			  }

		let isFolderDrop: Bool = {
			if self.coordinator.nodeFor(destIndexPath)?.representedObject is Folder, let propCell = collectionView.cellForItem(at: destIndexPath) {
				return coordinator.session.location(in: propCell).y >= 0
			}
			return false
		}()

		// Based on the drop we have to determine a node to start looking for a parent container.
		let destNode: Node? = {

			if isFolderDrop {
				return self.coordinator.nodeFor(destIndexPath)
			} else {
				if destIndexPath.row == 0 {
					return self.coordinator.nodeFor(IndexPath(row: 0, section: destIndexPath.section))
				} else if destIndexPath.row > 0 {
					return self.coordinator.nodeFor(IndexPath(row: destIndexPath.row - 1, section: destIndexPath.section))
				} else {
					return nil
				}
			}

		}()

		// Now we start looking for the parent container
		let destinationContainer: Container? = {
			if let container = (destNode?.representedObject as? Container) ?? (destNode?.parent?.representedObject as? Container) {
				return container
			} else {
				// If we got here, we are trying to drop on an empty section header.  Go and find the Account for this section
				return self.coordinator.rootNode.childAtIndex(destIndexPath.section)?.representedObject as? Account
			}
		}()

		guard let destination = destinationContainer, let feed = dragNode.representedObject as? Feed else { return }

		if source === destination {
			reorderFeedInContainer(feed: feed, container: source, destIndexPath: destIndexPath)
		} else if source.account == destination.account {
			moveFeedInAccount(feed: feed, sourceContainer: source, destinationContainer: destination)
		} else {
			moveFeedBetweenAccounts(feed: feed, sourceContainer: source, destinationContainer: destination)
		}
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {

		guard let destIndexPath = destinationIndexPath, collectionView.hasActiveDrag else {
			return UICollectionViewDropProposal(operation: .forbidden)
		}

		// Forbid dropping a feed into a different category section.
		if let sourceNode = session.localDragSession?.items.first?.localObject as? Node,
		   let sourceIndexPath = coordinator.indexPathFor(sourceNode),
		   sourceIndexPath.section != destIndexPath.section {
			return UICollectionViewDropProposal(operation: .forbidden)
		}

		// destIndexPath may be an insertion point beyond the last existing item; clamp to a valid row
		// so the node lookup succeeds even when dropping at the end of a section.
		let sectionCount = collectionView.numberOfItems(inSection: destIndexPath.section)
		let clampedRow = min(destIndexPath.row, max(0, sectionCount - 1))
		let lookupPath = IndexPath(row: clampedRow, section: destIndexPath.section)

		guard let destFeed = coordinator.nodeFor(lookupPath)?.representedObject as? SidebarItem,
			  let destAccount = destFeed.account else {
			return UICollectionViewDropProposal(operation: .forbidden)
		}

		// Validate account specific behaviors...
		if destAccount.behaviors.contains(.disallowFeedInMultipleFolders),
		   let sourceNode = session.localDragSession?.items.first?.localObject as? Node,
		   let sourceFeed = sourceNode.representedObject as? Feed,
		   sourceFeed.account?.accountID != destAccount.accountID && destAccount.hasFeed(withURL: sourceFeed.url) {
			return UICollectionViewDropProposal(operation: .forbidden)
		}

		// Determine the correct drop proposal; cell is only needed for folder-drop y-position check.
		if destFeed is Folder, let destCell = collectionView.cellForItem(at: lookupPath) {
			if session.location(in: destCell).y >= 0 {
				return UICollectionViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
			} else {
				return UICollectionViewDropProposal(operation: .move, intent: .unspecified)
			}
		} else {
			return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
		}
	}

	func collectionView(_ collectionView: UICollectionView, canHandle session: any UIDropSession) -> Bool {
		return session.localDragSession != nil
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
	}

	func reorderFeedInContainer(feed: Feed, container: Container, destIndexPath: IndexPath) {
		let sectionCount = collectionView.numberOfItems(inSection: destIndexPath.section)
		var allNodes = (0..<sectionCount).compactMap { row in
			coordinator.nodeFor(IndexPath(row: row, section: destIndexPath.section))
		}

		guard let dragIndex = allNodes.firstIndex(where: { ($0.representedObject as? Feed) === feed }) else {
			return
		}

		let dragNode = allNodes.remove(at: dragIndex)
		let insertIndex = min(destIndexPath.row, allNodes.count)
		allNodes.insert(dragNode, at: insertIndex)

		let feedURLs = allNodes.compactMap { ($0.representedObject as? Feed)?.url }
		let sectionID = dataSource.snapshot().sectionIdentifiers[destIndexPath.section]
		FeedOrderStore.shared.saveOrder(feedURLs, forKey: sectionID)
		coordinator.rebuildBackingStoresImmediately(animated: false)
	}

	func moveFeedInAccount(feed: Feed, sourceContainer: Container, destinationContainer: Container) {
		guard sourceContainer !== destinationContainer else { return }

		BatchUpdate.shared.start()
		sourceContainer.account?.moveFeed(feed, from: sourceContainer, to: destinationContainer) { result in
			BatchUpdate.shared.end()
			switch result {
			case .success:
				break
			case .failure(let error):
				self.presentError(error)
			}
		}
	}

	func moveFeedBetweenAccounts(feed: Feed, sourceContainer: Container, destinationContainer: Container) {

		if let existingFeed = destinationContainer.account?.existingFeed(withURL: feed.url) {

			BatchUpdate.shared.start()
			destinationContainer.account?.addFeed(existingFeed, to: destinationContainer) { result in
				switch result {
				case .success:
					sourceContainer.account?.removeFeed(feed, from: sourceContainer) { result in
						BatchUpdate.shared.end()
						switch result {
						case .success:
							break
						case .failure(let error):
							self.presentError(error)
						}
					}
				case .failure(let error):
					BatchUpdate.shared.end()
					self.presentError(error)
				}
			}

		} else {

			BatchUpdate.shared.start()
			destinationContainer.account?.createFeed(url: feed.url, name: feed.editedName, container: destinationContainer, validateFeed: false) { result in
				switch result {
				case .success:
					sourceContainer.account?.removeFeed(feed, from: sourceContainer) { result in
						BatchUpdate.shared.end()
						switch result {
						case .success:
							break
						case .failure(let error):
							self.presentError(error)
						}
					}
				case .failure(let error):
					BatchUpdate.shared.end()
					self.presentError(error)
				}
			}

		}
	}

}
