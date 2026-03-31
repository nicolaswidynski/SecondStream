//
//  RegistrationViewController.swift
//  NetNewsWire-iOS
//
//  Created by Claude on 2026-03-14.
//  Copyright © 2026 STDN. All rights reserved.
//

import UIKit
import AuthenticationServices
import LocalAuthentication
import os.log

/// Handles both reconnection and new-user registration (Sign in with Apple).
///
/// Shows two buttons: "Existing User" (Face ID → Apple Sign In fallback) and "New User" (Apple Sign In).
final class RegistrationViewController: UIViewController {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Auth")

	/// Tracks whether a pending Apple Sign In sheet is for reconnection or new account creation.
	private var pendingAppleSignInIsReconnect = true

	/// Called after a successful sign-in or reconnect, just before dismissal.
	var didSucceedHandler: (() -> Void)?

	// MARK: - UI

	private let stackView: UIStackView = {
		let stack = UIStackView()
		stack.axis = .vertical
		stack.alignment = .center
		stack.spacing = 16
		stack.translatesAutoresizingMaskIntoConstraints = false
		return stack
	}()

	private let titleLabel: UILabel = {
		let label = UILabel()
		label.text = "Second Stream"
		label.font = .systemFont(ofSize: 32, weight: .bold)
		label.textAlignment = .center
		label.numberOfLines = 0
		return label
	}()

	private let existingUserButton: UIButton = {
		var config = UIButton.Configuration.filled()
		config.title = "Existing User"
		config.cornerStyle = .medium
		config.baseBackgroundColor = Assets.Colors.primaryAccent
		config.baseForegroundColor = .white
		let button = UIButton(configuration: config)
		button.translatesAutoresizingMaskIntoConstraints = false
		return button
	}()

	private let newUserButton: UIButton = {
		var config = UIButton.Configuration.tinted()
		config.title = "New User"
		config.cornerStyle = .medium
		let button = UIButton(configuration: config)
		button.translatesAutoresizingMaskIntoConstraints = false
		return button
	}()

	private let activityIndicator: UIActivityIndicatorView = {
		let indicator = UIActivityIndicatorView(style: .medium)
		indicator.hidesWhenStopped = true
		return indicator
	}()

	// MARK: - Lifecycle

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = Assets.Colors.background

		existingUserButton.addTarget(self, action: #selector(handleExistingUser), for: .touchUpInside)
		newUserButton.addTarget(self, action: #selector(handleNewUser), for: .touchUpInside)

		stackView.addArrangedSubview(titleLabel)
		stackView.setCustomSpacing(48, after: titleLabel)
		stackView.addArrangedSubview(existingUserButton)
		stackView.addArrangedSubview(newUserButton)
		stackView.addArrangedSubview(activityIndicator)

		view.addSubview(stackView)
		NSLayoutConstraint.activate([
			stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
			stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
			stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
			existingUserButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
			existingUserButton.heightAnchor.constraint(equalToConstant: 50),
			newUserButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
			newUserButton.heightAnchor.constraint(equalToConstant: 50),
		])
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		// Silently attempt Face ID on appear. If it fails, the user can tap "Existing User" to retry.
		if AppDefaults.shared.faceIDEnabled {
			authenticateWithFaceID(fallBackToApple: false)
		}
	}

	// MARK: - Actions

	@objc private func handleExistingUser() {
		if AppDefaults.shared.faceIDEnabled {
			authenticateWithFaceID(fallBackToApple: true)
		} else {
			triggerAppleSignIn(isReconnect: true)
		}
	}

	@objc private func handleNewUser() {
		triggerAppleSignIn(isReconnect: false)
	}

	// MARK: - Face ID

	private func authenticateWithFaceID(fallBackToApple: Bool) {
		let context = LAContext()
		var error: NSError?
		guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
			Self.logger.info("Biometrics unavailable: \(error?.localizedDescription ?? "unknown")")
			if fallBackToApple { triggerAppleSignIn(isReconnect: true) }
			return
		}
		let reason = NSLocalizedString("Reconnect to your Second Stream account", comment: "Face ID reason")
		context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, authError in
			DispatchQueue.main.async {
				guard let self else { return }
				if success {
					self.reconnect()
				} else {
					Self.logger.info("Face ID not completed: \(authError?.localizedDescription ?? "cancelled")")
					if fallBackToApple { self.triggerAppleSignIn(isReconnect: true) }
				}
			}
		}
	}

	// MARK: - Apple Sign In

	private func triggerAppleSignIn(isReconnect: Bool) {
		pendingAppleSignInIsReconnect = isReconnect
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
		setLoading(true)
		Task { @MainActor in
			defer { setLoading(false) }
			do {
				try await AuthManager.shared.reconnect(overrideAppleUserID: overrideAppleUserID)
				didSucceedHandler?()
				dismiss(animated: true)
			} catch AuthError.noStoredIdentity {
				// Keychain inaccessible (e.g. timing after unlock) — fall back to Apple Sign In.
				Self.logger.info("Reconnect: no stored identity, falling back to Apple Sign In")
				triggerAppleSignIn(isReconnect: true)
			} catch {
				Self.logger.error("Reconnect error: \(error.localizedDescription)")
				showError(error.localizedDescription)
			}
		}
	}

	// MARK: - Helpers

	private func setLoading(_ loading: Bool) {
		existingUserButton.isEnabled = !loading
		newUserButton.isEnabled = !loading
		if loading {
			activityIndicator.startAnimating()
		} else {
			activityIndicator.stopAnimating()
		}
	}

	private func showError(_ message: String, title: String = "Failed") {
		let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "OK", style: .default))
		present(alert, animated: true)
	}
}

