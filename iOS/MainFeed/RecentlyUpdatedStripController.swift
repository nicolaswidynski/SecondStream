//
//  RecentlyUpdatedStripController.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-10.
//  Copyright © 2026 STDN. All rights reserved.
//

import UIKit
import Account
import RSCore
import Articles

// MARK: - Payload types

struct DiscoverSourceItem {
	let name: String
	let author: String?
	let url: String
	let imageURL: String?
	let imageURLLight: String?
	let category: FeedCategory
}

enum RecentlyUpdatedStripPayload {
	case feed(Feed)
	case discover(DiscoverSourceItem)
}

// MARK: - RecentlyUpdatedStripController

/// Owns the "Recently Updated" / "Discover" horizontal strip that sits above the feed list.
///
/// Responsibilities:
/// - Building and owning the strip view hierarchy
/// - Computing payloads (recently-updated feeds or discover items)
/// - Animating icon appearance
///
/// `MainFeedCollectionViewController` holds this as a plain owned object, adds the views to
/// its hierarchy, wires `onPayloadTapped`, and calls `refresh()` when it needs the strip updated.
@MainActor final class RecentlyUpdatedStripController {

	// MARK: - Public interface

	/// The top inset the collection view must apply to clear the strip.
	let topInset: CGFloat = 156

	/// Called whenever the user taps an item in the strip.
	var onPayloadTapped: ((RecentlyUpdatedStripPayload) -> Void)?

	// MARK: - Views (owned; caller adds them to the view hierarchy)

	lazy var containerView: UIView = {
		let view = UIView()
		view.translatesAutoresizingMaskIntoConstraints = false
		return view
	}()

	lazy var navBarExtendedBackgroundView: UIVisualEffectView = {
		let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
		view.translatesAutoresizingMaskIntoConstraints = false
		view.isUserInteractionEnabled = false
		return view
	}()

	private lazy var titleLabel: UILabel = {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = UIFont.preferredFont(forTextStyle: .title3).bold()
		label.textColor = .label
		label.text = NSLocalizedString("Recently Updated", comment: "Recently Updated")
		return label
	}()

	private lazy var scrollView: UIScrollView = {
		let scrollView = UIScrollView()
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.showsHorizontalScrollIndicator = false
		scrollView.showsVerticalScrollIndicator = false
		scrollView.alwaysBounceVertical = false
		scrollView.isDirectionalLockEnabled = true
		return scrollView
	}()

	private lazy var backgroundView: UIVisualEffectView = {
		let view = UIVisualEffectView(effect: nil)
		view.translatesAutoresizingMaskIntoConstraints = false
		view.layer.cornerRadius = 20
		view.clipsToBounds = true
		return view
	}()

	private lazy var stackView: UIStackView = {
		let stack = UIStackView()
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.axis = .horizontal
		stack.spacing = 3
		stack.alignment = .center
		return stack
	}()

	// MARK: - Private state

	private var stripTask: Task<Void, Never>?

	// MARK: - Setup

