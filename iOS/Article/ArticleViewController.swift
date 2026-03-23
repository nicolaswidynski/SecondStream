//
//  ArticleViewController.swift
//  NetNewsWire
//
//  Created by Maurice Parker on 4/8/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import SafariServices
import WebKit
import RSCore
import Account
import Articles

final class ArticleViewController: UIViewController {

	typealias State = (extractedArticle: ExtractedArticle?,
		isShowingExtractedArticle: Bool,
		articleExtractorButtonState: ArticleExtractorButtonState,
		windowScrollY: Int)

	@IBOutlet private weak var prevArticleBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var nextArticleBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var readBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var starBarButtonItem: UIBarButtonItem!
	@IBOutlet private weak var actionBarButtonItem: UIBarButtonItem!

	@IBOutlet private var searchBar: ArticleSearchBar!
	@IBOutlet private var searchBarBottomConstraint: NSLayoutConstraint!
	private var defaultControls: [UIBarButtonItem]?
	private var lastNavigationIconKey: String?

	private var pageViewController: UIPageViewController!

	private var currentWebViewController: WebViewController? {
		return pageViewController?.viewControllers?.first as? WebViewController
	}

	private var ttsBarButtonItem: UIBarButtonItem?

	weak var coordinator: SceneCoordinator!

	var article: Article? {
		didSet {
			if let controller = currentWebViewController, controller.article != article {
				controller.setArticle(article)
				DispatchQueue.main.async {
					// You have to set the view controller to clear out the UIPageViewController child controller cache.
					// You also have to do it in an async call or you will get a strange assertion error.
					self.pageViewController.setViewControllers([controller], direction: .forward, animated: false, completion: nil)
				}
			}
			updateUI()
		}
	}

	var restoreScrollPosition: (isShowingExtractedArticle: Bool, articleWindowScrollY: Int)? {
		didSet {
			if let rsp = restoreScrollPosition {
				currentWebViewController?.setScrollPosition(isShowingExtractedArticle: rsp.isShowingExtractedArticle, articleWindowScrollY: rsp.articleWindowScrollY)
			}
		}
	}

	var currentState: State? {
		guard let controller = currentWebViewController else { return nil}
		return State(extractedArticle: controller.extractedArticle,
					 isShowingExtractedArticle: controller.isShowingExtractedArticle,
					 articleExtractorButtonState: controller.articleExtractorButtonState,
					 windowScrollY: controller.windowScrollY)
	}

	var restoreState: State?

