//
//  OnboardingRegistrationPageViewController.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-11.
//  Copyright © 2026 STDN. All rights reserved.
//

import UIKit
import AuthenticationServices
import LocalAuthentication
import Account
import os.log

/// Page 3 of onboarding: account creation / sign-in, followed by adding selected sources.
///
/// After a successful auth, each selected source is added via its manager's webhook, one by one,
/// with progress shown in the UI. The caller receives the resulting `[AddFeedRequest]` via
/// `onComplete` and is responsible for actually creating the feeds in the account.
@MainActor final class OnboardingRegistrationPageViewController: UIViewController {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "OnboardingRegistration")

	/// Sources chosen by the user on page 2. Set by `OnboardingViewController` before navigation.
	var selectedSources: [DiscoverSourceItem] = []

	/// Called after all webhook calls finish. Receives the assembled feed requests.
	var onComplete: (([AddFeedRequest]) -> Void)?

	// MARK: - State

	private var pendingIsReconnect = true

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

	private lazy var existingUserButton: UIButton = {
		var config = UIButton.Configuration.filled()
		config.title = "Already a User"
		config.cornerStyle = .medium
		config.baseBackgroundColor = Assets.Colors.primaryAccent
		config.baseForegroundColor = .white
		let button = UIButton(configuration: config)
		button.translatesAutoresizingMaskIntoConstraints = false
		button.addTarget(self, action: #selector(handleExistingUser), for: .touchUpInside)
		return button
	}()

	private lazy var newUserButton: UIButton = {
		var config = UIButton.Configuration.tinted()
		config.title = "Create an Account"
		config.cornerStyle = .medium
		let button = UIButton(configuration: config)
		button.translatesAutoresizingMaskIntoConstraints = false
		button.addTarget(self, action: #selector(handleNewUser), for: .touchUpInside)
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
		authStack.addArrangedSubview(existingUserButton)
		authStack.addArrangedSubview(newUserButton)
		authStack.addArrangedSubview(authSpinner)
		view.addSubview(authStack)

		NSLayoutConstraint.activate([
			existingUserButton.widthAnchor.constraint(equalTo: authStack.widthAnchor),
			existingUserButton.heightAnchor.constraint(equalToConstant: 50),
			newUserButton.widthAnchor.constraint(equalTo: authStack.widthAnchor),
			newUserButton.heightAnchor.constraint(equalToConstant: 50),
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

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		guard AppDefaults.shared.faceIDEnabled else { return }
		if UIApplication.shared.applicationState == .active {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
				self?.authenticateWithFaceID(fallBackToApple: false)
			}
		}
	}

	// MARK: - Auth actions

	@objc private func handleExistingUser() {
		pendingIsReconnect = true
		if AppDefaults.shared.faceIDEnabled {
			authenticateWithFaceID(fallBackToApple: true)
		} else {
			triggerAppleSignIn()
		}
	}

	@objc private func handleNewUser() {
		pendingIsReconnect = false
		triggerAppleSignIn()
	}

	// MARK: - Face ID

	private func authenticateWithFaceID(fallBackToApple: Bool) {
		let context = LAContext()
		var error: NSError?
		guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
			if fallBackToApple { triggerAppleSignIn() }
			return
		}
		let reason = NSLocalizedString("Reconnect to your Second Stream account", comment: "Face ID reason")
		context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, _ in
			DispatchQueue.main.async {
				guard let self else { return }
				if success {
					self.reconnect()
				} else if fallBackToApple {
					self.triggerAppleSignIn()
				}
			}
		}
	}

	// MARK: - Apple Sign In

	private func triggerAppleSignIn() {
		let provider = ASAuthorizationAppleIDProvider()
		let request = provider.createRequest()
		request.requestedScopes = [.email, .fullName]
		let controller = ASAuthorizationController(authorizationRequests: [request])
		controller.delegate = self
		controller.presentationContextProvider = self
		controller.performRequests()
	}

	// MARK: - Reconnect

	private func reconnect(overrideAppleUserID: String? = nil) {
		setAuthLoading(true)
		Task { @MainActor in
			defer { setAuthLoading(false) }
			do {
				try await AuthManager.shared.reconnect(overrideAppleUserID: overrideAppleUserID)
				await addSources()
			} catch AuthError.noStoredIdentity {
				pendingIsReconnect = true
				triggerAppleSignIn()
			} catch {
				showAuthError(error.localizedDescription)
			}
		}
	}

	// MARK: - Helpers

	private func setAuthLoading(_ loading: Bool) {
		existingUserButton.isEnabled = !loading
		newUserButton.isEnabled = !loading
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

		// Sync server subscriptions (restores feeds added on other devices).
		do {
			try await SubscriptionSyncManager.shared.sync()
		} catch {
			let alert = UIAlertController(title: "Sync Failed", message: error.localizedDescription, preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: "OK", style: .default))
			present(alert, animated: true)
		}

		// Brief pause so the user sees "All done!" before dismissal.
		try? await Task.sleep(nanoseconds: 700_000_000)
		onComplete?(feedRequests)
	}
}

// MARK: - ASAuthorizationControllerDelegate

extension OnboardingRegistrationPageViewController: ASAuthorizationControllerDelegate {

	func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
		guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }

		if pendingIsReconnect {
			reconnect(overrideAppleUserID: credential.user)
			return
		}

		let email = credential.email ?? ""
		guard !email.isEmpty else {
			if AuthManager.shared.isConnected {
				Task { await addSources() }
			} else if AuthManager.shared.isRegistered {
				Self.logger.info("Apple returned no email; falling back to reconnect()")
				reconnect()
			} else {
				showAuthError(
					"It looks like you previously started signing up but the account wasn't created. To try again, go to Settings → your name → Sign-In & Security → Apps Using Apple ID, find Second Stream, tap it, and select Stop Using Apple ID. Then come back and sign up again."
				)
			}
			return
		}

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
				try await AuthManager.shared.register(
					email: email,
					appleUserID: credential.user,
					firstName: credential.fullName?.givenName,
					lastName: credential.fullName?.familyName,
					identityToken: credential.identityToken,
					realUserStatus: realUserStatus
				)
				await addSources()
			} catch {
				Self.logger.error("Registration error: \(error.localizedDescription)")
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