	/// Installs the strip's subviews into `parentView` and activates Auto Layout constraints.
	/// Call once from `viewDidLoad`.
	func install(in parentView: UIView, above collectionView: UIView) {
		parentView.insertSubview(navBarExtendedBackgroundView, aboveSubview: collectionView)
		parentView.addSubview(containerView)
		containerView.addSubview(titleLabel)
		containerView.addSubview(backgroundView)
		backgroundView.contentView.addSubview(scrollView)
		scrollView.addSubview(stackView)

		NSLayoutConstraint.activate([
			navBarExtendedBackgroundView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
			navBarExtendedBackgroundView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
			navBarExtendedBackgroundView.topAnchor.constraint(equalTo: parentView.topAnchor),
			navBarExtendedBackgroundView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: 10),

			containerView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor, constant: 16),
			containerView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor, constant: -16),
			containerView.topAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.topAnchor, constant: 6),

			titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 2),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor),
			titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor),

			backgroundView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
			backgroundView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
			backgroundView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
			backgroundView.heightAnchor.constraint(equalToConstant: 86),
			backgroundView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

			scrollView.leadingAnchor.constraint(equalTo: backgroundView.contentView.leadingAnchor, constant: 10),
			scrollView.trailingAnchor.constraint(equalTo: backgroundView.contentView.trailingAnchor, constant: -10),
			scrollView.topAnchor.constraint(equalTo: backgroundView.contentView.topAnchor, constant: 8),
			scrollView.bottomAnchor.constraint(equalTo: backgroundView.contentView.bottomAnchor, constant: -8),

			stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
			stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
			stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
			stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor)
		])
	}

	/// Applies the navigation bar background style (opaque, uses `Assets.Colors.foreground`).
	func applyNavigationBarBackgroundStyle() {
		backgroundView.effect = nil
		backgroundView.backgroundColor = Assets.Colors.foreground
		navBarExtendedBackgroundView.effect = nil
		navBarExtendedBackgroundView.backgroundColor = Assets.Colors.foreground
		navBarExtendedBackgroundView.alpha = 1.0
	}

	// MARK: - Refresh

	/// Schedules a debounced strip refresh (150 ms). Cancels any in-flight refresh.
	func refresh() {
		stripTask?.cancel()
		stripTask = Task {
			try? await Task.sleep(for: .milliseconds(150))
			guard !Task.isCancelled else { return }
			await applyPayloads()
		}
	}

	// MARK: - Data pipeline

	private func applyPayloads() async {
		let payloads = await buildPayloads()
		guard !Task.isCancelled else { return }

		let isDiscoverMode: Bool = {
			guard let first = payloads.first else { return false }
			if case .discover = first { return true }
			return false
		}()
		titleLabel.text = isDiscoverMode
			? NSLocalizedString("Discover", comment: "Discover")
			: NSLocalizedString("Recently Updated", comment: "Recently Updated")

		let wasEmpty = stackView.arrangedSubviews.isEmpty

		stackView.arrangedSubviews.forEach { view in
			stackView.removeArrangedSubview(view)
			view.removeFromSuperview()
		}

		for payload in payloads {
			let itemView = RecentlyUpdatedFeedItemView()
			itemView.payload = payload
			itemView.translatesAutoresizingMaskIntoConstraints = false
			itemView.addTarget(self, action: #selector(itemTapped(_:)), for: .touchUpInside)
			switch payload {
			case .feed(let feed):
				itemView.accessibilityLabel = feed.nameForDisplay
				itemView.setImage(iconImage(forFeed: feed))
			case .discover(let source):
				itemView.accessibilityLabel = source.name
				itemView.setImage(iconImage(forSource: source))
			}
			NSLayoutConstraint.activate([
				itemView.widthAnchor.constraint(equalToConstant: 72),
				itemView.heightAnchor.constraint(equalToConstant: 68)
			])
			stackView.addArrangedSubview(itemView)
		}

		if !payloads.isEmpty && wasEmpty {
			let itemViews = stackView.arrangedSubviews
			for (index, view) in itemViews.enumerated() {
				view.alpha = 0
				view.transform = CGAffineTransform(translationX: 44, y: 0)
				UIView.animate(
					withDuration: 0.28,
					delay: Double(index) * 0.06,
					options: .curveEaseOut
				) {
					view.alpha = 1
					view.transform = .identity
				}
			}
		}
	}

	func buildPayloads() async -> [RecentlyUpdatedStripPayload] {
		let recentFeeds = await computeRecentlyUpdatedUnreadFeeds()
		if !recentFeeds.isEmpty {
			return recentFeeds.map { .feed($0) }
		}
		return buildDiscoverSourceItems().map { .discover($0) }
	}

	func computeRecentlyUpdatedUnreadFeeds() async -> [Feed] {
		var latestDateByFeedID = [String: Date]()
		var feedByID = [String: Feed]()

		for account in AccountManager.shared.activeAccounts {
			for feed in account.flattenedFeeds() where feed.unreadCount > 0 {
				feedByID[feed.feedID] = feed
			}

			guard !feedByID.isEmpty else {
				continue
			}

			guard let unreadArticles = try? await account.fetchArticlesAsync(.unread()) else {
				continue
			}

			for article in unreadArticles {
				guard feedByID[article.feedID] != nil else { continue }
				let date = article.logicalDatePublished
				let existing = latestDateByFeedID[article.feedID] ?? .distantPast
				if date > existing {
					latestDateByFeedID[article.feedID] = date
				}
			}
		}

		return latestDateByFeedID
			.sorted { $0.value > $1.value }
			.compactMap { feedByID[$0.key] }
	}

	func buildDiscoverSourceItems() -> [DiscoverSourceItem] {
		var items = [DiscoverSourceItem]()

		for source in Array(MediaSourcesManager.podcast.topSources.shuffled().prefix(2)) {
			items.append(DiscoverSourceItem(name: source.name, author: source.author, url: source.url, imageURL: source.imageURL, imageURLLight: source.imageURLLight, category: .podcast))
		}
		for source in Array(MediaSourcesManager.youtube.topSources.shuffled().prefix(2)) {
			items.append(DiscoverSourceItem(name: source.name, author: source.author, url: source.url, imageURL: source.imageURL, imageURLLight: source.imageURLLight, category: .youtube))
		}
		for source in Array(NewsSourcesManager.shared.newsSources.shuffled().prefix(2)) {
			items.append(DiscoverSourceItem(name: source.name, author: source.author, url: source.url, imageURL: source.imageURL, imageURLLight: source.imageURLLight, category: .news))
		}
		for source in Array(RSSSourcesManager.shared.rssSources.shuffled().prefix(2)) {
			items.append(DiscoverSourceItem(name: source.name, author: source.author, url: source.url, imageURL: source.imageURL, imageURLLight: source.imageURLLight, category: .rss))
		}

		return items
	}

	// MARK: - Icon helpers

	private func iconImage(forFeed feed: Feed) -> UIImage {
		let fallback = Assets.Images.nnwFeedIcon
		guard let iconImage = IconImageCache.shared.imageForFeed(feed) else {
			return fallback
		}
		guard let lightImage = iconImage.lightImage else {
			return iconImage.image
		}
		let asset = UIImageAsset()
		asset.register(iconImage.image, with: UITraitCollection(userInterfaceStyle: .dark))
		asset.register(lightImage, with: UITraitCollection(userInterfaceStyle: .light))
		return iconImage.image
	}

	private func iconImage(forSource source: DiscoverSourceItem) -> UIImage {
		if let imageURL = source.imageURL {
			let lightURL = source.imageURLLight
				?? (!source.url.isEmpty ? LightFeedIconStore.shared.lightIconURL(for: source.url) : nil)
			if let image = SourceImageCache.shared.adaptiveImage(darkURL: imageURL, lightURL: lightURL) {
				return image
			}
		}
		let config = UIImage.SymbolConfiguration(pointSize: 34, weight: .regular)
		let fallback: UIImage
		switch source.category {
		case .podcast:
			fallback = RSImage(named: "podcast_thin-symbol")?.applyingSymbolConfiguration(config)
				?? UIImage(systemName: "mic.fill", withConfiguration: config)
				?? Assets.Images.nnwFeedIcon
		case .youtube:
			fallback = UIImage(systemName: "play.rectangle", withConfiguration: config) ?? Assets.Images.nnwFeedIcon
		case .news:
			fallback = UIImage(systemName: "newspaper", withConfiguration: config) ?? Assets.Images.nnwFeedIcon
		case .rss:
			fallback = RSImage(named: "rss_thin-symbol")?.applyingSymbolConfiguration(config)
				?? UIImage(systemName: "dot.radiowaves.left.and.right", withConfiguration: config)
				?? Assets.Images.nnwFeedIcon
		}
		return fallback.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
	}

	// MARK: - Actions

	@objc private func itemTapped(_ sender: UIControl) {
		guard let itemView = sender as? RecentlyUpdatedFeedItemView,
			  let payload = itemView.payload else {
			return
		}
		itemView.performTapFeedback { [weak self] in
			self?.onPayloadTapped?(payload)
		}
	}
}

