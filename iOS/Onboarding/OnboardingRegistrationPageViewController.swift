//
//  OnboardingRegistrationPageViewController.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-11.
//  Copyright © 2026 STDN. All rights reserved.
//

import UIKit
import AuthenticationServices
import Account
import os.log

/// Page 3 of onboarding: Sign in with Apple, followed by adding selected sources.
///
/// Tapping "Getting Started" triggers Sign in with Apple. The credential is sent to the server
/// via `signIn()` and the HTTP status code determines what happens next:
///   - 201 (existing user) → skip source setup and complete immediately
///   - 202 (new user) → add the sources the user selected on page 2
@MainActor final class OnboardingRegistrationPageViewController: UIViewController {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "OnboardingRegistration")

	/// Sources chosen by the user on page 2. Set by `OnboardingViewController` before navigation.
	var selectedSources: [DiscoverSourceItem] = []

	/// Called after all webhook calls finish. Receives the assembled feed requests.
	var onComplete: (([AddFeedRequest]) -> Void)?

	// MARK: - Auth phase views

	private let authStack: UIStackView = {
		let stack = UIStackView()
		stack.axis = .vertical
		stack.alignment = .center
		stack.spacing = 16
		stack.translatesAutoresizingMaskIntoConstraints = false
		return stack
	}()

	private let titleLabel: UILabel = {
		let label = UILabel()
		label.text = "Create Your Account"
		label.font = .systemFont(ofSize: 34, weight: .bold)
		label.textAlignment = .center
		label.numberOfLines = 0
		return label
	}()

	private let subtitleLabel: UILabel = {
		let label = UILabel()
		label.text = "Sign in to sync your subscriptions and summaries across devices."
		label.font = .systemFont(ofSize: 17)
		label.textColor = .secondaryLabel
		label.textAlignment = .center
		label.numberOfLines = 0
		return label
	}()

	private lazy var signInButton: UIButton = {
		var config = UIButton.Configuration.filled()
		config.title = "Getting Started"
		config.cornerStyle = .medium
		config.baseBackgroundColor = Assets.Colors.primaryAccent
		config.baseForegroundColor = .white
		let button = UIButton(configuration: config)
		button.translatesAutoresizingMaskIntoConstraints = false
		button.addTarget(self, action: #selector(handleSignIn), for: .touchUpInside)
		return button
	}()

	private let authSpinner: UIActivityIndicatorView = {
		let iv = UIActivityIndicatorView(style: .medium)
		iv.hidesWhenStopped = true
		return iv
	}()

	// MARK: - Adding-sources phase views

	private let addingStack: UIStackView = {
		let stack = UIStackView()
		stack.axis = .vertical
		stack.alignment = .center
		stack.spacing = 20
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.isHidden = true
		stack.alpha = 0
		return stack
	}()

	private let addingTitleLabel: UILabel = {
		let label = UILabel()
		label.text = "Setting up your sources…"
		label.font = .systemFont(ofSize: 26, weight: .semibold)
		label.textAlignment = .center
		label.numberOfLines = 0
		return label
	}()

	private let addingSpinner: UIActivityIndicatorView = {
		let iv = UIActivityIndicatorView(style: .large)
		iv.hidesWhenStopped = true
		return iv
	}()

	private let addingProgressLabel: UILabel = {
		let label = UILabel()
		label.font = .systemFont(ofSize: 15)
		label.textColor = .secondaryLabel
		label.textAlignment = .center
		label.numberOfLines = 0
		return label
	}()

	// MARK: - Lifecycle

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = Assets.Colors.background

		// Auth phase
		authStack.addArrangedSubview(titleLabel)
		authStack.setCustomSpacing(8, after: titleLabel)
		authStack.addArrangedSubview(subtitleLabel)
		authStack.setCustomSpacing(48, after: subtitleLabel)
		authStack.addArrangedSubview(signInButton)
		authStack.addArrangedSubview(authSpinner)
		view.addSubview(authStack)

		NSLayoutConstraint.activate([
			signInButton.widthAnchor.constraint(equalTo: authStack.widthAnchor),
			signInButton.heightAnchor.constraint(equalToConstant: 50),
			authStack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
			authStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
			authStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
		])

		// Adding-sources phase
		addingStack.addArrangedSubview(addingTitleLabel)
		addingStack.addArrangedSubview(addingSpinner)
		addingStack.addArrangedSubview(addingProgressLabel)
		view.addSubview(addingStack)

		NSLayoutConstraint.activate([
			addingStack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
			addingStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
			addingStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
		])
	}

	// MARK: - Actions

	@objc private func handleSignIn() {
		let provider = ASAuthorizationAppleIDProvider()
		let request = provider.createRequest()
		request.requestedScopes = [.email, .fullName]
		let controller = ASAuthorizationController(authorizationRequests: [request])
		controller.delegate = self
		controller.presentationContextProvider = self
		controller.performRequests()
	}

	// MARK: - Helpers

	private func setAuthLoading(_ loading: Bool) {
		signInButton.isEnabled = !loading
		if loading {
			authSpinner.startAnimating()
		} else {
			authSpinner.stopAnimating()
		}
	}

	private func showAuthError(_ message: String) {
		let alert = UIAlertController(title: "Failed", message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "OK", style: .default))
		present(alert, animated: true)
	}

	// MARK: - Adding sources

	private func addSources() async {
		// Transition from auth UI to adding-sources UI
		UIView.animate(withDuration: 0.25) {
			self.authStack.alpha = 0
		} completion: { _ in
			self.authStack.isHidden = true
			self.addingStack.isHidden = false
			UIView.animate(withDuration: 0.25) {
				self.addingStack.alpha = 1
			}
		}
		addingSpinner.startAnimating()

		var feedRequests: [AddFeedRequest] = []
		let total = selectedSources.count

		for (index, source) in selectedSources.enumerated() {
			addingProgressLabel.text = "Adding \(source.name)… (\(index + 1) of \(total))"

			let manager: (any WebhookSourcesManaging)?
			let category: FeedCategory

			switch source.category {
			case .podcast:
				manager = MediaSourcesManager.podcast
				category = .podcast
			case .youtube:
				manager = MediaSourcesManager.youtube
				category = .youtube
			case .news:
				manager = NewsSourcesManager.shared
				category = .news
			case .rss:
				manager = nil
				category = .rss
			}

			guard let manager else { continue }

			let result = await manager.add(name: source.name, author: source.author)
			switch result {
			case .existsOnServer(let url), .newOnServer(let url, _):
				feedRequests.append(AddFeedRequest(
					urlString: url,
					category: category,
					name: source.name,
					author: source.author,
					imageURL: source.imageURL,
					imageURLLight: source.imageURLLight,
					validateFeed: false,
					summaryURL: url,
					skipLoadingIndicator: true
				))
			case .failure(let message):
				Self.logger.error("Failed to add source \(source.name, privacy: .public): \(message, privacy: .public)")
			}
		}

		addingProgressLabel.text = "All done!"
		addingSpinner.stopAnimating()

		// Brief pause so the user sees "All done!" before dismissal.
		try? await Task.sleep(nanoseconds: 700_000_000)
		onComplete?(feedRequests)
	}
}

