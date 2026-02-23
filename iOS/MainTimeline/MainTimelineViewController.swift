//
//  MainTimelineViewController.swift
//  NetNewsWire
//
//  Created by Maurice Parker on 4/8/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import WebKit
import RSCore
import RSWeb
import Account
import Articles

@MainActor private final class FeedNavigationTitleContainerView: UIView {
	private let fixedSize: CGSize

	init(size: CGSize) {
		self.fixedSize = size
		super.init(frame: CGRect(origin: .zero, size: size))
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override var intrinsicContentSize: CGSize {
		fixedSize
	}
}

@MainActor enum FeedNavigationChrome {
	private enum Tags {
		static let title = 200
		static let subtitle = 300
	}

	private static let titleContainerWidth: CGFloat = 260
	private static let titleContainerHeight: CGFloat = 34

	static func makeTitleView(target: Any?, action: Selector) -> UIView {
		let container = FeedNavigationTitleContainerView(size: CGSize(width: titleContainerWidth, height: titleContainerHeight))

		let nameLabel = UILabel()
		nameLabel.translatesAutoresizingMaskIntoConstraints = false
		nameLabel.font = UIFont.preferredFont(forTextStyle: .subheadline).bold()
		nameLabel.numberOfLines = 1
		nameLabel.lineBreakMode = .byTruncatingTail
		nameLabel.tag = Tags.title
		container.addSubview(nameLabel)

		let subtitleLabel = UILabel()
		subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
		subtitleLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
		subtitleLabel.textColor = .secondaryLabel
		subtitleLabel.numberOfLines = 1
		subtitleLabel.textAlignment = .right
		subtitleLabel.tag = Tags.subtitle
		container.addSubview(subtitleLabel)

		NSLayoutConstraint.activate([
			nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			nameLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
			nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: subtitleLabel.leadingAnchor, constant: -8),

			subtitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			subtitleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
		])

		nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		subtitleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
		container.setContentHuggingPriority(.required, for: .horizontal)
		container.setContentCompressionResistancePriority(.required, for: .horizontal)

		container.isUserInteractionEnabled = true
		let tap = UITapGestureRecognizer(target: target, action: action)
		container.addGestureRecognizer(tap)
		return container
	}

	static func setTitle(_ text: String?, in titleView: UIView?) {
		(titleView?.viewWithTag(Tags.title) as? UILabel)?.text = text
	}

	static func setSubtitle(_ text: String?, in titleView: UIView?) {
		guard let subtitleLabel = titleView?.viewWithTag(Tags.subtitle) as? UILabel else {
			return
		}
		subtitleLabel.text = text
		subtitleLabel.isHidden = text?.isEmpty ?? true
	}

	static func subtitleText(in titleView: UIView?) -> String? {
		(titleView?.viewWithTag(Tags.subtitle) as? UILabel)?.text
	}

	static func setSubtitleAlpha(_ alpha: CGFloat, in titleView: UIView?) {
		(titleView?.viewWithTag(Tags.subtitle) as? UILabel)?.alpha = alpha
	}

	static func makeBackIndicatorImage(from image: UIImage?) -> UIImage {
		guard let image else {
			return UIImage()
		}

		let targetSize = CGSize(width: 47, height: 47)
		let rendered = UIGraphicsImageRenderer(size: targetSize).image { _ in
			image.draw(in: CGRect(origin: .zero, size: targetSize))
		}
		return rendered.withRenderingMode(.alwaysOriginal)
	}
}

final class MainTimelineViewController: UITableViewController, UndoableCommandRunner {

