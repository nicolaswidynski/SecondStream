//
//  MainFeedCollectionViewController.swift
//  NetNewsWire-iOS
//
//  Created by Stuart Breckenridge on 23/06/2025.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import UIKit
import os
import SafariServices
import UniformTypeIdentifiers
import WebKit
import RSCore
import RSTree
import RSWeb
import Account
import Articles

private let reuseIdentifier = "FeedCell"
private let folderIdentifier = "Folder"
private let containerReuseIdentifier = "Container"

private struct DiscoverSourceItem {
	let name: String
	let author: String?
	let url: String
	let imageURL: String?
	let imageURLLight: String?
	let category: FeedCategory
}

private enum RecentlyUpdatedStripPayload {
	case feed(Feed)
	case discover(DiscoverSourceItem)
}

final class MainFeedCollectionViewController: UICollectionViewController, UndoableCommandRunner {

	private let keyboardManager = KeyboardManager(type: .sidebar)
	override var keyCommands: [UIKeyCommand]? {

		// If the first responder is the WKWebView (PreloadedWebView) we don't want to supply any keyboard
		// commands that the system is looking for by going up the responder chain. They will interfere with
		// the WKWebViews built in hardware keyboard shortcuts, specifically the up and down arrow keys.
		guard let current = UIResponder.currentFirstResponder, !(current is PreloadedWebView) else {
			return nil
		}

		return keyboardManager.keyCommands
	}

	override var canBecomeFirstResponder: Bool {
		return true
	}

	var undoableCommands = [UndoableCommand]()
	weak var coordinator: SceneCoordinator!

	/// On iPhone, this property is used to prevent the user from selecting a new feed while the current feed is being deselected.
	/// While `isAnimating` is `true`, `shouldSelectItemAt()` will not allow new selection.
	/// The value is set to `true` in `viewWillAppear(_:)` if a feed is selected, and reset to `false` in
	/// `viewDidAppear(_:)` after a delay to allow the deselection animation to complete.
	private var isAnimating: Bool = false


	// MARK: - Add Menu State
	private lazy var addBarButton: UIBarButtonItem = {
		let podcastAction = UIAction(
			title: NSLocalizedString("Podcasts", comment: "Podcasts"),
			image: RSImage(named: "podcast_thin-symbol") ?? UIImage(systemName: "mic.fill")
		) { [weak self] _ in self?.addPodcast() }

		let youtubeAction = UIAction(
			title: NSLocalizedString("YouTube", comment: "YouTube"),
			image: UIImage(systemName: "play.rectangle")
		) { [weak self] _ in self?.addYoutube() }

		let newsAction = UIAction(
			title: NSLocalizedString("News", comment: "News"),
			image: UIImage(systemName: "newspaper")
		) { [weak self] _ in self?.addNews() }

		let rssAction = UIAction(
			title: NSLocalizedString("RSS", comment: "RSS"),
			image: RSImage(named: "rss_thin-symbol") ?? UIImage(systemName: "dot.radiowaves.left.and.right")
		) { [weak self] _ in self?.addRSSFeed() }

		let menu = UIMenu(title: "", children: [rssAction, newsAction, youtubeAction, podcastAction])
		if #available(iOS 16.0, *) {
			menu.preferredElementSize = .large
		}