// MARK: - ASAuthorizationControllerDelegate

extension OnboardingRegistrationPageViewController: ASAuthorizationControllerDelegate {

	func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
		guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }

		let realUserStatus: String = {
			switch credential.realUserStatus {
			case .likelyReal: return "likelyReal"
			case .unknown: return "unknown"
			case .unsupported: return "unsupported"
			@unknown default: return "unknown"
			}
		}()

		setAuthLoading(true)
		Task { @MainActor in
			defer { setAuthLoading(false) }
			do {
				let outcome = try await AuthManager.shared.signIn(
					appleUserID: credential.user,
					email: credential.email,
					firstName: credential.fullName?.givenName,
					lastName: credential.fullName?.familyName,
					identityToken: credential.identityToken,
					realUserStatus: realUserStatus
				)
				if outcome == .existingUser {
					onComplete?([])
				} else {
					await addSources()
				}
			} catch {
				Self.logger.error("Sign in error: \(error.localizedDescription)")
				showAuthError(error.localizedDescription)
			}
		}
	}

	func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
		let nsError = error as NSError
		guard nsError.domain == ASAuthorizationError.errorDomain,
			  nsError.code == ASAuthorizationError.canceled.rawValue else {
			Self.logger.error("Sign in with Apple failed: \(error.localizedDescription)")
			showAuthError(error.localizedDescription)
			return
		}
		Self.logger.info("Sign in with Apple cancelled by user")
	}
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension OnboardingRegistrationPageViewController: ASAuthorizationControllerPresentationContextProviding {

	func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
		if let window = view.window { return window }
		guard let scene = UIApplication.shared.connectedScenes
			.compactMap({ $0 as? UIWindowScene }).first else {
			fatalError("No UIWindowScene available")
		}
		return scene.keyWindow ?? UIWindow(windowScene: scene)
	}
}