	private var numberOfTextLines = 0
	private var iconSize = IconSize.medium
	private lazy var feedTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(showFeedInspector(_:)))

	private var refreshProgressView: RefreshProgressView?

	@IBOutlet var markAllAsReadButton: UIBarButtonItem?

	private lazy var filterButton = UIBarButtonItem(image: Assets.Images.filter, style: .plain, target: self, action: #selector(toggleFilter(_:)))
	private lazy var firstUnreadButton = UIBarButtonItem(image: Assets.Images.nextUnread, style: .plain, target: self, action: #selector(firstUnread(_:)))
	private lazy var longPressReadToggleGestureRecognizer: UILongPressGestureRecognizer = {
		let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressToggleRead(_:)))
		gesture.minimumPressDuration = 0.45
		gesture.allowableMovement = 14
		return gesture
	}()

	private lazy var dataSource = makeDataSource()
	private let searchController = UISearchController(searchResultsController: nil)

	weak var coordinator: SceneCoordinator?
	var undoableCommands = [UndoableCommand]()
	let scrollPositionQueue = CoalescingQueue(name: "Timeline Scroll Position", interval: 0.3, maxInterval: 1.0)
	private var previousBackIndicatorImage: UIImage?
	private var previousBackIndicatorTransitionMaskImage: UIImage?
	private var shouldFadeInNavigationSubtitle = false

	private var timelineFeed: SidebarItem? {
		assert(coordinator != nil)
		return coordinator?.timelineFeed
	}

	private var showIcons: Bool {
		assert(coordinator != nil)
		return coordinator?.showIcons ?? false
	}

	private var currentArticle: Article? {
		assert(coordinator != nil)
		return coordinator?.currentArticle
	}

	private var timelineMiddleIndexPath: IndexPath? {
		get {
			coordinator?.timelineMiddleIndexPath
		}
		set {
			coordinator?.timelineMiddleIndexPath = newValue
		}
	}

	private var isTimelineViewControllerPending: Bool {
		get {
			coordinator?.isTimelineViewControllerPending ?? false
		}
		set {
			coordinator?.isTimelineViewControllerPending = newValue
		}
	}

	private var timelineIconImage: IconImage? {
		assert(coordinator != nil)
		return coordinator?.timelineIconImage
	}

	private var timelineDefaultReadFilterType: ReadFilterType {
		return timelineFeed?.defaultReadFilterType ?? .none
	}

	private var isReadArticlesFiltered: Bool {
		assert(coordinator != nil)
		return coordinator?.isReadArticlesFiltered ?? false
	}

	private var isTimelineUnreadAvailable: Bool {
		assert(coordinator != nil)
		return coordinator?.isTimelineUnreadAvailable ?? false
	}

	private var isRootSplitCollapsed: Bool {
		assert(coordinator != nil)
		return coordinator?.isRootSplitCollapsed ?? false
	}

	private var articles: ArticleArray? {
		assert(coordinator != nil)
		return coordinator?.articles
	}

	private let keyboardManager = KeyboardManager(type: .timeline)
	override var keyCommands: [UIKeyCommand]? {

		// If the first responder is the WKWebView (PreloadedWebView) we don't want to supply any keyboard
		// commands that the system is looking for by going up the responder chain. They will interfere with
		// the WKWebViews built in hardware keyboard shortcuts, specifically the up and down arrow keys.
		guard let current = UIResponder.currentFirstResponder, !(current is PreloadedWebView) else { return nil }

		return keyboardManager.keyCommands
	}

	private var navigationBarTitleView: UIView {
		FeedNavigationChrome.makeTitleView(target: self, action: #selector(showFeedInspector(_:)))
	}

	override var canBecomeFirstResponder: Bool {
		return true
	}

	override func viewDidLoad() {

		assert(coordinator != nil)

		super.viewDidLoad()

		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(statusesDidChange(_:)), name: .StatusesDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(feedIconDidBecomeAvailable(_:)), name: .feedIconDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(avatarDidBecomeAvailable(_:)), name: .AvatarDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(faviconDidBecomeAvailable(_:)), name: .FaviconDidBecomeAvailable, object: nil)

		// TODO: fix this temporary hack, which will probably require refactoring image handling.
		// We want to know when to possibly reconfigure our cells with a new image, and we don’t
		// always know when an image is available — but watching the .htmlMetadataAvailable Notification
		// lets us know that it’s time to request an image.
		NotificationCenter.default.addObserver(self, selector: #selector(faviconDidBecomeAvailable(_:)), name: .htmlMetadataAvailable, object: nil)

		NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.userDefaultsDidChange()
			}
		}
		NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChange), name: UIContentSizeCategory.didChangeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(displayNameDidChange), name: .DisplayNameDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)

		// Setup the Search Controller
		searchController.delegate = self
		searchController.searchResultsUpdater = self
		searchController.obscuresBackgroundDuringPresentation = false
		searchController.searchBar.delegate = self
		searchController.searchBar.placeholder = NSLocalizedString("Search Articles", comment: "Search Articles")
		searchController.searchBar.scopeButtonTitles = [
			NSLocalizedString("Here", comment: "Here"),
			NSLocalizedString("All Articles", comment: "All Articles")
		]
		navigationItem.searchController = searchController

		if traitCollection.userInterfaceIdiom == .pad {
			searchController.searchBar.selectedScopeButtonIndex = 1
			navigationItem.searchBarPlacementAllowsExternalIntegration = true
		}
		definesPresentationContext = true

		// Configure the table
		tableView.dataSource = dataSource
		tableView.isPrefetchingEnabled = false

		numberOfTextLines = AppDefaults.shared.timelineNumberOfLines
		iconSize = AppDefaults.shared.timelineIconSize

		refreshControl = UIRefreshControl()
		refreshControl!.addTarget(self, action: #selector(refreshAccounts(_:)), for: .valueChanged)

		// Custom pan gesture for swipe-left to open article with lower threshold
		let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSwipeLeftPan(_:)))
		pan.delegate = self
		tableView.addGestureRecognizer(pan)
		tableView.addGestureRecognizer(longPressReadToggleGestureRecognizer)

		configureToolbar()
		resetUI(resetScroll: true)

		// Load the table and then scroll to the saved position if available
		applyChanges(animated: false) {
			if let restoreIndexPath = self.timelineMiddleIndexPath {
				self.tableView.scrollToRow(at: restoreIndexPath, at: .middle, animated: false)
			}
		}

		// Disable swipe back on iPad mice.
		if let gesture = self.navigationController?.interactivePopGestureRecognizer as? UIPanGestureRecognizer {
			gesture.allowedScrollTypesMask = []
		}

		navigationItem.titleView = navigationBarTitleView
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		tableView.transform = .identity
		navigationController?.setNavigationBarHidden(false, animated: false)
		navigationItem.rightBarButtonItem = nil
		self.navigationController?.isToolbarHidden = false
		shouldFadeInNavigationSubtitle = true
		if let subtitleText = FeedNavigationChrome.subtitleText(in: navigationItem.titleView), !subtitleText.isEmpty {
			FeedNavigationChrome.setSubtitleAlpha(0, in: navigationItem.titleView)
		}
		hideBackIconVisualOnly()

		// If the nav bar is hidden, fade it in to avoid it showing stuff as it is getting laid out
		if navigationController?.navigationBar.isHidden ?? false {
			navigationController?.navigationBar.alpha = 0
		}

		updateNavigationBarTitle(coordinator?.timelineFeed?.nameForDisplay ?? "")
		coordinator?.updateNavigationBarSubtitles(nil)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		restoreBackIconAppearance()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(true)
		animateNavigationSubtitleIfNeeded()
		isTimelineViewControllerPending = false
		if navigationController?.navigationBar.alpha == 0 {
			UIView.animate(withDuration: 0.5) {
				self.navigationController?.navigationBar.alpha = 1
			}
		}
		if traitCollection.userInterfaceIdiom == .phone {
			if coordinator?.currentArticle != nil {
				if let indexPath = tableView.indexPathForSelectedRow {
					tableView.deselectRow(at: indexPath, animated: true)
				}
				coordinator?.selectArticle(nil)
			}
		}
	}

	// MARK: Actions

	@objc func openInBrowser(_ sender: Any?) {
		assert(coordinator != nil)
		coordinator?.showBrowserForCurrentArticle()
	}

	@objc func openInAppBrowser(_ sender: Any?) {
		assert(coordinator != nil)
		coordinator?.showInAppBrowser()
	}

	@IBAction func toggleFilter(_ sender: Any) {
		assert(coordinator != nil)
		coordinator?.toggleReadArticlesFilter()
	}

	@IBAction func markAllAsRead(_ sender: Any?) {
		let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

		if let popoverController = alert.popoverPresentationController,
		   let barButtonItem = sender as? UIBarButtonItem {
			popoverController.barButtonItem = barButtonItem
		}

		let markReadTitle = NSLocalizedString("Mark All as Read", comment: "Mark All as Read")
		alert.addAction(UIAlertAction(title: markReadTitle, style: .default) { [weak self] _ in
			self?.coordinator?.markAllAsReadInTimeline()
		})

		let markUnreadTitle = NSLocalizedString("Mark All as Unread", comment: "Mark All as Unread")
		alert.addAction(UIAlertAction(title: markUnreadTitle, style: .default) { [weak self] _ in
			self?.coordinator?.markAllAsUnreadInTimeline()
		})

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel")
		alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))

		present(alert, animated: true)
	}

	@IBAction func firstUnread(_ sender: Any) {
		assert(coordinator != nil)
		coordinator?.selectFirstUnread()
	}

	@objc func refreshAccounts(_ sender: Any) {
		refreshControl?.endRefreshing()

		// This is a hack to make sure that an error dialog doesn't interfere with dismissing the refreshControl.
		// If the error dialog appears too closely to the call to endRefreshing, then the refreshControl never disappears.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
			appDelegate.manualRefresh(errorHandler: ErrorHandler.present(self))
		}
	}

	// MARK: Keyboard shortcuts

	@objc func selectNextUp(_ sender: Any?) {
		assert(coordinator != nil)
		coordinator?.selectPrevArticle()
	}

	@objc func selectNextDown(_ sender: Any?) {
		assert(coordinator != nil)
		coordinator?.selectNextArticle()
	}

	@objc func navigateToSidebar(_ sender: Any?) {
		assert(coordinator != nil)
		coordinator?.navigateToFeeds()
	}

	@objc func navigateToDetail(_ sender: Any?) {
		assert(coordinator != nil)
		coordinator?.navigateToDetail()
	}

	@objc func showFeedInspector(_ sender: Any?) {
		assert(coordinator != nil)
		coordinator?.showBrowserForCurrentFeed()
	}

	// MARK: API

	func restoreSelectionIfNecessary(adjustScroll: Bool) {
		if let article = currentArticle, let indexPath = dataSource.indexPath(for: article) {
			if adjustScroll {
				tableView.selectRowAndScrollIfNotVisible(at: indexPath, animations: [])
			} else {
				tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
			}
		}
	}

	func updateNavigationBarTitle(_ text: String) {
		guard let titleView = navigationItem.titleView else {
			return
		}
		let isPseudoFeed = (coordinator?.timelineFeed as? PseudoFeed) != nil
		titleView.isUserInteractionEnabled = !isPseudoFeed

		FeedNavigationChrome.setTitle(text, in: titleView)
	}

	func updateNavigationBarSubtitle(_ text: String) {
		FeedNavigationChrome.setSubtitle(text, in: navigationItem.titleView)
		let hasSubtitleText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		let alpha: CGFloat = (shouldFadeInNavigationSubtitle && hasSubtitleText) ? 0 : 1
		FeedNavigationChrome.setSubtitleAlpha(alpha, in: navigationItem.titleView)
	}

	func reinitializeArticles(resetScroll: Bool) {
		resetUI(resetScroll: resetScroll)
	}

	func reloadArticles(animated: Bool) {
		applyChanges(animated: animated)
	}

	func updateArticleSelection(animations: Animations) {
		if let article = currentArticle, let indexPath = dataSource.indexPath(for: article) {
			if tableView.indexPathForSelectedRow != indexPath {
				tableView.selectRowAndScrollIfNotVisible(at: indexPath, animations: animations)
			}
		} else {
			tableView.selectRow(at: nil, animated: animations.contains(.select), scrollPosition: .none)
		}

		updateUI()
	}

	func updateUI() {
		refreshProgressView?.update()
		updateToolbar()
	}

	func hideSearch() {
		navigationItem.searchController?.isActive = false
	}

	func showSearchAll() {
		navigationItem.searchController?.isActive = true
		navigationItem.searchController?.searchBar.selectedScopeButtonIndex = 1
		navigationItem.searchController?.searchBar.becomeFirstResponder()
	}

	func focus() {
		becomeFirstResponder()
	}

	// MARK: - Table view

	override func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		return UISwipeActionsConfiguration(actions: [])
	}

	override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		return UISwipeActionsConfiguration(actions: [])
	}

	override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
		return nil
	}

	// MARK: - Swipe left pan gesture

	private var swipePanIndexPath: IndexPath?
	private var swipePanTriggered = false

	@objc private func handleSwipeLeftPan(_ gesture: UIPanGestureRecognizer) {
		let translation = gesture.translation(in: tableView)
		let velocity = gesture.velocity(in: tableView)

		switch gesture.state {
		case .began:
			let point = gesture.location(in: tableView)
			guard let indexPath = tableView.indexPathForRow(at: point),
				  let article = dataSource.itemIdentifier(for: indexPath),
				  coordinator?.beginInteractiveArticleOpen(article) == true else {
				gesture.state = .cancelled
				return
			}
			swipePanIndexPath = indexPath
			swipePanTriggered = false
			tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)

		case .changed:
			guard swipePanIndexPath != nil else { return }
			let progress = min(max(-translation.x / tableView.bounds.width, 0), 1)
			coordinator?.updateInteractiveArticleOpen(progress)

			if progress >= 0.25 && !swipePanTriggered {
				swipePanTriggered = true
				let generator = UIImpactFeedbackGenerator(style: .light)
				generator.impactOccurred()
			}

		case .ended, .cancelled:
			guard let indexPath = swipePanIndexPath else {
				resetSwipePan()
				return
			}

			let progress = min(max(-translation.x / tableView.bounds.width, 0), 1)
			let shouldOpenArticle = progress > 0.28 || velocity.x < -700

			if shouldOpenArticle {
				coordinator?.finishInteractiveArticleOpen()
			} else {
				coordinator?.cancelInteractiveArticleOpen()
				if tableView.indexPathForSelectedRow == indexPath {
					tableView.deselectRow(at: indexPath, animated: true)
				}
			}
			resetSwipePan()

		default:
			coordinator?.cancelInteractiveArticleOpen()
			resetSwipePan()
		}
	}

	@objc private func handleLongPressToggleRead(_ gesture: UILongPressGestureRecognizer) {
		guard gesture.state == .began else {
			return
		}

		let point = gesture.location(in: tableView)
		guard let indexPath = tableView.indexPathForRow(at: point),
			  let article = dataSource.itemIdentifier(for: indexPath) else {
			return
		}

		if let cell = tableView.cellForRow(at: indexPath) {
			animateDoubleFlash(on: cell)
		}

		let generator = UIImpactFeedbackGenerator(style: .light)
		generator.impactOccurred()
		coordinator?.toggleRead(article)
	}

	private func resetSwipePan() {
		swipePanIndexPath = nil
		swipePanTriggered = false
	}

	private func animateDoubleFlash(on cell: UITableViewCell) {
		let flashView = UIView(frame: cell.bounds)
		flashView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		flashView.backgroundColor = .white
		flashView.alpha = 0
		flashView.isUserInteractionEnabled = false
		cell.contentView.addSubview(flashView)

		UIView.animateKeyframes(withDuration: 0.56, delay: 0, options: [.allowUserInteraction, .calculationModeLinear]) {
			UIView.addKeyframe(withRelativeStartTime: 0.00, relativeDuration: 0.16) {
				flashView.alpha = 0.32
			}
			UIView.addKeyframe(withRelativeStartTime: 0.16, relativeDuration: 0.34) {
				flashView.alpha = 0
			}
		} completion: { _ in
			Task { @MainActor in
				flashView.removeFromSuperview()
			}
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		becomeFirstResponder()
		let article = dataSource.itemIdentifier(for: indexPath)
		coordinator?.selectArticle(article, animations: [.scroll, .select, .navigation])
	}

	override func scrollViewDidScroll(_ scrollView: UIScrollView) {
		scrollPositionQueue.add(self, #selector(scrollPositionDidChange))
	}

	// MARK: Notifications

	@objc dynamic func unreadCountDidChange(_ notification: Notification) {
		updateUI()
	}

	@objc func statusesDidChange(_ note: Notification) {
		guard let articleIDs = note.userInfo?[Account.UserInfoKey.articleIDs] as? Set<String>, !articleIDs.isEmpty else {
			return
		}

		let visibleArticles = tableView.indexPathsForVisibleRows!.compactMap { return dataSource.itemIdentifier(for: $0) }
		let visibleUpdatedArticles = visibleArticles.filter { articleIDs.contains($0.articleID) }

		for article in visibleUpdatedArticles {
			if let indexPath = dataSource.indexPath(for: article) {
				if let cell = tableView.cellForRow(at: indexPath) as? MainTimelineIconFeedCell {
					let cellData = configure(article: article)
					cell.cellData = cellData
				}
				if let cell = tableView.cellForRow(at: indexPath) as? MainTimelineFeedCell {
					let cellData = configure(article: article)
					cell.cellData = cellData
				}
			}
		}
	}

	@objc func feedIconDidBecomeAvailable(_ note: Notification) {
		guard let feed = note.userInfo?[UserInfoKey.feed] as? Feed else {
			return
		}
		guard let indexPaths = tableView.indexPathsForVisibleRows else {
			return
		}

		for indexPath in indexPaths {
			guard let article = dataSource.itemIdentifier(for: indexPath) else {
				continue
			}
			if article.feed == feed {
				if let cell = tableView.cellForRow(at: indexPath) as? MainTimelineIconFeedCell, let image = iconImageFor(article) {
					cell.setIconImage(image)
				}
			}
		}
	}

	@objc func avatarDidBecomeAvailable(_ note: Notification) {
		guard showIcons, let avatarURL = note.userInfo?[UserInfoKey.url] as? String else {
			return
		}
		guard let indexPaths = tableView.indexPathsForVisibleRows else {
			return
		}

		for indexPath in indexPaths {
			guard let article = dataSource.itemIdentifier(for: indexPath), let authors = article.authors, !authors.isEmpty else {
				continue
			}
			for author in authors {
				if author.avatarURL == avatarURL, let cell = tableView.cellForRow(at: indexPath) as? MainTimelineIconFeedCell, let image = iconImageFor(article) {
					cell.setIconImage(image)
				}
			}
		}
	}

	@objc func faviconDidBecomeAvailable(_ note: Notification) {
		if showIcons {
			queueReloadAvailableCells()
		}
	}

	func userDefaultsDidChange() {
		if self.numberOfTextLines != AppDefaults.shared.timelineNumberOfLines || self.iconSize != AppDefaults.shared.timelineIconSize {
			self.numberOfTextLines = AppDefaults.shared.timelineNumberOfLines
			self.iconSize = AppDefaults.shared.timelineIconSize
			self.reloadAllVisibleCells()
		}
		self.updateToolbar()
	}

	@objc func contentSizeCategoryDidChange(_ note: Notification) {
		reloadAllVisibleCells()
	}

	@objc func displayNameDidChange(_ note: Notification) {
		updateNavigationBarTitle(timelineFeed?.nameForDisplay ?? "")
	}

	@objc func willEnterForeground(_ note: Notification) {
		updateUI()
	}

	@objc func scrollPositionDidChange() {
		timelineMiddleIndexPath = tableView.middleVisibleRow()
	}

	// MARK: Reloading

	func queueReloadAvailableCells() {
		CoalescingQueue.standard.add(self, #selector(reloadAllVisibleCells))
	}

	@objc private func reloadAllVisibleCells() {
		let visibleArticles = tableView.indexPathsForVisibleRows!.compactMap { return dataSource.itemIdentifier(for: $0) }
		reloadCells(visibleArticles)
	}

	private func reloadCells(_ articles: [Article]) {
		var snapshot = dataSource.snapshot()
		snapshot.reloadItems(articles)
		dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
			self?.restoreSelectionIfNecessary(adjustScroll: false)
		}
	}
}

// MARK: Searching

extension MainTimelineViewController: UISearchControllerDelegate {

	func willPresentSearchController(_ searchController: UISearchController) {
		coordinator?.beginSearching()
		searchController.searchBar.showsScopeBar = true
	}

	func willDismissSearchController(_ searchController: UISearchController) {
		coordinator?.endSearching()
		searchController.searchBar.showsScopeBar = false
		updateToolbar()
	}

}

extension MainTimelineViewController: UISearchResultsUpdating {

	func updateSearchResults(for searchController: UISearchController) {
		let searchScope = SearchScope(rawValue: searchController.searchBar.selectedScopeButtonIndex)!
		searchArticles(searchController.searchBar.text!, searchScope)
	}

}

extension MainTimelineViewController: UISearchBarDelegate {
	func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
		let searchScope = SearchScope(rawValue: selectedScope)!
		searchArticles(searchBar.text!, searchScope)
	}
}