		var config = UIButton.Configuration.plain()
		config.image = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium))
		config.title = NSLocalizedString("Add", comment: "Add")
		config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
			var updated = attributes
			updated.font = UIFont.systemFont(ofSize: 11, weight: .medium)
			return updated
		}
		config.imagePlacement = .top
		config.imagePadding = 2

		let button = UIButton(configuration: config)
		button.menu = menu
		button.showsMenuAsPrimaryAction = true
		button.addAction(UIAction { _ in
			UIImpactFeedbackGenerator(style: .medium).impactOccurred()
		}, for: .touchDown)
		button.accessibilityLabel = NSLocalizedString("Add Feed", comment: "Add Feed")
		button.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			button.widthAnchor.constraint(equalToConstant: 56),
			button.heightAnchor.constraint(equalToConstant: 56),
		])

		return UIBarButtonItem(customView: button)
	}()

	/// The update status label (added directly to view, not navigation bar)
	private lazy var updateStatusLabel: UILabel = {
		let label = UILabel()
		label.font = .preferredFont(forTextStyle: .caption2)
		label.textColor = .secondaryLabel
		label.textAlignment = .right
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}()

	private var updateStatusTrailingConstraint: NSLayoutConstraint?
	private let recentlyUpdatedTopInset: CGFloat = 156
	private let defaultTopInset: CGFloat = 8

	private lazy var recentlyUpdatedContainerView: UIView = {
		let view = UIView()
		view.translatesAutoresizingMaskIntoConstraints = false
		return view
	}()

	private lazy var navBarExtendedBackgroundView: UIVisualEffectView = {
		let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
		view.translatesAutoresizingMaskIntoConstraints = false
		view.isUserInteractionEnabled = false
		return view
	}()

	private lazy var recentlyUpdatedTitleLabel: UILabel = {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = UIFont.preferredFont(forTextStyle: .title3).bold()
		label.textColor = .label
		label.text = NSLocalizedString("Recently Updated", comment: "Recently Updated")
		return label
	}()

	private lazy var recentlyUpdatedScrollView: UIScrollView = {
		let scrollView = UIScrollView()
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.showsHorizontalScrollIndicator = false
		scrollView.showsVerticalScrollIndicator = false
		scrollView.alwaysBounceVertical = false
		scrollView.isDirectionalLockEnabled = true
		return scrollView
	}()

	private lazy var recentlyUpdatedBackgroundView: UIVisualEffectView = {
		let view = UIVisualEffectView(effect: nil)//UIBlurEffect(style: .systemChromeMaterial))
		view.translatesAutoresizingMaskIntoConstraints = false
		view.layer.cornerRadius = 20
		view.clipsToBounds = true
		return view
	}()

	private lazy var recentlyUpdatedStackView: UIStackView = {
		let stack = UIStackView()
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.axis = .horizontal
		stack.spacing = 3
		stack.alignment = .center
		return stack
	}()

	/// The current update status text to display
	var updateStatusText: String? {
		didSet {
			updateStatusLabel.text = updateStatusText
		}
	}

	private lazy var creditsLabel: UILabel = {
		let label = UILabel()
		label.font = .preferredFont(forTextStyle: .caption2)
		label.textColor = .secondaryLabel
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}()

	private lazy var starredButton: UIBarButtonItem = {
		let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
		let image = UIImage(systemName: "bookmark", withConfiguration: config)
		let button = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(starredTapped))
		button.accessibilityLabel = NSLocalizedString("Starred", comment: "Starred")
		return button
	}()

	var dataSource: UICollectionViewDiffableDataSource<String, SidebarItemNode>!

	override func viewDidLoad() {
		super.viewDidLoad()
		registerForNotifications()
		configureCollectionView()
		configureDiffableDataSource()
		configureNavigationBar()
		configureRecentlyUpdatedStrip()
		configureToolbar()
		collectionView.dragDelegate = self
		collectionView.dropDelegate = self
		becomeFirstResponder()
		refreshRecentlyUpdatedShowsStrip()

		// Fetch sources on launch
		SourcesRefreshManager.shared.forceRefresh()

		// Credits: observe updates and fetch on first launch
		NotificationCenter.default.addObserver(self, selector: #selector(creditsDidUpdate), name: .creditsDidUpdate, object: nil)
		updateCreditsLabel()
		if FeedStatsManager.shared.cachedCredits == nil {
			Task { await FeedStatsManager.shared.fetchCredits() }
		}

		// Refresh sources when app comes to foreground
		NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

	private func configureToolbar() {
		setToolbarItems([.flexibleSpace(), addBarButton], animated: false)
		collectionView.contentInset.top = defaultTopInset
		collectionView.verticalScrollIndicatorInsets.top = defaultTopInset
	}
 

	private func configureNavigationBar() {
		navigationItem.title = nil

		// Left bar button: Settings
		let settingsButton = UIBarButtonItem(
			image: UIImage(systemName: "gearshape"),
			style: .plain,
			target: self,
			action: #selector(settingsTapped)
		)
		settingsButton.accessibilityLabel = NSLocalizedString("Settings", comment: "Settings")
		navigationItem.leftBarButtonItem = settingsButton

		// Right bar button: Starred smart feed shortcut
		navigationItem.rightBarButtonItem = starredButton

		// Add update status label to the view (not navigation bar)
		view.addSubview(updateStatusLabel)
		let trailingConstraint = updateStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -72)
		updateStatusTrailingConstraint = trailingConstraint
		NSLayoutConstraint.activate([
			updateStatusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: -40),
			trailingConstraint
		])

		// Credits label is hidden; the value is shown in Settings instead.
		creditsLabel.isHidden = true
		view.addSubview(creditsLabel)
		NSLayoutConstraint.activate([
			creditsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 72),
			creditsLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: -40)
		])
	}

	private func configureRecentlyUpdatedStrip() {
		view.insertSubview(navBarExtendedBackgroundView, aboveSubview: collectionView)
		view.addSubview(recentlyUpdatedContainerView)
		recentlyUpdatedContainerView.addSubview(recentlyUpdatedTitleLabel)
		recentlyUpdatedContainerView.addSubview(recentlyUpdatedBackgroundView)
		recentlyUpdatedBackgroundView.contentView.addSubview(recentlyUpdatedScrollView)
		recentlyUpdatedScrollView.addSubview(recentlyUpdatedStackView)

		NSLayoutConstraint.activate([
			navBarExtendedBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			navBarExtendedBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			navBarExtendedBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
			navBarExtendedBackgroundView.bottomAnchor.constraint(equalTo: recentlyUpdatedContainerView.bottomAnchor, constant: 10),

			recentlyUpdatedContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
			recentlyUpdatedContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
			recentlyUpdatedContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),

			recentlyUpdatedTitleLabel.leadingAnchor.constraint(equalTo: recentlyUpdatedContainerView.leadingAnchor, constant: 2),
			recentlyUpdatedTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: recentlyUpdatedContainerView.trailingAnchor),
			recentlyUpdatedTitleLabel.topAnchor.constraint(equalTo: recentlyUpdatedContainerView.topAnchor),

			recentlyUpdatedBackgroundView.leadingAnchor.constraint(equalTo: recentlyUpdatedContainerView.leadingAnchor),
			recentlyUpdatedBackgroundView.trailingAnchor.constraint(equalTo: recentlyUpdatedContainerView.trailingAnchor),
			recentlyUpdatedBackgroundView.topAnchor.constraint(equalTo: recentlyUpdatedTitleLabel.bottomAnchor, constant: 10),
			recentlyUpdatedBackgroundView.heightAnchor.constraint(equalToConstant: 86),
			recentlyUpdatedBackgroundView.bottomAnchor.constraint(equalTo: recentlyUpdatedContainerView.bottomAnchor),

			recentlyUpdatedScrollView.leadingAnchor.constraint(equalTo: recentlyUpdatedBackgroundView.contentView.leadingAnchor, constant: 10),
			recentlyUpdatedScrollView.trailingAnchor.constraint(equalTo: recentlyUpdatedBackgroundView.contentView.trailingAnchor, constant: -10),
			recentlyUpdatedScrollView.topAnchor.constraint(equalTo: recentlyUpdatedBackgroundView.contentView.topAnchor, constant: 8),
			recentlyUpdatedScrollView.bottomAnchor.constraint(equalTo: recentlyUpdatedBackgroundView.contentView.bottomAnchor, constant: -8),

			recentlyUpdatedStackView.leadingAnchor.constraint(equalTo: recentlyUpdatedScrollView.contentLayoutGuide.leadingAnchor),
			recentlyUpdatedStackView.trailingAnchor.constraint(equalTo: recentlyUpdatedScrollView.contentLayoutGuide.trailingAnchor),
			recentlyUpdatedStackView.topAnchor.constraint(equalTo: recentlyUpdatedScrollView.contentLayoutGuide.topAnchor),
			recentlyUpdatedStackView.bottomAnchor.constraint(equalTo: recentlyUpdatedScrollView.contentLayoutGuide.bottomAnchor)
		])
	}

	@objc private func settingsTapped() {
		coordinator.showSettings()
	}

	@objc private func starredTapped() {
		coordinator.selectStarredFeed()
	}

	@objc private func recentlyUpdatedFeedTapped(_ sender: UIControl) {
		guard let itemView = sender as? RecentlyUpdatedFeedItemView,
			  let payload = itemView.payload else {
			return
		}
		itemView.performTapFeedback { [weak self] in
			guard let self else {
				return
			}
			switch payload {
			case .feed(let feed):
				expandCategorySectionForCategory(feed.feedCategory)
				coordinator.selectFeed(feed, animations: [.navigation, .scroll])
			case .discover(let source):
				addDiscoverSource(source)
			}
		}
	}

	private func refreshRecentlyUpdatedShowsStrip() {
		Task { await applyRecentlyUpdatedStripPayloads() }
	}

	private func applyRecentlyUpdatedStripPayloads() async {
		let payloads = await buildRecentlyUpdatedStripPayloads()
		let isDiscoverMode: Bool = {
			guard let first = payloads.first else { return false }
			if case .discover = first { return true }
			return false
		}()
		recentlyUpdatedTitleLabel.text = isDiscoverMode
			? NSLocalizedString("Discover", comment: "Discover")
			: NSLocalizedString("Recently Updated", comment: "Recently Updated")

		recentlyUpdatedStackView.arrangedSubviews.forEach { view in
			recentlyUpdatedStackView.removeArrangedSubview(view)
			view.removeFromSuperview()
		}

		for payload in payloads {
			let itemView = RecentlyUpdatedFeedItemView()
			itemView.payload = payload
			itemView.translatesAutoresizingMaskIntoConstraints = false
			itemView.addTarget(self, action: #selector(recentlyUpdatedFeedTapped(_:)), for: .touchUpInside)
			switch payload {
			case .feed(let feed):
				itemView.accessibilityLabel = feed.nameForDisplay
				itemView.setImage(recentlyUpdatedIconImage(for: feed))
			case .discover(let source):
				itemView.accessibilityLabel = source.name
				itemView.setImage(discoverSourceIconImage(for: source))
			}
			NSLayoutConstraint.activate([
				itemView.widthAnchor.constraint(equalToConstant: 72),
				itemView.heightAnchor.constraint(equalToConstant: 68)
			])
			recentlyUpdatedStackView.addArrangedSubview(itemView)
		}

		let hasFeeds = !payloads.isEmpty
		recentlyUpdatedContainerView.isHidden = !hasFeeds
		navBarExtendedBackgroundView.isHidden = !hasFeeds
		let topInset = hasFeeds ? recentlyUpdatedTopInset : defaultTopInset
		collectionView.contentInset.top = topInset
		collectionView.verticalScrollIndicatorInsets.top = topInset
	}

	private func buildRecentlyUpdatedStripPayloads() async -> [RecentlyUpdatedStripPayload] {
		let recentFeeds = await computeRecentlyUpdatedUnreadFeeds()
		if !recentFeeds.isEmpty {
			return recentFeeds.map { .feed($0) }
		}
		return buildDiscoverSourceItems().map { .discover($0) }
	}

	private func computeRecentlyUpdatedUnreadFeeds() async -> [Feed] {
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
				guard feedByID[article.feedID] != nil else {
					continue
				}
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

	private func buildDiscoverSourceItems() -> [DiscoverSourceItem] {
		var discoverItems = [DiscoverSourceItem]()

		let randomPodcastSources = Array(PodcastSourcesManager.shared.podcastSources.shuffled().prefix(2))
		for source in randomPodcastSources {
			discoverItems.append(DiscoverSourceItem(name: source.name, author: source.author, url: source.url, imageURL: source.imageURL, imageURLLight: source.imageURLLight, category: .podcast))
		}

		let randomYoutubeSources = Array(YoutubeSourcesManager.shared.youtubeSources.shuffled().prefix(2))
		for source in randomYoutubeSources {
			discoverItems.append(DiscoverSourceItem(name: source.name, author: source.author, url: source.url, imageURL: source.imageURL, imageURLLight: source.imageURLLight, category: .youtube))
		}

		let randomNewsSources = Array(NewsSourcesManager.shared.newsSources.shuffled().prefix(2))
		for source in randomNewsSources {
			discoverItems.append(DiscoverSourceItem(name: source.name, author: source.author, url: source.url, imageURL: source.imageURL, imageURLLight: source.imageURLLight, category: .news))
		}

		let randomRSSSources = Array(RSSSourcesManager.shared.rssSources.shuffled().prefix(2))
		for source in randomRSSSources {
			discoverItems.append(DiscoverSourceItem(name: source.name, author: source.author, url: source.url, imageURL: source.imageURL, imageURLLight: source.imageURLLight, category: .rss))
		}

		return discoverItems
	}

	private func recentlyUpdatedIconImage(for feed: Feed) -> UIImage {
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

	private func discoverSourceIconImage(for source: DiscoverSourceItem) -> UIImage {
		if let imageURL = source.imageURL {
			// Rule 1: library feeds carry imageURLLight directly in the source entry.
			// Rule 2: webhook-only feeds store their light URL in LightFeedIconStore.
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

	private func addDiscoverSource(_ source: DiscoverSourceItem) {
		let urlString = source.url.trimmingCharacters(in: .whitespacesAndNewlines)
		if !urlString.isEmpty {
			addFeedDirectly(urlString: urlString, category: source.category, sourceName: source.name, sourceAuthor: source.author, sourceImageURL: source.imageURL, sourceImageURLLight: source.imageURLLight)
			return
		}

		switch source.category {
		case .podcast:
			addPodcastWithWebhook(name: source.name, author: source.author)
		case .youtube:
			addYoutubeWithWebhook(name: source.name, author: source.author)
		case .news:
			addTopicWithWebhook(name: source.name, author: source.author)
		case .rss:
			break
		}
	}

	@objc private func addRSSFeed() {
		presentRSSPicker()
	}

	private func presentRSSPicker() {
		let picker = RSSPickerViewController()
		picker.delegate = self
		let navController = UINavigationController(rootViewController: picker)
		applyPickerNavigationBarAppearance(to: navController)
		present(navController, animated: true)
	}

	@objc private func addPodcast() {
		presentPodcastPicker()
	}

	private func presentPodcastPicker() {
		let picker = PodcastPickerViewController()
		picker.delegate = self
		let navController = UINavigationController(rootViewController: picker)
		applyPickerNavigationBarAppearance(to: navController)
		present(navController, animated: true)
	}

	@objc private func addYoutube() {
		presentYoutubePicker()
	}

	private func presentYoutubePicker() {
		let picker = YoutubePickerViewController()
		picker.delegate = self
		let navController = UINavigationController(rootViewController: picker)
		applyPickerNavigationBarAppearance(to: navController)
		present(navController, animated: true)
	}

	private func applyPickerNavigationBarAppearance(to navController: UINavigationController) {
		// Prevent black flash: UINavigationController.view has no background
		// by default, which shows as black when the nav bar goes transparent
		// during scroll-edge transitions.
		navController.view.backgroundColor = .systemBackground

		let appearance = UINavigationBarAppearance()
		appearance.configureWithOpaqueBackground()
		appearance.backgroundColor = .systemBackground
		navController.navigationBar.standardAppearance = appearance
		navController.navigationBar.scrollEdgeAppearance = appearance
		navController.navigationBar.compactAppearance = appearance
		navController.navigationBar.compactScrollEdgeAppearance = appearance
	}

	@objc private func addNews() {
		presentNewsPicker()
	}

	private func presentNewsPicker() {
		let picker = NewsPickerViewController()
		picker.delegate = self
		let navController = UINavigationController(rootViewController: picker)
		navController.modalPresentationStyle = .formSheet
		present(navController, animated: true)
	}

	/// Adds a feed by URL directly (no gate check).
	///
	/// Pass `sourceName`, `sourceAuthor`, and `sourceImageURL` when the caller already has that
	/// metadata (e.g. from a picker).
	/// Pass `summaryURL` to fetch canonical show name/author from the server-side JSON file
	/// instead of relying on the user-entered string when reporting the add to update-user-stats.
	private func addFeedDirectly(urlString: String, category: FeedCategory, sourceName: String? = nil, sourceAuthor: String? = nil, sourceImageURL: String? = nil, sourceImageURLLight: String? = nil, validateFeed: Bool = true, summaryURL: String? = nil, completion: (() -> Void)? = nil) {
		let normalizedURL = urlString.normalizedURL
		guard !normalizedURL.isEmpty, let url = URL(string: normalizedURL) else {
			return
		}

		// Get the first active account
		guard let account = AccountManager.shared.activeAccounts.first else {
			return
		}

		// Check if already subscribed
		if account.hasFeed(withURL: url.absoluteString) {
			let alert = UIAlertController(
				title: NSLocalizedString("Already Subscribed", comment: "Already Subscribed"),
				message: NSLocalizedString("You are already subscribed to this feed.", comment: "Already subscribed message"),
				preferredStyle: .alert
			)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default))
			present(alert, animated: true)
			return
		}

		// Show loading indicator
		let loadingAlert = UIAlertController(title: nil, message: NSLocalizedString("Adding...", comment: "Adding..."), preferredStyle: .alert)
		let activityIndicator = UIActivityIndicatorView(style: .medium)
		activityIndicator.translatesAutoresizingMaskIntoConstraints = false
		activityIndicator.startAnimating()
		loadingAlert.view.addSubview(activityIndicator)
		NSLayoutConstraint.activate([
			activityIndicator.centerXAnchor.constraint(equalTo: loadingAlert.view.centerXAnchor),
			activityIndicator.bottomAnchor.constraint(equalTo: loadingAlert.view.bottomAnchor, constant: -20)
		])
		present(loadingAlert, animated: true) {
			Task {
				BatchUpdate.shared.start()

				account.createFeed(url: url.absoluteString, name: sourceName, container: account, validateFeed: validateFeed) { result in
				// Set category and rebuild sidebar immediately so feed appears in the correct section
				if case .success(let feed) = result {
					feed.feedCategory = category
					NotificationCenter.default.post(name: .ChildrenDidChange, object: account)
					// Store light icon URL from library source (picker flow).
					if let lightURL = sourceImageURLLight {
						LightFeedIconStore.shared.setLightIconURL(lightURL, for: feed.url)
					}
					if !validateFeed, let summaryURL {
						Task {
							if let icons = await Self.fetchFeedIconURL(summaryURL: summaryURL) {
								await MainActor.run {
									feed.iconURL = icons.dark
									LightFeedIconStore.shared.setLightIconURL(icons.light, for: feed.url)
								}
							}
						}
					}
				}

				BatchUpdate.shared.end()

				loadingAlert.dismiss(animated: true) {
					switch result {
					case .success(let feed):
						Task {
							if category == .rss {
								// RSS: report just this one add
								await FeedStatsManager.shared.reportAdd(
									type: category,
									name: sourceName ?? url.absoluteString,
									author: sourceAuthor
								)
							} else {
								// Pod / YT / Topics: send a full subscription snapshot
								await FeedStatsManager.shared.reportUpdate()
							}
						}
						NotificationCenter.default.post(
							name: .UserDidAddFeed,
							object: self,
							userInfo: [
								UserInfoKey.feed: feed,
								UserInfoKey.suppressFeedDisclosure: true
							]
						)
						// Expand the corresponding category section
						self.expandCategorySectionForCategory(category)
						completion?()
					case .failure(let error):
						self.presentError(error)
					}
				}
			}
		}
		}
	}

	/// Fetches the JSON at `urlString` and returns the canonical `(name, author)` for the show.
	/// The expected format is the source library format: `[{"data": [{"Name": ..., "Author": ...}]}]`.
	/// Returns `nil` on network error, unexpected format, or missing name.
	private static func fetchSummaryInfo(urlString: String) async -> (name: String, author: String?)? {
		guard let url = URL(string: urlString) else {
			return nil
		}
		do {
			let (data, response) = try await URLSession.shared.data(from: url)
			guard let httpResponse = response as? HTTPURLResponse,
				  (200...299).contains(httpResponse.statusCode) else {
				return nil
			}
			guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
				  let firstItem = jsonArray.first,
				  let dataArray = firstItem["data"] as? [[String: Any]],
				  let entry = dataArray.first else {
				return nil
			}
			let nameKeys = ["Name", "name", "title"]
			let authorKeys = ["Author", "author"]
			var foundName: String?
			for key in nameKeys {
				if let v = entry[key] as? String {
					let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
					if !trimmed.isEmpty { foundName = trimmed; break }
				}
			}
			guard let name = foundName else {
				return nil
			}
			var foundAuthor: String?
			for key in authorKeys {
				if let v = entry[key] as? String {
					let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
					if !trimmed.isEmpty { foundAuthor = trimmed; break }
				}
			}
			return (name: name, author: foundAuthor)
		} catch {
			return nil
		}
	}

	/// Fetches the generated feed JSON at  and returns the  value.
	/// The expected format is the generated feed header: {"title":...,"image_link":...}.
	private static func fetchFeedIconURL(summaryURL: String) async -> (dark: String?, light: String?)? {
		guard let url = URL(string: summaryURL) else { return nil }
		guard let (data, response) = try? await URLSession.shared.data(from: url),
			  let httpResponse = response as? HTTPURLResponse,
			  (200...299).contains(httpResponse.statusCode),
			  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			return nil
		}
		var dark: String? = nil
		var light: String? = nil
		let keys = ["image_link", "icon", "favicon"]
		for key in keys {
			if let v = json[key] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				dark = v
				break
			}
		}
		if let v = json["image_link_light"] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			light = v
		}
		if dark == nil && light == nil { return nil }
		return (dark, light)
	}


	private func expandCategorySectionForCategory(_ category: FeedCategory) {
		let section: FeedSectionIdentifier
		switch category {
		case .rss:
			section = .rssFeeds
		case .podcast:
			section = .podcasts
		case .youtube:
			section = .youtube
		case .news:
			section = .news
		}
		coordinator.expandCategorySection(section)
	}

	override func viewWillAppear(_ animated: Bool) {
		navigationController?.setToolbarHidden(false, animated: animated)
		navigationController?.additionalSafeAreaInsets.bottom = 60
		applyNavigationBarBackgroundStyleToRecentlyUpdatedStrip()
		refreshRecentlyUpdatedShowsStrip()
		updateUI()
		super.viewWillAppear(animated)

		if traitCollection.userInterfaceIdiom == .phone {
			self.navigationController?.navigationBar.prefersLargeTitles = false
			self.navigationItem.largeTitleDisplayMode = .never
			
//			navigationController?.navigationBar.backgroundColor = .red

			/// On iPhone, we want to deselect the feed when the user navigates
			/// back to the feeds view. To prevent the user from selecting a new feed while
			/// the current feed is being deselected, set `isAnimating` to true.
			///
			/// `shouldSelectItemAt()` will not allow selection when `isAnimating`
			/// is `true.`
			if collectionView.indexPathsForSelectedItems != nil {
				isAnimating = true
			}
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		/// On iPhone, once the deselection animation has completed, set `isAnimating`
		/// to false and this will allow selection.
		if traitCollection.userInterfaceIdiom == .phone {
			if collectionView.indexPathsForSelectedItems != nil {
				coordinator.selectSidebarItem(indexPath: nil, animations: [.select])
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: {
					self.isAnimating = false
				})
			}
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		navigationController?.additionalSafeAreaInsets.bottom = 0
	}

	func registerForNotifications() {
		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidInitialize(_:)), name: .UnreadCountDidInitialize, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(faviconDidBecomeAvailable(_:)), name: .FaviconDidBecomeAvailable, object: nil)
		// TODO: fix this temporary hack, which will probably require refactoring image handling.
		// We want to know when to possibly reconfigure our cells with a new image, and we don’t
		// always know when an image is available — but watching the .htmlMetadataAvailable Notification
		// lets us know that it’s time to request an image.
		NotificationCenter.default.addObserver(self, selector: #selector(faviconDidBecomeAvailable(_:)), name: .htmlMetadataAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(feedIconDidBecomeAvailable(_:)), name: .feedIconDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(feedSettingDidChange(_:)), name: .feedSettingDidChange, object: nil)

			registerForTraitChanges([UITraitPreferredContentSizeCategory.self], target: self, action: #selector(preferredContentSizeCategoryDidChange))
		NotificationCenter.default.addObserver(self, selector: #selector(sourceImageDidBecomeAvailable(_:)), name: .sourceImageDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsDidChange(_:)), name: UserDefaults.didChangeNotification, object: nil)

	}

	private func applyNavigationBarBackgroundStyleToRecentlyUpdatedStrip() {
		guard let navigationBar = navigationController?.navigationBar else {
			recentlyUpdatedBackgroundView.effect = nil//UIBlurEffect(style: .systemChromeMaterial)
			navBarExtendedBackgroundView.effect = UIBlurEffect(style: .systemChromeMaterial)
			navBarExtendedBackgroundView.alpha = 0.9//1.0
			return
		}

		let appearance = navigationBar.scrollEdgeAppearance ?? navigationBar.standardAppearance
		if let backgroundEffect = appearance.backgroundEffect {
			recentlyUpdatedBackgroundView.effect = nil//backgroundEffect
			navBarExtendedBackgroundView.effect = backgroundEffect
		} else {
			recentlyUpdatedBackgroundView.effect = nil//UIBlurEffect(style: .systemChromeMaterial)
			navBarExtendedBackgroundView.effect = UIBlurEffect(style: .systemChromeMaterial)
			navBarExtendedBackgroundView.alpha = 0.9//1.0
		}

		recentlyUpdatedBackgroundView.backgroundColor = .clear
		navBarExtendedBackgroundView.backgroundColor = .clear
	}

	// MARK: - Collection View Configuration
	func configureCollectionView() {
		var config = UICollectionLayoutListConfiguration(appearance: traitCollection.userInterfaceIdiom == .pad ? .sidebar : .insetGrouped)
		config.separatorConfiguration.color = .tertiarySystemFill
		config.headerMode = .supplementary
		// Don't use section footers - we use a standalone footer label instead

		config.trailingSwipeActionsConfigurationProvider = { [unowned self] indexPath in
			let deleteTitle = NSLocalizedString("Delete", comment: "Delete")
			let deleteAction = UIContextualAction(style: .destructive, title: nil) { [weak self] _, _, completion in
				self?.delete(indexPath: indexPath)
				completion(true)
			}
			deleteAction.image = UIImage(systemName: "trash")
			deleteAction.accessibilityLabel = deleteTitle
			deleteAction.backgroundColor = UIColor.systemRed

			let config = UISwipeActionsConfiguration(actions: [deleteAction])
			config.performsFirstActionWithFullSwipe = false

			return config
		}

		let layout = UICollectionViewCompositionalLayout.list(using: config)
		collectionView.setCollectionViewLayout(layout, animated: false)
		collectionView.refreshControl = UIRefreshControl()
		collectionView.refreshControl!.addTarget(self, action: #selector(refreshAccounts(_:)), for: .valueChanged)

		if config.appearance == .sidebar {
			// This defrosts the glass.
			collectionView.backgroundColor = .clear
		}
	}

	func configureDiffableDataSource() {
		dataSource = UICollectionViewDiffableDataSource<String, SidebarItemNode>(
			collectionView: collectionView
		) { [weak self] collectionView, indexPath, sidebarItemNode -> UICollectionViewCell? in
			guard let self else {
				return nil
			}

			if sidebarItemNode.node.representedObject is Folder {
				let cell = collectionView.dequeueReusableCell(
					withReuseIdentifier: folderIdentifier,
					for: indexPath
				) as! MainFeedCollectionViewFolderCell
				self.configure(cell, sidebarItemNode: sidebarItemNode)
				cell.delegate = self
				return cell
			} else {
				let cell = collectionView.dequeueReusableCell(
					withReuseIdentifier: reuseIdentifier,
					for: indexPath
				) as! MainFeedCollectionViewCell
				self.configure(cell, sidebarItemNode: sidebarItemNode)
				return cell
			}
		}

		dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
			guard let self else {
				return nil
			}

			guard kind == UICollectionView.elementKindSectionHeader else {
				return UICollectionReusableView()
			}

			let headerView = collectionView.dequeueReusableSupplementaryView(
				ofKind: kind,
				withReuseIdentifier: containerReuseIdentifier,
				for: indexPath
			) as! MainFeedCollectionHeaderReusableView

			// Get section identifier from snapshot
			let snapshot = self.dataSource.snapshot()
			let sectionIdentifiers = snapshot.sectionIdentifiers
			guard indexPath.section < sectionIdentifiers.count else {
				return UICollectionReusableView()
			}

			let sectionID = sectionIdentifiers[indexPath.section]

			// Check if this is a feed type section
			if let feedSection = FeedSectionIdentifier(rawValue: sectionID) {
				headerView.delegate = self
				headerView.sectionID = sectionID
				let icon = AppDefaults.shared.showSectionHeaderIcons ? feedSection.sectionIcon : nil
			headerView.configure(title: feedSection.displayName, icon: icon)
				headerView.unreadCount = self.unreadCountForSection(feedSection)
				headerView.disclosureExpanded = self.coordinator.isCategorySectionExpanded(feedSection)
				// Don't add context menu to category headers (no account actions apply)
				return headerView
			}

			// Fallback for non-category sections (should not happen with new structure)
			guard let nameProvider = self.coordinator.rootNode.childAtIndex(indexPath.section)?.representedObject as? DisplayNameProvider else {
				return UICollectionReusableView()
			}

			headerView.delegate = self
			headerView.configure(title: nameProvider.nameForDisplay)

			guard let sectionNode = self.coordinator.rootNode.childAtIndex(indexPath.section) else {
				return headerView
			}

			if let account = sectionNode.representedObject as? Account {
				headerView.unreadCount = account.unreadCount
			} else {
				headerView.unreadCount = 0
			}

			headerView.sectionID = sectionID
			headerView.disclosureExpanded = self.coordinator.isExpanded(sectionNode)

			if indexPath.section != 0 {
				headerView.addInteraction(UIContextMenuInteraction(delegate: self))
			}

			return headerView
		}
	}

	private func unreadCountForSection(_ section: FeedSectionIdentifier) -> Int {
		return coordinator.unreadCountForCategorySection(section)
	}


	func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<String, SidebarItemNode>, animatingDifferences: Bool, completion: (() -> Void)? = nil) {
		dataSource.apply(snapshot, animatingDifferences: animatingDifferences) { [weak self] in
			completion?()
			self?.refreshVisibleSectionHeaders()
		}
	}

	private func refreshVisibleSectionHeaders() {
		let sectionIdentifiers = dataSource.snapshot().sectionIdentifiers
		for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionHeader) {
			guard indexPath.section < sectionIdentifiers.count,
				  let headerView = collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: indexPath) as? MainFeedCollectionHeaderReusableView,
				  let feedSection = FeedSectionIdentifier(rawValue: sectionIdentifiers[indexPath.section]) else {
				continue
			}
			headerView.disclosureExpanded = coordinator.isCategorySectionExpanded(feedSection)
		}
	}

    // MARK: UICollectionViewDelegate

	override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		becomeFirstResponder()
		coordinator.selectSidebarItem(indexPath: indexPath, animations: [.navigation, .select, .scroll])
	}

    // MARK: UICollectionViewDelegate

    /*
    // Uncomment this method to specify if the specified item should be highlighted during tracking
    override func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        return true
    }
    */

    // Uncomment this method to specify if the specified item should be selected
    override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
		if traitCollection.userInterfaceIdiom == .pad { return true }
		return !isAnimating
    }

	override func collectionView(_ collectionView: UICollectionView, shouldShowMenuForItemAt indexPath: IndexPath) -> Bool {
        return true
    }

    override func collectionView(_ collectionView: UICollectionView, canPerformAction action: Selector, forItemAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        return false
    }

    override func collectionView(_ collectionView: UICollectionView, performAction action: Selector, forItemAt indexPath: IndexPath, withSender sender: Any?) {

    }

	override func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
		return nil
	}

	// MARK: - Key Commands

	// MARK: - Keyboard shortcuts

	@objc func collapseAllExceptForGroupItems(_ sender: Any?) {
		coordinator.collapseAllFolders()
	}

	@objc func collapseSelectedRows(_ sender: Any?) {
		if let indexPath = coordinator.currentFeedIndexPath, let node = coordinator.nodeFor(indexPath) {
			coordinator.collapse(node)
			if let folder = collectionView.cellForItem(at: indexPath) as? MainFeedCollectionViewFolderCell {
				folder.disclosureExpanded = false
			}
		}
	}

	@objc override func delete(_ sender: Any?) {
		if let indexPath = coordinator.currentFeedIndexPath {
			delete(indexPath: indexPath)
		}
	}

	@objc func expandAll(_ sender: Any?) {
		coordinator.expandAllSectionsAndFolders()
	}

	@objc func expandSelectedRows(_ sender: Any?) {
		if let indexPath = coordinator.currentFeedIndexPath, let node = coordinator.nodeFor(indexPath) {
			coordinator.expand(node)
			if let folder = collectionView.cellForItem(at: indexPath) as? MainFeedCollectionViewFolderCell {
				folder.disclosureExpanded = true
			}
		}
	}

	@objc func markAllAsRead(_ sender: Any) {
		guard let indexPath = collectionView.indexPathsForSelectedItems?.first, let contentView = collectionView.cellForItem(at: indexPath)?.contentView else {
			return
		}

		let title = NSLocalizedString("Mark All as Read", comment: "Mark All as Read")
		MarkAsReadAlertController.confirm(self, coordinator: coordinator, confirmTitle: title, sourceType: contentView) { [weak self] in
			self?.coordinator.markAllAsReadInTimeline()
		}
	}

	@objc func navigateToTimeline(_ sender: Any?) {
		coordinator.navigateToTimeline()
	}

	@objc func openInBrowser(_ sender: Any?) {
		coordinator.showBrowserForCurrentFeed()
	}

	@objc func selectNextDown(_ sender: Any?) {
		coordinator.selectNextFeed()
	}

	@objc func selectNextUp(_ sender: Any?) {
		coordinator.selectPrevFeed()
	}

	@objc func showFeedInspector(_ sender: Any?) {
		coordinator.showFeedInspector()
	}

	// MARK: - API

	func focus() {
		becomeFirstResponder()
	}

	func updateUI() {
		// Filter state is managed via settings, not a visible button
	}

	func updateFeedSelection(animations: Animations) {
		if let indexPath = coordinator.currentFeedIndexPath {
			collectionView.selectItemAndScrollIfNotVisible(at: indexPath, animations: animations)
		} else {
			if let indexPath = collectionView.indexPathsForSelectedItems?.first {
				if animations.contains(.select) {
					collectionView.deselectItem(at: indexPath, animated: true)
				} else {
					collectionView.deselectItem(at: indexPath, animated: false)
				}
			}
		}
	}

	func openInAppBrowser() {
		if let indexPath = coordinator.currentFeedIndexPath,
			let url = coordinator.homePageURLForFeed(indexPath) {
			let vc = SFSafariViewController(url: url)
			vc.modalPresentationStyle = .overFullScreen
			present(vc, animated: true)
		}
	}

	func applyToAvailableCells(_ completion: (MainFeedCollectionViewCell, IndexPath) -> Void) {
		for cell in collectionView.visibleCells {
			guard let indexPath = collectionView.indexPath(for: cell) else {
				continue
			}
			if let cell = collectionView.cellForItem(at: indexPath) as? MainFeedCollectionViewCell {
				completion(cell, indexPath)
			}
		}
	}

	func configureIcon(_ cell: MainFeedCollectionViewCell, sidebarItem: SidebarItem) {
		guard let sidebarItemID = sidebarItem.sidebarItemID else {
			return
		}
		cell.iconImage = IconImageCache.shared.imageFor(sidebarItemID)
	}

	func configureIcon(_ cell: MainFeedCollectionViewFolderCell, sidebarItem: SidebarItem) {
		guard let sidebarItemID = sidebarItem.sidebarItemID else {
			return
		}
		cell.iconImage = IconImageCache.shared.imageFor(sidebarItemID)
	}

	func configureIcon(_ cell: MainFeedCollectionViewCell, _ indexPath: IndexPath) {
		guard let node = coordinator.nodeFor(indexPath),
			  let sidebarItem = node.representedObject as? SidebarItem,
			  let sidebarItemID = sidebarItem.sidebarItemID else {
			return
		}
		cell.iconImage = IconImageCache.shared.imageFor(sidebarItemID)
	}

	func configureIcon(_ cell: MainFeedCollectionViewFolderCell, _ indexPath: IndexPath) {
		guard let node = coordinator.nodeFor(indexPath),
			  let sidebarItem = node.representedObject as? SidebarItem,
			  let sidebarItemID = sidebarItem.sidebarItemID else {
			return
		}
		cell.iconImage = IconImageCache.shared.imageFor(sidebarItemID)
	}

	func configureCellsForRepresentedObject(_ representedObject: AnyObject) {
		// applyToCellsForRepresentedObject(representedObject, configure)
	}

	func applyToCellsForRepresentedObject(_ representedObject: AnyObject, _ completion: (MainFeedCollectionViewCell, IndexPath) -> Void) {
		applyToAvailableCells { (cell, indexPath) in
			if let node = coordinator.nodeFor(indexPath),
			   let representedSidebarItem = representedObject as? SidebarItem,
			   let candidateSidebarItem = node.representedObject as? SidebarItem,
			   representedSidebarItem.sidebarItemID == candidateSidebarItem.sidebarItemID {
				completion(cell, indexPath)
			}
		}
	}

	func restoreSelectionIfNecessary(adjustScroll: Bool) {
		if let indexPath = coordinator.mainFeedIndexPathForCurrentTimeline() {
			if adjustScroll {
				collectionView.selectItemAndScrollIfNotVisible(at: indexPath, animations: [])
			} else {
				collectionView.selectItem(at: indexPath, animated: false, scrollPosition: .centeredVertically)
			}
		}
	}

	// MARK: - Private

	/// Configure standard feed cells
	func configure(_ cell: MainFeedCollectionViewCell, sidebarItemNode: SidebarItemNode) {
		let node = sidebarItemNode.node
		var indentationLevel = 0
		if node.parent?.representedObject is Folder {
			indentationLevel = 1
		}

		if let sidebarItem = node.representedObject as? SidebarItem {
			cell.feedTitle.text = sidebarItem.nameForDisplay
			cell.unreadCount = sidebarItem.unreadCount
			// Feed rows (including Smart Feeds pseudo-feeds) use wider spacing between count and chevron.
			cell.useWideUnreadChevronSpacing = true
			cell.indentationLevel = indentationLevel
			configureIcon(cell, sidebarItem: sidebarItem)
		}
	}

	/// Configure folders
	func configure(_ cell: MainFeedCollectionViewFolderCell, sidebarItemNode: SidebarItemNode) {
		let node = sidebarItemNode.node

		if let folder = node.representedObject as? Folder {
			cell.folderTitle.text = folder.nameForDisplay
			cell.unreadCount = folder.unreadCount
			configureIcon(cell, sidebarItem: folder)
		}

		if let containerID = (node.representedObject as? Container)?.containerID {
			cell.setDisclosure(isExpanded: coordinator.isExpanded(containerID), animated: false)
		}
	}

	func configure(_ cell: MainFeedCollectionViewCell, indexPath: IndexPath) {
		guard let node = coordinator.nodeFor(indexPath) else {
			return
		}
		var indentationLevel = 0
		if node.parent?.representedObject is Folder {
			indentationLevel = 1
		}

		if let sidebarItem = node.representedObject as? SidebarItem {
			cell.feedTitle.text = sidebarItem.nameForDisplay
			cell.unreadCount = sidebarItem.unreadCount
			// Feed rows (including Smart Feeds pseudo-feeds) use wider spacing between count and chevron.
			cell.useWideUnreadChevronSpacing = true
			cell.indentationLevel = indentationLevel
			configureIcon(cell, indexPath)
		}
	}

	/// Configure folders
	func configure(_ cell: MainFeedCollectionViewFolderCell, indexPath: IndexPath) {
		guard let node = coordinator.nodeFor(indexPath) else {
			return
		}

		if let folder = node.representedObject as? Folder {
			cell.folderTitle.text = folder.nameForDisplay
			cell.unreadCount = folder.unreadCount
			configureIcon(cell, indexPath)
		}

		if let containerID = (node.representedObject as? Container)?.containerID {
			cell.setDisclosure(isExpanded: coordinator.isExpanded(containerID), animated: false)
		}
	}

	private func headerViewForAccount(_ account: Account) -> MainFeedCollectionHeaderReusableView? {

		guard let node = coordinator.rootNode.childNodeRepresentingObject(account),
			  let sectionIndex = coordinator.rootNode.indexOfChild(node) else {
			return nil
		}
		if sectionIndex == 0 { return nil }

		return collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: sectionIndex)) as? MainFeedCollectionHeaderReusableView
	}

	private func reloadAllVisibleCells(completion: (() -> Void)? = nil) {
		guard let indexPaths = collectionView.indexPathsForSelectedItems else {
			return
		}
		collectionView.reloadItems(at: indexPaths)
		restoreSelectionIfNecessary(adjustScroll: false)
	}


	// MARK: - Notifications

	@objc func preferredContentSizeCategoryDidChange() {
		IconImageCache.shared.emptyCache()
		reloadAllVisibleCells()
	}

	@objc func unreadCountDidChange(_ note: Notification) {
		refreshRecentlyUpdatedShowsStrip()
		updateUI()

		// Update category section headers (My Feeds, My Podcasts, etc.)
		updateCategorySectionUnreadCounts()

		guard let unreadCountProvider = note.object as? UnreadCountProvider else {
			return
		}

		if let account = unreadCountProvider as? Account {
			if let headerView = headerViewForAccount(account) {
				headerView.unreadCount = account.unreadCount
			}
			return
		}

		let node: Node? = coordinator.rootNode.descendantNodeRepresentingObject(unreadCountProvider as AnyObject)

		guard let unreadCountNode = node, let indexPath = coordinator.indexPathFor(unreadCountNode) else {
			return
		}

		if let cell = collectionView.cellForItem(at: indexPath) as? MainFeedCollectionViewCell {
			cell.unreadCount = unreadCountProvider.unreadCount
		}

		if let cell = collectionView.cellForItem(at: indexPath) as? MainFeedCollectionViewFolderCell {
			cell.unreadCount = unreadCountProvider.unreadCount
		}
	}

	@objc func unreadCountDidInitialize(_ note: Notification) {
		refreshRecentlyUpdatedShowsStrip()
		// Update all category section headers when unread counts are fully initialized
		updateCategorySectionUnreadCounts()
	}

	private func updateCategorySectionUnreadCounts() {
		let sectionIdentifiers = dataSource.snapshot().sectionIdentifiers

		for (sectionIndex, sectionID) in sectionIdentifiers.enumerated() {
			if let feedSection = FeedSectionIdentifier(rawValue: sectionID) {
				let indexPath = IndexPath(item: 0, section: sectionIndex)
				if let headerView = collectionView.supplementaryView(
					forElementKind: UICollectionView.elementKindSectionHeader,
					at: indexPath
				) as? MainFeedCollectionHeaderReusableView {
					headerView.unreadCount = unreadCountForSection(feedSection)
				}
			}
		}
	}

	@objc func feedSettingDidChange(_ note: Notification) {
		guard let feed = note.object as? Feed, let key = note.userInfo?[Feed.SettingUserInfoKey] as? String else {
			return
		}
		if key == Feed.SettingKey.homePageURL || key == Feed.SettingKey.faviconURL || key == Feed.SettingKey.iconURL {
			// Defer so FeedIconDownloader's feedSettingDidChange (cache invalidation) runs first.
			DispatchQueue.main.async {
				self.applyToCellsForRepresentedObject(feed, self.configureIcon(_:_:))
			}
		}
	}

	@objc func faviconDidBecomeAvailable(_ note: Notification) {
		applyToAvailableCells(configureIcon)
	}

	@objc func feedIconDidBecomeAvailable(_ note: Notification) {
		guard let feed = note.userInfo?[UserInfoKey.feed] as? Feed else {
			return
		}
		applyToCellsForRepresentedObject(feed, configureIcon(_:_:))
		refreshRecentlyUpdatedShowsStrip()
	}

	@objc func sourceImageDidBecomeAvailable(_ note: Notification) {
		refreshRecentlyUpdatedShowsStrip()
		applyToAvailableCells { (cell, indexPath) in
			configureIcon(cell, indexPath)
		}
	}

	@objc func userDefaultsDidChange(_ note: Notification) {
		let snapshot = dataSource.snapshot()
		for (sectionIndex, sectionID) in snapshot.sectionIdentifiers.enumerated() {
			guard let feedSection = FeedSectionIdentifier(rawValue: sectionID),
				  let headerView = collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: sectionIndex)) as? MainFeedCollectionHeaderReusableView else {
				continue
			}
			let icon = AppDefaults.shared.showSectionHeaderIcons ? feedSection.sectionIcon : nil
			headerView.configure(title: feedSection.displayName, icon: icon)
		}
	}

	// MARK: - Actions

	@objc func refreshAccounts(_ sender: Any) {
		collectionView.refreshControl?.endRefreshing()

		// This is a hack to make sure that an error dialog doesn't interfere with dismissing the refreshControl.
		// If the error dialog appears too closely to the call to endRefreshing, then the refreshControl never disappears.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
			appDelegate.manualRefresh(errorHandler: ErrorHandler.present(self))
		}

		// Also refresh sources (throttled to every 5 minutes)
		SourcesRefreshManager.shared.refreshIfNeeded()
	}

	@objc private func appWillEnterForeground() {
		SourcesRefreshManager.shared.refreshIfNeeded()
		refreshRecentlyUpdatedShowsStrip()
		Task { await FeedStatsManager.shared.fetchCredits() }
	}

	@objc private func creditsDidUpdate() {
		updateCreditsLabel()
	}

	private func updateCreditsLabel() {
		if let credits = FeedStatsManager.shared.cachedCredits {
			creditsLabel.text = "credits: \(credits)"
		} else {
			creditsLabel.text = nil
		}
	}

	private func showEnterRSSURLDialog() {
		let alert = UIAlertController(
			title: NSLocalizedString("Enter RSS URL", comment: "Enter RSS URL"),
			message: nil,
			preferredStyle: .alert
		)

		alert.addTextField { textField in
			textField.placeholder = "https://example.com/feed.xml"
			textField.keyboardType = .URL
			textField.autocapitalizationType = .none
			textField.autocorrectionType = .no
			if let clipboardString = UIPasteboard.general.string, clipboardString.mayBeURL {
				textField.text = clipboardString.normalizedURL
			}
		}

		let addAction = UIAlertAction(title: NSLocalizedString("Add", comment: "Add"), style: .default) { _ in
			if let urlText = alert.textFields?.first?.text, !urlText.isEmpty {
				self.addFeedDirectly(urlString: urlText, category: .rss)
			}
		}

		let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel)
		alert.addAction(addAction)
		alert.addAction(cancelAction)
		present(alert, animated: true)
	}

	private func showEnterPodcastNameDialog() {
		var seen = Set<String>()
		var items = [SourceSearchItem]()
		for source in PodcastSourcesManager.shared.podcastSources + PodcastSourcesManager.shared.podcastLibrarySources {
			let key = source.name.lowercased()
			if seen.insert(key).inserted {
				items.append(SourceSearchItem(name: source.name, author: source.author))
			}
		}
		let searchVC = SourceSearchViewController(
			placeholder: NSLocalizedString("Podcast name", comment: "Podcast name placeholder"),
			items: items,
			onSelect: { [weak self] item in
				self?.addPodcastWithWebhook(name: item.name, author: item.author)
			},
			onManualAdd: { [weak self] name in
				self?.addPodcastWithWebhook(name: name, author: nil)
			}
		)
		searchVC.title = NSLocalizedString("Add Podcast", comment: "Add Podcast")
		let nav = UINavigationController(rootViewController: searchVC)
		present(nav, animated: true)
	}

	private func addPodcastWithWebhook(name: String, author: String?) {
		// Show loading indicator
		let loadingAlert = UIAlertController(
			title: nil,
			message: NSLocalizedString("Searching for podcast...", comment: "Searching for podcast..."),
			preferredStyle: .alert
		)

		let activityIndicator = UIActivityIndicatorView(style: .medium)
		activityIndicator.translatesAutoresizingMaskIntoConstraints = false
		activityIndicator.startAnimating()
		loadingAlert.view.addSubview(activityIndicator)

		NSLayoutConstraint.activate([
			activityIndicator.centerXAnchor.constraint(equalTo: loadingAlert.view.centerXAnchor),
			activityIndicator.bottomAnchor.constraint(equalTo: loadingAlert.view.bottomAnchor, constant: -20)
		])

		present(loadingAlert, animated: true) {
			Task {
				let result = await PodcastSourcesManager.shared.addPodcast(name: name, author: author)

				if case .successExisting = result { SourcesRefreshManager.shared.forceRefresh() }
				if case .successNew = result { SourcesRefreshManager.shared.forceRefresh() }

				loadingAlert.dismiss(animated: true) {
					switch result {
					case .successExisting(let summaryURL):
						self.addFeedDirectly(urlString: summaryURL, category: .podcast, sourceName: name, sourceAuthor: author, validateFeed: false, summaryURL: summaryURL) {
							appDelegate.manualRefresh(errorHandler: ErrorHandler.present(self))
						}

					case .successNew(let summaryURL):
						self.addFeedDirectly(urlString: summaryURL, category: .podcast, sourceName: name, sourceAuthor: author, validateFeed: false, summaryURL: summaryURL) {
							self.showPodcastSuccessMessage {}
						}

					case .failure(let message):
						self.showPodcastError(message: message)
					}
				}
			}
		}
	}

	private func showPodcastSuccessMessage(completion: @escaping () -> Void) {
		let alert = UIAlertController(
			title: NSLocalizedString("Podcast Added", comment: "Podcast Added"),
			message: NSLocalizedString("Episodes from the last 2 months will be populated within approximately 15 minutes.", comment: "Podcast success message"),
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default) { _ in
			completion()
		})
		present(alert, animated: true)
	}

	private func showPodcastError(message: String) {
		let alert = UIAlertController(
			title: NSLocalizedString("Error", comment: "Error"),
			message: message,
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default))
		present(alert, animated: true)
	}

	func toggle(_ headerView: MainFeedCollectionHeaderReusableView) {
		guard let sectionID = headerView.sectionID else {
			return
		}

		// Check if this is a category section
		if let feedSection = FeedSectionIdentifier(rawValue: sectionID) {
			// Toggle category section expansion
			let isExpanded = coordinator.isCategorySectionExpanded(feedSection)
			// Set unread count BEFORE changing expansion state so the label shows correctly
			headerView.unreadCount = unreadCountForSection(feedSection)
			headerView.disclosureExpanded = !isExpanded
			coordinator.toggleCategorySection(feedSection)
			return
		}

		// Fallback for non-category sections (shouldn't happen with new structure)
		let snapshot = dataSource.snapshot()
		guard let sectionIndex = snapshot.sectionIdentifiers.firstIndex(of: sectionID),
			  let sectionNode = coordinator.rootNode.childAtIndex(sectionIndex) else {
			return
		}

		if coordinator.isExpanded(sectionNode) {
			headerView.disclosureExpanded = false
			coordinator.collapse(sectionNode)
		} else {
			headerView.disclosureExpanded = true
			coordinator.expand(sectionNode)
		}
	}
}

