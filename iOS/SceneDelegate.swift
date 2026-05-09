//
//  AppDelegate.swift
//  NetNewsWire
//
//  Created by Maurice Parker on 6/28/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import UserNotifications
import Account
import AuthenticationServices
import RSCore
import os

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

	var window: UIWindow?
	var coordinator: SceneCoordinator!

	// UIWindowScene delegate

	func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {

		window!.tintColor = Assets.Colors.primaryAccent

		let globalNavAppearance = UINavigationBarAppearance()
		globalNavAppearance.configureWithOpaqueBackground()
		globalNavAppearance.backgroundColor = Assets.Colors.FeedSceneNavBarColor
		UINavigationBar.appearance().standardAppearance = globalNavAppearance
		UINavigationBar.appearance().scrollEdgeAppearance = globalNavAppearance
		UINavigationBar.appearance().compactAppearance = globalNavAppearance
		UINavigationBar.appearance().compactScrollEdgeAppearance = globalNavAppearance

		let rootViewController = window!.rootViewController as! RootSplitViewController
		rootViewController.presentsWithGesture = true
		rootViewController.showsSecondaryOnlyButton = true
		rootViewController.preferredDisplayMode = UISplitViewController.DisplayMode(rawValue: AppDefaults.shared.splitViewPreferredDisplayMode) ?? .oneBesideSecondary

		coordinator = SceneCoordinator(rootSplitViewController: rootViewController)
		rootViewController.coordinator = coordinator
		rootViewController.delegate = coordinator

		coordinator.restoreWindowState(activity: session.stateRestorationActivity)

		updateUserInterfaceStyle()

		// Always show the launch loading screen first so the feed scene is never visible
		// before auth checks are complete. Auth routing happens inside presentLaunchLoading's
		// onReady callback once the loading phase finishes.
		presentLaunchLoading()

		if AuthManager.shared.isConnected && AppDefaults.shared.shouldShowLandingPage {
			syncAfterAuth()
		}

		NotificationCenter.default.addObserver(self, selector: #selector(handleUserInterfaceColorPaletteDidUpdate(_:)), name: .userInterfaceColorPaletteDidUpdate, object: AppDefaults.self)

		if connectionOptions.urlContexts.first?.url != nil {
			self.scene(scene, openURLContexts: connectionOptions.urlContexts)
			return
		}

		if let shortcutItem = connectionOptions.shortcutItem {
			handleShortcutItem(shortcutItem)
			return
		}

		if let notificationResponse = connectionOptions.notificationResponse {
			coordinator.handle(notificationResponse)
			return
		}

		// Handle activities from external sources (Handoff, Spotlight, Siri Shortcuts).
		// Skip handling session.stateRestorationActivity since UserDefaults now handles state restoration.
		if let userActivity = connectionOptions.userActivities.first {
			coordinator.handle(userActivity)
		}
	}

	func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
		appDelegate.resumeDatabaseProcessingIfNecessary()
		handleShortcutItem(shortcutItem)
		completionHandler(true)
	}

	func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
		appDelegate.resumeDatabaseProcessingIfNecessary()
		coordinator.handle(userActivity)
	}

	func sceneDidEnterBackground(_ scene: UIScene) {
		coordinator.didEnterBackground()
		ArticleStringFormatter.emptyCaches()
		appDelegate.prepareAccountsForBackground()
	}

	func sceneWillEnterForeground(_ scene: UIScene) {
		appDelegate.resumeDatabaseProcessingIfNecessary()
		appDelegate.prepareAccountsForForeground()
		coordinator.resetFocus()
		Task { @MainActor in BootstrapProgressManager.shared.resumeFromBackground() }
		if !AuthManager.shared.isConnected {
			// Skip auth routing during initial launch — the launch loading VC owns routing at that point.
			// Only intervene if the loading VC is no longer active (i.e. this is a foreground resume).
			let isLoadingActive = window?.rootViewController?.children.contains { $0 is LaunchLoadingViewController } == true
			guard !isLoadingActive else { return }
			if AppDefaults.shared.shouldShowLandingPage {
				presentOnboarding()
			} else {
				presentRegistration()
			}
		}
	}

	func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
		return coordinator.stateRestorationActivity
	}

	// API

	func handle(_ response: UNNotificationResponse) {
		appDelegate.resumeDatabaseProcessingIfNecessary()
		coordinator.handle(response)
	}

	func suspend() {
		coordinator.suspend()
	}

	func cleanUp(conditional: Bool) {
		coordinator.cleanUp(conditional: conditional)
	}

	// Handle Opening of URLs

	func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
		guard let context = urlContexts.first else { return }

		DispatchQueue.main.async {

			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				self.coordinator.dismissIfLaunchingFromExternalAction()
			}

			let urlString = context.url.absoluteString

			// Handle the feed: and feeds: schemes
			if urlString.starts(with: "feed:") || urlString.starts(with: "feeds:") {
				let normalizedURLString = urlString.normalizedURL
				if normalizedURLString.mayBeURL {
					self.coordinator.showAddFeed(initialFeed: normalizedURLString, initialFeedName: nil)
				}
			}

			// Show Unread View or Article
			if urlString.contains(WidgetDeepLink.unread.url.absoluteString) {
				guard let comps = URLComponents(string: urlString ) else { return  }
				let id = comps.queryItems?.first(where: { $0.name == "id" })?.value
				if id != nil {
					if AccountManager.shared.isSuspended {
						AccountManager.shared.resumeAll()
					}
					self.coordinator.selectAllUnreadFeed {
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
							self.coordinator.selectArticleInCurrentFeed(id!)
						}
					}
				} else {
					self.coordinator.selectAllUnreadFeed()
				}
			}

			// Show Today View or Article
			if urlString.contains(WidgetDeepLink.today.url.absoluteString) {
				guard let comps = URLComponents(string: urlString ) else { return  }
				let id = comps.queryItems?.first(where: { $0.name == "id" })?.value
				if id != nil {
					if AccountManager.shared.isSuspended {
						AccountManager.shared.resumeAll()
					}
					self.coordinator.selectTodayFeed {
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
							self.coordinator.selectArticleInCurrentFeed(id!)
						}
					}
				} else {
					self.coordinator.selectTodayFeed()
				}
			}

			// Show Starred View or Article
			if urlString.contains(WidgetDeepLink.starred.url.absoluteString) {
				guard let comps = URLComponents(string: urlString ) else { return  }
				let id = comps.queryItems?.first(where: { $0.name == "id" })?.value
				if id != nil {
					if AccountManager.shared.isSuspended {
						AccountManager.shared.resumeAll()
					}
					self .coordinator.selectStarredFeed {
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
							self.coordinator.selectArticleInCurrentFeed(id!)
						}
					}
				} else {
					self.coordinator.selectStarredFeed()
				}
			}

			let filename = context.url.standardizedFileURL.path
			if filename.hasSuffix(ArticleTheme.nnwThemeSuffix) {
				self.coordinator.importTheme(filename: filename)
				return
			}

			// Handle theme URLs: netnewswire://theme/add?url={url}
			guard let comps = URLComponents(url: context.url, resolvingAgainstBaseURL: false),
				  "theme" == comps.host,
				 let queryItems = comps.queryItems else {
				return
			}

			if let providedThemeURL = queryItems.first(where: { $0.name == "url" })?.value {
				if let themeURL = URL(string: providedThemeURL) {
					let request = URLRequest(url: themeURL)

					DispatchQueue.main.async {
						NotificationCenter.default.post(name: .didBeginDownloadingTheme, object: nil)
					}
					let task = URLSession.shared.downloadTask(with: request) { location, _, error in
						guard
							  let location = location else { return }

						Task { @MainActor in
							do {
								try ArticleThemeDownloader.shared.handleFile(at: location)
							} catch {
								NotificationCenter.default.post(name: .didFailToImportThemeWithError, object: nil, userInfo: ["error": error])
							}
						}
					}
					task.resume()
				} else {
					print("No theme URL")
					return
				}
			} else {
				return
			}
		}
	}

	func presentRegistration() {
		// Defer to the next run loop so the window is visible before we present.
		DispatchQueue.main.async {
			guard !(self.window?.rootViewController?.presentedViewController is RegistrationViewController) else {
				return
			}
			let registrationVC = RegistrationViewController()
			registrationVC.modalPresentationStyle = .fullScreen
			registrationVC.isModalInPresentation = true // prevents swipe-to-dismiss
			registrationVC.didSucceedHandler = { [weak self] in
				self?.syncAfterAuth()
			}
			self.window?.rootViewController?.present(registrationVC, animated: false)
		}
	}

	func presentLandingPage(reason: LandingViewController.Reason = .reinstall) {
		DispatchQueue.main.async {
			let landingVC = LandingViewController()
			landingVC.reason = reason
			landingVC.modalPresentationStyle = .fullScreen
			landingVC.isModalInPresentation = true
			self.window?.rootViewController?.present(landingVC, animated: true)
		}
	}

	func presentLaunchLoading() {
		guard let rootVC = window?.rootViewController else { return }
		let loadingVC = LaunchLoadingViewController()
		loadingVC.onReady = { [weak self] missing in
			guard let self else { return }

			func removeLoadingVC() {
				MainActor.assumeIsolated {
					loadingVC.willMove(toParent: nil)
					loadingVC.view.removeFromSuperview()
					loadingVC.removeFromParent()
				}
			}

			if !AuthManager.shared.isConnected {
				// Present the auth VC directly on top of the loading screen (no gap) then
				// tear down the loading VC once the presentation is fully on-screen.
				let authVC: UIViewController
				if AppDefaults.shared.shouldShowLandingPage {
					let vc = OnboardingViewController()
					vc.onComplete = { [weak self] requests in
						self?.syncAfterAuth(addingFeeds: requests)
					}
					authVC = vc
				} else {
					let vc = RegistrationViewController()
					vc.didSucceedHandler = { [weak self] in
						self?.syncAfterAuth()
					}
					authVC = vc
				}
				authVC.modalPresentationStyle = .fullScreen
				authVC.isModalInPresentation = true
				rootVC.present(authVC, animated: false) {
					removeLoadingVC()
				}
			} else if !missing.isEmpty {
				UIView.animate(withDuration: 0.25, animations: {
					loadingVC.view.alpha = 0
				}, completion: { _ in
					removeLoadingVC()
					self.presentSourceRestore(missing)
				})
			} else {
				UIView.animate(withDuration: 0.25, animations: {
					loadingVC.view.alpha = 0
				}, completion: { _ in
					removeLoadingVC()
				})
			}
		}
		rootVC.addChild(loadingVC)
		loadingVC.view.frame = rootVC.view.bounds
		loadingVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		rootVC.view.addSubview(loadingVC.view)
		loadingVC.didMove(toParent: rootVC)
	}

	func presentSourceRestore(_ feeds: [MissingFeed]) {
		DispatchQueue.main.async {
			let restoreVC = SourceRestoreViewController(feeds: feeds)
			restoreVC.modalPresentationStyle = .fullScreen
			restoreVC.isModalInPresentation = true
			restoreVC.onComplete = { [weak self] in
				self?.window?.rootViewController?.dismiss(animated: true) {
					guard let rootVC = self?.window?.rootViewController else { return }
					appDelegate.manualRefresh(errorHandler: ErrorHandler.present(rootVC))
				}
			}
			self.window?.rootViewController?.present(restoreVC, animated: true)
		}
	}

	func presentOnboarding(isDebug: Bool = false) {
		DispatchQueue.main.async {
			let onboardingVC = OnboardingViewController(isDebug: isDebug)
			onboardingVC.modalPresentationStyle = .fullScreen
			onboardingVC.isModalInPresentation = true
			onboardingVC.onComplete = { [weak self] requests in
				self?.syncAfterAuth(addingFeeds: requests)
			}
			self.window?.rootViewController?.present(onboardingVC, animated: false)
		}
	}

	/// Single post-auth handler. Called after every successful register or reconnect,
	/// from every entry point (onboarding, registration screen, or scene launch).
	/// Adds any onboarding-selected feeds, syncs server subscriptions, and refreshes.
	func syncAfterAuth(addingFeeds: [AddFeedRequest] = []) {
		Task { @MainActor in
			if !addingFeeds.isEmpty, let account = AccountManager.shared.activeAccounts.first {
				BatchUpdate.shared.start()
				for request in addingFeeds {
					let normalized = request.urlString.normalizedURL
					guard !normalized.isEmpty, let feedURL = URL(string: normalized) else { continue }
					guard !account.hasFeed(withURL: feedURL.absoluteString) else { continue }
					await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
						account.createFeed(url: feedURL.absoluteString, name: request.name, container: account, validateFeed: false) { result in
							if case .success(let feed) = result {
								feed.feedCategory = request.category
								if let lightURL = request.imageURLLight {
									LightFeedIconStore.shared.setLightIconURL(lightURL, for: feed.url)
								}
								NotificationCenter.default.post(name: .ChildrenDidChange, object: account)
							}
							continuation.resume()
						}
					}
				}
				BatchUpdate.shared.end()

				// Expand category sections for all feed categories that were just added so
				// the sidebar isn't collapsed when the user first sees the feed scene.
				let addedCategories = Set(addingFeeds.map { $0.category })
				if addedCategories.contains(.podcast) { coordinator.expandCategorySection(.podcasts) }
				if addedCategories.contains(.youtube) { coordinator.expandCategorySection(.youtube) }
				if addedCategories.contains(.news)    { coordinator.expandCategorySection(.news) }
				if addedCategories.contains(.rss)     { coordinator.expandCategorySection(.rssFeeds) }
			}
			AppDefaults.shared.hasShownLandingPage = true
			try? await SubscriptionSyncManager.shared.sync()
			if let rootVC = self.window?.rootViewController {
				appDelegate.manualRefresh(errorHandler: ErrorHandler.present(rootVC))
			}
		}
	}
}

private extension SceneDelegate {

	func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) {
		switch shortcutItem.type {
		case "com.stdn.SecondStream.FirstUnread":
			coordinator.selectFirstUnreadInAllUnread()
		case "com.stdn.SecondStream.ShowSearch":
			coordinator.showSearch()
		case "com.stdn.SecondStream.ShowAdd":
			coordinator.showAddFeed()
		default:
			break
		}
	}

	@objc func handleUserInterfaceColorPaletteDidUpdate(_ notification: Notification) {
		assert(Thread.isMainThread)
		Task {
			updateUserInterfaceStyle()
		}
	}

	@MainActor func updateUserInterfaceStyle() {
		switch AppDefaults.userInterfaceColorPalette {
		case .automatic:
			self.window?.overrideUserInterfaceStyle = .unspecified
		case .light:
			self.window?.overrideUserInterfaceStyle = .light
		case .dark:
			self.window?.overrideUserInterfaceStyle = .dark
		}
	}

}