// MARK: UIGestureRecognizerDelegate

extension MainTimelineViewController: UIGestureRecognizerDelegate {
	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
		let velocity = pan.velocity(in: tableView)
		// Only begin for horizontal left swipes (negative X, dominant over Y)
		return velocity.x < 0 && abs(velocity.x) > abs(velocity.y)
	}

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		return false
	}
}

// MARK: Private

private extension MainTimelineViewController {

	func hideBackIconVisualOnly() {
		guard let navigationBar = activeNavigationController()?.navigationBar else {
			return
		}

		if previousBackIndicatorImage == nil {
			previousBackIndicatorImage = navigationBar.backIndicatorImage
		}
		if previousBackIndicatorTransitionMaskImage == nil {
			previousBackIndicatorTransitionMaskImage = navigationBar.backIndicatorTransitionMaskImage
		}

		let feedIcon: UIImage?
		if let feed = coordinator?.timelineFeed as? Feed {
			feedIcon = IconImageCache.shared.imageForFeed(feed)?.image
		} else if let pseudoFeed = coordinator?.timelineFeed as? PseudoFeed {
			feedIcon = pseudoFeed.smallIcon?.image
		} else {
			feedIcon = nil
		}
		let backImage = FeedNavigationChrome.makeBackIndicatorImage(from: feedIcon)
		navigationBar.backIndicatorImage = backImage
		navigationBar.backIndicatorTransitionMaskImage = backImage
	}