extension MainFeedCollectionViewController: MainFeedCollectionHeaderReusableViewDelegate {
	func mainFeedCollectionHeaderReusableViewDidTapDisclosureIndicator(_ view: MainFeedCollectionHeaderReusableView) {
		toggle(view)
	}
}

extension MainFeedCollectionViewController: MainFeedCollectionViewFolderCellDelegate {
	func mainFeedCollectionFolderViewCellDisclosureDidToggle(_ sender: MainFeedCollectionViewFolderCell, expanding: Bool) {
		if expanding {
			expand(sender)
		} else {
			collapse(sender)
		}
	}

	func expand(_ cell: MainFeedCollectionViewFolderCell) {
		guard let indexPath = collectionView.indexPath(for: cell), let node = coordinator.nodeFor(indexPath) else {
			return
		}
		coordinator.expand(node)
	}

	func collapse(_ cell: MainFeedCollectionViewFolderCell) {
		guard let indexPath = collectionView.indexPath(for: cell), let node = coordinator.nodeFor(indexPath) else {
			return
		}
		coordinator.collapse(node)
	}
}

extension MainFeedCollectionViewController: UIContextMenuInteractionDelegate {
	func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {

		guard let headerView = interaction.view as? MainFeedCollectionHeaderReusableView,
			  let sectionID = headerView.sectionID else {
			return nil
		}

		// Check if this is a category section
		if let feedSection = FeedSectionIdentifier(rawValue: sectionID) {
			// Category sections can have Add Folder (adds to first active account)
			return UIContextMenuConfiguration(identifier: sectionID as NSCopying, previewProvider: nil) { _ in
				var menuElements = [UIMenuElement]()

				// Add Folder action for category sections
				let addFolderTitle = NSLocalizedString("Add Folder", comment: "Add Folder")
				let addFolderAction = UIAction(title: addFolderTitle, image: Assets.Images.folderOutlinePlus) { [weak self] _ in
					self?.coordinator.showAddFolder()
				}
				menuElements.append(UIMenu(title: "", options: .displayInline, children: [addFolderAction]))

				// Mark All as Read for this category
				if let markAllAction = self.markAllAsReadActionForSection(feedSection, contentView: interaction.view) {
					menuElements.append(UIMenu(title: "", options: .displayInline, children: [markAllAction]))
				}

				return UIMenu(title: "", children: menuElements)
			}
		}

		// Fallback for old account-based sections (should not happen with new structure)
		let snapshot = dataSource.snapshot()
		guard let sectionIndex = snapshot.sectionIdentifiers.firstIndex(of: sectionID),
			let sectionNode = coordinator.rootNode.childAtIndex(sectionIndex),
			let account = sectionNode.representedObject as? Account
				else {
					return nil
		}

		return UIContextMenuConfiguration(identifier: sectionID as NSCopying, previewProvider: nil) { _ in

			var menuElements = [UIMenuElement]()
			menuElements.append(UIMenu(title: "", options: .displayInline, children: [self.getAccountInfoAction(account: account)]))

			// Add Folder action
			let addFolderAction = self.addFolderAction(account: account)
			menuElements.append(UIMenu(title: "", options: .displayInline, children: [addFolderAction]))

			if let markAllAction = self.markAllAsReadAction(account: account, contentView: interaction.view) {
				menuElements.append(UIMenu(title: "", options: .displayInline, children: [markAllAction]))
			}

			menuElements.append(UIMenu(title: "", options: .displayInline, children: [self.deactivateAccountAction(account: account)]))

			return UIMenu(title: "", children: menuElements)
		}
	}

