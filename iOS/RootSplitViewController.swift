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
		let dimView = UIView()
		dimView.translatesAutoresizingMaskIntoConstraints = false
		dimView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
		dimView.alpha = 0
		dimView.isHidden = true
		let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dimViewTapped))
		dimView.addGestureRecognizer(tapGesture)
		view.addSubview(dimView)
		NSLayoutConstraint.activate([
			dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			dimView.topAnchor.constraint(equalTo: view.topAnchor),
			dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
		])
		leftMenuDimView = dimView

		let menuVC = LeftSideMenuViewController()
		menuVC.coordinator = coordinator
		addChild(menuVC)
		menuVC.view.translatesAutoresizingMaskIntoConstraints = false
		menuVC.view.layer.shadowColor = UIColor.black.cgColor
		menuVC.view.layer.shadowOpacity = 0.2
		menuVC.view.layer.shadowRadius = 8
		menuVC.view.layer.shadowOffset = CGSize(width: 4, height: 0)
		view.addSubview(menuVC.view)
		let leadingConstraint = menuVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -leftMenuWidth)
		NSLayoutConstraint.activate([
			leadingConstraint,
			menuVC.view.widthAnchor.constraint(equalToConstant: leftMenuWidth),
			menuVC.view.topAnchor.constraint(equalTo: view.topAnchor),
			menuVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
		])
		leftMenuLeadingConstraint = leadingConstraint
		leftMenuViewController = menuVC
		menuVC.didMove(toParent: self)
	}

	func showLeftMenu() {
		guard !isLeftMenuOpen else {
			return
		}
		UIImpactFeedbackGenerator(style: .medium).impactOccurred()
		isLeftMenuOpen = true
		leftMenuDimView?.isHidden = false
		leftMenuLeadingConstraint?.constant = 0
		UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
			self.view.layoutIfNeeded()
			self.leftMenuDimView?.alpha = 1
		}
	}

	func hideLeftMenu(completion: (() -> Void)? = nil) {
		guard isLeftMenuOpen else {
			completion?()
			return
		}
		isLeftMenuOpen = false
		leftMenuViewController?.resetNavigation()
		leftMenuLeadingConstraint?.constant = -leftMenuWidth
		UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseIn) {
			self.view.layoutIfNeeded()
			self.leftMenuDimView?.alpha = 0
		} completion: { _ in
			self.leftMenuDimView?.isHidden = true
			completion?()
		}
	}

	@objc private func dimViewTapped() {
		hideLeftMenu()
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
		coordinator.showSettings()
	}

	@objc func toggleRead(_ sender: Any?) {
		coordinator.toggleReadForCurrentArticle()
	}

	@objc func toggleStarred(_ sender: Any?) {
		coordinator.toggleStarredForCurrentArticle()
	}
}