	private let keyboardManager = KeyboardManager(type: .detail)
	override var keyCommands: [UIKeyCommand]? {
		return keyboardManager.keyCommands
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(statusesDidChange(_:)), name: .StatusesDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChange(_:)), name: UIContentSizeCategory.didChangeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(feedIconDidBecomeAvailable(_:)), name: .feedIconDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsDidChange(_:)), name: UserDefaults.didChangeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(sourceImageDidBecomeAvailable(_:)), name: .sourceImageDidBecomeAvailable, object: nil)

		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: ArticleViewController, _: UITraitCollection) in
			self.lastNavigationIconKey = nil
			self.updateNavigationHeader()
		}

		let titleView = FeedNavigationChrome.makeTitleView(target: self, action: #selector(showCurrentFeedHomepage(_:)))
		titleView.transform = CGAffineTransform(translationX: 0, y: -3)
		navigationItem.titleView = titleView
		navigationItem.rightBarButtonItems = nil

		// Add TTS button after share
		ttsBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "speaker.wave.2"), style: .plain, target: self, action: #selector(ttsTapped))
		configureToolbarAsSingleBlock()

		pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [:])
		pageViewController.delegate = self
		pageViewController.dataSource = self

		pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(pageViewController.view)
		addChild(pageViewController!)

		// Article paging is disabled; avoid horizontal pan conflicts with native back-swipe.
		pageViewController.scrollViewInsidePageControl?.isScrollEnabled = false

		NSLayoutConstraint.activate([
			view.leadingAnchor.constraint(equalTo: pageViewController.view.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: pageViewController.view.trailingAnchor),
			view.topAnchor.constraint(equalTo: pageViewController.view.topAnchor),
			view.bottomAnchor.constraint(equalTo: pageViewController.view.bottomAnchor)
		])

		let controller: WebViewController
		if let state = restoreState {
			controller = createWebViewController(article, updateView: false)
			controller.extractedArticle = state.extractedArticle
			controller.isShowingExtractedArticle = state.isShowingExtractedArticle
			controller.articleExtractorButtonState = state.articleExtractorButtonState
			controller.windowScrollY = state.windowScrollY
		} else {
			controller = createWebViewController(article, updateView: true)
		}

		if let rsp = restoreScrollPosition {
			controller.setScrollPosition(isShowingExtractedArticle: rsp.isShowingExtractedArticle, articleWindowScrollY: rsp.articleWindowScrollY)
		}

		self.pageViewController.setViewControllers([controller], direction: .forward, animated: false, completion: nil)
		if AppDefaults.shared.logicalArticleFullscreenEnabled {
			controller.hideBars()
		}

		// Search bar
		searchBar.translatesAutoresizingMaskIntoConstraints = false
		NotificationCenter.default.addObserver(self, selector: #selector(beginFind(_:)), name: .FindInArticle, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(endFind(_:)), name: .EndFindInArticle, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)), name: UIWindow.keyboardWillChangeFrameNotification, object: nil)
		searchBar.delegate = self
		view.bringSubviewToFront(searchBar)

		updateUI()
	}

	override func viewWillAppear(_ animated: Bool) {
		let hideToolbars = AppDefaults.shared.logicalArticleFullscreenEnabled
		if hideToolbars {
			currentWebViewController?.hideBars()
		} else {
			currentWebViewController?.showBars()
		}
		updateNavigationHeader()
		navigationController?.setNavigationBarHidden(false, animated: false)
		super.viewWillAppear(animated)
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(true)
		navigationController?.navigationBar.topItem?.subtitle = nil
		coordinator.isArticleViewControllerPending = false
		searchBar.shouldBeginEditing = true
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if searchBar != nil && !searchBar.isHidden {
			endFind()
			searchBar.shouldBeginEditing = false
		}
	}

	override func viewSafeAreaInsetsDidChange() {
		// This will animate if the show/hide bars animation is happening.
		view.layoutIfNeeded()
	}

	override func willTransition(to newCollection: UITraitCollection, with coordinator: any UIViewControllerTransitionCoordinator) {
		// We only want to show bars when rotating to horizontalSizeClass == .regular
		// (i.e., big) iPhones to resolve crash #4483.
		if traitCollection.userInterfaceIdiom == .phone && newCollection.horizontalSizeClass == .regular {
			currentWebViewController?.showBars()
		}
	}

	func updateUI() {
		updateNavigationHeader()

		guard let article = article else {
			prevArticleBarButtonItem.isEnabled = false
			nextArticleBarButtonItem.isEnabled = false
			readBarButtonItem.isEnabled = false
			starBarButtonItem.isEnabled = false
			actionBarButtonItem.isEnabled = false
			ttsBarButtonItem?.isEnabled = false
			return
		}

		prevArticleBarButtonItem.isEnabled = coordinator.isPrevArticleAvailable
		nextArticleBarButtonItem.isEnabled = coordinator.isNextArticleAvailable
		readBarButtonItem.isEnabled = true
		starBarButtonItem.isEnabled = true

		let feedCategory = article.feed?.feedCategory ?? .rss
		switch feedCategory {
		case .rss:
			actionBarButtonItem.isEnabled = article.preferredURL != nil
		case .podcast, .youtube, .news:
			actionBarButtonItem.isEnabled = true
		}

		// Update TTS button state
		ttsBarButtonItem?.isEnabled = true
		if TextToSpeechManager.shared.isSpeaking {
			ttsBarButtonItem?.image = UIImage(systemName: "stop.circle")
		} else if TextToSpeechManager.shared.isPaused {
			ttsBarButtonItem?.image = UIImage(systemName: "play.circle")
		} else {
			ttsBarButtonItem?.image = UIImage(systemName: "speaker.wave.2")
		}

		if article.status.read {
			readBarButtonItem.image = Assets.Images.circleOpen
			readBarButtonItem.isEnabled = article.isAvailableToMarkUnread
			readBarButtonItem.accLabelText = NSLocalizedString("Mark Article Unread", comment: "Mark Article Unread")
		} else {
			readBarButtonItem.image = Assets.Images.circleClosed
			readBarButtonItem.isEnabled = true
			readBarButtonItem.accLabelText = NSLocalizedString("Selected - Mark Article Unread", comment: "Selected - Mark Article Unread")
		}

		let bookmarkConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
		if article.status.starred {
			starBarButtonItem.image = UIImage(systemName: "bookmark.fill", withConfiguration: bookmarkConfig)
			starBarButtonItem.accLabelText = NSLocalizedString("Selected - Star Article", comment: "Selected - Star Article")
		} else {
			starBarButtonItem.image = UIImage(systemName: "bookmark", withConfiguration: bookmarkConfig)
			starBarButtonItem.accLabelText = NSLocalizedString("Star Article", comment: "Star Article")
		}

	}

	// MARK: Notifications

	@objc dynamic func unreadCountDidChange(_ notification: Notification) {
		updateUI()
	}

	@objc func statusesDidChange(_ note: Notification) {
		guard let articleIDs = note.userInfo?[Account.UserInfoKey.articleIDs] as? Set<String> else {
			return
		}
		guard let article = article else {
			return
		}
		if articleIDs.contains(article.articleID) {
			updateUI()
		}
	}

	@objc func contentSizeCategoryDidChange(_ note: Notification) {
		currentWebViewController?.fullReload()
	}

	@objc func feedIconDidBecomeAvailable(_ note: Notification) {
		guard let feed = note.userInfo?[UserInfoKey.feed] as? Feed else {
			return
		}
		if let timelineFeed = coordinator?.timelineFeed as? Feed, timelineFeed == feed {
			let iconKey = String(describing: timelineFeed.sidebarItemID)
			FeedNavigationChrome.clearTopBarFeedIcon(cacheKey: iconKey)
			lastNavigationIconKey = nil
			updateNavigationHeader()
			return
		}
		guard article?.feed == feed else {
			return
		}
		let iconKey = String(describing: feed.sidebarItemID)
		FeedNavigationChrome.clearTopBarFeedIcon(cacheKey: iconKey)
		lastNavigationIconKey = nil
		updateNavigationHeader()
	}

	@objc func sourceImageDidBecomeAvailable(_ note: Notification) {
		lastNavigationIconKey = nil
		updateNavigationHeader()
	}

	@objc func willEnterForeground(_ note: Notification) {
		// The toolbar will come back on you if you don't hide it again
		if AppDefaults.shared.logicalArticleFullscreenEnabled {
			currentWebViewController?.hideBars()
		}
	}

	@objc func userDefaultsDidChange(_ note: Notification) {
		if !AppDefaults.shared.ttsEnabled, TextToSpeechManager.shared.isActive {
			TextToSpeechManager.shared.stop()
		}
		configureToolbarAsSingleBlock()
		updateUI()
	}

	// MARK: Actions

	@objc func showBars(_ sender: Any) {
		currentWebViewController?.showBars()
	}

	@objc func showCurrentFeedHomepage(_ sender: Any?) {
		coordinator?.openHomepageForArticleOrTimelineFeed(article)
	}

	@IBAction func toggleArticleExtractor(_ sender: Any) {
		currentWebViewController?.toggleArticleExtractor()
	}

	@IBAction func prevArticle(_ sender: Any) {
		coordinator.selectPrevArticle()
	}

	@IBAction func nextArticle(_ sender: Any) {
		coordinator.selectNextArticle()
	}

	@IBAction func toggleRead(_ sender: Any) {
		coordinator.toggleReadForCurrentArticle()
	}

	@IBAction func toggleStar(_ sender: Any) {
		coordinator.toggleStarredForCurrentArticle()
	}

	@IBAction func showActivityDialog(_ sender: Any) {
		currentWebViewController?.showActivityDialog(popOverBarButtonItem: actionBarButtonItem)
	}

	@objc func ttsTapped() {
		guard AppDefaults.shared.ttsEnabled else {
			return
		}
		if TextToSpeechManager.shared.isActive {
			// TTS is active - stop it
			TextToSpeechManager.shared.stop()
		} else {
			currentWebViewController?.getArticleText { [weak self] text in
				guard let text, !text.isEmpty else {
					return
				}
				let voiceIdentifier = AppDefaults.shared.ttsVoiceIdentifier
				TextToSpeechManager.shared.speak(text: text, voiceIdentifier: voiceIdentifier)
				self?.updateUI()
			}
		}
		updateUI()
	}

	@objc func toggleReaderView(_ sender: Any?) {
		currentWebViewController?.toggleArticleExtractor()
	}

	// MARK: Keyboard Shortcuts

	@objc func navigateToTimeline(_ sender: Any?) {
		coordinator.navigateToTimeline()
	}

	// MARK: API

	func focus() {
		currentWebViewController?.focus()
	}

	func canScrollDown() -> Bool {
		return currentWebViewController?.canScrollDown() ?? false
	}

	func canScrollUp() -> Bool {
		return currentWebViewController?.canScrollUp() ?? false
	}

	func scrollPageDown() {
		currentWebViewController?.scrollPageDown()
	}

	func scrollPageUp() {
		currentWebViewController?.scrollPageUp()
	}

	func stopArticleExtractorIfProcessing() {
		currentWebViewController?.stopArticleExtractorIfProcessing()
	}

	func openInAppBrowser() {
		currentWebViewController?.openInAppBrowser()
	}

	func setScrollPosition(isShowingExtractedArticle: Bool, articleWindowScrollY: Int) {
		currentWebViewController?.setScrollPosition(isShowingExtractedArticle: isShowingExtractedArticle, articleWindowScrollY: articleWindowScrollY)
	}
}