// MARK: - RecentlyUpdatedFeedItemView

final class RecentlyUpdatedFeedItemView: UIControl {
	var payload: RecentlyUpdatedStripPayload?

	private let iconImageView: UIImageView = {
		let imageView = UIImageView()
		imageView.translatesAutoresizingMaskIntoConstraints = false
		imageView.contentMode = .scaleAspectFill
		imageView.backgroundColor = Assets.Colors.foreground
		imageView.layer.cornerRadius = 12
		imageView.clipsToBounds = true
		return imageView
	}()

	private let pressOverlayView: UIView = {
		let view = UIView()
		view.translatesAutoresizingMaskIntoConstraints = false
		view.backgroundColor = Assets.Colors.primaryAccent.withAlphaComponent(1)
		view.isUserInteractionEnabled = false
		view.alpha = 0
		return view
	}()

	override var isHighlighted: Bool {
		didSet {
			pressOverlayView.alpha = isHighlighted ? 1 : 0
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		addSubview(iconImageView)
		iconImageView.addSubview(pressOverlayView)

		NSLayoutConstraint.activate([
			iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
			iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
			iconImageView.widthAnchor.constraint(equalToConstant: 68),
			iconImageView.heightAnchor.constraint(equalToConstant: 68),

			pressOverlayView.leadingAnchor.constraint(equalTo: iconImageView.leadingAnchor),
			pressOverlayView.trailingAnchor.constraint(equalTo: iconImageView.trailingAnchor),
			pressOverlayView.topAnchor.constraint(equalTo: iconImageView.topAnchor),
			pressOverlayView.bottomAnchor.constraint(equalTo: iconImageView.bottomAnchor)
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func setImage(_ image: UIImage?) {
		iconImageView.image = image
	}

	func performTapFeedback(_ completion: @escaping () -> Void) {
		pressOverlayView.alpha = 1
		UIView.animate(withDuration: 0.08, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
			self.pressOverlayView.alpha = 0
		} completion: { _ in
			completion()
		}
	}
}