	private func markAllAsReadActionForSection(_ section: FeedSectionIdentifier, contentView: UIView?) -> UIAction? {
		guard section != .smartFeeds else {
			return nil
		}

		let targetType: FeedCategory
		switch section {
		case .rssFeeds:
			targetType = .rss
		case .podcasts:
			targetType = .podcast
		case .youtube:
			targetType = .youtube
		case .news:
			targetType = .news
		case .smartFeeds:
			return nil
		}

		// Collect all feeds of this type
		var feedsToMark = [Feed]()
		for account in AccountManager.shared.activeAccounts {
			for feed in account.flattenedFeeds() {
				if feed.feedCategory == targetType {
					feedsToMark.append(feed)
				}
			}
		}

		guard !feedsToMark.isEmpty else {
			return nil
		}

		let title = NSLocalizedString("Mark All as Read", comment: "Mark All as Read")
		return UIAction(title: title, image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
			// Collect all unread articles from feeds of this category
			var allArticles = [Article]()
			for feed in feedsToMark {
				if let articles = try? feed.fetchUnreadArticles() {
					allArticles.append(contentsOf: articles)
				}
			}
			if !allArticles.isEmpty {
				self?.coordinator.markAllAsRead(allArticles)
			}
		}
	}

	func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {

		guard let sectionIndex = configuration.identifier as? Int,
			let cell = collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: sectionIndex)) as? MainFeedCollectionHeaderReusableView else {
				return nil
		}
		return UITargetedPreview(view: cell, parameters: CroppingPreviewParameters(view: cell))
	}
}

