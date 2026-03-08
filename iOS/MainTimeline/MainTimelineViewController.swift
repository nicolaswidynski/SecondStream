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
	private struct RGBA {
		let r: UInt8
		let g: UInt8
		let b: UInt8
		let a: UInt8
	}

	private static let titleContainerWidth: CGFloat = 242
	private static let titleContainerHeight: CGFloat = 34
	private static let topBarIconCache = NSCache<NSString, UIImage>()
	private static let topBarIconCacheVersion = "v10-nav-height-square"

	static func clearTopBarFeedIcon(cacheKey: String?) {
		guard let cacheKey else {
			return
		}
		topBarIconCache.removeObject(forKey: cacheKey as NSString)
		topBarIconCache.removeObject(forKey: namespacedTopBarIconCacheKey(cacheKey))
	}

	private static func namespacedTopBarIconCacheKey(_ cacheKey: String) -> NSString {
		"\(topBarIconCacheVersion)|\(cacheKey)" as NSString
	}

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
			nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: subtitleLabel.leadingAnchor, constant: -10),

			subtitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
			subtitleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
		])

		nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		subtitleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
		container.setContentHuggingPriority(.required, for: .horizontal)
		container.setContentCompressionResistancePriority(.required, for: .horizontal)
		container.isUserInteractionEnabled = false
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

	static func makeTopBarFeedIcon(from iconImage: IconImage, isPseudoFeedIcon: Bool, cacheKey: String? = nil) -> UIImage {
		let namespacedCacheKey = cacheKey.map(namespacedTopBarIconCacheKey)
		if let namespacedCacheKey, let cached = topBarIconCache.object(forKey: namespacedCacheKey) {
			return cached
		}

		// Pseudo feeds (Today / Starred / All Unread) should stay at true 1x sizing.
		if isPseudoFeedIcon {
			let tintColor = iconImage.preferredColor.map(UIColor.init(cgColor:)) ?? Assets.Colors.secondaryAccent
			let symbolConfig = UIImage.SymbolConfiguration(pointSize: 25, weight: .regular)
			let configured = iconImage.image.applyingSymbolConfiguration(symbolConfig) ?? iconImage.image
			let rendered = configured.withTintColor(tintColor, renderingMode: .alwaysOriginal)
			if let namespacedCacheKey {
				topBarIconCache.setObject(rendered, forKey: namespacedCacheKey)
			}
			return rendered
		}

		// Render non-smart feed icons as full-bleed circular images.
		// Match the actual compact nav-bar custom-view height to avoid 44x44->44x36 squeeze.
		let canvasSize = CGSize(width: 36, height: 36)
		let sourceImage = iconImage.image
		let result = UIGraphicsImageRenderer(size: canvasSize).image { _ in
			UIBezierPath(ovalIn: CGRect(origin: .zero, size: canvasSize)).addClip()
			let sourceSize = sourceImage.size
			guard sourceSize.width > 0, sourceSize.height > 0 else {
				return
			}
			let scale = max(canvasSize.width / sourceSize.width, canvasSize.height / sourceSize.height)
			let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
			let origin = CGPoint(x: (canvasSize.width - drawSize.width) / 2, y: (canvasSize.height - drawSize.height) / 2)
			sourceImage.draw(in: CGRect(origin: origin, size: drawSize))
		}.withRenderingMode(.alwaysOriginal)
		if let namespacedCacheKey {
			topBarIconCache.setObject(result, forKey: namespacedCacheKey)
		}
		return result
	}

	private static func trimmedIconImage(from image: UIImage) -> UIImage? {
		guard let alphaTrimmed = trimmedTransparentImage(from: image) else {
			return nil
		}
		return trimmedFlatBorderImage(from: alphaTrimmed) ?? alphaTrimmed
	}

	private static func trimmedTransparentImage(from image: UIImage) -> UIImage? {
		let normalized = UIGraphicsImageRenderer(size: image.size).image { _ in
			image.draw(in: CGRect(origin: .zero, size: image.size))
		}
		guard let cgImage = normalized.cgImage else {
			return nil
		}

		let width = cgImage.width
		let height = cgImage.height
		guard width > 0, height > 0 else {
			return nil
		}

		let bytesPerPixel = 4
		let bytesPerRow = width * bytesPerPixel
		var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
		guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
			  let context = CGContext(data: &pixels,
								 width: width,
								 height: height,
								 bitsPerComponent: 8,
								 bytesPerRow: bytesPerRow,
								 space: colorSpace,
								 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
			return nil
		}

		context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

		var minX = width
		var minY = height
		var maxX = 0
		var maxY = 0
		var foundOpaque = false
		let alphaThreshold: UInt8 = 8

		for y in 0..<height {
			for x in 0..<width {
				let alpha = pixels[(y * bytesPerRow) + (x * bytesPerPixel) + 3]
				if alpha > alphaThreshold {
					foundOpaque = true
					minX = min(minX, x)
					minY = min(minY, y)
					maxX = max(maxX, x)
					maxY = max(maxY, y)
				}
			}
		}

		guard foundOpaque else {
			return nil
		}

		let cropRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
		guard let cropped = cgImage.cropping(to: cropRect) else {
			return nil
		}

		return UIImage(cgImage: cropped, scale: normalized.scale, orientation: .up)
	}

	private static func trimmedFlatBorderImage(from image: UIImage) -> UIImage? {
		guard let cgImage = image.cgImage else {
			return nil
		}

		let width = cgImage.width
		let height = cgImage.height
		guard width > 6, height > 6 else {
			return image
		}

		let bytesPerPixel = 4
		let bytesPerRow = width * bytesPerPixel
		var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
		guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
			  let context = CGContext(data: &pixels,
								 width: width,
								 height: height,
								 bitsPerComponent: 8,
								 bytesPerRow: bytesPerRow,
								 space: colorSpace,
								 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
			return image
		}

		context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

		func pixel(atX x: Int, y: Int) -> RGBA {
			let i = (y * bytesPerRow) + (x * bytesPerPixel)
			return RGBA(r: pixels[i], g: pixels[i + 1], b: pixels[i + 2], a: pixels[i + 3])
		}

		let cornerColors = [
			pixel(atX: 0, y: 0),
			pixel(atX: width - 1, y: 0),
			pixel(atX: 0, y: height - 1),
			pixel(atX: width - 1, y: height - 1)
		]

		func isSimilar(_ p1: RGBA, _ p2: RGBA, tolerance: Int = 24) -> Bool {
			let dr = abs(Int(p1.r) - Int(p2.r))
			let dg = abs(Int(p1.g) - Int(p2.g))
			let db = abs(Int(p1.b) - Int(p2.b))
			let da = abs(Int(p1.a) - Int(p2.a))
			return dr <= tolerance && dg <= tolerance && db <= tolerance && da <= tolerance
		}

		func looksLikeBorderPixel(_ pixel: RGBA) -> Bool {
			guard pixel.a > 8 else {
				return true
			}
			for corner in cornerColors where isSimilar(pixel, corner) {
				return true
			}
			return false
		}

		func edgeLooksLikeBorder(minX: Int, maxX: Int, minY: Int, maxY: Int) -> Bool {
			var borderPixels = 0
			var total = 0
			for y in minY...maxY {
				for x in minX...maxX {
					total += 1
					if looksLikeBorderPixel(pixel(atX: x, y: y)) {
						borderPixels += 1
					}
				}
			}
			guard total > 0 else {
				return false
			}
			return CGFloat(borderPixels) / CGFloat(total) > 0.92
		}

		var minX = 0
		var maxX = width - 1
		var minY = 0
		var maxY = height - 1

		while minY < maxY - 2 && edgeLooksLikeBorder(minX: minX, maxX: maxX, minY: minY, maxY: minY) {
			minY += 1
		}
		while maxY > minY + 2 && edgeLooksLikeBorder(minX: minX, maxX: maxX, minY: maxY, maxY: maxY) {
			maxY -= 1
		}
		while minX < maxX - 2 && edgeLooksLikeBorder(minX: minX, maxX: minX, minY: minY, maxY: maxY) {
			minX += 1
		}
		while maxX > minX + 2 && edgeLooksLikeBorder(minX: maxX, maxX: maxX, minY: minY, maxY: maxY) {
			maxX -= 1
		}

		guard minX > 0 || minY > 0 || maxX < width - 1 || maxY < height - 1 else {
			return image
		}

		let cropRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
		guard cropRect.width > 0, cropRect.height > 0, let cropped = cgImage.cropping(to: cropRect) else {
			return image
		}
		return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
	}

	static func makeTopBarFeedBarButton(iconImage: IconImage, isPseudoFeedIcon: Bool, cacheKey: String? = nil, target: Any?, action: Selector?) -> UIBarButtonItem {
		let icon = makeTopBarFeedIcon(from: iconImage, isPseudoFeedIcon: isPseudoFeedIcon, cacheKey: cacheKey).withRenderingMode(.alwaysOriginal)
		return makeTopBarFeedBarButton(image: icon, fillsCircularButton: !isPseudoFeedIcon, target: target, action: action)
	}

	static func makeTopBarFeedBarButton(image: UIImage, fillsCircularButton: Bool = true, target: Any?, action: Selector?) -> UIBarButtonItem {
		// Keep custom icon buttons square to the real nav-bar slot height.
		let size: CGFloat = fillsCircularButton ? 36 : 30
		let iconButton = UIButton(type: .custom)
		iconButton.frame = CGRect(x: 0, y: 0, width: size, height: size)
		iconButton.translatesAutoresizingMaskIntoConstraints = false

		if fillsCircularButton {
			iconButton.setBackgroundImage(image.withRenderingMode(.alwaysOriginal), for: .normal)
		} else {
			iconButton.setImage(image.withRenderingMode(.alwaysOriginal), for: .normal)
			iconButton.imageView?.contentMode = .scaleAspectFit
		}

		iconButton.layer.cornerRadius = size / 2
		iconButton.layer.masksToBounds = true
		iconButton.clipsToBounds = true
		iconButton.backgroundColor = .clear

		if let target = target, let action = action {
			iconButton.addTarget(target, action: action, for: .touchUpInside)
		}

		NSLayoutConstraint.activate([
			iconButton.widthAnchor.constraint(equalToConstant: size),
			iconButton.heightAnchor.constraint(equalToConstant: size)
		])

		return UIBarButtonItem(customView: iconButton)
	}
}

