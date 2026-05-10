//
//  LaunchLoadingViewController.swift
//  NetNewsWire-iOS
//

import UIKit
import AuthenticationServices
import os

/// Full-screen loading overlay shown on normal launch while sources and icons are being prepared.
/// Runs auth migration, source JSON fetch, and image prefetch in parallel, then calls `onReady`.
final class LaunchLoadingViewController: UIViewController {

	/// Called on the main thread when all loading is complete.
	/// Receives any feeds that are missing from the local account and need to be restored.
	var onReady: (([MissingFeed]) -> Void)?

	private let titleLabel: UILabel = {
		let label = UILabel()
		label.text = "Second Stream"
		label.font = .systemFont(ofSize: 28, weight: .bold)
		label.textColor = .label
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}()

	private let underlineView: UIView = {
		let view = UIView()
		view.backgroundColor = .label
		view.translatesAutoresizingMaskIntoConstraints = false
		return view
	}()

	private var underlineWidthConstraint: NSLayoutConstraint!

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = Assets.Colors.background
		view.addSubview(titleLabel)
		view.addSubview(underlineView)

		underlineWidthConstraint = underlineView.widthAnchor.constraint(equalToConstant: 0)

		NSLayoutConstraint.activate([
			titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),

			underlineView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
			underlineView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			underlineView.heightAnchor.constraint(equalToConstant: 2),
			underlineWidthConstraint,
		])
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		underlineWidthConstraint.constant = titleLabel.bounds.width
		UIView.animate(withDuration: 1.0, delay: 0, options: .curveEaseInOut) {
			self.view.layoutIfNeeded()
		}
		Task { await load() }
	}

	// MARK: - Loading

	private func load() async {
		// Auth migration + subscription sync runs in parallel with sources + image prefetch.
		async let missing = authAndSync()
		async let sources: Void = sourcesAndImages()
		let missingFeeds = await missing
		await sources
		await FeedStatsManager.shared.fetchCreditsIfNeeded()
		onReady?(missingFeeds)
	}

	/// Silently reconnects if needed (per-user token migration) then detects missing feeds.
	/// Skips all network work when the user is not connected — auth routing is handled by the caller.
	private func authAndSync() async -> [MissingFeed] {
		// Verify Apple credential state first. If revoked or not found, wipe local identity
		// so the routing in onReady correctly sends the user back through onboarding.
		await verifyAppleCredentialState()

		guard AuthManager.shared.isConnected else { return [] }
		if AuthManager.shared.sessionToken == nil {
			_ = try? await AuthManager.shared.reconnect()
		}
		return (try? await SubscriptionSyncManager.shared.detectMissingFeeds()) ?? []
	}

	/// Checks whether the stored Apple user ID is still valid. Clears local identity if Apple
	/// reports the credential as revoked or not found. The onboarding gate (`hasShownLandingPage`)
	/// is intentionally preserved so revoked-but-existing users are routed to Registration, not Onboarding.
	private func verifyAppleCredentialState() async {
		guard let appleUserID = AuthManager.shared.appleUserID else {
				return
		}
		do {
			let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: appleUserID)
			switch state {
			case .revoked, .notFound:
				await MainActor.run {
					AuthManager.shared.clearStoredIdentity()
				}
			case .authorized, .transferred:
				break
			@unknown default:
				break
			}
		} catch {
			// Non-fatal — leave existing state intact, but log so it's visible in production.
			os_log(.error, "verifyAppleCredentialState failed: %{public}@", error.localizedDescription)
		}
	}

	/// Fetches fresh source JSON files then prefetches discover strip icons.
	private func sourcesAndImages() async {
		await SourcesRefreshManager.shared.forceRefreshAndWait()

		// Build the payloads a temporary strip controller would show, then prefetch their icons.
		let stripController = RecentlyUpdatedStripController()
		let payloads = await stripController.buildPayloads()

		let imageURLs: [String] = payloads.flatMap { payload -> [String] in
			guard case .discover(let source) = payload else { return [] }
			return [source.imageURL, source.imageURLLight].compactMap { $0 }
		}

		guard !imageURLs.isEmpty else { return }
		await SourceImageCache.shared.prefetchAndWait(for: imageURLs, timeout: 3.0)
	}
}