extension MainFeedCollectionViewController {
	func makeFeedContextMenu(indexPath: IndexPath, includeDeleteRename: Bool) -> UIContextMenuConfiguration {
		return UIContextMenuConfiguration(identifier: MainFeedRowIdentifier(indexPath: indexPath), previewProvider: nil, actionProvider: { [ weak self] _ in

			guard let self = self else {
				return nil
			}

			var menuElements = [UIMenuElement]()

			if let inspectorAction = self.getInfoAction(indexPath: indexPath) {
				menuElements.append(UIMenu(title: "", options: .displayInline, children: [inspectorAction]))
			}

			if let homePageAction = self.homePageAction(indexPath: indexPath) {
				menuElements.append(UIMenu(title: "", options: .displayInline, children: [homePageAction]))
			}

			var pageActions = [UIAction]()
			if let copyFeedPageAction = self.copyFeedPageAction(indexPath: indexPath) {
				pageActions.append(copyFeedPageAction)
			}
			if let copyHomePageAction = self.copyHomePageAction(indexPath: indexPath) {
				pageActions.append(copyHomePageAction)
			}
			if !pageActions.isEmpty {
				menuElements.append(UIMenu(title: "", options: .displayInline, children: pageActions))
			}

			if let markAllAction = self.markAllAsReadAction(indexPath: indexPath) {
				menuElements.append(UIMenu(title: "", options: .displayInline, children: [markAllAction]))
			}

			if includeDeleteRename {
				menuElements.append(UIMenu(title: "",
										   options: .displayInline,
										   children: [
											self.renameAction(indexPath: indexPath),
											self.deleteAction(indexPath: indexPath)
										   ]))
			}

			return UIMenu(title: "", children: menuElements)
		})
	}

