//
//  SourceRestoreViewController.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-11.
//  Copyright © 2026 STDN. All rights reserved.
//

import UIKit
import os.log

/// Presented fullscreen when `SubscriptionSyncManager.detectMissingFeeds()` finds server
/// subscriptions that are absent from local storage (clean reinstall, new device, iCloud
/// restore, device wipe).
///
/// Shows the same "Setting up your sources…" progress UI as onboarding, then calls
/// `onComplete` when all feeds have been restored locally.
@MainActor final class SourceRestoreViewController: UIViewController {

	var onComplete: (() -> Void)?

	private let feeds: [MissingFeed]
	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SourceRestore")

	// MARK: - Views

	private let titleLabel: UILabel = {
		let label = UILabel()
		label.text = "Restoring your sources…"
		label.font = .systemFont(ofSize: 26, weight: .semibold)
		label.textAlignment = .center
		label.numberOfLines = 0
		return label
	}()

	private let spinner: UIActivityIndicatorView = {
		let iv = UIActivityIndicatorView(style: .large)
		iv.hidesWhenStopped = true
		return iv
	}()

	private let progressLabel: UILabel = {
		let label = UILabel()
		label.font = .systemFont(ofSize: 15)
		label.textColor = .secondaryLabel
		label.textAlignment = .center
		label.numberOfLines = 0
		return label
	}()

	// MARK: - Init

	init(feeds: [MissingFeed]) {
		self.feeds = feeds
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	// MARK: - Lifecycle

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = Assets.Colors.background

		let stack = UIStackView(arrangedSubviews: [titleLabel, spinner, progressLabel])
		stack.axis = .vertical
		stack.alignment = .center
		stack.spacing = 20
		stack.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(stack)

		NSLayoutConstraint.activate([
			stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
			stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
		])
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		Task { await performRestore() }
	}

	// MARK: - Restore

	private func performRestore() async {
		spinner.startAnimating()

		await SubscriptionSyncManager.shared.restore(feeds) { [weak self] name, index, total in
			self?.progressLabel.text = "Restoring \(name)… (\(index + 1) of \(total))"
		}

		progressLabel.text = "All done!"
		spinner.stopAnimating()
		Self.logger.info("SourceRestoreViewController: all \(self.feeds.count) feed(s) restored")

		// Fetch credits now — UserDefaults is empty after a reinstall so cachedCredits
		// is nil until this call. Without it the sidebar would show nothing.
		await FeedStatsManager.shared.fetchCredits()

		try? await Task.sleep(nanoseconds: 700_000_000)
		onComplete?()
	}
}
