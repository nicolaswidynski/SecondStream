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

final class MainFeedCollectionViewController: UICollectionViewController, UndoableCommandRunner {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AddSource")

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



	/// The update status label shown in the navigation bar title view
	private lazy var updateStatusLabel: UILabel = {
		let label = UILabel()
		label.font = .preferredFont(forTextStyle: .caption2)
		label.textColor = .secondaryLabel
		label.textAlignment = .right
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}()
	private let stripController = RecentlyUpdatedStripController()

	/// The current update status text to display
	var updateStatusText: String? {
		didSet {
			updateStatusLabel.text = updateStatusText
		}
	}

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
		view.backgroundColor = Assets.Colors.background
		registerForNotifications()
		configureCollectionView()
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: MainFeedCollectionViewController, _: UITraitCollection) in
			guard let self, traitCollection.userInterfaceIdiom == .phone else { return }
			collectionView.layoutSectionCardShadows(in: &sectionShadowViews)
		}
		configureDiffableDataSource()
		configureNavigationBar()
		configureRecentlyUpdatedStrip()
		collectionView.dragDelegate = self
		collectionView.dropDelegate = self
		becomeFirstResponder()
		stripController.refresh()

		// Fetch sources on launch
		SourcesRefreshManager.shared.forceRefresh()


		// Refresh sources when app comes to foreground
		NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }


	private func configureNavigationBar() {
		navigationItem.title = nil

		// Left bar button: Open left side menu
		let menuButton = UIBarButtonItem(
			image: UIImage(systemName: "line.3.horizontal"),
			style: .plain,
			target: self,
			action: #selector(hamburgerTapped)
		)
		menuButton.accessibilityLabel = NSLocalizedString("Menu", comment: "Menu")
		navigationItem.leftBarButtonItem = menuButton

		// Right swipe to open left menu
		let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(hamburgerTapped))
		swipeRight.direction = .right
		collectionView.addGestureRecognizer(swipeRight)

		// Right bar button: Starred smart feed shortcut
		navigationItem.rightBarButtonItem = starredButton

		// Show update status text in the navigation bar title area
		navigationItem.titleView = updateStatusLabel

	}

	private func configureRecentlyUpdatedStrip() {
		stripController.install(in: view, above: collectionView)
		collectionView.contentInset.top = stripController.topInset
		collectionView.verticalScrollIndicatorInsets.top = stripController.topInset

		stripController.onPayloadTapped = { [weak self] payload in
			guard let self else { return }
			switch payload {
			case .feed(let feed):
				expandCategorySectionForCategory(feed.feedCategory)
				coordinator.selectFeed(feed, animations: [.navigation, .scroll])
			case .discover(let source):
				addDiscoverSource(source)
			}
		}
	}

	@objc private func hamburgerTapped() {
		coordinator.showLeftMenu()
	}

	@objc private func starredTapped() {
		coordinator.selectStarredFeed()
	}

	private func addDiscoverSource(_ source: DiscoverSourceItem) {
		let urlString = source.url.trimmingCharacters(in: .whitespacesAndNewlines)
		if !urlString.isEmpty {
			addFeedDirectly(AddFeedRequest(urlString: urlString, category: source.category, name: source.name, author: source.author, imageURL: source.imageURL, imageURLLight: source.imageURLLight))
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
		showRSSPicker()
	}

	func showRSSPicker() {
		let picker = RSSPickerViewController()
		picker.delegate = self
		let navController = UINavigationController(rootViewController: picker)
		applyPickerNavigationBarAppearance(to: navController)
		present(navController, animated: true)
	}

	@objc private func addPodcast() {
		showPodcastPicker()
	}

	func showPodcastPicker() {
		let picker = MediaPickerViewController(manager: .podcast)
		picker.delegate = self
		let navController = UINavigationController(rootViewController: picker)
		applyPickerNavigationBarAppearance(to: navController)
		present(navController, animated: true)
	}

	@objc private func addYoutube() {
		showYoutubePicker()
	}

	func showYoutubePicker() {
		let picker = MediaPickerViewController(manager: .youtube)
		picker.delegate = self
		let navController = UINavigationController(rootViewController: picker)
		applyPickerNavigationBarAppearance(to: navController)
		present(navController, animated: true)
	}

	private func applyPickerNavigationBarAppearance(to navController: UINavigationController) {
		let appearance = UINavigationBarAppearance()
		appearance.configureWithOpaqueBackground()
		appearance.backgroundColor = Assets.Colors.foreground
		navController.navigationBar.standardAppearance = appearance
		navController.navigationBar.scrollEdgeAppearance = appearance
		navController.navigationBar.compactAppearance = appearance
		navController.navigationBar.compactScrollEdgeAppearance = appearance
	}

	@objc private func addNews() {
		showNewsPicker()
	}

	func showNewsPicker() {
		let picker = NewsPickerViewController()
		picker.delegate = self
		let navController = UINavigationController(rootViewController: picker)
		applyPickerNavigationBarAppearance(to: navController)
		present(navController, animated: true)
	}

	/// Adds a feed by URL directly (no gate check).
	///
	/// Use `AddFeedRequest` to supply metadata (name, author, image URLs, etc.).
	/// Pass `summaryURL` inside the request to fetch the canonical feed icon from the
	/// server-side JSON instead of relying on the user-entered string.
	private func addFeedDirectly(_ request: AddFeedRequest, completion: (() -> Void)? = nil) {
		let urlString = request.urlString
		let category = request.category
		Self.logger.debug("addFeedDirectly: urlString=\(urlString, privacy: .public) category=\(String(describing: category), privacy: .public)")
		let normalizedURL = urlString.normalizedURL
		guard !normalizedURL.isEmpty, let url = URL(string: normalizedURL) else {
			Self.logger.debug("addFeedDirectly: BAIL — bad URL normalizedURL=\(normalizedURL, privacy: .public)")
			return
		}

		// Get the first active account
		guard let account = AccountManager.shared.activeAccounts.first else {
			Self.logger.debug("addFeedDirectly: BAIL — no active account")
			return
		}

		// Check if already subscribed
		let alreadySubscribed = account.hasFeed(withURL: url.absoluteString)
		Self.logger.debug("addFeedDirectly: url=\(url.absoluteString, privacy: .public) alreadySubscribed=\(alreadySubscribed)")
		if alreadySubscribed {
			let alert = UIAlertController(
				title: NSLocalizedString("Already Subscribed", comment: "Already Subscribed"),
				message: NSLocalizedString("You are already subscribed to this feed.", comment: "Already subscribed message"),
				preferredStyle: .alert
			)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default))
			let alreadyPresenter = topMostPresentingViewController()
			Self.logger.debug("addFeedDirectly: presenting alreadySubscribed alert via \(type(of: alreadyPresenter))")
			alreadyPresenter.present(alert, animated: true) {
				completion?()
			}
			return
		}

		let validateFeed = request.validateFeed
		let summaryURL = request.summaryURL

		let performCreate: (@escaping () -> Void) -> Void = { afterCreate in
			Task {
				BatchUpdate.shared.start()
				account.createFeed(url: url.absoluteString, name: request.name, container: account, validateFeed: validateFeed) { result in
					Self.logger.debug("addFeedDirectly: createFeed result=\(String(describing: result), privacy: .public)")
					if case .success(let feed) = result {
						feed.feedCategory = category
						NotificationCenter.default.post(name: .ChildrenDidChange, object: account)
						if let lightURL = request.imageURLLight {
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
					afterCreate()
					switch result {
					case .success(let feed):
						Self.logger.debug("addFeedDirectly: success — posting UserDidAddFeed feedURL=\(feed.url, privacy: .public)")
						NotificationCenter.default.post(
							name: .UserDidAddFeed,
							object: self,
							userInfo: [
								UserInfoKey.feed: feed,
								UserInfoKey.suppressFeedDisclosure: true
							]
						)
						self.expandCategorySectionForCategory(category)
						completion?()
					case .failure(let error):
						Self.logger.debug("addFeedDirectly: failure — error=\(error.localizedDescription, privacy: .public)")
						self.presentError(error)
						completion?()
					}
				}
			}
		}

		if request.skipLoadingIndicator {
			Self.logger.debug("addFeedDirectly: skipLoadingIndicator — calling createFeed directly url=\(url.absoluteString, privacy: .public)")
			performCreate({})
			return
		}

		// Show loading indicator
		let loadingAlert = buildLoadingAlert()
		let presenterForLoading = topMostPresentingViewController()
		Self.logger.debug("addFeedDirectly: presenting loadingAlert via \(type(of: presenterForLoading))")
		presenterForLoading.present(loadingAlert, animated: true) {
			Self.logger.debug("addFeedDirectly: loadingAlert presented — calling createFeed url=\(url.absoluteString, privacy: .public)")
			performCreate {
				Self.logger.debug("addFeedDirectly: dismissing loadingAlert")
				loadingAlert.dismiss(animated: true)
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

	private var sectionShadowViews: [UIView] = []

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		guard traitCollection.userInterfaceIdiom == .phone else { return }
		collectionView.layoutSectionCardShadows(in: &sectionShadowViews)
	}


	override func viewWillAppear(_ animated: Bool) {
		navigationController?.view.backgroundColor = Assets.Colors.background
		navigationController?.setToolbarHidden(false, animated: animated)
		navigationController?.additionalSafeAreaInsets.bottom = 60
		stripController.applyNavigationBarBackgroundStyle()
		stripController.refresh()
		updateUI()
		refreshVisibleSectionHeaders()
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
		
		// If the user navigates away while a snap-scroll is in flight, the scroll animation
		// is abandoned and scrollViewDidEndScrollingAnimation never fires. Apply the pending
		// toggle immediately so the coordinator state stays consistent.
//		if let feedSection = pendingToggleFeedSection {
//			pendingToggleFeedSection = nil
//			coordinator.toggleCategorySection(feedSection)
//		}
//		
		
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
			registerForTraitChanges([UITraitUserInterfaceStyle.self], target: self, action: #selector(userInterfaceStyleDidChange))
		NotificationCenter.default.addObserver(self, selector: #selector(sourceImageDidBecomeAvailable(_:)), name: .sourceImageDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsDidChange(_:)), name: UserDefaults.didChangeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(bootstrapProgressDidUpdate(_:)), name: .bootstrapProgressDidUpdate, object: nil)
	}

	// MARK: - Collection View Configuration
	func configureCollectionView() {
		var config = UICollectionLayoutListConfiguration(appearance: traitCollection.userInterfaceIdiom == .pad ? .sidebar : .insetGrouped)
		config.backgroundColor = .clear
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
		} else {
			collectionView.backgroundColor = Assets.Colors.background
		}

		updateScrollIndicatorStyle()
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

	override func collectionView(_ collectionView: UICollectionView, willDisplaySupplementaryView view: UICollectionReusableView, forElementKind elementKind: String, at indexPath: IndexPath) {
		guard elementKind == UICollectionView.elementKindSectionHeader,
			  let headerView = view as? MainFeedCollectionHeaderReusableView,
			  let sectionID = headerView.sectionID,
			  let feedSection = FeedSectionIdentifier(rawValue: sectionID) else {
			return
		}
		headerView.disclosureExpanded = coordinator.isCategorySectionExpanded(feedSection)
	}

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
		// Block selection while bootstrap is in progress
		if let node = coordinator.nodeFor(indexPath),
		   let feed = node.representedObject as? Feed,
		   BootstrapProgressManager.shared.progress(forFeedURL: feed.url) != nil {
			return false
		}
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

		if let feed = node.representedObject as? Feed {
			cell.bootstrapProgress = BootstrapProgressManager.shared.progress(forFeedURL: feed.url)
		} else {
			cell.bootstrapProgress = nil
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

		if let feed = node.representedObject as? Feed {
			cell.bootstrapProgress = BootstrapProgressManager.shared.progress(forFeedURL: feed.url)
		} else {
			cell.bootstrapProgress = nil
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


	// MARK: - Appearance

	private func updateScrollIndicatorStyle() {
		collectionView.indicatorStyle = traitCollection.userInterfaceStyle == .dark ? .white : .default
	}

	@objc func userInterfaceStyleDidChange() {
		updateScrollIndicatorStyle()
	}

	// MARK: - Notifications

	@objc func preferredContentSizeCategoryDidChange() {
		IconImageCache.shared.emptyCache()
		reloadAllVisibleCells()
	}

	@objc func unreadCountDidChange(_ note: Notification) {
		stripController.refresh()
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
		stripController.refresh()
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
		stripController.refresh()
	}

	@objc func sourceImageDidBecomeAvailable(_ note: Notification) {
		stripController.refresh()
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

	@objc func bootstrapProgressDidUpdate(_ note: Notification) {
		// Reload every visible feed cell so bootstrap progress rings update
		applyToAvailableCells { (cell, indexPath) in
			guard let node = coordinator.nodeFor(indexPath),
				  let feed = node.representedObject as? Feed else {
				return
			}
			cell.bootstrapProgress = BootstrapProgressManager.shared.progress(forFeedURL: feed.url)
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
	}

	@objc private func appWillEnterForeground() {
		SourcesRefreshManager.shared.refreshIfNeeded()
		stripController.refresh()
		Task { await FeedStatsManager.shared.fetchCreditsIfNeeded() }
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
				self.addFeedDirectly(AddFeedRequest(urlString: urlText, category: .rss))
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
		for source in MediaSourcesManager.podcast.topSources + MediaSourcesManager.podcast.librarySources {
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

	/// Returns the topmost view controller that can safely accept a modal presentation.
	/// Walks the presented-VC chain from the window's root, stopping at any VC that
	/// is currently being dismissed or is no longer attached to a window (orphaned after dismiss).
	private func topMostPresentingViewController() -> UIViewController {
		guard let root = view.window?.rootViewController else {
			Self.logger.debug("topMostPresenter: no root — falling back to self")
			return self
		}
		var vc: UIViewController = root
		while let presented = vc.presentedViewController,
			  !presented.isBeingDismissed,
			  presented.viewIfLoaded?.window != nil {
			vc = presented
		}
		Self.logger.debug("topMostPresenter: \(type(of: vc))")
		return vc
	}

	/// Returns true if the active account already has a feed in `category` whose display name
	/// matches `name` (case-insensitive). Used to skip the webhook when the user re-adds
	/// something they already subscribe to.
	private func feedAlreadySubscribed(name: String, category: FeedCategory) -> Bool {
		guard let account = AccountManager.shared.activeAccounts.first else { return false }
		return account.flattenedFeeds().contains {
			$0.feedCategory == category &&
			$0.nameForDisplay.localizedCaseInsensitiveCompare(name) == .orderedSame
		}
	}

	private func buildLoadingAlert(message: String = NSLocalizedString("Adding...", comment: "Adding...")) -> UIAlertController {
		let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
		let activityIndicator = UIActivityIndicatorView(style: .medium)
		activityIndicator.translatesAutoresizingMaskIntoConstraints = false
		activityIndicator.startAnimating()
		alert.view.addSubview(activityIndicator)
		NSLayoutConstraint.activate([
			activityIndicator.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
			activityIndicator.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -20)
		])
		return alert
	}

	private func addPodcastWithWebhook(name: String, author: String?) {
		if feedAlreadySubscribed(name: name, category: .podcast) {
			showAddSourceError(message: NSLocalizedString("You are already subscribed to this podcast.", comment: "Already subscribed to podcast"))
			return
		}
		let coordinator = AddSourceCoordinator(manager: MediaSourcesManager.podcast, category: .podcast)
		let successTitle = NSLocalizedString("Podcast Added", comment: "Podcast Added")
		addWithWebhook(name: name, author: author, coordinator: coordinator, successTitle: successTitle)
	}

	private func showAddSourceSuccess(title: String, message: String, completion: @escaping () -> Void) {
		let presenter = topMostPresentingViewController()
		Self.logger.debug("showAddSourceSuccess: title=\(title, privacy: .public) presenter=\(type(of: presenter)) presenterWindowNil=\(presenter.viewIfLoaded?.window == nil) presenterIsBeingDismissed=\(presenter.isBeingDismissed) presenterPresentedVC=\(String(describing: presenter.presentedViewController.map { type(of: $0) }), privacy: .public)")
		let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default) { _ in
			completion()
		})
		presenter.present(alert, animated: true) {
			Self.logger.debug("showAddSourceSuccess: alert present-completion fired")
		}
	}

	private func showAddSourceError(message: String) {
		let presenter = topMostPresentingViewController()
		Self.logger.debug("showAddSourceError: msg=\(message, privacy: .public) presenter=\(type(of: presenter))")
		let alert = UIAlertController(
			title: NSLocalizedString("Error", comment: "Error"),
			message: message,
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default))
		presenter.present(alert, animated: true)
	}

	/// Pending section to toggle after a snap-scroll completes.
	private var pendingToggleFeedSection: FeedSectionIdentifier?
 
	func toggle(_ headerView: MainFeedCollectionHeaderReusableView) {
		guard let sectionID = headerView.sectionID else {
			return
		}
 
		if let feedSection = FeedSectionIdentifier(rawValue: sectionID) {
			let isExpanded = coordinator.isCategorySectionExpanded(feedSection)
			headerView.unreadCount = unreadCountForSection(feedSection)
			headerView.disclosureExpanded = !isExpanded
 
			// If the list is scrolled just a little away from the natural top, snap it the
			// rest of the way before toggling. This prevents UIKit's contentOffset adjustment
			// during the snapshot apply from causing a visible jump.
			// Only fires when "near the top" (within ~150 pt) — not when scrolled far down.
			
			
			
			let naturalTopOffset = -collectionView.adjustedContentInset.top
			let distanceFromTop = collectionView.contentOffset.y - naturalTopOffset
			let isFirstSection = dataSource.snapshot().sectionIdentifiers.first == sectionID
			if distanceFromTop > 1 && distanceFromTop < 130 && isFirstSection {
				pendingToggleFeedSection = feedSection
				collectionView.setContentOffset(CGPoint(x: 0, y: naturalTopOffset), animated: true)
				return
			}
			
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
	
	override func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
		guard let feedSection = pendingToggleFeedSection else {
			return
		}
		pendingToggleFeedSection = nil
		coordinator.toggleCategorySection(feedSection)
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
			self.addFeedDirectly(AddFeedRequest(urlString: url, category: .rss))
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
			// so we can subscribe directly without a webhook call.
			self.addFeedDirectly(AddFeedRequest(urlString: urlString, category: .rss, name: source.name, author: source.author, imageURL: source.imageURL))
		}
	}

	func rssPickerDidCancel(_ picker: RSSPickerViewController) {
		picker.dismiss(animated: true)
	}
}

// MARK: - MediaPickerDelegate

extension MainFeedCollectionViewController: MediaPickerDelegate {

	func mediaPicker(_ picker: MediaPickerViewController, didSelectSource source: MediaSource) {
		picker.navigationController?.dismiss(animated: true) {
			switch picker.manager.category {
			case .podcast:
				self.addPodcastWithWebhook(name: source.name, author: source.author)
			case .youtube:
				self.addYoutubeWithWebhook(name: source.name, author: source.author)
			default:
				break
			}
		}
	}

	func mediaPickerDidCancel(_ picker: MediaPickerViewController) {
		picker.navigationController?.dismiss(animated: true)
	}

	private func showEnterYoutubeChannelNameDialog() {
		var seen = Set<String>()
		var items = [SourceSearchItem]()
		for source in MediaSourcesManager.youtube.topSources + MediaSourcesManager.youtube.librarySources {
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
		if feedAlreadySubscribed(name: name, category: .youtube) {
			showAddSourceError(message: NSLocalizedString("You are already subscribed to this channel.", comment: "Already subscribed to channel"))
			return
		}
		let coordinator = AddSourceCoordinator(manager: MediaSourcesManager.youtube, category: .youtube)
		let successTitle = NSLocalizedString("Channel Added", comment: "Channel Added")
		addWithWebhook(name: name, author: author, coordinator: coordinator, successTitle: successTitle)
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
		if feedAlreadySubscribed(name: name, category: .news) {
			showAddSourceError(message: NSLocalizedString("You are already subscribed to this topic.", comment: "Already subscribed to topic"))
			return
		}
		let coordinator = AddSourceCoordinator(manager: NewsSourcesManager.shared, category: .news)
		let loadingMessage = NSLocalizedString("Searching for topic...", comment: "Searching for topic...")
		// News 202 never shows a success message — pass nil so the alert is skipped.
		addWithWebhook(name: name, author: author, coordinator: coordinator, loadingMessage: loadingMessage, successTitle: nil)
	}

	/// Shared implementation for webhook-based source additions (podcast, YouTube, news).
	///
	/// Shows a loading alert, calls the coordinator, then dismisses the alert and handles
	/// the resulting state. `successTitle` controls whether a success alert is shown on 202;
	/// pass `nil` to skip it (used for news topics that carry no server message).
	private func addWithWebhook(
		name: String,
		author: String?,
		coordinator: AddSourceCoordinator,
		loadingMessage: String = NSLocalizedString("Adding...", comment: "Adding..."),
		successTitle: String?
	) {
		let loadingAlert = buildLoadingAlert(message: loadingMessage)
		let presenter = topMostPresentingViewController()
		Self.logger.debug("addWithWebhook: presenting loadingAlert via \(type(of: presenter))")
		presenter.present(loadingAlert, animated: true)

		Task { @MainActor [weak self] in
			guard let self else {
				loadingAlert.dismiss(animated: false)
				return
			}
			Self.logger.debug("addWithWebhook: calling webhook for \"\(name, privacy: .public)\" category=\(String(describing: coordinator.category), privacy: .public)")

			await coordinator.add(name: name, author: author)

			if case .existsOnServer = coordinator.state { SourcesRefreshManager.shared.forceRefresh() }
			if case .newOnServer = coordinator.state { SourcesRefreshManager.shared.forceRefresh() }

			await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
				loadingAlert.dismiss(animated: true) { cont.resume() }
			}

			let category = coordinator.category

			switch coordinator.state {
			case .existsOnServer(let summaryURL):
				Self.logger.debug("addWithWebhook: existsOnServer summaryURL=\(summaryURL, privacy: .public)")
				let feedURL = URL(string: summaryURL.normalizedURL)?.absoluteString ?? summaryURL
				BootstrapProgressManager.shared.cancelBootstrap(feedURL: feedURL)
				self.addFeedDirectly(AddFeedRequest(urlString: summaryURL, category: category, name: name, author: author, validateFeed: false, summaryURL: summaryURL, skipLoadingIndicator: true)) {
					Self.logger.debug("addWithWebhook: existsOnServer addFeedDirectly completion called")
					appDelegate.manualRefresh(errorHandler: ErrorHandler.present(self))
				}

			case .newOnServer(let summaryURL, let message):
				Self.logger.debug("addWithWebhook: newOnServer summaryURL=\(summaryURL, privacy: .public) message=\(message, privacy: .public)")
				let feedURL = URL(string: summaryURL.normalizedURL)?.absoluteString ?? summaryURL
				let bootstrapType = coordinator.bootstrapType
				if !bootstrapType.isEmpty {
					BootstrapProgressManager.shared.startBootstrap(type: bootstrapType, show: name, author: author ?? "", feedURL: feedURL)
				}
				self.addFeedDirectly(AddFeedRequest(urlString: summaryURL, category: category, name: name, author: author, validateFeed: false, summaryURL: summaryURL, skipLoadingIndicator: true)) {
					Self.logger.debug("addWithWebhook: newOnServer addFeedDirectly completion called")
					if let successTitle, !message.isEmpty {
						self.showAddSourceSuccess(title: successTitle, message: message) {}
					}
				}

			case .failed(let message):
				Self.logger.debug("addWithWebhook: failed message=\(message, privacy: .public)")
				self.showAddSourceError(message: message)

			case .idle, .webhookPending:
				break
			}
		}
	}
}

// MARK: - Default sources (first-launch setup)

extension MainFeedCollectionViewController {

}