	func makeFolderContextMenu(indexPath: IndexPath) -> UIContextMenuConfiguration {
		return UIContextMenuConfiguration(identifier: MainFeedRowIdentifier(indexPath: indexPath), previewProvider: nil, actionProvider: { [weak self] _ in

			guard let self = self else {
				return nil
			}

			var menuElements = [UIMenuElement]()

			if let markAllAction = self.markAllAsReadAction(indexPath: indexPath) {
				menuElements.append(UIMenu(title: "", options: .displayInline, children: [markAllAction]))
			}

			menuElements.append(UIMenu(title: "",
									   options: .displayInline,
									   children: [
										self.renameAction(indexPath: indexPath),
										self.deleteAction(indexPath: indexPath)
									   ]))

			return UIMenu(title: "", children: menuElements)

		})
	}

	func makePseudoFeedContextMenu(indexPath: IndexPath) -> UIContextMenuConfiguration? {
		guard let markAllAction = self.markAllAsReadAction(indexPath: indexPath) else {
			return nil
		}

		return UIContextMenuConfiguration(identifier: MainFeedRowIdentifier(indexPath: indexPath), previewProvider: nil, actionProvider: { _ in
			return UIMenu(title: "", children: [markAllAction])
		})
	}

	func homePageAction(indexPath: IndexPath) -> UIAction? {
		guard coordinator.homePageURLForFeed(indexPath) != nil else {
			return nil
		}

		let title = NSLocalizedString("Open Home Page", comment: "Open Home Page")
		let action = UIAction(title: title, image: Assets.Images.safari) { [weak self] _ in
			self?.coordinator.showBrowserForFeed(indexPath)
		}
		return action
	}

