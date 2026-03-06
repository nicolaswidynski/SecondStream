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
	private var structuredArticleViewController: StructuredArticleContentViewController?

	private var currentWebViewController: WebViewController? {
		return pageViewController?.viewControllers?.first as? WebViewController
	}

	private var isShowingStructuredArticleView: Bool {
		return !(structuredArticleViewController?.view.isHidden ?? true)
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
			structuredArticleViewController?.setArticle(article)
			updateContentPresentation()
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

		navigationItem.titleView = FeedNavigationChrome.makeTitleView(target: self, action: #selector(showCurrentFeedHomepage(_:)))
		navigationItem.rightBarButtonItems = nil

		// Add TTS button after share
		ttsBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "speaker.wave.2"), style: .plain, target: self, action: #selector(ttsTapped))
		if let ttsButton = ttsBarButtonItem {
			toolbarItems?.append(ttsButton)
		}
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

			let structuredController = StructuredArticleContentViewController()
			structuredController.view.translatesAutoresizingMaskIntoConstraints = false
			view.addSubview(structuredController.view)
			addChild(structuredController)
			NSLayoutConstraint.activate([
				view.leadingAnchor.constraint(equalTo: structuredController.view.leadingAnchor),
				view.trailingAnchor.constraint(equalTo: structuredController.view.trailingAnchor),
				view.topAnchor.constraint(equalTo: structuredController.view.topAnchor),
				view.bottomAnchor.constraint(equalTo: structuredController.view.bottomAnchor)
			])
			structuredController.didMove(toParent: self)
			structuredController.setArticle(article)
			structuredArticleViewController = structuredController

			// Search bar
			searchBar.translatesAutoresizingMaskIntoConstraints = false
		NotificationCenter.default.addObserver(self, selector: #selector(beginFind(_:)), name: .FindInArticle, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(endFind(_:)), name: .EndFindInArticle, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)), name: UIWindow.keyboardWillChangeFrameNotification, object: nil)
			searchBar.delegate = self
			view.bringSubviewToFront(searchBar)

			updateContentPresentation()
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

		let permalinkPresent = article.preferredLink != nil
		actionBarButtonItem.isEnabled = permalinkPresent

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

		if article.status.starred {
			starBarButtonItem.image = Assets.Images.starClosed
			starBarButtonItem.accLabelText = NSLocalizedString("Selected - Star Article", comment: "Selected - Star Article")
		} else {
			starBarButtonItem.image = Assets.Images.starOpen
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
		structuredArticleViewController?.setArticle(article)
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

	@objc func willEnterForeground(_ note: Notification) {
		// The toolbar will come back on you if you don't hide it again
		if AppDefaults.shared.logicalArticleFullscreenEnabled {
			currentWebViewController?.hideBars()
		}
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
		if TextToSpeechManager.shared.isActive {
			// TTS is active - stop it
			TextToSpeechManager.shared.stop()
		} else {
			let startTTS: (String?) -> Void = { [weak self] text in
				guard let text, !text.isEmpty else {
					return
				}
				let voiceIdentifier = AppDefaults.shared.ttsVoiceIdentifier
				TextToSpeechManager.shared.speak(text: text, voiceIdentifier: voiceIdentifier)
				self?.updateUI()
			}

			// Start TTS with current article content.
			if isShowingStructuredArticleView {
				startTTS(structuredArticleViewController?.articleTextForSpeech())
			} else {
				currentWebViewController?.getArticleText { text in
					startTTS(text)
				}
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
		if isShowingStructuredArticleView {
			return structuredArticleViewController?.canScrollDown() ?? false
		}
		return currentWebViewController?.canScrollDown() ?? false
	}

	func canScrollUp() -> Bool {
		if isShowingStructuredArticleView {
			return structuredArticleViewController?.canScrollUp() ?? false
		}
		return currentWebViewController?.canScrollUp() ?? false
	}

	func scrollPageDown() {
		if isShowingStructuredArticleView {
			structuredArticleViewController?.scrollPageDown()
			return
		}
		currentWebViewController?.scrollPageDown()
	}

	func scrollPageUp() {
		if isShowingStructuredArticleView {
			structuredArticleViewController?.scrollPageUp()
			return
		}
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
		if isShowingStructuredArticleView {
			return
		}
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

	func shouldUseStructuredArticleView(for article: Article?) -> Bool {
		_ = article
		return false
	}

	func updateContentPresentation() {
		let shouldShowStructured = shouldUseStructuredArticleView(for: article)
		pageViewController?.view.isHidden = shouldShowStructured
		structuredArticleViewController?.view.isHidden = !shouldShowStructured
	}

	func configureToolbarAsSingleBlock() {
		guard let ttsBarButtonItem else {
			return
		}

		let items: [UIBarButtonItem] = [
			.flexibleSpace(),
			readBarButtonItem,
			starBarButtonItem,
			prevArticleBarButtonItem,
			nextArticleBarButtonItem,
			actionBarButtonItem,
			ttsBarButtonItem,
			.flexibleSpace()
		]

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

		guard let iconImage = IconImageCache.shared.imageForFeed(iconSource) else {
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
			target: self,
			action: #selector(showCurrentFeedHomepage(_:))
		)
		lastNavigationIconKey = iconKey
	}

}

private final class StructuredArticleContentViewController: UIViewController {
	private struct RowModel {
		let id = UUID()
		let text: NSAttributedString
		let actionURL: URL?
	}

	private struct SectionModel {
		let id = UUID()
		let title: String?
		let rows: [RowModel]
		let collapsible: Bool
	}

	private struct ShowArticleContent: Decodable {
		struct Guest: Decodable {
			let name: String
			let description: String?
		}

		struct TitledContent: Decodable {
			let title: String
			let content: String
		}

		struct Timestamp: Decodable {
			let timestamp: String
			let content: String
		}

		struct Summary: Decodable {
			private enum CodingKeys: String, CodingKey {
				case thesis
				case practical
			}

			let thesis: [TitledContent]
			let practical: [TitledContent]

			init(from decoder: Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				self.thesis = try container.decodeIfPresent([TitledContent].self, forKey: .thesis) ?? []
				self.practical = try container.decodeIfPresent([TitledContent].self, forKey: .practical) ?? []
			}
		}

		private enum CodingKeys: String, CodingKey {
			case guests
			case summary
			case inDepthAnalysis = "in_depth_analysis"
			case timestamps
		}

		let guests: [Guest]
		let summary: Summary?
		let inDepthAnalysis: [TitledContent]
		let timestamps: [Timestamp]
	}

	private struct TopicFeedContainer: Decodable {
		let data: [TopicItem]
	}

	private struct TopicItem: Decodable {
		struct Metadata: Decodable {
			let link: String?
			let author: String?
			let pubDate: String?
		}

		private enum CodingKeys: String, CodingKey {
			case title
			case summary
			case metadata
		}

		let title: String?
		let summary: String?
		let summaryList: [String]
		let metadata: Metadata?

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			title = try container.decodeIfPresent(String.self, forKey: .title)
			metadata = try container.decodeIfPresent(Metadata.self, forKey: .metadata)

			if let list = try? container.decode([String].self, forKey: .summary) {
				summaryList = list
				summary = nil
			} else {
				summary = try container.decodeIfPresent(String.self, forKey: .summary)
				summaryList = []
			}
		}
	}

	private var article: Article?
	private var sectionModels = [SectionModel]()
	private var sectionLookup = [UUID: SectionModel]()
	private var rowLookup = [UUID: RowModel]()
	private var expandedSections = Set<UUID>()
	private var currentHeaderMode: UICollectionLayoutListConfiguration.HeaderMode = .supplementary

	private var collectionView: UICollectionView!
	private var dataSource: UICollectionViewDiffableDataSource<UUID, UUID>!

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = .systemBackground
		configureCollectionView()
		configureDataSource()
		applySnapshot(animated: false)
	}

	func setArticle(_ article: Article?) {
		self.article = article
		rebuildSections()
		applySnapshot(animated: false)
	}

	func articleTextForSpeech() -> String? {
		let rows = sectionModels.flatMap(\.rows)
		guard !rows.isEmpty else {
			return article?.title
		}
		return rows.map { $0.text.string }.joined(separator: "\n\n")
	}

	func canScrollDown() -> Bool {
		return collectionView.contentOffset.y + collectionView.bounds.height < collectionView.contentSize.height - 1
	}

	func canScrollUp() -> Bool {
		return collectionView.contentOffset.y > 1
	}

	func scrollPageDown() {
		let target = min(collectionView.contentOffset.y + (collectionView.bounds.height * 0.8), max(collectionView.contentSize.height - collectionView.bounds.height, 0))
		collectionView.setContentOffset(CGPoint(x: 0, y: target), animated: true)
	}

	func scrollPageUp() {
		let target = max(collectionView.contentOffset.y - (collectionView.bounds.height * 0.8), 0)
		collectionView.setContentOffset(CGPoint(x: 0, y: target), animated: true)
	}
}

private extension StructuredArticleContentViewController {
	private func configureCollectionView() {
		let layout = makeLayout(headerMode: currentHeaderMode)

		collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
		collectionView.translatesAutoresizingMaskIntoConstraints = false
		collectionView.backgroundColor = .clear
		collectionView.delegate = self
		view.addSubview(collectionView)

		NSLayoutConstraint.activate([
			view.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor),
			view.topAnchor.constraint(equalTo: collectionView.topAnchor),
			view.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor)
		])
	}

	private func makeLayout(headerMode: UICollectionLayoutListConfiguration.HeaderMode) -> UICollectionViewCompositionalLayout {
		var listConfig = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
		listConfig.headerMode = headerMode
		return UICollectionViewCompositionalLayout.list(using: listConfig)
	}

	private func updateLayoutHeaderModeIfNeeded(_ mode: UICollectionLayoutListConfiguration.HeaderMode) {
		guard currentHeaderMode != mode else {
			return
		}
		currentHeaderMode = mode
		let newLayout = makeLayout(headerMode: mode)
		collectionView.setCollectionViewLayout(newLayout, animated: false)
	}

	private func configureDataSource() {
		let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, UUID> { [weak self] cell, _, rowID in
			guard let row = self?.rowLookup[rowID] else {
				return
			}

			var content = UIListContentConfiguration.cell()
			content.textProperties.numberOfLines = 0
			content.textProperties.adjustsFontForContentSizeCategory = true
			content.attributedText = self?.displayText(for: row) ?? row.text
			cell.contentConfiguration = content
			cell.isUserInteractionEnabled = row.actionURL != nil
		}

		let headerRegistration = UICollectionView.SupplementaryRegistration<StructuredArticleSectionHeaderView>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] view, _, indexPath in
			guard let self else {
				return
			}
			let sectionID = self.dataSource.snapshot().sectionIdentifiers[indexPath.section]
			guard let section = self.sectionLookup[sectionID],
				  let title = section.title else {
				view.onTap = nil
				return
			}
			let isExpanded = self.expandedSections.contains(sectionID)
			view.configure(title: title, isExpanded: isExpanded, showsDisclosure: section.collapsible)
			if section.collapsible {
				view.onTap = { [weak self] in
					self?.toggleSection(sectionID: sectionID)
				}
			} else {
				view.onTap = nil
			}
		}

		dataSource = UICollectionViewDiffableDataSource<UUID, UUID>(collectionView: collectionView) { collectionView, indexPath, itemID in
			collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: itemID)
		}

		dataSource.supplementaryViewProvider = { [weak self] collectionView, _, indexPath in
			guard let self else { return nil }
			let sectionID = self.dataSource.snapshot().sectionIdentifiers[indexPath.section]
			guard let section = self.sectionLookup[sectionID], section.title != nil else {
				return nil
			}
			return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
		}
	}

	private func toggleSection(sectionID: UUID) {
		guard let section = sectionLookup[sectionID], section.collapsible else {
			return
		}
		if expandedSections.contains(sectionID) {
			expandedSections.remove(sectionID)
		} else {
			expandedSections.insert(sectionID)
		}
		applySnapshot(animated: true)
	}

	private func applySnapshot(animated: Bool) {
		sectionLookup = Dictionary(uniqueKeysWithValues: sectionModels.map { ($0.id, $0) })
		rowLookup = Dictionary(uniqueKeysWithValues: sectionModels.flatMap { section in
			section.rows.map { ($0.id, $0) }
		})

		var snapshot = NSDiffableDataSourceSnapshot<UUID, UUID>()
		let sectionIDs = sectionModels.map(\.id)
		snapshot.appendSections(sectionIDs)

		for section in sectionModels {
			let shouldShowRows = !section.collapsible || expandedSections.contains(section.id)
			if shouldShowRows {
				snapshot.appendItems(section.rows.map(\.id), toSection: section.id)
			}
		}

		dataSource.apply(snapshot, animatingDifferences: animated)
	}

	private func rebuildSections() {
		guard let article,
			  let category = article.feed?.feedCategory else {
			sectionModels = []
			expandedSections = []
			return
		}

		updateLayoutHeaderModeIfNeeded(category == .news ? .none : .supplementary)

		switch category {
		case .podcast, .youtube:
			sectionModels = buildShowSections(from: article.contentJSON)
		case .news:
			sectionModels = buildTopicSections(from: article.contentJSON)
		case .rss:
			sectionModels = []
		}

		expandedSections = Set(sectionModels.filter { $0.collapsible }.map(\.id))
	}

	private func buildShowSections(from jsonString: String?) -> [SectionModel] {
		guard let jsonString,
			  let data = jsonString.data(using: .utf8),
			  let content = try? JSONDecoder().decode(ShowArticleContent.self, from: data) else {
			return [
				SectionModel(
					title: NSLocalizedString("Summary", comment: "Structured article section title"),
					rows: [RowModel(text: attributedBody("Unable to load structured content for this article."), actionURL: nil)],
					collapsible: true
				)
			]
		}

		let guests = SectionModel(
			title: NSLocalizedString("Guest(s)", comment: "Structured article section title"),
			rows: [RowModel(text: bulletedGuests(content.guests), actionURL: nil)],
			collapsible: true
		)

		let summary = SectionModel(
			title: NSLocalizedString("Summary", comment: "Structured article section title"),
			rows: [
				RowModel(text: bulletedSummaryRow(
					rowTitle: NSLocalizedString("Core Thesis", comment: "Structured article summary row title"),
					items: content.summary?.thesis ?? []
				), actionURL: nil),
				RowModel(text: bulletedSummaryRow(
					rowTitle: NSLocalizedString("Practical Applications", comment: "Structured article summary row title"),
					items: content.summary?.practical ?? []
				), actionURL: nil)
			],
			collapsible: true
		)

		let inDepthRows = content.inDepthAnalysis.isEmpty ?
			[RowModel(text: attributedBody("No in-depth analysis available."), actionURL: nil)] :
			content.inDepthAnalysis.map { item in
				RowModel(text: paragraphWithStrongTitle(title: item.title, body: item.content), actionURL: nil)
			}
		let inDepth = SectionModel(
			title: NSLocalizedString("In-Depth Analysis", comment: "Structured article section title"),
			rows: inDepthRows,
			collapsible: true
		)

		let timestamps = SectionModel(
			title: NSLocalizedString("Timestamps", comment: "Structured article section title"),
			rows: [RowModel(text: bulletedTimestamps(content.timestamps), actionURL: nil)],
			collapsible: true
		)

		return [guests, summary, inDepth, timestamps]
	}

	private func buildTopicSections(from jsonString: String?) -> [SectionModel] {
		guard let jsonString,
			  let data = jsonString.data(using: .utf8) else {
			return [
				SectionModel(title: nil, rows: [RowModel(text: attributedBody("No topic content available."), actionURL: nil)], collapsible: false)
			]
		}

		let entries: [TopicItem]
		if let directEntries = try? JSONDecoder().decode([TopicItem].self, from: data) {
			entries = directEntries
		} else {
			let containers = (try? JSONDecoder().decode([TopicFeedContainer].self, from: data)) ??
				((try? JSONDecoder().decode(TopicFeedContainer.self, from: data)).map { [$0] } ?? [])
			entries = containers.flatMap(\.data)
		}
		guard !entries.isEmpty else {
			return [
				SectionModel(title: nil, rows: [RowModel(text: attributedBody("No topic content available."), actionURL: nil)], collapsible: false)
			]
		}

		return entries.map { entry in
			let titleText = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines)
			let summaryText = entry.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
			let linkURL = entry.metadata?.link?.trimmingCharacters(in: .whitespacesAndNewlines)
			let parsedURL = linkURL.flatMap { URL(string: $0) }

			let titleRow = RowModel(
				text: parsedURL == nil
					? attributedTitle(titleText?.isEmpty == false ? titleText! : "Untitled")
					: attributedLinkedTitle(titleText?.isEmpty == false ? titleText! : "Untitled"),
				actionURL: parsedURL
			)
			let metadataRow = RowModel(text: bulletedTopicMetadata(entry.metadata), actionURL: nil)
			let summaryRow = RowModel(
				text: attributedTopicSummary(
					summaryList: entry.summaryList,
					summaryText: summaryText
				),
				actionURL: nil
			)

			return SectionModel(title: nil, rows: [titleRow, metadataRow, summaryRow], collapsible: false)
		}
	}

	private func displayText(for row: RowModel) -> NSAttributedString {
		guard row.actionURL == nil else {
			return row.text
		}
		let cleaned = NSMutableAttributedString(attributedString: row.text)
		let range = NSRange(location: 0, length: cleaned.length)
		cleaned.removeAttribute(.underlineStyle, range: range)
		cleaned.removeAttribute(.link, range: range)
		return cleaned
	}

	private func attributedBody(_ text: String) -> NSAttributedString {
		NSAttributedString(string: text, attributes: [
			.font: UIFont.preferredFont(forTextStyle: .body),
			.foregroundColor: UIColor.label
		])
	}

	private func attributedTitle(_ text: String) -> NSAttributedString {
		NSAttributedString(string: text, attributes: [
			.font: UIFont.preferredFont(forTextStyle: .headline),
			.foregroundColor: UIColor.label
		])
	}

	private func attributedLinkedTitle(_ text: String) -> NSAttributedString {
		NSAttributedString(string: text, attributes: [
			.font: UIFont.preferredFont(forTextStyle: .headline),
			.foregroundColor: UIColor.link,
			.underlineStyle: NSUnderlineStyle.single.rawValue
		])
	}

	private func bulletedTopicMetadata(_ metadata: TopicItem.Metadata?) -> NSAttributedString {
		var lines = [String]()
//		if let author = metadata?.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
//			lines.append("• Author: \(author)")
//		}
//		if let pubDate = metadata?.pubDate?.trimmingCharacters(in: .whitespacesAndNewlines), !pubDate.isEmpty {
//			lines.append("• Published: \(pubDate)")
//		}
//		if let link = metadata?.link?.trimmingCharacters(in: .whitespacesAndNewlines), !link.isEmpty {
//			lines.append("• Link: \(link)")
//		}
//		if lines.isEmpty {
//			lines.append("• No metadata available.")
//		}
		if let author = metadata?.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
			lines.append("Author: \(author)")
		}
		if let pubDate = metadata?.pubDate?.trimmingCharacters(in: .whitespacesAndNewlines), !pubDate.isEmpty {
			lines.append("Published: \(pubDate)")
		}
		if lines.isEmpty {
			lines.append("No metadata available.")
		}
		return NSAttributedString(string: lines.joined(separator: "\n"), attributes: [
			.font: UIFont.preferredFont(forTextStyle: .subheadline),
			.foregroundColor: UIColor.secondaryLabel
		])
	}

	private func attributedTopicSummary(summaryList: [String], summaryText: String?) -> NSAttributedString {
		var lines = [String]()

		if !summaryList.isEmpty {
			lines = summaryList
				.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
				.filter { !$0.isEmpty }
				.map { line in
					let normalized = line.hasPrefix("- ")
						? String(line.dropFirst(2))
						: line
					return "• \(normalized)"
				}
		} else if let summaryText, !summaryText.isEmpty {
			let split = summaryText
				.components(separatedBy: .newlines)
				.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
				.filter { !$0.isEmpty }
			if split.allSatisfy({ $0.hasPrefix("- ") || $0.hasPrefix("• ") }) {
				lines = split.map { line in
					if line.hasPrefix("• ") { return line }
					return "• \(String(line.dropFirst(2)))"
				}
			} else {
				return attributedBody(summaryText)
			}
		}

		if lines.isEmpty {
			return attributedBody("No summary available.")
		}

		return NSAttributedString(string: lines.joined(separator: "\n"), attributes: [
			.font: UIFont.preferredFont(forTextStyle: .body),
			.foregroundColor: UIColor.label
		])
	}

	private func bulletedGuests(_ guests: [ShowArticleContent.Guest]) -> NSAttributedString {
		let body = NSMutableAttributedString()
		if guests.isEmpty {
			body.append(attributedBody("No guests listed."))
			return body
		}
		for (index, guest) in guests.enumerated() {
			let line = NSMutableAttributedString(string: "• \(guest.name)", attributes: [
				.font: UIFont.preferredFont(forTextStyle: .body),
				.foregroundColor: UIColor.label
			])
			if let description = guest.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				line.append(NSAttributedString(string: " - \(description)", attributes: [
					.font: UIFont.preferredFont(forTextStyle: .body),
					.foregroundColor: UIColor.secondaryLabel
				]))
			}
			body.append(line)
			if index < guests.count - 1 {
				body.append(NSAttributedString(string: "\n"))
			}
		}
		return body
	}

	private func bulletedSummaryRow(rowTitle: String, items: [ShowArticleContent.TitledContent]) -> NSAttributedString {
		let result = NSMutableAttributedString(string: rowTitle + "\n\n", attributes: [
			.font: UIFont.preferredFont(forTextStyle: .headline),
			.foregroundColor: UIColor.label
		])
		if items.isEmpty {
			result.append(attributedBody("No items."))
			return result
		}
		for (index, item) in items.enumerated() {
//			let line = NSMutableAttributedString(string: "• ", attributes: [
//				.font: UIFont.preferredFont(forTextStyle: .body),
//				.foregroundColor: UIColor.label
//			])
//			line.append(NSAttributedString(string: item.title, attributes: [
//				.font: UIFont.boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize),
//				.foregroundColor: UIColor.label
//			]))
			let line = NSMutableAttributedString(string: item.title, attributes: [
				.font: UIFont.boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize),
				.foregroundColor: UIColor.label
			])
			line.append(NSAttributedString(string: ": \(item.content)", attributes: [
				.font: UIFont.preferredFont(forTextStyle: .body),
				.foregroundColor: UIColor.label
			]))
			result.append(line)
			if index < items.count - 1 {
				result.append(NSAttributedString(string: "\n\n"))
			}
		}
		return result
	}

	private func paragraphWithStrongTitle(title: String, body: String) -> NSAttributedString {
		let result = NSMutableAttributedString()
		result.append(NSAttributedString(string: "\(title)\n\n" , attributes: [
			.font: UIFont.boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize),
			.foregroundColor: UIColor.label
		]))
		result.append(NSAttributedString(string: body, attributes: [
			.font: UIFont.preferredFont(forTextStyle: .body),
			.foregroundColor: UIColor.label
		]))
		return result
	}

	private func bulletedTimestamps(_ items: [ShowArticleContent.Timestamp]) -> NSAttributedString {
		let result = NSMutableAttributedString()
		if items.isEmpty {
			result.append(attributedBody("No timestamps available."))
			return result
		}
		for (index, item) in items.enumerated() {
			let line = NSMutableAttributedString(string: "• \(item.timestamp)", attributes: [
				.font: UIFont.preferredFont(forTextStyle: .body),
				.foregroundColor: UIColor.label
			])
			if !item.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				line.append(NSAttributedString(string: " - \(item.content)", attributes: [
					.font: UIFont.preferredFont(forTextStyle: .body),
					.foregroundColor: UIColor.secondaryLabel
				]))
			}
			result.append(line)
			if index < items.count - 1 {
				result.append(NSAttributedString(string: "\n"))
			}
		}
		return result
	}
}

