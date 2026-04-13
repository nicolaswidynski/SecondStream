//
//  LandingViewController.swift
//  NetNewsWire-iOS
//
//  Created by Claude on 2026-03-25.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit

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

	/// Called in the dismiss completion block after the landing page finishes.
	/// Set by the presenter (SceneDelegate) to perform any post-setup work.
	var onReady: (() -> Void)?

	private let minimumDisplaySeconds: Double = 5

	private var gradientLayer: CAGradientLayer?

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
		label.textColor = .label
		return label
	}()

	private let spinner: UIActivityIndicatorView = {
		let indicator = UIActivityIndicatorView(style: .large)
		indicator.color = .label
		indicator.hidesWhenStopped = true
		return indicator
	}()

	// MARK: - Lifecycle

	override func viewDidLoad() {
		super.viewDidLoad()

		view.backgroundColor = Assets.Colors.background

		let gradient = CAGradientLayer()
		gradient.startPoint = CGPoint(x: 0.5, y: 0)
		gradient.endPoint = CGPoint(x: 0.5, y: 1)
		gradient.frame = view.bounds
		view.layer.insertSublayer(gradient, at: 0)
		gradientLayer = gradient
		updateGradientColors()

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

		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
			self.updateGradientColors()
		}
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		gradientLayer?.frame = view.bounds
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		spinner.startAnimating()
		startLoading()
	}

	// MARK: - Private

	private func updateGradientColors() {
		gradientLayer?.colors = [
			Assets.Colors.foreground.resolvedColor(with: traitCollection).cgColor,
			Assets.Colors.background.resolvedColor(with: traitCollection).cgColor
		]
	}

	// MARK: - Loading

	private func startLoading() {
		Task {
			// Run source refresh, minimum display timer, and subscription sync concurrently.
			// The sync task returns any error as a value to avoid capturing mutable state
			// across @Sendable task boundaries.
			let syncError: Error? = await withTaskGroup(of: Error?.self) { group in
				group.addTask { await SourcesRefreshManager.shared.forceRefreshAndWait(); return nil }
				group.addTask {
					try? await Task.sleep(nanoseconds: UInt64(self.minimumDisplaySeconds * 1_000_000_000))
					return nil
				}
				group.addTask {
					do {
						try await SubscriptionSyncManager.shared.sync()
						return nil
					} catch {
						return error
					}
				}
				var result: Error?
				for await taskError in group {
					if let taskError { result = taskError }
				}
				return result
			}

			AppDefaults.shared.hasShownLandingPage = true
			AppDefaults.shared.debugShowLandingPage = false

			if let error = syncError {
				await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
					let alert = UIAlertController(title: "Sync Failed", message: error.localizedDescription, preferredStyle: .alert)
					alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in cont.resume() })
					self.present(alert, animated: true)
				}
			}

			dismiss(animated: true) { [weak self] in
				self?.onReady?()
			}
		}
	}
}
