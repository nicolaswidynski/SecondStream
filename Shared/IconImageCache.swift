//
//  IconImageCache.swift
//  NetNewsWire-iOS
//
//  Created by Brent Simmons on 5/2/21.
//  Copyright © 2021 Ranchero Software. All rights reserved.
//

import Foundation
import RSCore
import Account
import Articles

@MainActor final class IconImageCache {

	static var shared = IconImageCache()

	private var smartFeedIconImageCache = [SidebarItemIdentifier: IconImage]()
	private var feedIconImageCache = [SidebarItemIdentifier: IconImage]()
	private var faviconImageCache = [SidebarItemIdentifier: IconImage]()
	private var smallIconImageCache = [SidebarItemIdentifier: IconImage]()
	private var authorIconImageCache = [Author: IconImage]()

	func imageFor(_ feedID: SidebarItemIdentifier) -> IconImage? {
		if let smartFeed = SmartFeedsController.shared.find(by: feedID) {
			return imageForFeed(smartFeed)
		}
		if let feed = AccountManager.shared.existingFeed(with: feedID) {
			return imageForFeed(feed)
		}
		return nil
	}

	func imageForFeed(_ sidebarItem: SidebarItem) -> IconImage? {
		guard let sidebarItemID = sidebarItem.sidebarItemID else {
			return nil
		}

		if let smartFeed = sidebarItem as? PseudoFeed {
			return imageForSmartFeed(smartFeed, sidebarItemID)
		}
		if let feed = sidebarItem as? Feed, let iconImage = imageForFeed(feed, sidebarItemID) {
			return iconImage
		}
		if let smallIconProvider = sidebarItem as? SmallIconProvider {
			return imageForSmallIconProvider(smallIconProvider, sidebarItemID)
		}

		return nil
	}

	func imageForArticle(_ article: Article) -> IconImage? {
		if let iconImage = imageForAuthors(article.authors) {
			return iconImage
		}
		guard let feed = article.feed else {
			return nil
		}
		return imageForFeed(feed)
	}

	func emptyCache() {
		smartFeedIconImageCache = [SidebarItemIdentifier: IconImage]()
		feedIconImageCache = [SidebarItemIdentifier: IconImage]()
		faviconImageCache = [SidebarItemIdentifier: IconImage]()
		smallIconImageCache = [SidebarItemIdentifier: IconImage]()
		authorIconImageCache = [Author: IconImage]()
	}
}

private extension IconImageCache {

	func imageForSmartFeed(_ smartFeed: PseudoFeed, _ feedID: SidebarItemIdentifier) -> IconImage? {
		if let iconImage = smartFeedIconImageCache[feedID] {
			return iconImage
		}
		if let iconImage = smartFeed.smallIcon {
			smartFeedIconImageCache[feedID] = iconImage
			return iconImage
		}
		return nil
	}

	func imageForFeed(_ feed: Feed, _ feedID: SidebarItemIdentifier) -> IconImage? {
		if let iconImage = feedIconImageCache[feedID] {
			return iconImage
		}
		if let iconImage = FeedIconDownloader.shared.icon(for: feed) {
			feedIconImageCache[feedID] = iconImage
			return iconImage
		}
		if let faviconImage = faviconImageCache[feedID] {
			return faviconImage
		}
		if let faviconImage = FaviconDownloader.shared.faviconAsIcon(for: feed) {
			faviconImageCache[feedID] = faviconImage
			return faviconImage
		}
		return categoryIcon(for: feed.feedCategory)
	}

	func categoryIcon(for category: FeedCategory) -> IconImage? {
		let symbolName: String
		let color: RSColor
		switch category {
		case .podcast:
			symbolName = "mic.fill"
			color = .systemPurple
		case .youtube:
			symbolName = "play.rectangle.fill"
			color = .systemRed
		case .news:
			symbolName = "newspaper.fill"
			color = .systemBlue
		case .rss:
			return nil
		}
		let config = RSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
		guard let symbol = RSImage(systemName: symbolName, withConfiguration: config) else {
			return nil
		}
		let size = CGSize(width: 36, height: 36)
		let renderer = UIGraphicsImageRenderer(size: size)
		let image = renderer.image { _ in
			color.set()
			let symbolSize = symbol.size
			let x = (size.width - symbolSize.width) / 2
			let y = (size.height - symbolSize.height) / 2
			symbol.draw(at: CGPoint(x: x, y: y))
		}.withRenderingMode(.alwaysOriginal)
		return IconImage(image, isSymbol: false, isBackgroundSuppressed: true)
	}

	func imageForSmallIconProvider(_ provider: SmallIconProvider, _ feedID: SidebarItemIdentifier) -> IconImage? {
		if let iconImage = smallIconImageCache[feedID] {
			return iconImage
		}
		if let iconImage = provider.smallIcon {
			smallIconImageCache[feedID] = iconImage
			return iconImage
		}
		return nil
	}

	func imageForAuthors(_ authors: Set<Author>?) -> IconImage? {
		guard let authors = authors, authors.count == 1, let author = authors.first else {
			return nil
		}
		return imageForAuthor(author)
	}

	func imageForAuthor(_ author: Author) -> IconImage? {
		if let iconImage = authorIconImageCache[author] {
			return iconImage
		}
		if let iconImage = AuthorAvatarDownloader.shared.image(for: author) {
			authorIconImageCache[author] = iconImage
			return iconImage
		}
		return nil
	}
}
