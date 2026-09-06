//
//  RootSplitViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 9/4/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import Account

final class RootSplitViewController: UISplitViewController {

	var coordinator: SceneCoordinator! {
		didSet {
			leftMenuViewController?.coordinator = coordinator
		}
	}

	private var miniPlayerView: MiniPlayerView?
	private var miniPlayerBottomConstraint: NSLayoutConstraint?

	// MARK: - Left Side Menu Drawer

	private let leftMenuWidth: CGFloat = 280
	private var leftMenuViewController: LeftSideMenuViewController?
	private var leftMenuDimView: UIView?
	private var leftMenuLeadingConstraint: NSLayoutConstraint?
	private var isLeftMenuOpen = false
	private var panStartX: CGFloat = 0

	override var prefersStatusBarHidden: Bool {
		return coordinator.prefersStatusBarHidden
	}

	override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
		return .slide
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = Assets.Colors.background
		setupMiniPlayer()
		setupLeftMenuDrawer()
	}

	// MARK: - Scene Pane Styling

	private let styledColumns: [Column] = [.supplementary, .secondary]
	private var styledPaneViews = Set<ObjectIdentifier>()

	private func targetPaneView(for vc: UIViewController) -> UIView {
		if let navView = vc.navigationController?.view { return navView }
		return vc.view
	}

	override func setViewController(_ vc: UIViewController?, for column: Column) {
		super.setViewController(vc, for: column)
		guard styledColumns.contains(column), let vc else { return }
		let target = targetPaneView(for: vc)
		applyScenePaneStyle(to: target)
		styledPaneViews.insert(ObjectIdentifier(target))
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		for column in styledColumns {
			guard let vc = viewController(for: column) else { continue }
			let target = targetPaneView(for: vc)
			let id = ObjectIdentifier(target)
			if !styledPaneViews.contains(id) {
				applyScenePaneStyle(to: target)
				styledPaneViews.insert(id)
			}
		}
	}

	private func applyScenePaneStyle(to view: UIView) {
		view.layer.cornerRadius = Assets.Colors.scenePaneCornerRadius
		view.layer.cornerCurve = .continuous
		view.clipsToBounds = true
	}

	override func viewDidAppear(_ animated: Bool) {
		coordinator.resetFocus()
	}

	private func setupMiniPlayer() {
		let playerView = MiniPlayerView()
		playerView.translatesAutoresizingMaskIntoConstraints = false
		playerView.isHidden = true
		view.addSubview(playerView)

		let bottomConstraint = playerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
		NSLayoutConstraint.activate([
			playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			playerView.heightAnchor.constraint(equalToConstant: 130),
			bottomConstraint
		])

		miniPlayerView = playerView
		miniPlayerBottomConstraint = bottomConstraint
	}

	override func show(_ column: UISplitViewController.Column) {
		guard !coordinator.isNavigationDisabled else { return }

		/// Always show the column on iPhone
		if UIDevice.current.userInterfaceIdiom == .phone {
			super.show(column)
			return
		}

		/// In certain scenarios, we don't want to select a feed or article
		/// and have the display mode change as this interferes with state
		/// restoration of the feeds and timeline display modes.

		/// Don't show primary when the preferred display mode is timeline + article or article only.
		if column == .primary && (preferredDisplayMode == .oneBesideSecondary || preferredDisplayMode == .secondaryOnly) {
			return
		}

		/// Don't show the timeline when the preferred display mode is article only.
		if column == .supplementary && preferredDisplayMode == .secondaryOnly {
			return
		}

		super.show(column)
	}

	// MARK: - Left Menu Drawer

	private func setupLeftMenuDrawer() {
		let menuVC = LeftSideMenuViewController()
		menuVC.coordinator = coordinator
		addChild(menuVC)

		let menuView = menuVC.view!
		menuView.translatesAutoresizingMaskIntoConstraints = false
		// Start off-screen to the left
		menuView.transform = CGAffineTransform(translationX: -leftMenuWidth, y: 0)

		// Dim overlay — sits behind the menu, above the content
		let dimView = UIView()
		dimView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
		dimView.alpha = 0
		dimView.isHidden = true
		dimView.translatesAutoresizingMaskIntoConstraints = false
		let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dimViewTapped))
		dimView.addGestureRecognizer(tapGesture)

		view.addSubview(dimView)
		view.addSubview(menuView)
		menuVC.didMove(toParent: self)

		NSLayoutConstraint.activate([
			dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			dimView.topAnchor.constraint(equalTo: view.topAnchor),
			dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			menuView.topAnchor.constraint(equalTo: view.topAnchor),
			menuView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			menuView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			menuView.widthAnchor.constraint(equalToConstant: leftMenuWidth),
		])

		leftMenuViewController = menuVC
		leftMenuDimView = dimView

		let pan = UIPanGestureRecognizer(target: self, action: #selector(handleMenuPan(_:)))
		pan.delegate = self
		view.addGestureRecognizer(pan)
	}

	func showLeftMenu() {
		guard !isLeftMenuOpen else { return }
		UIImpactFeedbackGenerator(style: .medium).impactOccurred()
		isLeftMenuOpen = true
		leftMenuDimView?.isHidden = false
		UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: []) {
			self.leftMenuViewController?.view.transform = .identity
			self.leftMenuDimView?.alpha = 1
		}
	}

	func hideLeftMenu(completion: (() -> Void)? = nil) {
		guard isLeftMenuOpen else {
			completion?()
			return
		}
		isLeftMenuOpen = false
		UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseIn) {
			self.leftMenuViewController?.view.transform = CGAffineTransform(translationX: -self.leftMenuWidth, y: 0)
			self.leftMenuDimView?.alpha = 0
		} completion: { _ in
			self.leftMenuDimView?.isHidden = true
			self.leftMenuViewController?.resetNavigation()
			completion?()
		}
	}

	@objc private func dimViewTapped() {
		hideLeftMenu()
	}

	@objc private func handleMenuPan(_ gesture: UIPanGestureRecognizer) {
		let translation = gesture.translation(in: view).x
		let velocity = gesture.velocity(in: view).x

		guard let menuView = leftMenuViewController?.view else { return }

		switch gesture.state {
		case .began:
			panStartX = isLeftMenuOpen ? 0 : -leftMenuWidth
			if !isLeftMenuOpen {
				leftMenuDimView?.isHidden = false
			}
		case .changed:
			let newX = max(-leftMenuWidth, min(0, panStartX + translation))
			menuView.transform = CGAffineTransform(translationX: newX, y: 0)
			let progress = (newX + leftMenuWidth) / leftMenuWidth
			leftMenuDimView?.alpha = progress
		case .ended, .cancelled:
			let currentX = menuView.transform.tx
			let progress = (currentX + leftMenuWidth) / leftMenuWidth
			let shouldOpen = velocity > 300 || (velocity > -300 && progress > 0.4)
			if shouldOpen {
				if !isLeftMenuOpen {
					UIImpactFeedbackGenerator(style: .medium).impactOccurred()
				}
				isLeftMenuOpen = true
				let springVel = max(0, velocity) / max(1, abs(currentX))
				UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: springVel, options: []) {
					menuView.transform = .identity
					self.leftMenuDimView?.alpha = 1
				}
			} else {
				isLeftMenuOpen = false
				UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseIn) {
					menuView.transform = CGAffineTransform(translationX: -self.leftMenuWidth, y: 0)
					self.leftMenuDimView?.alpha = 0
				} completion: { _ in
					self.leftMenuDimView?.isHidden = true
					self.leftMenuViewController?.resetNavigation()
				}
			}
		default:
			break
		}
	}

	// MARK: Keyboard Shortcuts

	@objc func scrollOrGoToNextUnread(_ sender: Any?) {
		coordinator.scrollOrGoToNextUnread()
	}

	@objc func scrollUp(_ sender: Any?) {
		coordinator.scrollUp()
	}

	@objc func goToPreviousUnread(_ sender: Any?) {
		coordinator.selectPrevUnread()
	}

	@objc func nextUnread(_ sender: Any?) {
		coordinator.selectNextUnread()
	}

	@objc func markRead(_ sender: Any?) {
		coordinator.markAsReadForCurrentArticle()
	}

	@objc func markUnreadAndGoToNextUnread(_ sender: Any?) {
		coordinator.markAsUnreadForCurrentArticle()
		coordinator.selectNextUnread()
	}

	@objc func markAllAsReadAndGoToNextUnread(_ sender: Any?) {
		coordinator.markAllAsReadInTimeline {
			self.coordinator.selectNextUnread()
		}
	}

	@objc func markAboveAsRead(_ sender: Any?) {
		coordinator.markAboveAsRead()
	}

	@objc func markBelowAsRead(_ sender: Any?) {
		coordinator.markBelowAsRead()
	}

	@objc func markUnread(_ sender: Any?) {
		coordinator.markAsUnreadForCurrentArticle()
	}

	@objc func goToPreviousSubscription(_ sender: Any?) {
		coordinator.selectPrevFeed()
	}

	@objc func goToNextSubscription(_ sender: Any?) {
		coordinator.selectNextFeed()
	}

	@objc func openInBrowser(_ sender: Any?) {
		coordinator.showBrowserForCurrentArticle()
	}

	@objc func openInAppBrowser(_ sender: Any?) {
		coordinator.showInAppBrowser()
	}

	@objc func articleSearch(_ sender: Any?) {
		coordinator.showSearch()
	}

	@objc func addNewFeed(_ sender: Any?) {
		coordinator.showAddFeed()
	}

	@objc func addNewFolder(_ sender: Any?) {
		coordinator.showAddFolder()
	}

	@objc func cleanUp(_ sender: Any?) {
		coordinator.cleanUp(conditional: false)
	}

	@objc func toggleReadFeedsFilter(_ sender: Any?) {
		coordinator.toggleReadFeedsFilter()
	}

	@objc func toggleReadArticlesFilter(_ sender: Any?) {
		coordinator.toggleReadArticlesFilter()
	}

	@objc func refresh(_ sender: Any?) {
		appDelegate.manualRefresh(errorHandler: ErrorHandler.present(self))
	}

	@objc func goToToday(_ sender: Any?) {
		coordinator.selectTodayFeed()
	}

	@objc func goToAllUnread(_ sender: Any?) {
		coordinator.selectAllUnreadFeed()
	}

	@objc func goToStarred(_ sender: Any?) {
		coordinator.selectStarredFeed()
	}

	@objc func goToSettings(_ sender: Any?) {
		coordinator.showLeftMenu()
	}

	@objc func toggleRead(_ sender: Any?) {
		coordinator.toggleReadForCurrentArticle()
	}

	@objc func toggleStarred(_ sender: Any?) {
		coordinator.toggleStarredForCurrentArticle()
	}
}

// MARK: - UIGestureRecognizerDelegate

extension RootSplitViewController: UIGestureRecognizerDelegate {

	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
		let vel = pan.velocity(in: view)
		guard abs(vel.x) > abs(vel.y) else { return false }
		// When the menu is closed, only begin for rightward swipes so we don't
		// compete with table view trailing-swipe actions (read/unread toggle).
		if !isLeftMenuOpen { return vel.x > 0 }
		return true
	}

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		// Wait for the system back-swipe gesture to fail before our menu pan can begin.
		// When the user is inside an article and can go back, the edge pan succeeds and
		// ours is never started. When there is nothing to pop, the edge pan fails
		// immediately and our gesture proceeds.
		return otherGestureRecognizer is UIScreenEdgePanGestureRecognizer
	}
}
