//
//  LandingViewController.swift
//  NetNewsWire-iOS
//
//  Created by Claude on 2026-03-25.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit
import Account

/// Shown on first launch (and on demand via debug setting) while source lists and
/// images are downloaded. Stays on screen for at least 5 seconds.
@MainActor
final class LandingViewController: UIViewController {

	enum Reason {
		case debug       // triggered from debug settings
		case newAccount  // user just completed registration
		case reinstall   // existing account, app reinstalled (hasShownLandingPage reset)
	}

	var reason: Reason = .reinstall

	private let minimumDisplaySeconds: Double = 5

	// MARK: - UI

	private let stackView: UIStackView = {
		let stack = UIStackView()
		stack.axis = .vertical
		stack.alignment = .center
		stack.spacing = 32
		stack.translatesAutoresizingMaskIntoConstraints = false
		return stack
	}()

	private let iconImageView: UIImageView = {
		let imageView = UIImageView()
		imageView.image = UIImage(named: "AppIcon")
		imageView.contentMode = .scaleAspectFit
		imageView.layer.cornerRadius = 22
		imageView.clipsToBounds = true
		imageView.translatesAutoresizingMaskIntoConstraints = false
		return imageView
	}()

	private let messageLabel: UILabel = {
		let label = UILabel()
		label.text = NSLocalizedString("Preparing Podcasts and YouTube episodes for you…", comment: "Landing page loading message")
		label.font = .systemFont(ofSize: 20, weight: .semibold)
		label.textAlignment = .center
		label.numberOfLines = 0
		label.textColor = .white
		return label
	}()

	private let spinner: UIActivityIndicatorView = {
		let indicator = UIActivityIndicatorView(style: .large)
		indicator.color = .white
		indicator.hidesWhenStopped = true
		return indicator
	}()

	// MARK: - Lifecycle

	override func viewDidLoad() {
		super.viewDidLoad()

		view.backgroundColor = .systemBackground

		// Gradient background
		let gradient = CAGradientLayer()
		gradient.colors = [
			UIColor(red: 0.04, green: 0.11, blue: 0.45, alpha: 1).cgColor,
			UIColor(red: 0.0, green: 0.35, blue: 0.70, alpha: 1).cgColor
		]
		gradient.startPoint = CGPoint(x: 0, y: 0)
		gradient.endPoint = CGPoint(x: 1, y: 1)
		gradient.frame = view.bounds
		view.layer.insertSublayer(gradient, at: 0)

		stackView.addArrangedSubview(iconImageView)
		stackView.addArrangedSubview(messageLabel)
		stackView.addArrangedSubview(spinner)
		view.addSubview(stackView)

		NSLayoutConstraint.activate([
			iconImageView.widthAnchor.constraint(equalToConstant: 100),
			iconImageView.heightAnchor.constraint(equalToConstant: 100),

			messageLabel.widthAnchor.constraint(lessThanOrEqualTo: stackView.widthAnchor),

			stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -60),
			stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
			stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40)
		])
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		// Keep gradient in sync with view size (e.g. after rotation)
		if let gradient = view.layer.sublayers?.first as? CAGradientLayer {
			gradient.frame = view.bounds
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		spinner.startAnimating()
		startLoading()
	}

	// MARK: - Loading

	private func startLoading() {
		Task {
			let shouldAddDefaults = reason == .debug || reason == .newAccount

			await withTaskGroup(of: Void.self) { group in
				// Refresh source library first, then add defaults (news/RSS need loaded sources).
				group.addTask {
					await SourcesRefreshManager.shared.forceRefreshAndWait()
					if shouldAddDefaults {
						await self.addDefaultFeeds()
					}
				}
				group.addTask {
					try? await Task.sleep(nanoseconds: UInt64(self.minimumDisplaySeconds * 1_000_000_000))
				}
				await group.waitForAll()
			}

			if shouldAddDefaults {
				await FeedStatsManager.shared.reportUpdate()
			}

			AppDefaults.shared.hasShownLandingPage = true
			AppDefaults.shared.debugShowLandingPage = false

			dismiss(animated: true)
		}
	}

	/// Adds four default feeds. Podcast and YouTube go via webhook; News and RSS use their
	/// already-loaded source URL. All four run concurrently and fail silently on error.
	private func addDefaultFeeds() async {
		guard let account = AccountManager.shared.activeAccounts.first else { return }

		await withTaskGroup(of: Void.self) { group in
			// Podcast via webhook
			group.addTask {
				let result = await PodcastSourcesManager.shared.addPodcast(name: "The Tim Ferriss Show")
				switch result {
				case .successExisting(let url), .successNew(let url):
					await self.createFeedIfNeeded(url: url, name: "The Tim Ferriss Show", category: .podcast, account: account)
				case .failure:
					break
				}
			}

			// YouTube via webhook — must use @handle
			group.addTask {
				let result = await YoutubeSourcesManager.shared.addYoutube(name: "@veritasium")
				switch result {
				case .successExisting(let url), .successNew(let url):
					await self.createFeedIfNeeded(url: url, name: "Veritasium", category: .youtube, account: account)
				case .failure:
					break
				}
			}

			// News: find URL directly from the loaded source list
			group.addTask {
				if let source = NewsSourcesManager.shared.newsSources.first(where: {
					$0.name.localizedCaseInsensitiveContains("Artificial Intelligence")
				}) {
					await self.createFeedIfNeeded(url: source.url, name: source.name, category: .news, account: account)
				}
			}

			// RSS: find URL directly from the loaded source list
			group.addTask {
				if let source = RSSSourcesManager.shared.rssSources.first(where: {
					$0.name.localizedCaseInsensitiveContains("Ars Technica")
				}) {
					await self.createFeedIfNeeded(url: source.url, name: source.name, category: .rss, account: account)
				}
			}

			await group.waitForAll()
		}
	}

	private func createFeedIfNeeded(url: String, name: String, category: FeedCategory, account: Account) async {
		let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, URL(string: trimmed) != nil, !account.hasFeed(withURL: trimmed) else {
			return
		}

		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			account.createFeed(url: trimmed, name: name, container: account, validateFeed: false) { result in
				if case .success(let feed) = result {
					feed.feedCategory = category
					NotificationCenter.default.post(name: .ChildrenDidChange, object: account)
				}
				continuation.resume()
			}
		}
	}
}