// MARK: - ASAuthorizationControllerDelegate

extension RegistrationViewController: ASAuthorizationControllerDelegate {

	func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
		guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
			return
		}

		if pendingAppleSignInIsReconnect {
			reconnect(overrideAppleUserID: credential.user)
			return
		}

		// New account creation flow
		let appleUserID = credential.user
		let email = credential.email ?? ""
		let firstName = credential.fullName?.givenName
		let lastName = credential.fullName?.familyName
		let identityToken = credential.identityToken
		let realUserStatus: String = {
			switch credential.realUserStatus {
			case .likelyReal: return "likelyReal"
			case .unknown: return "unknown"
			case .unsupported: return "unsupported"
			@unknown default: return "unknown"
			}
		}()

		guard !email.isEmpty else {
			if AuthManager.shared.isConnected {
				didSucceedHandler?()
				dismiss(animated: true)
			} else if AuthManager.shared.isRegistered {
				Self.logger.info("Apple returned no email; using reconnect() path")
				reconnect()
			} else {
				showError(
					"It looks like you previously started signing up but the account wasn't created. To try again, go to Settings → your name → Sign-In & Security → Apps Using Apple ID, find Second Stream, tap it, and select Stop Using Apple ID. Then come back and sign up again.",
					title: "Account Setup Incomplete"
				)
			}
			return
		}

		setLoading(true)

		Task { @MainActor in
			defer { setLoading(false) }
			do {
				try await AuthManager.shared.register(
					email: email,
					appleUserID: appleUserID,
					firstName: firstName,
					lastName: lastName,
					identityToken: identityToken,
					realUserStatus: realUserStatus
				)
				didSucceedHandler?()
				dismiss(animated: true)
			} catch {
				Self.logger.error("Registration error: \(error.localizedDescription)")
				showError(error.localizedDescription)
			}
		}
	}

	func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
		let nsError = error as NSError
		guard nsError.domain == ASAuthorizationError.errorDomain,
			  nsError.code == ASAuthorizationError.canceled.rawValue else {
			Self.logger.error("Sign in with Apple failed: \(error.localizedDescription)")
			showError(error.localizedDescription)
			return
		}
		Self.logger.info("Sign in with Apple cancelled by user")
	}
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension RegistrationViewController: ASAuthorizationControllerPresentationContextProviding {

	func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
		if let window = view.window {
			return window
		}
		guard let scene = UIApplication.shared.connectedScenes
			.compactMap({ $0 as? UIWindowScene })
			.first else {
			fatalError("No UIWindowScene available")
		}
		return scene.keyWindow ?? UIWindow(windowScene: scene)
	}
}
