//
//  RegistrationViewController.swift
//  NetNewsWire-iOS
//
//  Created by Claude on 2026-03-14.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit
import AuthenticationServices
import os.log

/// Presents the Sign in with Apple sheet and registers the user with the backend.
///
/// Present this modally when `AuthManager.shared.isRegistered` is `false`.
/// Dismiss it (or let the user dismiss it) once registration succeeds.
final class RegistrationViewController: UIViewController {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Auth")

	// MARK: - UI

	private let stackView: UIStackView = {
		let stack = UIStackView()
		stack.axis = .vertical
		stack.alignment = .center
		stack.spacing = 24
		stack.translatesAutoresizingMaskIntoConstraints = false
		return stack
	}()

	private let titleLabel: UILabel = {
		let label = UILabel()
		label.text = "Create your account"
		label.font = .systemFont(ofSize: 28, weight: .bold)
		label.textAlignment = .center
		label.numberOfLines = 0
		return label
	}()

	private let subtitleLabel: UILabel = {
		let label = UILabel()
		label.text = "Sign in with Apple to get started.\nNo password needed."
		label.font = .systemFont(ofSize: 16)
		label.textColor = .secondaryLabel
		label.textAlignment = .center
		label.numberOfLines = 0
		return label
	}()

	private let signInButton: ASAuthorizationAppleIDButton = {
		// Use .signUp style so iOS shows the correct copy on first use.
		let button = ASAuthorizationAppleIDButton(type: .signUp, style: .black)
		button.cornerRadius = 12
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
		view.backgroundColor = .systemBackground
		setupLayout()
		signInButton.addTarget(self, action: #selector(handleSignIn), for: .touchUpInside)
	}

	// MARK: - Layout

	private func setupLayout() {
		stackView.addArrangedSubview(titleLabel)
		stackView.addArrangedSubview(subtitleLabel)
		stackView.addArrangedSubview(signInButton)
		stackView.addArrangedSubview(activityIndicator)

		view.addSubview(stackView)

		NSLayoutConstraint.activate([
			stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
			stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
			stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

			signInButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
			signInButton.heightAnchor.constraint(equalToConstant: 50)
		])
	}

	// MARK: - Actions

	@objc private func handleSignIn() {
		let provider = ASAuthorizationAppleIDProvider()
		let request = provider.createRequest()
		// Request email on every attempt; Apple only returns it on the very first
		// sign-in — subsequent logins return nil, so we rely on the stored appleUserID.
		request.requestedScopes = [.email, .fullName]

		let controller = ASAuthorizationController(authorizationRequests: [request])
		controller.delegate = self
		controller.presentationContextProvider = self
		controller.performRequests()
	}

	// MARK: - State helpers

	private func setLoading(_ loading: Bool) {
		signInButton.isEnabled = !loading
		if loading {
			activityIndicator.startAnimating()
		} else {
			activityIndicator.stopAnimating()
		}
	}

	private func showError(_ message: String) {
		let alert = UIAlertController(title: "Registration Failed", message: message, preferredStyle: .alert)
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

		// `email` is only present on the very first Sign in with Apple for this app.
		// If it's nil the user has already authorised before; we can still update
		// the stored appleUserID without re-sending the email.
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
			// The user has already signed in with Apple previously. If we already
			// have a stored identity we're done; otherwise we can't register without
			// an email — show a helpful message.
			if AuthManager.shared.isRegistered {
				Self.logger.info("Returning user, identity already stored")
				dismiss(animated: true)
			} else {
				showError("Your email address wasn't shared. Please go to Settings > Apple ID > Password & Security > Apps Using Apple ID, remove this app, and try again.")
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
				dismiss(animated: true)
			} catch {
				Self.logger.error("Registration error: \(error.localizedDescription)")
				showError(error.localizedDescription)
			}
		}
	}

	func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
		// ASAuthorizationError.canceled (code 1001) means the user dismissed the sheet — no need to show an alert.
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
		// Unreachable in practice — view must be on screen to trigger auth.
		// A running iOS app always has at least one UIWindowScene.
		guard let scene = UIApplication.shared.connectedScenes
			.compactMap({ $0 as? UIWindowScene })
			.first else {
			fatalError("No UIWindowScene available")
		}
		return scene.keyWindow ?? UIWindow(windowScene: scene)
	}
}
