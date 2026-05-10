//
//  OnboardingViewController.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-11.
//  Copyright © 2026 STDN. All rights reserved.
//

import UIKit

/// Full-screen onboarding flow shown to first-time users.
///
/// Three pages:
///   1. `OnboardingWelcomePageViewController` — app value proposition + screenshot
///   2. `OnboardingSourceSelectionPageViewController` — pick podcasts / YouTube / topics
///   3. `OnboardingRegistrationPageViewController` — sign in / register, then add selected sources
///
/// Navigation is driven entirely by Continue buttons — no swipe gestures.
@MainActor final class OnboardingViewController: UIViewController {

	let isDebug: Bool

	/// Called after dismissal with the feed requests assembled on the registration page.
	var onComplete: (([AddFeedRequest]) -> Void)?

	// MARK: - Child pages

	private lazy var welcomePage = OnboardingWelcomePageViewController()
	private lazy var selectionPage = OnboardingSourceSelectionPageViewController()
	private lazy var registrationPage = OnboardingRegistrationPageViewController()
	private lazy var pages: [UIViewController] = [welcomePage, selectionPage, registrationPage]

	// MARK: - Views

	private let pageVC = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)

	// MARK: - State

	private var currentIndex = 0

	// MARK: - Init

	init(isDebug: Bool = false) {
		self.isDebug = isDebug
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError() }

	// MARK: - Lifecycle

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = Assets.Colors.background

		setupPageViewController()
		if isDebug { setupDebugCloseButton() }
		wirePageCallbacks()
		prefetchSources()
	}

	// MARK: - Page navigation (called by child pages)

	func advance(to index: Int) {
		guard index < pages.count, index != currentIndex else { return }
		let direction: UIPageViewController.NavigationDirection = index > currentIndex ? .forward : .reverse
		pageVC.setViewControllers([pages[index]], direction: direction, animated: true)
		currentIndex = index
	}

	/// Dismisses the onboarding and signals completion with the assembled feed requests.
	func finish(with requests: [AddFeedRequest]) {
		AppDefaults.shared.debugShowLandingPage = false
		dismiss(animated: true) { [weak self] in
			self?.onComplete?(requests)
		}
	}

	// MARK: - Setup

	private func setupPageViewController() {
		addChild(pageVC)
		pageVC.view.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(pageVC.view)
		pageVC.didMove(toParent: self)
		pageVC.setViewControllers([welcomePage], direction: .forward, animated: false)

		// Disable all swipe navigation — Continue buttons are the only way forward.
		pageVC.view.subviews.compactMap { $0 as? UIScrollView }.forEach { $0.isScrollEnabled = false }

		NSLayoutConstraint.activate([
			pageVC.view.topAnchor.constraint(equalTo: view.topAnchor),
			pageVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			pageVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			pageVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		])
	}

	private func setupDebugCloseButton() {
		let closeBtn = UIButton(type: .close)
		closeBtn.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(closeBtn)
		closeBtn.addTarget(self, action: #selector(debugClose), for: .touchUpInside)
		NSLayoutConstraint.activate([
			closeBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
			closeBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
		])
	}

	private func wirePageCallbacks() {
		welcomePage.onContinue = { [weak self] in
			self?.advance(to: 1)
		}
		welcomePage.onExistingUser = { [weak self] in
			self?.presentExistingUserSignIn()
		}
		selectionPage.onContinue = { [weak self] sources in
			self?.registrationPage.selectedSources = sources
			self?.advance(to: 2)
		}
		registrationPage.onComplete = { [weak self] requests in
			self?.finish(with: requests)
		}
	}

	/// Presents `RegistrationViewController` for users who already have an account.
	/// On success, finishes onboarding without source selection (feeds restored via sync).
	/// On 553 (user not found), dismisses and falls through to the normal new-user flow.
	private func presentExistingUserSignIn() {
		let vc = RegistrationViewController()
		vc.modalPresentationStyle = .fullScreen
		vc.isModalInPresentation = true
		vc.didSucceedHandler = { [weak self] in
			self?.finish(with: [])
		}
		vc.didFailWithUserNotFound = { [weak self] in
			self?.advance(to: 1)
		}
		present(vc, animated: true)
	}

	private func prefetchSources() {
		Task {
			await SourcesRefreshManager.shared.forceRefreshAndWait()
			selectionPage.reloadSources()
		}
	}

	// MARK: - Actions

	@objc private func debugClose() {
		AppDefaults.shared.debugShowLandingPage = false
		dismiss(animated: true)
	}
}