	func homePageAlertAction(indexPath: IndexPath, completion: @escaping (Bool) -> Void) -> UIAlertAction? {
		guard coordinator.homePageURLForFeed(indexPath) != nil else {
			return nil
		}

		let title = NSLocalizedString("Open Home Page", comment: "Open Home Page")
		let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
			self?.coordinator.showBrowserForFeed(indexPath)
			completion(true)
		}
		return action
	}

	func copyFeedPageAction(indexPath: IndexPath) -> UIAction? {
		guard let feed = coordinator.nodeFor(indexPath)?.representedObject as? Feed,
			  let url = URL(string: feed.url) else {
				  return nil
			  }

		let title = NSLocalizedString("Copy Feed URL", comment: "Copy Feed URL")
		let action = UIAction(title: title, image: Assets.Images.copy) { _ in
			UIPasteboard.general.url = url
		}
		return action
	}

	func copyFeedPageAlertAction(indexPath: IndexPath, completion: @escaping (Bool) -> Void) -> UIAlertAction? {
		guard let feed = coordinator.nodeFor(indexPath)?.representedObject as? Feed,
			  let url = URL(string: feed.url) else {
				  return nil
			  }

		let title = NSLocalizedString("Copy Feed URL", comment: "Copy Feed URL")
		let action = UIAlertAction(title: title, style: .default) { _ in
			UIPasteboard.general.url = url
			completion(true)
		}
		return action
	}

	func copyHomePageAction(indexPath: IndexPath) -> UIAction? {
		guard let feed = coordinator.nodeFor(indexPath)?.representedObject as? Feed,
			  let homePageURL = feed.homePageURL,
			  let url = URL(string: homePageURL) else {
				  return nil
			  }

		let title = NSLocalizedString("Copy Home Page URL", comment: "Copy Home Page URL")
		let action = UIAction(title: title, image: Assets.Images.copy) { _ in
			UIPasteboard.general.url = url
		}
		return action
	}

	func copyHomePageAlertAction(indexPath: IndexPath, completion: @escaping (Bool) -> Void) -> UIAlertAction? {
		guard let feed = coordinator.nodeFor(indexPath)?.representedObject as? Feed,
			  let homePageURL = feed.homePageURL,
			  let url = URL(string: homePageURL) else {
				  return nil
			  }

		let title = NSLocalizedString("Copy Home Page URL", comment: "Copy Home Page URL")
		let action = UIAlertAction(title: title, style: .default) { _ in
			UIPasteboard.general.url = url
			completion(true)
		}
		return action
	}

	func markAllAsReadAlertAction(indexPath: IndexPath, completion: @escaping (Bool) -> Void) -> UIAlertAction? {
		guard let feed = coordinator.nodeFor(indexPath)?.representedObject as? Feed,
			feed.unreadCount > 0,
			let articles = try? feed.fetchArticles(), let contentView = self.collectionView.cellForItem(at: indexPath)?.contentView else {
				return nil
		}

		let localizedMenuText = NSLocalizedString("Mark All as Read in “%@”", comment: "Command")
		let title = NSString.localizedStringWithFormat(localizedMenuText as NSString, feed.nameForDisplay) as String
		let cancel = {
			completion(true)
		}

		let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
			MarkAsReadAlertController.confirm(self, coordinator: self?.coordinator, confirmTitle: title, sourceType: contentView, cancelCompletion: cancel) { [weak self] in
				self?.coordinator.markAllAsRead(Array(articles))
				completion(true)
			}
		}
		return action
	}

	func deleteAction(indexPath: IndexPath) -> UIAction {
		let title = NSLocalizedString("Delete", comment: "Delete")

		let action = UIAction(title: title, image: Assets.Images.trash, attributes: .destructive) { [weak self] _ in
			self?.delete(indexPath: indexPath)
		}
		return action
	}

	func renameAction(indexPath: IndexPath) -> UIAction {
		let title = NSLocalizedString("Rename", comment: "Rename")
		let action = UIAction(title: title, image: Assets.Images.edit) { [weak self] _ in
			self?.rename(indexPath: indexPath)
		}
		return action
	}

	func getInfoAction(indexPath: IndexPath) -> UIAction? {
		guard let feed = coordinator.nodeFor(indexPath)?.representedObject as? Feed else {
			return nil
		}

		let title = NSLocalizedString("Get Info", comment: "Get Info")
		let action = UIAction(title: title, image: Assets.Images.info) { [weak self] _ in
			self?.coordinator.showFeedInspector(for: feed)
		}
		return action
	}

	func getAccountInfoAction(account: Account) -> UIAction {
		let title = NSLocalizedString("Get Info", comment: "Get Info")
		let action = UIAction(title: title, image: Assets.Images.info) { [weak self] _ in
			self?.coordinator.showAccountInspector(for: account)
		}
		return action
	}

	func deactivateAccountAction(account: Account) -> UIAction {
		let title = NSLocalizedString("Deactivate", comment: "Deactivate")
		let action = UIAction(title: title, image: Assets.Images.deactivate) { _ in
			account.isActive = false
		}
		return action
	}

	func addFolderAction(account: Account) -> UIAction {
		let title = NSLocalizedString("Add Folder", comment: "Add Folder")
		let action = UIAction(title: title, image: Assets.Images.folderOutlinePlus) { [weak self] _ in
			self?.coordinator.showAddFolder()
		}
		return action
	}

	func getInfoAlertAction(indexPath: IndexPath, completion: @escaping (Bool) -> Void) -> UIAlertAction? {
		guard let feed = coordinator.nodeFor(indexPath)?.representedObject as? Feed else {
			return nil
		}

		let title = NSLocalizedString("Get Info", comment: "Get Info")
		let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
			self?.coordinator.showFeedInspector(for: feed)
			completion(true)
		}
		return action
	}

	func markAllAsReadAction(indexPath: IndexPath) -> UIAction? {
		guard let sidebarItem = coordinator.nodeFor(indexPath)?.representedObject as? SidebarItem,
			  let contentView = self.collectionView.cellForItem(at: indexPath)?.contentView,
			  sidebarItem.unreadCount > 0 else {
				  return nil
			  }

		let localizedMenuText = NSLocalizedString("Mark All as Read in “%@”", comment: "Command")
		let title = NSString.localizedStringWithFormat(localizedMenuText as NSString, sidebarItem.nameForDisplay) as String
		let action = UIAction(title: title, image: Assets.Images.markAllAsRead) { [weak self] _ in
			MarkAsReadAlertController.confirm(self, coordinator: self?.coordinator, confirmTitle: title, sourceType: contentView) { [weak self] in
				if let articles = try? sidebarItem.fetchUnreadArticles() {
					self?.coordinator.markAllAsRead(Array(articles))
				}
			}
		}

		return action
	}

	func markAllAsReadAction(account: Account, contentView: UIView?) -> UIAction? {
		guard account.unreadCount > 0, let contentView else {
			return nil
		}

		let localizedMenuText = NSLocalizedString("Mark All as Read in “%@”", comment: "Command")
		let title = NSString.localizedStringWithFormat(localizedMenuText as NSString, account.nameForDisplay) as String
		let action = UIAction(title: title, image: Assets.Images.markAllAsRead) { [weak self] _ in
			MarkAsReadAlertController.confirm(self, coordinator: self?.coordinator, confirmTitle: title, sourceType: contentView) { [weak self] in
				// If you don't have this delay the screen flashes when it executes this code
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
					if let articles = try? account.fetchArticles(.unread()) {
						self?.coordinator.markAllAsRead(Array(articles))
					}
				}
			}
		}

		return action
	}

	func rename(indexPath: IndexPath) {
		guard let sidebarItem = coordinator.nodeFor(indexPath)?.representedObject as? SidebarItem else {
			return
		}

		let formatString = NSLocalizedString("Rename “%@”", comment: "Rename feed")
		let title = NSString.localizedStringWithFormat(formatString as NSString, sidebarItem.nameForDisplay) as String

		let alertController = UIAlertController(title: title, message: nil, preferredStyle: .alert)

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel")
		alertController.addAction(UIAlertAction(title: cancelTitle, style: .cancel))

		let renameTitle = NSLocalizedString("Rename", comment: "Rename")
		let renameAction = UIAlertAction(title: renameTitle, style: .default) { [weak self] _ in

			guard let name = alertController.textFields?[0].text, !name.isEmpty else {
				return
			}

			if let feed = sidebarItem as? Feed {
				feed.rename(to: name) { result in
					switch result {
					case .success:
						break
					case .failure(let error):
						self?.presentError(error)
					}
				}
			} else if let folder = sidebarItem as? Folder {
				folder.rename(to: name) { result in
					switch result {
					case .success:
						break
					case .failure(let error):
						self?.presentError(error)
					}
				}
			}

		}

		alertController.addAction(renameAction)
		alertController.preferredAction = renameAction

		alertController.addTextField { textField in
			textField.text = sidebarItem.nameForDisplay
			textField.placeholder = NSLocalizedString("Name", comment: "Name")
			textField.clearButtonMode = .always
		}

		self.present(alertController, animated: true) {

		}

	}

	func delete(indexPath: IndexPath) {
		guard let sidebarItem = coordinator.nodeFor(indexPath)?.representedObject as? SidebarItem else {
			return
		}

		let title: String
		let message: String
		if sidebarItem is Folder {
			title = NSLocalizedString("Delete Folder", comment: "Delete folder")
			let localizedInformativeText = NSLocalizedString("Are you sure you want to delete the “%@” folder?", comment: "Folder delete text")
			message = NSString.localizedStringWithFormat(localizedInformativeText as NSString, sidebarItem.nameForDisplay) as String
		} else {
			title = NSLocalizedString("Delete Feed", comment: "Delete feed")
			let localizedInformativeText = NSLocalizedString("Are you sure you want to delete the “%@” feed?", comment: "Feed delete text")
			message = NSString.localizedStringWithFormat(localizedInformativeText as NSString, sidebarItem.nameForDisplay) as String
		}

		let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel")
		alertController.addAction(UIAlertAction(title: cancelTitle, style: .cancel))

		let deleteTitle = NSLocalizedString("Delete", comment: "Delete")
		let deleteAction = UIAlertAction(title: deleteTitle, style: .destructive) { [weak self] _ in
			self?.performDelete(indexPath: indexPath)
		}
		alertController.addAction(deleteAction)
		alertController.preferredAction = deleteAction

		self.present(alertController, animated: true)
	}

	func performDelete(indexPath: IndexPath) {
		guard let undoManager = undoManager,
			  let deleteNode = coordinator.nodeFor(indexPath),
			  let deleteCommand = DeleteCommand(nodesToDelete: [deleteNode], undoManager: undoManager, errorHandler: ErrorHandler.present(self)) else {
			return
		}

		if let folder = deleteNode.representedObject as? Folder {
			ActivityManager.cleanUp(folder)
		} else if let feed = deleteNode.representedObject as? Feed {
			ActivityManager.cleanUp(feed)
		}

		// Queue feed stats before deletion so we still have the feed object available.
		if let feed = deleteNode.representedObject as? Feed {
			FeedStatsManager.shared.queueDelete(
				type: feed.feedCategory,
				name: feed.nameForDisplay,
				author: feed.authors?.first?.name
			)
		}

		if indexPath == coordinator.currentFeedIndexPath {
			coordinator.selectSidebarItem(indexPath: nil)
		}

		pushUndoableCommand(deleteCommand)
		deleteCommand.perform()
	}
}

// MARK: - RSSPickerDelegate

extension MainFeedCollectionViewController: RSSPickerDelegate {

	func rssPickerDidSelectCustomURL(_ picker: RSSPickerViewController) {
		picker.dismiss(animated: true) {
			self.showEnterRSSURLDialog()
		}
	}

	func rssPicker(_ picker: RSSPickerViewController, didEnterFeedURL url: String) {
		let normalizedURL = url.normalizedURL
		guard !normalizedURL.isEmpty, URL(string: normalizedURL) != nil else {
			let alert = UIAlertController(
				title: NSLocalizedString("Invalid URL", comment: "Invalid URL"),
				message: NSLocalizedString("Please enter a valid feed URL starting with http:// or https://.", comment: "Invalid URL message"),
				preferredStyle: .alert
			)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default))
			picker.present(alert, animated: true)
			return
		}
		picker.dismiss(animated: true) {
			self.addFeedDirectly(urlString: url, category: .rss)
		}
	}

	func rssPicker(_ picker: RSSPickerViewController, didSelectFeed source: RSSSource) {
		picker.dismiss(animated: true) {
			let urlString = source.url.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !urlString.isEmpty else {
				let alert = UIAlertController(
					title: NSLocalizedString("Feed URL Missing", comment: "Feed URL Missing"),
					message: NSLocalizedString("This source does not provide a feed URL yet.", comment: "Missing feed URL message"),
					preferredStyle: .alert
				)
				alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default))
				self.present(alert, animated: true)
				return
			}
			// RSS top picks include a concrete feed URL in the source list,
			// so we can subscribe directly without going through add-show-source.
			self.addFeedDirectly(urlString: urlString, category: .rss, sourceName: source.name, sourceAuthor: source.author, sourceImageURL: source.imageURL)
		}
	}

	func rssPickerDidCancel(_ picker: RSSPickerViewController) {
		picker.dismiss(animated: true)
	}
}

// MARK: - PodcastPickerDelegate

extension MainFeedCollectionViewController: PodcastPickerDelegate {

	func podcastPickerDidSelectPodcastName(_ picker: PodcastPickerViewController) {
		picker.dismiss(animated: true) {
			self.showEnterPodcastNameDialog()
		}
	}

	func podcastPicker(_ picker: PodcastPickerViewController, didEnterPodcastName name: String) {
		picker.dismiss(animated: true) {
			self.addPodcastWithWebhook(name: name, author: nil)
		}
	}

	func podcastPicker(_ picker: PodcastPickerViewController, didSelectPodcast source: PodcastSource) {
		picker.dismiss(animated: true) {
			self.addPodcastWithWebhook(name: source.name, author: source.author)
		}
	}

	func podcastPickerDidCancel(_ picker: PodcastPickerViewController) {
		picker.dismiss(animated: true)
	}
}

// MARK: - YoutubePickerDelegate

extension MainFeedCollectionViewController: YoutubePickerDelegate {

	func youtubePickerDidSelectChannelName(_ picker: YoutubePickerViewController) {
		picker.dismiss(animated: true) {
			self.showEnterYoutubeChannelNameDialog()
		}
	}

