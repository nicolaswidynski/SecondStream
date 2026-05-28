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
	case feed(Feed, Article)
	case discover(DiscoverSourceItem)
}

// MARK: - RecentlyUpdatedStripController

/// Owns the "Recently Updated" / "Discover" paging strip that sits above the feed list.
///
/// Each page shows one feed: icon on the left, article title and snippet on the right.
/// For feeds with multiple unread articles, the oldest unread article is shown.
/// Tapping navigates directly to that article.
@MainActor final class RecentlyUpdatedStripController: NSObject {

	// MARK: - Public interface

	/// The top inset the collection view must apply to clear the strip.
	let topInset: CGFloat = 164

	/// Called whenever the user taps a card in the strip.
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

	private lazy var pageControlBackgroundView: UIView = {
		let view = UIView()
		view.translatesAutoresizingMaskIntoConstraints = false
		view.isUserInteractionEnabled = false
		return view
	}()

	private lazy var titleLabel: UILabel = {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = UIFont.preferredFont(forTextStyle: .title3).bold()
		label.textColor = .label
		label.text = NSLocalizedString("Recent Articles", comment: "Recent Articles")
		return label
	}()

	private lazy var pageScrollView: UIScrollView = {
		let sv = UIScrollView()
		sv.translatesAutoresizingMaskIntoConstraints = false
		sv.isPagingEnabled = true
		sv.showsHorizontalScrollIndicator = false
		sv.showsVerticalScrollIndicator = false
		sv.alwaysBounceVertical = false
		sv.isDirectionalLockEnabled = true
		sv.clipsToBounds = true
		sv.layer.cornerRadius = 16
		sv.delegate = self
		return sv
	}()

	private lazy var pageControl: CompactPageControl = {
		let pc = CompactPageControl()
		pc.translatesAutoresizingMaskIntoConstraints = false
		pc.currentPageIndicatorTintColor = .label
		pc.pageIndicatorTintColor = .tertiaryLabel
		pc.hidesForSinglePage = true
		return pc
	}()

	// MARK: - Private state

	private var payloads: [RecentlyUpdatedStripPayload] = []
	private var cardViews: [RecentlyUpdatedCardView] = []
	private var stripTask: Task<Void, Never>?
	private var autoScrollTimer: Timer?
	private var inactivityTimer: Timer?

	// MARK: - Setup