// MARK: Find in Article
public extension Notification.Name {
	static let FindInArticle = Notification.Name("FindInArticle")
	static let EndFindInArticle = Notification.Name("EndFindInArticle")
}

extension ArticleViewController: SearchBarDelegate {

	func searchBar(_ searchBar: ArticleSearchBar, textDidChange searchText: String) {
		currentWebViewController?.searchText(searchText) { found in
			searchBar.resultsCount = found.count

			if let index = found.index {
				searchBar.selectedResult = index + 1
			}
		}
	}

	func doneWasPressed(_ searchBar: ArticleSearchBar) {
		NotificationCenter.default.post(name: .EndFindInArticle, object: nil)
	}

	func nextWasPressed(_ searchBar: ArticleSearchBar) {
		if searchBar.selectedResult < searchBar.resultsCount {
			currentWebViewController?.selectNextSearchResult()
			searchBar.selectedResult += 1
		}
	}

	func previousWasPressed(_ searchBar: ArticleSearchBar) {
		if searchBar.selectedResult > 1 {
			currentWebViewController?.selectPreviousSearchResult()
			searchBar.selectedResult -= 1
		}
	}
}

extension ArticleViewController {

	@objc func beginFind(_ _: Any? = nil) {
		searchBar.isHidden = false
		navigationController?.setToolbarHidden(true, animated: true)
		currentWebViewController?.additionalSafeAreaInsets.bottom = searchBar.frame.height
		searchBar.becomeFirstResponder()
	}

