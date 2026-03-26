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
/// Always starts in reconnect mode. The user can tap "Create a new account instead"
/// to switch to sign-in (creation) mode.
final class RegistrationViewController: UIViewController {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Auth")

	private enum Mode { case reconnect, signIn }

	private var mode: Mode {
		didSet { applyMode() }
	}

	/// Called after a successful sign-in or reconnect, just before dismissal.
	var didSucceedHandler: (() -> Void)?

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
		label.font = .systemFont(ofSize: 28, weight: .bold)
		label.textAlignment = .center
		label.numberOfLines = 0
		return label
	}()

	private let subtitleLabel: UILabel = {
		let label = UILabel()
		label.font = .systemFont(ofSize: 16)
		label.textColor = .secondaryLabel
		label.textAlignment = .center
		label.numberOfLines = 0
		return label
	}()

	/// Fast reconnect — only shown when a stored identity exists.
	private let reconnectButton: UIButton = {
		var config = UIButton.Configuration.filled()
		config.title = "Reconnect"
		config.cornerStyle = .medium
		config.baseBackgroundColor = .systemBlue
		config.baseForegroundColor = .white
		let button = UIButton(configuration: config)
		button.translatesAutoresizingMaskIntoConstraints = false
		return button
	}()

	/// "Continue with Apple" — shown in reconnect mode for Apple-sign-in reconnection.
	private let reconnectAppleButton: ASAuthorizationAppleIDButton = {
		let button = ASAuthorizationAppleIDButton(type: .continue, style: .black)
		button.cornerRadius = 12
		button.translatesAutoresizingMaskIntoConstraints = false
		return button
	}()

	/// "Sign up with Apple" — shown in sign-in (creation) mode.
	private let createAppleButton: ASAuthorizationAppleIDButton = {
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

	/// Shown in reconnect mode — switches to creation mode.
	private let switchModeButton: UIButton = {
		let button = UIButton(type: .system)
		button.setTitle("Create a new account instead", for: .normal)
		button.titleLabel?.font = .systemFont(ofSize: 14)
		button.translatesAutoresizingMaskIntoConstraints = false
		return button
	}()

	/// Retry Face ID — shown in reconnect mode when Face ID is enabled.
	private let retryFaceIDButton: UIButton = {
		var config = UIButton.Configuration.tinted()
		config.title = "Use Face ID"
		config.image = UIImage(systemName: "faceid")
		config.imagePadding = 8
		config.cornerStyle = .medium
		let button = UIButton(configuration: config)
		button.translatesAutoresizingMaskIntoConstraints = false
		return button
	}()

	/// Shown in sign-in mode — switches back to reconnect mode.
	private let backToReconnectButton: UIButton = {
		let button = UIButton(type: .system)
		button.setTitle("Sign in to existing account", for: .normal)
		button.titleLabel?.font = .systemFont(ofSize: 14)
		button.translatesAutoresizingMaskIntoConstraints = false
		return button
	}()

	// MARK: - Init

	init() {
		self.mode = .reconnect
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		self.mode = .reconnect
		super.init(coder: coder)
	}

	// MARK: - Lifecycle

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if AppDefaults.shared.faceIDEnabled && AuthManager.shared.isRegistered {
			authenticateWithFaceID()
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = .systemBackground

		reconnectButton.addTarget(self, action: #selector(handleReconnect), for: .touchUpInside)
		reconnectAppleButton.addTarget(self, action: #selector(handleReconnectApple), for: .touchUpInside)
		createAppleButton.addTarget(self, action: #selector(handleCreateApple), for: .touchUpInside)
		retryFaceIDButton.addTarget(self, action: #selector(handleRetryFaceID), for: .touchUpInside)
		switchModeButton.addTarget(self, action: #selector(switchToSignIn), for: .touchUpInside)
		backToReconnectButton.addTarget(self, action: #selector(switchToReconnect), for: .touchUpInside)

		stackView.addArrangedSubview(titleLabel)
		stackView.addArrangedSubview(subtitleLabel)
		stackView.addArrangedSubview(retryFaceIDButton)
		stackView.addArrangedSubview(reconnectButton)
		stackView.addArrangedSubview(reconnectAppleButton)
		stackView.addArrangedSubview(createAppleButton)
		stackView.addArrangedSubview(activityIndicator)
		stackView.addArrangedSubview(switchModeButton)
		stackView.addArrangedSubview(backToReconnectButton)

		view.addSubview(stackView)
		NSLayoutConstraint.activate([
			stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
			stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
			stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
			retryFaceIDButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
			retryFaceIDButton.heightAnchor.constraint(equalToConstant: 50),
			reconnectButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
			reconnectButton.heightAnchor.constraint(equalToConstant: 50),
			reconnectAppleButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
			reconnectAppleButton.heightAnchor.constraint(equalToConstant: 50),
			createAppleButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
			createAppleButton.heightAnchor.constraint(equalToConstant: 50),
		])

		applyMode()
	}

	// MARK: - Mode switching

	private func applyMode() {
		guard isViewLoaded else { return }
		switch mode {
		case .reconnect:
			titleLabel.text = "Welcome back"
			subtitleLabel.text = "Sign in with Apple to restore access to your account."
			retryFaceIDButton.isHidden = !(AppDefaults.shared.faceIDEnabled && AuthManager.shared.isRegistered)
			reconnectButton.isHidden = !AuthManager.shared.isRegistered
			reconnectAppleButton.isHidden = false
			createAppleButton.isHidden = true
			switchModeButton.isHidden = false
			backToReconnectButton.isHidden = true
		case .signIn:
			titleLabel.text = "Create your account"
			subtitleLabel.text = "Sign in with Apple to get started.\nNo password needed."
			retryFaceIDButton.isHidden = true
			reconnectButton.isHidden = true
			reconnectAppleButton.isHidden = true
			createAppleButton.isHidden = false
			switchModeButton.isHidden = true
			backToReconnectButton.isHidden = false
		}
	}

	@objc private func switchToSignIn() {
		mode = .signIn
	}

	@objc private func switchToReconnect() {
		mode = .reconnect
	}

	// MARK: - Actions

	/// Fast reconnect via stored Keychain identity (shown only when isRegistered).
	@objc private func handleReconnect() {
		setLoading(true)
		Task { @MainActor in
			defer { setLoading(false) }
			do {
				try await AuthManager.shared.reconnect()
				didSucceedHandler?()
				dismiss(animated: true)
			} catch {
				Self.logger.error("Reconnect error: \(error.localizedDescription)")
				showError(error.localizedDescription)
			}
		}
	}

	@objc private func handleRetryFaceID() {
		authenticateWithFaceID()
	}

	@objc private func handleReconnectApple() {
		triggerAppleSignIn()
	}

	@objc private func handleCreateApple() {
		triggerAppleSignIn()
	}

	private func triggerAppleSignIn() {
		let provider = ASAuthorizationAppleIDProvider()
		let request = provider.createRequest()
		request.requestedScopes = [.email, .fullName]

		let controller = ASAuthorizationController(authorizationRequests: [request])
		controller.delegate = self
		controller.presentationContextProvider = self
		controller.performRequests()
	}

	// MARK: - State helpers

	private func setLoading(_ loading: Bool) {
		retryFaceIDButton.isEnabled = !loading
		reconnectButton.isEnabled = !loading
		reconnectAppleButton.isEnabled = !loading
		createAppleButton.isEnabled = !loading
		switchModeButton.isEnabled = !loading
		backToReconnectButton.isEnabled = !loading
		if loading {
			activityIndicator.startAnimating()
		} else {
			activityIndicator.stopAnimating()
		}
	}

	private func authenticateWithFaceID() {
		let context = LAContext()
		var error: NSError?
		guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
			Self.logger.info("Biometrics unavailable: \(error?.localizedDescription ?? "unknown")")
			return
		}
		let reason = NSLocalizedString("Reconnect to your Second Stream account", comment: "Face ID reason")
		context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, authError in
			DispatchQueue.main.async {
				guard let self else { return }
				if success {
					self.handleReconnect()
				} else {
					Self.logger.info("Face ID not completed: \(authError?.localizedDescription ?? "cancelled")")
				}
			}
		}
	}

	private func showError(_ message: String, title: String = "Failed") {
		let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "OK", style: .default))
		present(alert, animated: true)
	}

	private func showError(title: String, message: String) {
		showError(message, title: title)
	}
}

// MARK: - ASAuthorizationControllerDelegate

extension RegistrationViewController: ASAuthorizationControllerDelegate {

	func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
		guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
			return
		}

		if mode == .reconnect {
			// Reconnect using the Apple user ID — email not required.
			setLoading(true)
			Task { @MainActor in
				defer { setLoading(false) }
				do {
					try await AuthManager.shared.reconnect(overrideAppleUserID: credential.user)
					didSucceedHandler?()
					dismiss(animated: true)
				} catch {
					Self.logger.error("Reconnect (Apple) error: \(error.localizedDescription)")
					showError(error.localizedDescription)
				}
			}
			return
		}

		// Creation flow
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
				// Identity stored — fall back to reconnect().
				Self.logger.info("Apple returned no email; using reconnect() path")
				setLoading(true)
				Task { @MainActor in
					defer { setLoading(false) }
					do {
						try await AuthManager.shared.reconnect()
						didSucceedHandler?()
						dismiss(animated: true)
					} catch {
						showError(error.localizedDescription)
					}
				}
			} else {
				showError(
					title: "Account Setup Incomplete",
					message: "It looks like you previously started signing up but the account wasn't created. To try again, go to Settings → your name → Sign-In & Security → Apps Using Apple ID, find Second Stream, tap it, and select Stop Using Apple ID. Then come back and sign up again."
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
