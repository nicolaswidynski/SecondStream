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

/// Handles reconnection and new-user registration via Sign in with Apple.
///
/// Shows a single "Reconnect" button. Face ID is attempted automatically on appear when enabled.
/// The Apple credential's email presence determines the operation — email present means first-time
/// authorization, so `register()` is called and the server decides (201 = existing, 202 = new);
/// no email means a returning user, so `reconnect()` is called.
final class RegistrationViewController: UIViewController {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Auth")

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

	private lazy var reconnectButton: UIButton = {
		var config = UIButton.Configuration.filled()
		config.title = "Reconnect"
		config.cornerStyle = .medium
		config.baseBackgroundColor = Assets.Colors.primaryAccent
		config.baseForegroundColor = .white
		let button = UIButton(configuration: config)
		button.translatesAutoresizingMaskIntoConstraints = false
		button.addTarget(self, action: #selector(handleReconnect), for: .touchUpInside)
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

		stackView.addArrangedSubview(titleLabel)
		stackView.setCustomSpacing(48, after: titleLabel)
		stackView.addArrangedSubview(reconnectButton)
		stackView.addArrangedSubview(activityIndicator)

		view.addSubview(stackView)
		NSLayoutConstraint.activate([
			stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
			stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
			stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
			reconnectButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
			reconnectButton.heightAnchor.constraint(equalToConstant: 50),
		])
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		guard AppDefaults.shared.faceIDEnabled else { return }
		// LAContext silently fails with notInteractive if the app isn't fully active yet.
		// If we're already active (e.g. forced sign-out mid-session), a short delay is enough.
		// If we're still launching, wait for didBecomeActive before triggering.
		if UIApplication.shared.applicationState == .active {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
				self?.authenticateWithFaceID(fallBackToApple: false)
			}
		} else {
			NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
		}
	}

	@objc private func appDidBecomeActive() {
		NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
		guard AppDefaults.shared.faceIDEnabled else { return }
		authenticateWithFaceID(fallBackToApple: false)
	}

	// MARK: - Actions

	@objc private func handleReconnect() {
		triggerAppleSignIn()
	}

	// MARK: - Face ID

	private func authenticateWithFaceID(fallBackToApple: Bool) {
		let context = LAContext()
		var error: NSError?
		guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
			Self.logger.info("Biometrics unavailable: \(error?.localizedDescription ?? "unknown")")
			if fallBackToApple { triggerAppleSignIn() }
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
					if fallBackToApple { self.triggerAppleSignIn() }
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

	// MARK: - Reconnect (Face ID path — no Apple credential)

	private func reconnect() {
		setLoading(true)
		Task { @MainActor in
			defer { setLoading(false) }
			do {
				_ = try await AuthManager.shared.reconnect()
				didSucceedHandler?()
				dismiss(animated: true)
			} catch AuthError.noStoredIdentity {
				Self.logger.info("Reconnect: no stored identity, falling back to Apple Sign In")
				triggerAppleSignIn()
			} catch {
				Self.logger.error("Reconnect error: \(error.localizedDescription)")
				showError(error.localizedDescription)
			}
		}
	}

	// MARK: - Helpers

	private func setLoading(_ loading: Bool) {
		reconnectButton.isEnabled = !loading
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

		let realUserStatus: String = {
			switch credential.realUserStatus {
			case .likelyReal: return "likelyReal"
			case .unknown: return "unknown"
			case .unsupported: return "unsupported"
			@unknown default: return "unknown"
			}
		}()

		setLoading(true)
		Task { @MainActor in
			defer { setLoading(false) }
			do {
				_ = try await AuthManager.shared.signIn(
					appleUserID: credential.user,
					email: credential.email,
					firstName: credential.fullName?.givenName,
					lastName: credential.fullName?.familyName,
					identityToken: credential.identityToken,
					realUserStatus: realUserStatus
				)
				didSucceedHandler?()
				dismiss(animated: true)
			} catch {
				Self.logger.error("Sign in error: \(error.localizedDescription)")
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