	/// Installs the strip's subviews into `parentView` and activates Auto Layout constraints.
	/// Call once from `viewDidLoad`.
	func install(in parentView: UIView, above collectionView: UIView) {
		parentView.insertSubview(navBarExtendedBackgroundView, aboveSubview: collectionView)
		parentView.insertSubview(pageControlBackgroundView, aboveSubview: navBarExtendedBackgroundView)
		parentView.addSubview(containerView)
		containerView.addSubview(titleLabel)
		containerView.addSubview(pageScrollView)
		containerView.addSubview(pageControl)

		let pageControlHeight = pageControl.heightAnchor.constraint(equalToConstant: 20)
		pageControlHeight.priority = .required

		NSLayoutConstraint.activate([
			navBarExtendedBackgroundView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
			navBarExtendedBackgroundView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
			navBarExtendedBackgroundView.topAnchor.constraint(equalTo: parentView.topAnchor),
			navBarExtendedBackgroundView.bottomAnchor.constraint(equalTo: pageScrollView.bottomAnchor),

			pageControlBackgroundView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
			pageControlBackgroundView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
			pageControlBackgroundView.topAnchor.constraint(equalTo: pageScrollView.bottomAnchor),
			pageControlBackgroundView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: 10),

			containerView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor, constant: 16),
			containerView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor, constant: -16),
			containerView.topAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.topAnchor, constant: 6),

			titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 2),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor),
			titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor),

			pageScrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
			pageScrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
			pageScrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
			pageScrollView.heightAnchor.constraint(equalToConstant: 88),

			pageControlHeight,
			pageControl.topAnchor.constraint(equalTo: pageScrollView.bottomAnchor, constant: 6),
			pageControl.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
			pageControl.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
		])
	}

	func applyNavigationBarBackgroundStyle() {
		navBarExtendedBackgroundView.effect = nil
		navBarExtendedBackgroundView.contentView.backgroundColor = Assets.Colors.FeedSceneRecentlyUpdatedLabelColor
		navBarExtendedBackgroundView.alpha = 1.0
		pageControlBackgroundView.backgroundColor = Assets.Colors.FeedSceneRecentlyUpdatedColor
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
		let newPayloads = await buildPayloads()
		guard !Task.isCancelled else { return }

		let isDiscoverMode: Bool = {
			guard let first = newPayloads.first else { return false }
			if case .discover = first { return true }
			return false
		}()
		titleLabel.text = isDiscoverMode
			? NSLocalizedString("Discover", comment: "Discover")
			: NSLocalizedString("Recent Articles", comment: "Recent Articles")

		let wasEmpty = cardViews.isEmpty

		cardViews.forEach { $0.removeFromSuperview() }
		cardViews = []
		payloads = newPayloads

		pageControl.numberOfPages = newPayloads.count
		pageControl.currentPage = 0

		for (index, payload) in newPayloads.enumerated() {
			let card = RecentlyUpdatedCardView()
			card.payload = payload
			card.translatesAutoresizingMaskIntoConstraints = false
			card.addTarget(self, action: #selector(cardTapped(_:)), for: .touchUpInside)

			switch payload {
			case .feed(let feed, let article):
				card.accessibilityLabel = feed.nameForDisplay
				card.setImage(iconImage(forFeed: feed))
				card.setText(title: article.title ?? feed.nameForDisplay, snippet: snippetText(for: article))
			case .discover(let source):
				card.accessibilityLabel = source.name
				card.setImage(iconImage(forSource: source))
				card.setText(title: source.name, snippet: source.author)
			}

			pageScrollView.addSubview(card)
			cardViews.append(card)

			var cardConstraints: [NSLayoutConstraint] = [
				card.topAnchor.constraint(equalTo: pageScrollView.contentLayoutGuide.topAnchor),
				card.bottomAnchor.constraint(equalTo: pageScrollView.contentLayoutGuide.bottomAnchor),
				card.widthAnchor.constraint(equalTo: pageScrollView.frameLayoutGuide.widthAnchor),
				card.heightAnchor.constraint(equalTo: pageScrollView.frameLayoutGuide.heightAnchor),
			]

			if index == 0 {
				cardConstraints.append(card.leadingAnchor.constraint(equalTo: pageScrollView.contentLayoutGuide.leadingAnchor))
			} else {
				cardConstraints.append(card.leadingAnchor.constraint(equalTo: cardViews[index - 1].trailingAnchor))
			}

			if index == newPayloads.count - 1 {
				cardConstraints.append(card.trailingAnchor.constraint(equalTo: pageScrollView.contentLayoutGuide.trailingAnchor))
			}

			NSLayoutConstraint.activate(cardConstraints)
		}

		if !newPayloads.isEmpty && wasEmpty {
			pageScrollView.alpha = 0
			UIView.animate(withDuration: 0.28, delay: 0, options: .curveEaseOut) {
				self.pageScrollView.alpha = 1
			}
		}

		resetInactivityTimer()
	}

	func buildPayloads() async -> [RecentlyUpdatedStripPayload] {
		let recentFeeds = await computeRecentlyUpdatedUnreadFeeds()
		if !recentFeeds.isEmpty {
			return recentFeeds.map { .feed($0.feed, $0.article) }
		}
		return buildDiscoverSourceItems().map { .discover($0) }
	}

	func computeRecentlyUpdatedUnreadFeeds() async -> [(feed: Feed, article: Article)] {
		var feedByID = [String: Feed]()
		var results: [(feed: Feed, article: Article)] = []

		for account in AccountManager.shared.activeAccounts {
			for feed in account.flattenedFeeds() where feed.unreadCount > 0 {
				feedByID[feed.feedID] = feed
			}
			guard !feedByID.isEmpty else { continue }
			guard let unreadArticles = try? await account.fetchArticlesAsync(.unread()) else { continue }
			for article in unreadArticles {
				guard let feed = feedByID[article.feedID] else { continue }
				results.append((feed: feed, article: article))
			}
		}

		return results.sorted { $0.article.logicalDatePublished > $1.article.logicalDatePublished }
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

	// MARK: - Snippet

	private func snippetText(for article: Article) -> String? {
		if let summary = article.summary, !summary.isEmpty {
			return summary
		}
		if let text = article.contentText, !text.isEmpty {
			let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
			if !trimmed.isEmpty { return String(trimmed.prefix(300)) }
		}
		if let html = article.contentHTML, !html.isEmpty {
			let stripped = html
				.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
				.replacingOccurrences(of: "&amp;", with: "&")
				.replacingOccurrences(of: "&lt;", with: "<")
				.replacingOccurrences(of: "&gt;", with: ">")
				.replacingOccurrences(of: "&quot;", with: "\"")
				.replacingOccurrences(of: "&#39;", with: "'")
				.replacingOccurrences(of: "&nbsp;", with: " ")
				.components(separatedBy: .whitespacesAndNewlines)
				.filter { !$0.isEmpty }
				.joined(separator: " ")
			if !stripped.isEmpty { return String(stripped.prefix(300)) }
		}
		return nil
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

	@objc private func cardTapped(_ sender: UIControl) {
		guard let card = sender as? RecentlyUpdatedCardView,
			  let payload = card.payload else { return }
		resetInactivityTimer()
		card.performTapFeedback { [weak self] in
			self?.onPayloadTapped?(payload)
		}
	}

	// MARK: - Auto-scroll

	private func startAutoScrollTimer() {
		autoScrollTimer?.invalidate()
		guard payloads.count > 1 else { return }
		autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated { self?.advanceToNextPage() }
		}
	}

	private func stopAutoScrollTimer() {
		autoScrollTimer?.invalidate()
		autoScrollTimer = nil
	}

	/// Stops auto-scroll and restarts the 20-second inactivity countdown.
	/// Call on any user interaction with the strip or feed list.
	func resetInactivityTimer() {
		stopAutoScrollTimer()
		inactivityTimer?.invalidate()
		inactivityTimer = nil
		guard payloads.count > 1, AppDefaults.shared.recentlyUpdatedAutoScroll else { return }
		inactivityTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: false) { [weak self] _ in
			MainActor.assumeIsolated { self?.startAutoScrollTimer() }
		}
	}

	private func advanceToNextPage() {
		guard payloads.count > 1, pageScrollView.bounds.width > 0 else { return }
		let next = (pageControl.currentPage + 1) % payloads.count
		pageScrollView.setContentOffset(CGPoint(x: CGFloat(next) * pageScrollView.bounds.width, y: 0), animated: true)
	}
}

