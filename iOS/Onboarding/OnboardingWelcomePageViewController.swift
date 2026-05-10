//
//  OnboardingWelcomePageViewController.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-11.
//  Copyright © 2026 STDN. All rights reserved.
//

import UIKit

/// Page 1 of onboarding: app name, value proposition, and an adaptive screenshot.
///
/// Add two images to the asset catalog:
///   - `onboarding_screenshot_dark`  — dark-mode screenshot
///   - `onboarding_screenshot_light` — light-mode screenshot
@MainActor final class OnboardingWelcomePageViewController: UIViewController {

	/// Called when the user taps "Get Started" — advances to source selection.
	var onContinue: (() -> Void)?

	/// Called when the user taps "Existing user" — presents sign-in for returning users.
	var onExistingUser: (() -> Void)?

	// MARK: - Views

	private var gradientLayer: CAGradientLayer?

	private let scrollView: UIScrollView = {
		let sv = UIScrollView()
		sv.showsVerticalScrollIndicator = false
		sv.translatesAutoresizingMaskIntoConstraints = false
		return sv
	}()

	private let contentStack: UIStackView = {
		let stack = UIStackView()
		stack.axis = .vertical
		stack.alignment = .center
		stack.spacing = 20
		stack.translatesAutoresizingMaskIntoConstraints = false
		return stack
	}()

	private let titleLabel: UILabel = {
		let label = UILabel()
		label.text = "Welcome to\nSecond Stream"
		label.font = .systemFont(ofSize: 36, weight: .bold)
		label.textAlignment = .center
		label.numberOfLines = 0
		return label
	}()

	private let subtitleLabel: UILabel = {
		let label = UILabel()
		label.text = "AI-powered summaries of new podcast episodes and YouTube videos as they publish, curated weekly coverage of topics you care about, and all your RSS feeds — in one place."
		label.font = .systemFont(ofSize: 17)
		label.textColor = .secondaryLabel
		label.textAlignment = .center
		label.numberOfLines = 0
		return label
	}()

	/// Outer view carries the shadow (clipsToBounds = false); inner UIImageView clips to corner radius.
	private let screenshotShadowView: UIView = {
		let view = UIView()
		view.translatesAutoresizingMaskIntoConstraints = false
		view.layer.shadowColor = UIColor.black.cgColor
		view.layer.shadowOffset = CGSize(width: 0, height: 10)
		view.layer.shadowRadius = 24
		view.layer.shadowOpacity = 0.12
		return view
	}()

	private let screenshotImageView: UIImageView = {
		let iv = UIImageView()
		iv.contentMode = .scaleAspectFit
		iv.layer.cornerRadius = 22
		iv.clipsToBounds = true
		iv.translatesAutoresizingMaskIntoConstraints = false
		return iv
	}()

	private lazy var continueButton: UIButton = {
		var config = UIButton.Configuration.filled()
		config.title = "Get Started"
		config.cornerStyle = .medium
		config.baseBackgroundColor = Assets.Colors.primaryAccent
		config.baseForegroundColor = .white
		let button = UIButton(configuration: config)
		button.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
		return button
	}()

	private lazy var existingUserButton: UIButton = {
		var config = UIButton.Configuration.plain()
		config.title = "Existing user"
		config.baseForegroundColor = .secondaryLabel
		let button = UIButton(configuration: config)
		button.addTarget(self, action: #selector(existingUserTapped), for: .touchUpInside)
		return button
	}()

	private lazy var buttonStack: UIStackView = {
		let stack = UIStackView(arrangedSubviews: [continueButton, existingUserButton])
		stack.axis = .vertical
		stack.spacing = 4
		stack.translatesAutoresizingMaskIntoConstraints = false
		return stack
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

		screenshotShadowView.addSubview(screenshotImageView)
		contentStack.addArrangedSubview(titleLabel)
		contentStack.addArrangedSubview(subtitleLabel)
		contentStack.setCustomSpacing(32, after: subtitleLabel)
		contentStack.addArrangedSubview(screenshotShadowView)
		scrollView.addSubview(contentStack)
		view.addSubview(scrollView)
		view.addSubview(buttonStack)

		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -16),

			contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 48),
			contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 28),
			contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -28),
			contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
			contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -56),

			// Shadow wrapper fills the stack width; height is 1.6× width (portrait screenshot ratio)
			screenshotShadowView.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
			screenshotShadowView.heightAnchor.constraint(equalTo: screenshotShadowView.widthAnchor, multiplier: 1.6),

			screenshotImageView.topAnchor.constraint(equalTo: screenshotShadowView.topAnchor),
			screenshotImageView.leadingAnchor.constraint(equalTo: screenshotShadowView.leadingAnchor),
			screenshotImageView.trailingAnchor.constraint(equalTo: screenshotShadowView.trailingAnchor),
			screenshotImageView.bottomAnchor.constraint(equalTo: screenshotShadowView.bottomAnchor),

			buttonStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
			buttonStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
			buttonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
			continueButton.heightAnchor.constraint(equalToConstant: 50),
		])

		updateScreenshot()

		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
			self.updateGradientColors()
			self.updateScreenshot()
		}
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		gradientLayer?.frame = view.bounds
	}

	// MARK: - Actions

	@objc private func continueTapped() {
		onContinue?()
	}

	@objc private func existingUserTapped() {
		onExistingUser?()
	}

	// MARK: - Private

	private func updateGradientColors() {
		gradientLayer?.colors = [
			Assets.Colors.foreground.resolvedColor(with: traitCollection).cgColor,
			Assets.Colors.background.resolvedColor(with: traitCollection).cgColor
		]
	}

	private func updateScreenshot() {
		let isDark = traitCollection.userInterfaceStyle == .dark
		screenshotImageView.image = UIImage(named: isDark ? "onboarding_screenshot_dark" : "onboarding_screenshot_light")
	}
}
