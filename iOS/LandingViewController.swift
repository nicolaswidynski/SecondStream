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
			UIColor.systemBlue.cgColor,
			UIColor.systemCyan.cgColor
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
			stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
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
			await withTaskGroup(of: Void.self) { group in
				group.addTask {
					await SourcesRefreshManager.shared.forceRefreshAndWait()
				}
				group.addTask {
					try? await Task.sleep(nanoseconds: UInt64(self.minimumDisplaySeconds * 1_000_000_000))
				}
				await group.waitForAll()
			}

			AppDefaults.shared.hasShownLandingPage = true
			AppDefaults.shared.debugShowLandingPage = false

			dismiss(animated: true)
		}
	}
}