// MARK: - UIScrollViewDelegate

extension RecentlyUpdatedStripController: UIScrollViewDelegate {
	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		guard scrollView.bounds.width > 0 else { return }
		let page = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
		pageControl.currentPage = max(0, min(page, payloads.count - 1))
	}

	func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
		stopAutoScrollTimer()
	}

	func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
		resetInactivityTimer()
	}
}

// MARK: - RecentlyUpdatedCardView

final class RecentlyUpdatedCardView: UIControl {
	var payload: RecentlyUpdatedStripPayload?

	private let iconImageView: UIImageView = {
		let iv = UIImageView()
		iv.translatesAutoresizingMaskIntoConstraints = false
		iv.contentMode = .scaleAspectFill
		iv.backgroundColor = Assets.Colors.foreground
		iv.layer.cornerRadius = 12
		iv.clipsToBounds = true
		return iv
	}()

	private let titleLabel: UILabel = {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = .preferredFont(forTextStyle: .subheadline).bold()
		label.textColor = .label
		label.numberOfLines = 1
		return label
	}()

	private let snippetLabel: UILabel = {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = .preferredFont(forTextStyle: .caption1)
		label.textColor = .secondaryLabel
		label.numberOfLines = 3
		label.lineBreakMode = .byTruncatingTail
		return label
	}()