	func restoreBackIconAppearance() {
		guard let navigationBar = activeNavigationController()?.navigationBar else {
			return
		}
		navigationBar.backIndicatorImage = previousBackIndicatorImage
		navigationBar.backIndicatorTransitionMaskImage = previousBackIndicatorTransitionMaskImage
	}

	func activeNavigationController() -> UINavigationController? {
		return (navigationController?.parent as? UINavigationController) ?? navigationController
	}

	func animateNavigationSubtitleIfNeeded() {
		guard shouldFadeInNavigationSubtitle else {
			return
		}
		shouldFadeInNavigationSubtitle = false

		guard let subtitleText = FeedNavigationChrome.subtitleText(in: navigationItem.titleView),
			  !subtitleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			return
		}

		FeedNavigationChrome.setSubtitleAlpha(0, in: navigationItem.titleView)
		UIView.animate(withDuration: 0.36, delay: 0.08, options: [.curveEaseOut]) {
			FeedNavigationChrome.setSubtitleAlpha(1, in: self.navigationItem.titleView)
		}
	}

	func searchArticles(_ searchString: String, _ searchScope: SearchScope) {
		assert(coordinator != nil)
		coordinator?.searchArticles(searchString, searchScope)
	}

	func configureToolbar() {
		if traitCollection.userInterfaceIdiom == .phone {
			toolbarItems?.insert(.flexibleSpace(), at: 1)
			toolbarItems?.insert(navigationItem.searchBarPlacementBarButtonItem, at: 2)
		}
	}

	func resetUI(resetScroll: Bool) {
		navigationItem.rightBarButtonItem = nil

		tableView.selectRow(at: nil, animated: false, scrollPosition: .top)

		if resetScroll {
			let snapshot = dataSource.snapshot()
			if snapshot.sectionIdentifiers.count > 0 && snapshot.itemIdentifiers(inSection: 0).count > 0 {
				tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
			}
		}

		updateToolbar()
	}

	func updateToolbar() {
		firstUnreadButton.isEnabled = isTimelineUnreadAvailable

		if isRootSplitCollapsed {
			if let toolbarItems = toolbarItems, toolbarItems.last != firstUnreadButton {
				var items = toolbarItems
				items.append(firstUnreadButton)
				setToolbarItems(items, animated: false)
			}
		} else {
			if let toolbarItems = toolbarItems, toolbarItems.last == firstUnreadButton {
				let items = Array(toolbarItems[0..<toolbarItems.count - 1])
				setToolbarItems(items, animated: false)
			}
		}
	}

	func applyChanges(animated: Bool, completion: (() -> Void)? = nil) {
		if (articles?.count ?? 0) == 0 {
			tableView.rowHeight = tableView.estimatedRowHeight
		} else {
			tableView.rowHeight = UITableView.automaticDimension
		}

        var snapshot = NSDiffableDataSourceSnapshot<Int, Article>()
		snapshot.appendSections([0])
		snapshot.appendItems(articles ?? ArticleArray(), toSection: 0)

		dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
			self?.restoreSelectionIfNecessary(adjustScroll: false)
			completion?()
		}
	}

	func makeDataSource() -> UITableViewDiffableDataSource<Int, Article> {
		let dataSource: UITableViewDiffableDataSource<Int, Article> =
			MainTimelineDataSource(tableView: tableView, cellProvider: { [weak self] tableView, indexPath, article in
				let cellData = self!.configure(article: article)
				if self!.showIcons {
					let cell = tableView.dequeueReusableCell(withIdentifier: "MainTimelineIconFeedCell", for: indexPath) as! MainTimelineIconFeedCell
					cell.cellData = cellData
					return cell
				} else {
					let cell = tableView.dequeueReusableCell(withIdentifier: "MainTimelineFeedCell", for: indexPath) as! MainTimelineFeedCell
					cell.cellData = cellData
					return cell
				}

			})
		dataSource.defaultRowAnimation = .middle
		return dataSource
    }

	@discardableResult
	func configure(article: Article) -> MainTimelineCellData {
		let iconImage = iconImageFor(article)
		let showFeedNames = coordinator?.showFeedNames ?? ShowFeedName.none
		let showIcon = showIcons && iconImage != nil
		let cellData = MainTimelineCellData(article: article, showFeedName: showFeedNames, feedName: article.feed?.nameForDisplay, byline: article.byline(), iconImage: iconImage, showIcon: showIcon, numberOfLines: numberOfTextLines, iconSize: iconSize)
		return cellData
	}

	func iconImageFor(_ article: Article) -> IconImage? {
		if !showIcons {
			return nil
		}
		return article.iconImage()
	}

	func toggleRead(_ article: Article) {
		assert(coordinator != nil)
		coordinator?.toggleRead(article)
	}

	func toggleArticleReadStatusAction(_ article: Article) -> UIAction? {
		guard !article.status.read || article.isAvailableToMarkUnread else { return nil }

		let title = article.status.read ?
			NSLocalizedString("Mark as Unread", comment: "Mark as Unread") :
			NSLocalizedString("Mark as Read", comment: "Mark as Read")
		let image = article.status.read ? Assets.Images.circleClosed : Assets.Images.circleOpen

		let action = UIAction(title: title, image: image) { [weak self] _ in
			self?.toggleRead(article)
		}

		return action
	}

	func toggleStar(_ article: Article) {
		assert(coordinator != nil)
		coordinator?.toggleStar(article)
	}

	func toggleArticleStarStatusAction(_ article: Article) -> UIAction {

		let title = article.status.starred ?
			NSLocalizedString("Mark as Unstarred", comment: "Mark as Unstarred") :
			NSLocalizedString("Mark as Starred", comment: "Mark as Starred")
		let image = article.status.starred ? Assets.Images.starOpen : Assets.Images.starClosed

		let action = UIAction(title: title, image: image) { [weak self] _ in
			self?.toggleStar(article)
		}

		return action
	}

	func markAboveAsRead(_ article: Article) {
		assert(coordinator != nil)
		coordinator?.markAboveAsRead(article)
	}

	func canMarkAboveAsRead(for article: Article) -> Bool {
		assert(coordinator != nil)
		return coordinator?.canMarkAboveAsRead(for: article) ?? false
	}

	func markAboveAsReadAction(_ article: Article, indexPath: IndexPath) -> UIAction? {
		guard canMarkAboveAsRead(for: article), let contentView = self.tableView.cellForRow(at: indexPath)?.contentView else {
			return nil
		}

		let title = NSLocalizedString("Mark Above as Read", comment: "Mark Above as Read")
		let image = Assets.Images.markAboveAsRead
		let action = UIAction(title: title, image: image) { [weak self] _ in
			MarkAsReadAlertController.confirm(self, coordinator: self?.coordinator, confirmTitle: title, sourceType: contentView) { [weak self] in
				self?.markAboveAsRead(article)
			}
		}
		return action
	}

	func markBelowAsRead(_ article: Article) {
		assert(coordinator != nil)
		coordinator?.markBelowAsRead(article)
	}

	func canMarkBelowAsRead(for article: Article) -> Bool {
		assert(coordinator != nil)
		return coordinator?.canMarkBelowAsRead(for: article) ?? false
	}

	func markBelowAsReadAction(_ article: Article, indexPath: IndexPath) -> UIAction? {
		guard canMarkBelowAsRead(for: article), let contentView = self.tableView.cellForRow(at: indexPath)?.contentView else {
			return nil
		}

		let title = NSLocalizedString("Mark Below as Read", comment: "Mark Below as Read")
		let image = Assets.Images.markBelowAsRead
		let action = UIAction(title: title, image: image) { [weak self] _ in
			MarkAsReadAlertController.confirm(self, coordinator: self?.coordinator, confirmTitle: title, sourceType: contentView) { [weak self] in
				self?.markBelowAsRead(article)
			}
		}
		return action
	}

	func markAboveAsReadAlertAction(_ article: Article, indexPath: IndexPath, completion: @escaping (Bool) -> Void) -> UIAlertAction? {
		guard canMarkAboveAsRead(for: article), let contentView = self.tableView.cellForRow(at: indexPath)?.contentView else {
			return nil
		}

		let title = NSLocalizedString("Mark Above as Read", comment: "Mark Above as Read")
		let cancel = {
			completion(true)
		}

		let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
			MarkAsReadAlertController.confirm(self, coordinator: self?.coordinator, confirmTitle: title, sourceType: contentView, cancelCompletion: cancel) { [weak self] in
				self?.markAboveAsRead(article)
				completion(true)
			}
		}
		return action
	}

	func markBelowAsReadAlertAction(_ article: Article, indexPath: IndexPath, completion: @escaping (Bool) -> Void) -> UIAlertAction? {
		guard canMarkBelowAsRead(for: article), let contentView = self.tableView.cellForRow(at: indexPath)?.contentView else {
			return nil
		}

		let title = NSLocalizedString("Mark Below as Read", comment: "Mark Below as Read")
		let cancel = {
			completion(true)
		}

		let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
			MarkAsReadAlertController.confirm(self, coordinator: self?.coordinator, confirmTitle: title, sourceType: contentView, cancelCompletion: cancel) { [weak self] in
				self?.markBelowAsRead(article)
				completion(true)
			}
		}
		return action
	}

	func timelineFeedIsEqualTo(_ feed: Feed) -> Bool {
		assert(coordinator != nil)
		return coordinator?.timelineFeedIsEqualTo(feed) ?? false
	}

	func discloseFeed(_ feed: Feed, animations: Animations = []) {
		assert(coordinator != nil)
		coordinator?.discloseFeed(feed, animations: animations)
	}

	func discloseFeedAction(_ article: Article) -> UIAction? {
		guard let feed = article.feed,
			!timelineFeedIsEqualTo(feed) else { return nil }

		let title = NSLocalizedString("Go to Feed", comment: "Go to Feed")
		let action = UIAction(title: title, image: Assets.Images.openInSidebar) { [weak self] _ in
			self?.discloseFeed(feed, animations: [.scroll, .navigation])
		}
		return action
	}

	func discloseFeedAlertAction(_ article: Article, completion: @escaping (Bool) -> Void) -> UIAlertAction? {
		guard let feed = article.feed,
			!timelineFeedIsEqualTo(feed) else { return nil }

		let title = NSLocalizedString("Go to Feed", comment: "Go to Feed")
		let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
			self?.discloseFeed(feed, animations: [.scroll, .navigation])
			completion(true)
		}
		return action
	}

	func markAllAsRead(_ articles: ArticleArray) {
		assert(coordinator != nil)
		coordinator?.markAllAsRead(articles)
	}

	func markAllInFeedAsReadAction(_ article: Article, indexPath: IndexPath) -> UIAction? {
		guard let feed = article.feed else { return nil }
		guard let fetchedArticles = try? feed.fetchArticles() else {
			return nil
		}

		let articles = Array(fetchedArticles)
		guard articles.canMarkAllAsRead(), let contentView = self.tableView.cellForRow(at: indexPath)?.contentView else {
			return nil
		}

		let localizedMenuText = NSLocalizedString("Mark All as Read in “%@”", comment: "Command")
		let title = NSString.localizedStringWithFormat(localizedMenuText as NSString, feed.nameForDisplay) as String

		let action = UIAction(title: title, image: Assets.Images.markAllAsRead) { [weak self] _ in
			MarkAsReadAlertController.confirm(self, coordinator: self?.coordinator, confirmTitle: title, sourceType: contentView) { [weak self] in
				self?.markAllAsRead(articles)
			}
		}
		return action
	}

	func markAllInFeedAsReadAlertAction(_ article: Article, indexPath: IndexPath, completion: @escaping (Bool) -> Void) -> UIAlertAction? {
		guard let feed = article.feed else { return nil }
		guard let fetchedArticles = try? feed.fetchArticles() else {
			return nil
		}

		let articles = Array(fetchedArticles)
		guard articles.canMarkAllAsRead(), let contentView = self.tableView.cellForRow(at: indexPath)?.contentView else {
			return nil
		}

		let localizedMenuText = NSLocalizedString("Mark All as Read in “%@”", comment: "Mark All as Read in Feed")
		let title = NSString.localizedStringWithFormat(localizedMenuText as NSString, feed.nameForDisplay) as String
		let cancel = {
			completion(true)
		}

		let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
			MarkAsReadAlertController.confirm(self, coordinator: self?.coordinator, confirmTitle: title, sourceType: contentView, cancelCompletion: cancel) { [weak self] in
				self?.markAllAsRead(articles)
				completion(true)
			}
		}
		return action
	}

	func copyArticleURLAction(_ article: Article) -> UIAction? {
		guard let url = article.preferredURL else { return nil }
		let title = NSLocalizedString("Copy Article URL", comment: "Copy Article URL")
		let action = UIAction(title: title, image: Assets.Images.copy) { _ in
			UIPasteboard.general.url = url
		}
		return action
	}

	func copyExternalURLAction(_ article: Article) -> UIAction? {
		guard let externalLink = article.externalLink, externalLink != article.preferredLink, let url = URL(string: externalLink) else { return nil }
		let title = NSLocalizedString("Copy External URL", comment: "Copy External URL")
		let action = UIAction(title: title, image: Assets.Images.copy) { _ in
			UIPasteboard.general.url = url
		}
		return action
	}

	func showBrowserForArticle(_ article: Article) {
		assert(coordinator != nil)
		coordinator?.showBrowserForArticle(article)
	}

	func openInBrowserAction(_ article: Article) -> UIAction? {
		guard article.preferredURL != nil else {
			return nil
		}
		let title = NSLocalizedString("Open in Browser", comment: "Open in Browser")
		let action = UIAction(title: title, image: Assets.Images.safari) { [weak self] _ in
			self?.showBrowserForArticle(article)
		}
		return action
	}

	func openInBrowserAlertAction(_ article: Article, completion: @escaping (Bool) -> Void) -> UIAlertAction? {
		guard article.preferredURL != nil else {
			return nil
		}

		let title = NSLocalizedString("Open in Browser", comment: "Open in Browser")
		let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
			self?.showBrowserForArticle(article)
			completion(true)
		}
		return action
	}

	func shareDialogForTableCell(indexPath: IndexPath, url: URL, title: String?) {
		let activityViewController = UIActivityViewController(url: url, title: title, applicationActivities: nil)

		guard let cell = tableView.cellForRow(at: indexPath) else {
			return
		}
		let popoverController = activityViewController.popoverPresentationController
		popoverController?.sourceView = cell
		popoverController?.sourceRect = CGRect(x: 0, y: 0, width: cell.frame.size.width, height: cell.frame.size.height)

		present(activityViewController, animated: true)
	}

	func shareAction(_ article: Article, indexPath: IndexPath) -> UIAction? {
		guard let url = article.preferredURL else { return nil }
		let title = NSLocalizedString("Share", comment: "Share")
		let action = UIAction(title: title, image: Assets.Images.share) { [weak self] _ in
			self?.shareDialogForTableCell(indexPath: indexPath, url: url, title: article.title)
		}
		return action
	}

	func shareAlertAction(_ article: Article, indexPath: IndexPath, completion: @escaping (Bool) -> Void) -> UIAlertAction? {
		guard let url = article.preferredURL else { return nil }
		let title = NSLocalizedString("Share", comment: "Share")
		let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
			completion(true)
			self?.shareDialogForTableCell(indexPath: indexPath, url: url, title: article.title)
		}
		return action
	}

}