	func youtubePicker(_ picker: YoutubePickerViewController, didEnterChannelHandle handle: String) {
		picker.dismiss(animated: true) {
			self.addYoutubeWithWebhook(name: handle, author: nil)
		}
	}

	func youtubePickerDidCancel(_ picker: YoutubePickerViewController) {
		picker.dismiss(animated: true)
	}

	func youtubePicker(_ picker: YoutubePickerViewController, didSelectChannel source: YoutubeSource) {
		picker.dismiss(animated: true) {
			self.addYoutubeWithWebhook(name: source.name, author: source.author)
		}
	}

	private func showEnterYoutubeChannelNameDialog() {
		var seen = Set<String>()
		var items = [SourceSearchItem]()
		for source in YoutubeSourcesManager.shared.youtubeSources + YoutubeSourcesManager.shared.youtubeLibrarySources {
			let key = (source.author ?? source.name).lowercased()
			if seen.insert(key).inserted {
				items.append(SourceSearchItem(name: source.name, author: source.author))
			}
		}
		let searchVC = SourceSearchViewController(
			placeholder: NSLocalizedString("@channel", comment: "YouTube channel handle placeholder"),
			items: items,
			matchesQuery: { item, query in
				item.author?.localizedCaseInsensitiveContains(query) ?? false
			},
			onSelect: { [weak self] item in
				self?.addYoutubeWithWebhook(name: item.name, author: item.author)
			},
			onManualAdd: { [weak self] name in
				self?.addYoutubeWithWebhook(name: name, author: nil)
			}
		)
		searchVC.title = NSLocalizedString("Add Channel", comment: "Add Channel")
		let nav = UINavigationController(rootViewController: searchVC)
		present(nav, animated: true)
	}

	private func addYoutubeWithWebhook(name: String, author: String?) {
		// Show loading indicator
		let loadingAlert = UIAlertController(
			title: nil,
			message: NSLocalizedString("Searching for YouTube channel...", comment: "Searching for YouTube channel..."),
			preferredStyle: .alert
		)

		let activityIndicator = UIActivityIndicatorView(style: .medium)
		activityIndicator.translatesAutoresizingMaskIntoConstraints = false
		activityIndicator.startAnimating()
		loadingAlert.view.addSubview(activityIndicator)

		NSLayoutConstraint.activate([
			activityIndicator.centerXAnchor.constraint(equalTo: loadingAlert.view.centerXAnchor),
			activityIndicator.bottomAnchor.constraint(equalTo: loadingAlert.view.bottomAnchor, constant: -20)
		])

		present(loadingAlert, animated: true) {
			Task {
				let result = await YoutubeSourcesManager.shared.addYoutube(name: name, author: author)

				if case .successExisting = result { SourcesRefreshManager.shared.forceRefresh() }
				if case .successNew = result { SourcesRefreshManager.shared.forceRefresh() }

				loadingAlert.dismiss(animated: true) {
					switch result {
					case .successExisting(let summaryURL):
						self.addFeedDirectly(urlString: summaryURL, category: .youtube, sourceName: name, sourceAuthor: author, validateFeed: false, summaryURL: summaryURL) {
							appDelegate.manualRefresh(errorHandler: ErrorHandler.present(self))
						}

					case .successNew(let summaryURL):
						self.addFeedDirectly(urlString: summaryURL, category: .youtube, sourceName: name, sourceAuthor: author, validateFeed: false, summaryURL: summaryURL) {
							self.showYoutubeSuccessMessage {}
						}

					case .failure(let message):
						self.showYoutubeError(message: message)
					}
				}
			}
		}
	}

	private func showYoutubeSuccessMessage(completion: @escaping () -> Void) {
		let alert = UIAlertController(
			title: NSLocalizedString("Channel Added", comment: "Channel Added"),
			message: NSLocalizedString("The YouTube channel has been added. It may take a few minutes for episodes to appear.", comment: "YouTube channel added message"),
			preferredStyle: .alert
		)

		let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default) { _ in
			completion()
		}

		alert.addAction(okAction)
		present(alert, animated: true)
	}

	private func showYoutubeError(message: String) {
		let alert = UIAlertController(
			title: NSLocalizedString("Error", comment: "Error"),
			message: message,
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default))
		present(alert, animated: true)
	}
}

// MARK: - NewsPickerDelegate

extension MainFeedCollectionViewController: NewsPickerDelegate {

	func newsPickerDidCancel(_ picker: NewsPickerViewController) {
		picker.dismiss(animated: true)
	}

	func newsPicker(_ picker: NewsPickerViewController, didSelectSource source: NewsSource) {
		picker.dismiss(animated: true) {
			self.addTopicWithWebhook(name: source.name, author: source.author)
		}
	}

	private func addTopicWithWebhook(name: String, author: String?) {
		// Show loading indicator
		let loadingAlert = UIAlertController(
			title: nil,
			message: NSLocalizedString("Searching for topic...", comment: "Searching for topic..."),
			preferredStyle: .alert
		)

		let activityIndicator = UIActivityIndicatorView(style: .medium)
		activityIndicator.translatesAutoresizingMaskIntoConstraints = false
		activityIndicator.startAnimating()
		loadingAlert.view.addSubview(activityIndicator)

		NSLayoutConstraint.activate([
			activityIndicator.centerXAnchor.constraint(equalTo: loadingAlert.view.centerXAnchor),
			activityIndicator.bottomAnchor.constraint(equalTo: loadingAlert.view.bottomAnchor, constant: -20)
		])

		present(loadingAlert, animated: true) {
			Task {
				let result = await NewsSourcesManager.shared.addNews(name: name, author: author)

				loadingAlert.dismiss(animated: true) {
					self.handleTopicResult(result, name: name, author: author)
				}
			}
		}
	}

	private func handleTopicResult(_ result: AddNewsResult, name: String, author: String?) {
		switch result {
		case .successExisting(let summaryURL):
			self.addFeedDirectly(urlString: summaryURL, category: .news, sourceName: name, sourceAuthor: author, summaryURL: summaryURL)

		case .successNew(let summaryURL):
			self.addFeedDirectly(urlString: summaryURL, category: .news, sourceName: name, sourceAuthor: author, summaryURL: summaryURL)

		case .failure(let message):
			self.showTopicError(message: message)
		}
	}

	private func showTopicError(message: String) {
		let alert = UIAlertController(
			title: NSLocalizedString("Error", comment: "Error"),
			message: message,
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default))
		present(alert, animated: true)
	}
}

// MARK: - Default sources (first-launch setup)

extension MainFeedCollectionViewController {

	/// Subscribes to the four default sources after first account setup.
	/// Mirrors the existing `addDiscoverSource` / `addFeedDirectly` flow exactly:
	/// uses the library URL when available and non-empty, otherwise calls the webhook.
	func addDefaultSourcesIfNeeded() {
		Task { @MainActor in
			guard let account = AccountManager.shared.activeAccounts.first else { return }

			// Wraps addFeedDirectly in an async call so we can sequence them without
			// presenting multiple alerts at the same time. Pre-checks hasFeed using the
			// same URL normalization that addFeedDirectly uses, so the "Already Subscribed"
			// branch (which never calls the completion) is never hit.
			@MainActor func addAndWait(urlString: String, category: FeedCategory, name: String, author: String? = nil, imageURL: String? = nil, imageURLLight: String? = nil, summaryURL: String? = nil) async {
				let normalizedURL = urlString.normalizedURL
				guard !normalizedURL.isEmpty, let url = URL(string: normalizedURL) else { return }
				guard !account.hasFeed(withURL: url.absoluteString) else { return }
				await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
					// withCheckedContinuation's closure is nonisolated; hop back to
					// MainActor so we can call the @MainActor-isolated addFeedDirectly.
					Task { @MainActor [self] in
						addFeedDirectly(urlString: urlString, category: category, sourceName: name, sourceAuthor: author, sourceImageURL: imageURL, sourceImageURLLight: imageURLLight, validateFeed: false, summaryURL: summaryURL) {
							continuation.resume()
						}
					}
				}
			}

			// RSS: Ars Technica — URL lives in the library
			if let s = RSSSourcesManager.shared.rssSources.first(where: { $0.name.localizedCaseInsensitiveContains("Ars Technica") }) {
				await addAndWait(urlString: s.url, category: .rss, name: s.name, author: s.author, imageURL: s.imageURL, imageURLLight: s.imageURLLight)
			}

			// News: Artificial Intelligence — URL lives in the library
			if let s = NewsSourcesManager.shared.newsSources.first(where: { $0.name.localizedCaseInsensitiveContains("Artificial Intelligence") }) {
				await addAndWait(urlString: s.url, category: .news, name: s.name, author: s.author, imageURL: s.imageURL, imageURLLight: s.imageURLLight)
			}

			// YouTube: use library URL if non-empty, else call webhook for summaryURL
			let allYT = YoutubeSourcesManager.shared.youtubeSources + YoutubeSourcesManager.shared.youtubeLibrarySources
			let ytSource = allYT.first(where: {
				$0.author?.localizedCaseInsensitiveContains("veritasium") == true
					|| $0.name.localizedCaseInsensitiveContains("veritasium")
			})
			let ytURL: String?
			if let s = ytSource, !s.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				ytURL = s.url
			} else {
				let result = await YoutubeSourcesManager.shared.addYoutube(name: "@veritasium")
				switch result {
				case .successExisting(let url), .successNew(let url): ytURL = url
				case .failure: ytURL = nil
				}
			}
			if let url = ytURL {
				await addAndWait(urlString: url, category: .youtube, name: ytSource?.name ?? "Veritasium", author: ytSource?.author, imageURL: ytSource?.imageURL, imageURLLight: ytSource?.imageURLLight, summaryURL: url)
			}

			// Podcast: use library URL if non-empty, else call webhook for summaryURL
			let allPod = PodcastSourcesManager.shared.podcastSources + PodcastSourcesManager.shared.podcastLibrarySources
			let podSource = allPod.first(where: { $0.name.localizedCaseInsensitiveContains("Tim Ferriss") })
			let podURL: String?
			if let s = podSource, !s.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				podURL = s.url
			} else {
				let result = await PodcastSourcesManager.shared.addPodcast(name: "The Tim Ferriss Show")
				switch result {
				case .successExisting(let url), .successNew(let url): podURL = url
				case .failure: podURL = nil
				}
			}
			if let url = podURL {
				await addAndWait(urlString: url, category: .podcast, name: podSource?.name ?? "The Tim Ferriss Show", author: podSource?.author, imageURL: podSource?.imageURL, imageURLLight: podSource?.imageURLLight, summaryURL: url)
			}
		}
	}
}

private final class RecentlyUpdatedFeedItemView: UIControl {
	var payload: RecentlyUpdatedStripPayload?

	private let iconImageView: UIImageView = {
		let imageView = UIImageView()
		imageView.translatesAutoresizingMaskIntoConstraints = false
		imageView.contentMode = .scaleAspectFill
		imageView.backgroundColor = .secondarySystemBackground// .white
		imageView.layer.cornerRadius = 12
		imageView.clipsToBounds = true
		return imageView
	}()

	private let pressOverlayView: UIView = {
		let view = UIView()
		view.translatesAutoresizingMaskIntoConstraints = false
		view.backgroundColor = UIColor.systemBlue.withAlphaComponent(1)
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