final class MainTimelineViewController: UITableViewController, UndoableCommandRunner {

	private var numberOfTextLines = 0
	private var iconSize = IconSize.medium
	private var refreshProgressView: RefreshProgressView?

	@IBOutlet var markAllAsReadButton: UIBarButtonItem?

	private lazy var filterButton = UIBarButtonItem(image: Assets.Images.filter, style: .plain, target: self, action: #selector(toggleFilter(_:)))
	private lazy var firstUnreadButton = UIBarButtonItem(image: Assets.Images.nextUnread, style: .plain, target: self, action: #selector(firstUnread(_:)))
	private lazy var longPressStarToggleGestureRecognizer: UILongPressGestureRecognizer = {
		let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressToggleStar(_:)))
		gesture.minimumPressDuration = 0.45
		gesture.allowableMovement = 14
		return gesture
	}()

	private lazy var dataSource = makeDataSource()
	private let searchController = UISearchController(searchResultsController: nil)

	weak var coordinator: SceneCoordinator?
	var undoableCommands = [UndoableCommand]()
	let scrollPositionQueue = CoalescingQueue(name: "Timeline Scroll Position", interval: 0.3, maxInterval: 1.0)
	private var shouldFadeInNavigationSubtitle = false
	private var lastNavigationIconKey: String?
	private(set) var lastRowDistanceAnimationDuration: CFTimeInterval = 0.40
	private(set) var lastRowDistanceMaxDistance: Int = 0
	private(set) var lastRowDistanceListCount: Int = 0
	private(set) var lastRowDistanceUsedDistance: Int = 0
	private(set) var lastRowDistanceReferenceDistance: Int?
	private(set) var lastRowDistanceReferenceOldIndex: Int?
	private(set) var lastRowDistanceReferenceNewIndex: Int?
	private(set) var lastRowDistanceResolvedReferenceArticleID: String?
	private(set) var lastRowDistanceMode: String = "fallback"
	private(set) var lastRowDistanceHardJumpApplied: Bool = false
	private(set) var lastRowDistanceHardJumpThreshold: Int = 0
	private(set) var lastRowDistanceHardJumpTailDistance: Int = 0
	private(set) var lastRowDistanceRawDuration: CFTimeInterval = 0
	private(set) var lastRowDistanceMinApplied: Bool = false
	private var rowDistanceReferenceArticleID: String?
	private var elevatedRowArticleID: String?
	private let elevatedCellZPosition: CGFloat = 1000
	private let rowDistanceSecondsPerRow: CFTimeInterval = 0.05
	private let rowDistanceNoMovementDuration: CFTimeInterval = 0.040
	private let rowDistanceMinDuration: CFTimeInterval = 0.22
	private let rowAnimationBaselineDuration: CFTimeInterval = 0.35
	private let hardJumpTailEnabled = true
	var debugRowDistanceSecondsPerRow: CFTimeInterval { rowDistanceSecondsPerRow }

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