	@objc func endFind(_ _: Any? = nil) {
		searchBar.resignFirstResponder()
		searchBar.isHidden = true
		navigationController?.setToolbarHidden(false, animated: true)
		currentWebViewController?.additionalSafeAreaInsets.bottom = 0
		currentWebViewController?.endSearch()
	}

	@objc func keyboardWillChangeFrame(_ notification: Notification) {
		if !searchBar.isHidden,
			let duration = notification.userInfo?[UIWindow.keyboardAnimationDurationUserInfoKey] as? Double,
			let curveRaw = notification.userInfo?[UIWindow.keyboardAnimationCurveUserInfoKey] as? UInt,
			let frame = notification.userInfo?[UIWindow.keyboardFrameEndUserInfoKey] as? CGRect {

			let curve = UIView.AnimationOptions(rawValue: curveRaw)
			let newHeight = view.safeAreaLayoutGuide.layoutFrame.maxY - frame.minY
			currentWebViewController?.additionalSafeAreaInsets.bottom = newHeight + searchBar.frame.height + 10
			self.searchBarBottomConstraint.constant = newHeight
			UIView.animate(withDuration: duration, delay: 0, options: curve, animations: {
				self.view.layoutIfNeeded()
			})
		}
	}

}

// MARK: WebViewControllerDelegate