	private let textStack: UIStackView = {
		let stack = UIStackView()
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.axis = .vertical
		stack.spacing = 2
		stack.alignment = .leading
		stack.isUserInteractionEnabled = false
		return stack
	}()

	private let pressOverlayView: UIView = {
		let view = UIView()
		view.translatesAutoresizingMaskIntoConstraints = false
		view.backgroundColor = .black.withAlphaComponent(0.06)
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
		backgroundColor = Assets.Colors.FeedSceneRecentlyUpdatedColor

		textStack.addArrangedSubview(titleLabel)
		textStack.addArrangedSubview(snippetLabel)
		addSubview(iconImageView)
		addSubview(textStack)
		addSubview(pressOverlayView)

		NSLayoutConstraint.activate([
			iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
			iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
			iconImageView.widthAnchor.constraint(equalToConstant: 70),
			iconImageView.heightAnchor.constraint(equalToConstant: 70),

			textStack.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 10),
			textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
			textStack.centerYAnchor.constraint(equalTo: centerYAnchor),

			pressOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
			pressOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
			pressOverlayView.topAnchor.constraint(equalTo: topAnchor),
			pressOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func setImage(_ image: UIImage?) {
		iconImageView.image = image
	}

	func setText(title: String?, snippet: String?) {
		titleLabel.text = title
		snippetLabel.text = snippet
		snippetLabel.isHidden = snippet == nil || snippet!.isEmpty
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

// MARK: - CompactPageControl

final class CompactPageControl: UIView {

	var numberOfPages: Int = 0 { didSet { setNeedsLayout() } }
	var currentPage: Int = 0 { didSet { setNeedsLayout() } }
	var hidesForSinglePage = true { didSet { setNeedsLayout() } }
	var currentPageIndicatorTintColor: UIColor = .label { didSet { setNeedsLayout() } }
	var pageIndicatorTintColor: UIColor = .tertiaryLabel { didSet { setNeedsLayout() } }

	private let maxDots = 5
	private let fullSize: CGFloat = 7
	private let smallSize: CGFloat = 4
	private let spacing: CGFloat = 5
	private var dots: [UIView] = []

	override init(frame: CGRect) { super.init(frame: frame); setup() }
	required init?(coder: NSCoder) { super.init(coder: coder); setup() }

	private func setup() {
		for _ in 0..<maxDots {
			let dot = UIView()
			addSubview(dot)
			dots.append(dot)
		}
	}

	private var windowStart: Int {
		guard numberOfPages > maxDots else { return 0 }
		return max(0, min(currentPage - maxDots / 2, numberOfPages - maxDots))
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		isHidden = hidesForSinglePage && numberOfPages <= 1

		let count = min(numberOfPages, maxDots)
		let start = windowStart

		var sizes = [CGFloat](repeating: fullSize, count: count)
		if numberOfPages > maxDots {
			if start > 0 { sizes[0] = smallSize }
			if start + count < numberOfPages { sizes[count - 1] = smallSize }
		}

		let totalWidth = sizes.reduce(0, +) + CGFloat(max(0, count - 1)) * spacing
		var x = (bounds.width - totalWidth) / 2
		let midY = bounds.height / 2

		for i in 0..<maxDots {
			let dot = dots[i]
			guard i < count else { dot.frame = .zero; continue }
			let page = start + i
			let size = sizes[i]
			dot.frame = CGRect(x: x, y: midY - size / 2, width: size, height: size)
			dot.layer.cornerRadius = size / 2
			dot.backgroundColor = (page == currentPage) ? currentPageIndicatorTintColor : pageIndicatorTintColor
			x += size + spacing
		}
	}
}