		tableView.addGestureRecognizer(longPressStarToggleGestureRecognizer)

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
		updateNavigationFeedIcon()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		navigationController?.setNavigationBarHidden(false, animated: false)
		self.navigationController?.isToolbarHidden = false
		shouldFadeInNavigationSubtitle = true
		if let subtitleText = FeedNavigationChrome.subtitleText(in: navigationItem.titleView), !subtitleText.isEmpty {
			FeedNavigationChrome.setSubtitleAlpha(0, in: navigationItem.titleView)
		}

		// If the nav bar is hidden, fade it in to avoid it showing stuff as it is getting laid out
		if navigationController?.navigationBar.isHidden ?? false {
			navigationController?.navigationBar.alpha = 0
		}
		
		updateNavigationBarTitle(coordinator?.timelineFeed?.nameForDisplay ?? "")
		coordinator?.updateNavigationBarSubtitles(nil)
		updateNavigationFeedIcon()
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
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
		coordinator?.openHomepageForCurrentTimelineFeed()
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
		// Allow native iOS back-swipe from the leading edge.
		return nil
	}

	override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		true
	}

	override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		guard let article = dataSource.itemIdentifier(for: indexPath) else {
			return nil
		}

		let readAction = UIContextualAction(style: .normal, title: nil) { [weak self] _, _, completion in
			self?.coordinator?.toggleRead(article)
			completion(true)
		}
		readAction.image = article.status.read ? Assets.Images.circleClosed : Assets.Images.circleOpen
		readAction.backgroundColor = Assets.Colors.secondaryAccent

		let config = UISwipeActionsConfiguration(actions: [readAction])
		config.performsFirstActionWithFullSwipe = true
		return config
	}

	override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
		return nil
	}

	@objc private func handleLongPressToggleStar(_ gesture: UILongPressGestureRecognizer) {
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
		coordinator?.toggleStar(article)
	}

	private func animateDoubleFlash(on cell: UITableViewCell) {
		if traitCollection.userInterfaceStyle == .dark {
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
			return
		}

		let flashView = UIView(frame: cell.bounds)
		flashView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		flashView.backgroundColor = .white
		flashView.alpha = 0
		flashView.isUserInteractionEnabled = false
		cell.contentView.addSubview(flashView)

		let secondFlashView = UIView(frame: cell.bounds)
		secondFlashView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		secondFlashView.backgroundColor = .black
		secondFlashView.alpha = 0
		secondFlashView.isUserInteractionEnabled = false
		cell.contentView.addSubview(secondFlashView)

		UIView.animateKeyframes(withDuration: 0.72, delay: 0, options: [.allowUserInteraction, .calculationModeLinear]) {
			UIView.addKeyframe(withRelativeStartTime: 0.00, relativeDuration: 0.16) {
				flashView.alpha = 0.32
			}
			UIView.addKeyframe(withRelativeStartTime: 0.16, relativeDuration: 0.18) {
				flashView.alpha = 0
			}

			UIView.addKeyframe(withRelativeStartTime: 0.42, relativeDuration: 0.14) {
				secondFlashView.alpha = 0.22
			}
			UIView.addKeyframe(withRelativeStartTime: 0.56, relativeDuration: 0.20) {
				secondFlashView.alpha = 0
			}
		} completion: { _ in
			Task { @MainActor in
				flashView.removeFromSuperview()
				secondFlashView.removeFromSuperview()
			}
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		becomeFirstResponder()
		let article = dataSource.itemIdentifier(for: indexPath)
		coordinator?.selectArticle(article, animations: [.scroll, .select, .navigation])
	}

	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		let isElevated = dataSource.itemIdentifier(for: indexPath).map { $0.articleID == elevatedRowArticleID } ?? false
		cell.layer.zPosition = isElevated ? elevatedCellZPosition : 0
		if isElevated {
			tableView.bringSubviewToFront(cell)
		}
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
		refreshVisibleCells(for: articleIDs)
	}

	private func refreshVisibleCells(for articleIDs: Set<String>) {
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
		if (timelineFeed as? Feed) == feed {
			let iconKey = String(describing: feed.sidebarItemID)
			FeedNavigationChrome.clearTopBarFeedIcon(cacheKey: iconKey)
			lastNavigationIconKey = nil
			updateNavigationFeedIcon()
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
		updateNavigationFeedIcon()
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

// MARK: Private

private extension MainTimelineViewController {

	func updateNavigationFeedIcon() {
		let iconImage: IconImage?
		let iconSource: SidebarItem?
		if let feed = timelineFeed as? Feed {
			iconImage = IconImageCache.shared.imageForFeed(feed)
			iconSource = feed
		} else if let pseudoFeed = timelineFeed as? PseudoFeed {
			iconImage = pseudoFeed.smallIcon
			iconSource = pseudoFeed
		} else {
			iconImage = nil
			iconSource = nil
		}

		guard let iconImage else {
			// Avoid transient icon pop-out while data/icon caches settle during transitions.
			if timelineFeed == nil {
				navigationItem.rightBarButtonItem = nil
				lastNavigationIconKey = nil
			}
			return
		}

		let iconKey = String(describing: iconSource?.sidebarItemID)
		if iconKey == lastNavigationIconKey, navigationItem.rightBarButtonItem != nil {
			return
		}

		let isPseudoFeedIcon = timelineFeed is PseudoFeed
		navigationItem.rightBarButtonItem = FeedNavigationChrome.makeTopBarFeedBarButton(
			iconImage: iconImage,
			isPseudoFeedIcon: isPseudoFeedIcon,
			cacheKey: iconKey,
			target: self,
			action: #selector(showFeedInspector(_:))
		)
		lastNavigationIconKey = iconKey
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
		updateNavigationFeedIcon()

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

		let previousItems = dataSource.snapshot().itemIdentifiers
		let finalItems = articles ?? ArticleArray()
		let finalSnapshot = makeTimelineSnapshot(with: finalItems)

		if animated {
			var animationDuration = rowDistanceAnimationDuration(previousItems: previousItems, newItems: finalItems)
			setElevatedRowArticleID(lastRowDistanceResolvedReferenceArticleID)
			rowDistanceReferenceArticleID = nil // one-shot reference for the next diff

			if let hardJump = hardJumpPlan(previousItems: previousItems, newItems: finalItems) {
				lastRowDistanceHardJumpApplied = true
				lastRowDistanceHardJumpThreshold = hardJump.threshold
				lastRowDistanceHardJumpTailDistance = hardJump.tailDistance
				lastRowDistanceMode = "reference-hard-jump"
				lastRowDistanceUsedDistance = hardJump.phaseDistance
				let rawDuration = rowDistanceSecondsPerRow * CFTimeInterval(hardJump.phaseDistance)
				lastRowDistanceRawDuration = rawDuration
				lastRowDistanceMinApplied = rawDuration < rowDistanceMinDuration
				animationDuration = max(rawDuration, rowDistanceMinDuration)
				lastRowDistanceAnimationDuration = animationDuration
				let resolvedReferenceID = lastRowDistanceResolvedReferenceArticleID

				let intermediateSnapshot = makeTimelineSnapshot(with: hardJump.items)
				applyAnimatedSnapshot(intermediateSnapshot, duration: animationDuration) { [weak self] in
					guard let self else {
						completion?()
						return
					}

					var shouldFinalizeWithHardJump = true
					if let resolvedReferenceID,
					   let currentIndex = self.dataSource.snapshot().itemIdentifiers.firstIndex(where: { $0.articleID == resolvedReferenceID }),
					   let finalIndex = finalItems.firstIndex(where: { $0.articleID == resolvedReferenceID }) {
						shouldFinalizeWithHardJump = currentIndex != finalIndex
					}

					guard shouldFinalizeWithHardJump else {
						self.restoreSelectionIfNecessary(adjustScroll: false)
						self.clearElevatedRowArticleID()
						completion?()
						return
					}

					self.dataSource.apply(finalSnapshot, animatingDifferences: false) { [weak self] in
						self?.restoreSelectionIfNecessary(adjustScroll: false)
						self?.clearElevatedRowArticleID()
						completion?()
					}
				}
				return
			} else {
				lastRowDistanceHardJumpApplied = false
				lastRowDistanceHardJumpThreshold = 0
				lastRowDistanceHardJumpTailDistance = 0
			}

			applyAnimatedSnapshot(finalSnapshot, duration: animationDuration) { [weak self] in
				self?.restoreSelectionIfNecessary(adjustScroll: false)
				self?.clearElevatedRowArticleID()
				completion?()
			}
		} else {
			rowDistanceReferenceArticleID = nil
			lastRowDistanceHardJumpApplied = false
			lastRowDistanceHardJumpThreshold = 0
			lastRowDistanceHardJumpTailDistance = 0
			clearElevatedRowArticleID()
			dataSource.apply(finalSnapshot, animatingDifferences: false) { [weak self] in
				self?.restoreSelectionIfNecessary(adjustScroll: false)
				completion?()
			}
		}
	}

	private func applyAnimatedSnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Int, Article>, duration: CFTimeInterval, completion: (() -> Void)? = nil) {
		let clampedDuration = max(duration, rowDistanceNoMovementDuration)
		let targetSpeed = Float(rowAnimationBaselineDuration / clampedDuration)
		let shouldAdjustSpeed = abs(targetSpeed - 1.0) > 0.01

		let originalSpeed = tableView.layer.speed
		let originalTimeOffset = tableView.layer.timeOffset
		let originalBeginTime = tableView.layer.beginTime

		if shouldAdjustSpeed {
			tableView.layer.speed = targetSpeed
			tableView.layer.timeOffset = 0
			tableView.layer.beginTime = 0
		}

		CATransaction.begin()
		CATransaction.setAnimationDuration(clampedDuration)
		CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
		dataSource.apply(snapshot, animatingDifferences: true) { [weak self] in
			guard let self else {
				completion?()
				return
			}
			if shouldAdjustSpeed {
				self.tableView.layer.speed = originalSpeed
				self.tableView.layer.timeOffset = originalTimeOffset
				self.tableView.layer.beginTime = originalBeginTime
			}
			completion?()
		}
		CATransaction.commit()
	}

	private func rowDistanceAnimationDuration(previousItems: [Article], newItems: [Article]) -> CFTimeInterval {
		lastRowDistanceListCount = newItems.count
		lastRowDistanceMaxDistance = 0
		lastRowDistanceUsedDistance = 0
		lastRowDistanceReferenceDistance = nil
		lastRowDistanceReferenceOldIndex = nil
		lastRowDistanceReferenceNewIndex = nil
		lastRowDistanceResolvedReferenceArticleID = nil
		lastRowDistanceMode = "fallback"

		if coordinator?.consumeBypassRowDistanceAnimation() == true {
			lastRowDistanceMode = "bypass"
			lastRowDistanceRawDuration = rowDistanceNoMovementDuration
			lastRowDistanceMinApplied = false
			lastRowDistanceAnimationDuration = rowDistanceNoMovementDuration
			return rowDistanceNoMovementDuration
		}

		guard !previousItems.isEmpty, !newItems.isEmpty else {
			lastRowDistanceRawDuration = rowDistanceNoMovementDuration
			lastRowDistanceMinApplied = false
			lastRowDistanceAnimationDuration = rowDistanceNoMovementDuration
			return rowDistanceNoMovementDuration
		}

		let previousIndexByID = Dictionary(uniqueKeysWithValues: previousItems.enumerated().map { ($1.articleID, $0) })
		var maxDistance = 0

		for (newIndex, article) in newItems.enumerated() {
			guard let oldIndex = previousIndexByID[article.articleID] else {
				continue
			}
			maxDistance = max(maxDistance, abs(newIndex - oldIndex))
		}
		lastRowDistanceMaxDistance = maxDistance

		var referenceDistance: Int?
		var resolvedReferenceID: String?
		if let referenceID = rowDistanceReferenceArticleID,
		   let oldIndex = previousIndexByID[referenceID] {
			resolvedReferenceID = referenceID
			lastRowDistanceReferenceOldIndex = oldIndex
			if let newIndex = newItems.firstIndex(where: { $0.articleID == referenceID }) {
				lastRowDistanceReferenceNewIndex = newIndex
				referenceDistance = abs(newIndex - oldIndex)
			}
		}
		if referenceDistance == nil,
		   let fallbackID = coordinator?.consumeRowDistanceReferenceArticleID(),
		   let oldIndex = previousIndexByID[fallbackID] {
			resolvedReferenceID = fallbackID
			lastRowDistanceReferenceOldIndex = oldIndex
			if let newIndex = newItems.firstIndex(where: { $0.articleID == fallbackID }) {
				lastRowDistanceReferenceNewIndex = newIndex
				referenceDistance = abs(newIndex - oldIndex)
			}
		}
		lastRowDistanceResolvedReferenceArticleID = resolvedReferenceID
		lastRowDistanceReferenceDistance = referenceDistance

		let usedDistance = referenceDistance ?? maxDistance
		lastRowDistanceUsedDistance = usedDistance
		lastRowDistanceMode = (referenceDistance != nil) ? "reference" : "max"

		guard usedDistance > 0 else {
			lastRowDistanceRawDuration = rowDistanceNoMovementDuration
			lastRowDistanceMinApplied = false
			lastRowDistanceAnimationDuration = rowDistanceNoMovementDuration
			return rowDistanceNoMovementDuration
		}

		let rawDuration = rowDistanceSecondsPerRow * CFTimeInterval(usedDistance)
		let finalDuration = max(rawDuration, rowDistanceMinDuration)
		lastRowDistanceRawDuration = rawDuration
		lastRowDistanceMinApplied = rawDuration < rowDistanceMinDuration
		lastRowDistanceAnimationDuration = finalDuration
		return finalDuration
	}

	private func makeTimelineSnapshot(with items: [Article]) -> NSDiffableDataSourceSnapshot<Int, Article> {
		var snapshot = NSDiffableDataSourceSnapshot<Int, Article>()
		snapshot.appendSections([0])
		snapshot.appendItems(items, toSection: 0)
		return snapshot
	}

	private func hardJumpPlan(previousItems: [Article], newItems: [Article]) -> (items: [Article], phaseDistance: Int, threshold: Int, tailDistance: Int)? {
		guard hardJumpTailEnabled,
			  lastRowDistanceMode == "reference",
			  let referenceID = lastRowDistanceResolvedReferenceArticleID,
			  let oldIndex = lastRowDistanceReferenceOldIndex,
			  let newIndex = lastRowDistanceReferenceNewIndex else {
			return nil
		}

		let totalDistance = abs(newIndex - oldIndex)
		guard totalDistance > 0 else {
			return nil
		}

		let threshold = visibleRowThreshold()
		guard totalDistance > threshold else {
			return nil
		}

		var intermediateItems = previousItems
		guard let currentReferenceIndex = intermediateItems.firstIndex(where: { $0.articleID == referenceID }) else {
			return nil
		}

		let referenceArticle = intermediateItems.remove(at: currentReferenceIndex)
		let direction = (newIndex > oldIndex) ? 1 : -1
		let targetIntermediateIndex = oldIndex + (direction * threshold)
		let clampedIntermediateIndex = max(0, min(targetIntermediateIndex, intermediateItems.count))
		intermediateItems.insert(referenceArticle, at: clampedIntermediateIndex)

		let phaseDistance = threshold
		let tailDistance = totalDistance - threshold
		return (intermediateItems, phaseDistance, threshold, tailDistance)
	}

	private func visibleRowThreshold() -> Int {
		let visibleRowHeights: [CGFloat] = (tableView.indexPathsForVisibleRows ?? []).compactMap { indexPath in
			let height = tableView.rectForRow(at: indexPath).height
			return height > 1 ? height : nil
		}
		let approximateRowHeight: CGFloat
		if !visibleRowHeights.isEmpty {
			approximateRowHeight = visibleRowHeights.reduce(0, +) / CGFloat(visibleRowHeights.count)
		} else if tableView.estimatedRowHeight > 1 {
			approximateRowHeight = tableView.estimatedRowHeight
		} else {
			approximateRowHeight = tableView.rowHeight > 1 ? tableView.rowHeight : 44
		}
		let visibleCount = Int(ceil(tableView.bounds.height / approximateRowHeight))
		let visibilityBuffer = 4
		return max(1, visibleCount + visibilityBuffer)
	}

	private func setElevatedRowArticleID(_ articleID: String?) {
		elevatedRowArticleID = articleID
		updateVisibleCellElevation()
	}

	private func clearElevatedRowArticleID() {
		elevatedRowArticleID = nil
		updateVisibleCellElevation()
	}

	private func updateVisibleCellElevation() {
		guard let visibleIndexPaths = tableView.indexPathsForVisibleRows else {
			return
		}

		for indexPath in visibleIndexPaths {
			guard let cell = tableView.cellForRow(at: indexPath) else {
				continue
			}
			let isElevated = dataSource.itemIdentifier(for: indexPath).map { $0.articleID == elevatedRowArticleID } ?? false
			cell.layer.zPosition = isElevated ? elevatedCellZPosition : 0
			if isElevated {
				tableView.bringSubviewToFront(cell)
			}
		}
	}

	func captureRowDistanceReferenceArticleID(_ articleID: String?) {
		rowDistanceReferenceArticleID = articleID
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
		rowDistanceReferenceArticleID = article.articleID
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