extension ArticleViewController: WebViewControllerDelegate {

	func webViewController(_ webViewController: WebViewController, articleExtractorButtonStateDidUpdate buttonState: ArticleExtractorButtonState) {
		// Article extractor button removed - no-op
	}

}

// MARK: UIPageViewControllerDataSource

extension ArticleViewController: UIPageViewControllerDataSource {

	func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
		return nil
	}

	func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
		return nil
	}

}

// MARK: UIPageViewControllerDelegate

extension ArticleViewController: UIPageViewControllerDelegate {

	func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
		guard finished, completed else { return }
		guard let article = currentWebViewController?.article else { return }

		coordinator.selectArticle(article, animations: [.select, .scroll, .navigation])

		for viewController in previousViewControllers {
			if let webViewController = viewController as? WebViewController {
				webViewController.stopWebViewActivity()
			}
		}
	}
}

// MARK: Private

private extension ArticleViewController {

	func configureToolbarAsSingleBlock() {
		var items: [UIBarButtonItem] = [
			.flexibleSpace(),
			readBarButtonItem,
			starBarButtonItem,
			prevArticleBarButtonItem,
			nextArticleBarButtonItem,
			actionBarButtonItem
		]
		if AppDefaults.shared.ttsEnabled, let ttsBarButtonItem {
			items.append(ttsBarButtonItem)
		}
		items.append(.flexibleSpace())

		setToolbarItems(items, animated: false)
	}

	func createWebViewController(_ article: Article?, updateView: Bool = true) -> WebViewController {
		let controller = WebViewController()
		controller.coordinator = coordinator
		controller.delegate = self
		controller.setArticle(article, updateView: updateView)
		return controller
	}

	func updateNavigationHeader() {
		let timelineItem = coordinator?.timelineFeed
		let isSmartTimeline = timelineItem is PseudoFeed
		let feedForHeader = isSmartTimeline ? article?.feed : (timelineItem as? Feed ?? article?.feed)
		let title = feedForHeader?.nameForDisplay ?? timelineItem?.nameForDisplay
		FeedNavigationChrome.setTitle(title, in: navigationItem.titleView)
		FeedNavigationChrome.setSubtitle(nil, in: navigationItem.titleView)

		let iconSource: SidebarItem?
		iconSource = isSmartTimeline ? article?.feed : (timelineItem ?? article?.feed)

		guard let iconSource else {
			navigationItem.rightBarButtonItem = nil
			lastNavigationIconKey = nil
			return
		}

		let iconKey = String(describing: iconSource.sidebarItemID)
		if iconKey == lastNavigationIconKey, navigationItem.rightBarButtonItem != nil {
			return
		}
		if let timelineFeed = timelineItem as? Feed,
		   iconSource.sidebarItemID == timelineFeed.sidebarItemID,
		   lastNavigationIconKey == nil,
		   navigationItem.rightBarButtonItem?.image != nil {
			// Keep the pre-seeded timeline icon so it stays visually stable during the push/pop animation.
			lastNavigationIconKey = iconKey
			return
		}

		let iconImage = IconImageCache.shared.imageForFeed(iconSource)

		guard let iconImage else {
			if isSmartTimeline {
				navigationItem.rightBarButtonItem = nil
				lastNavigationIconKey = nil
			}
			return
		}

		let isPseudoFeedIcon = iconSource is PseudoFeed
		navigationItem.rightBarButtonItem = FeedNavigationChrome.makeTopBarFeedBarButton(
			iconImage: iconImage,
			isPseudoFeedIcon: isPseudoFeedIcon,
			cacheKey: iconKey,
			userInterfaceStyle: traitCollection.userInterfaceStyle,
			target: self,
			action: #selector(showCurrentFeedHomepage(_:))
		)
		lastNavigationIconKey = iconKey
	}

}