extension StructuredArticleContentViewController: UICollectionViewDelegate {
	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		guard let rowID = dataSource.itemIdentifier(for: indexPath),
			  let row = rowLookup[rowID],
			  let url = row.actionURL else {
			return
		}

		collectionView.deselectItem(at: indexPath, animated: true)
		UIApplication.shared.open(url, options: [:])
	}
}

private final class StructuredArticleSectionHeaderView: UICollectionReusableView {
	private let button = UIButton(type: .system)
	var onTap: (() -> Void)?

	override init(frame: CGRect) {
		super.init(frame: frame)
		button.translatesAutoresizingMaskIntoConstraints = false
		button.contentHorizontalAlignment = .fill
		button.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
		addSubview(button)
		NSLayoutConstraint.activate([
			leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: -16),
			trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: 16),
			topAnchor.constraint(equalTo: button.topAnchor),
			bottomAnchor.constraint(equalTo: button.bottomAnchor)
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(title: String, isExpanded: Bool, showsDisclosure: Bool) {
		var configuration = UIButton.Configuration.plain()
		configuration.title = title
		configuration.baseForegroundColor = .label
		configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16)
		if showsDisclosure {
			configuration.image = UIImage(systemName: isExpanded ? "chevron.down" : "chevron.right")
			configuration.imagePlacement = .trailing
			configuration.imagePadding = 8
		} else {
			configuration.image = nil
		}
		configuration.titleAlignment = .leading
		button.configuration = configuration
	}

	@objc private func handleTap() {
		onTap?()
	}
}
