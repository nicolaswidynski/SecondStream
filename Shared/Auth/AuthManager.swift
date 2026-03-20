//
//  AuthManager.swift
//  NetNewsWire
//
//  Created by Claude on 2026-03-14.
//  Copyright © 2026 STDN. All rights reserved.
//

import Foundation
import Security
import os.log

/// Manages user registration and identity for the app's backend.
///
/// The unique user ID is the Apple `sub` claim — a stable, opaque identifier
/// assigned by Apple per user per developer team. It is stored in the Keychain
/// so it persists across app updates (but not across full uninstall/reinstall,
/// which is standard behaviour). The server (NocoDB) uses it as the primary key
/// for the user record.
@MainActor final class AuthManager {

	static let shared = AuthManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Auth")

	private let manageUserURL = URL(string: "https://n8n.nwidynski.com/webhook/manage-user")!

	// MARK: - Keychain keys

	private let keychainService = Bundle.main.bundleIdentifier ?? "com.ranchero.NetNewsWire"
	private let appleUserIDKey = "appleUserID"

	// MARK: - Public state

	/// Whether the user has a stored Apple user ID (identity) on this device.
	var isRegistered: Bool {
		appleUserID != nil
	}

	/// Whether the user is actively connected to the backend.
	/// False when explicitly disconnected, even if the identity is still stored.
	/// Existing users (registered before this flag existed) default to connected.
	var isConnected: Bool {
		isRegistered && !isExplicitlyDisconnected
	}

	/// The stored Apple `sub` identifier, or `nil` if the user hasn't registered yet.
	var appleUserID: String? {
		keychainRead(key: appleUserIDKey)
	}

	// MARK: - Disconnect flag

	private let disconnectedKey = "authIsDisconnected"

	private var isExplicitlyDisconnected: Bool {
		get { UserDefaults.standard.bool(forKey: disconnectedKey) }
		set { UserDefaults.standard.set(newValue, forKey: disconnectedKey) }
	}

	// MARK: - Registration

	/// Registers the user by sending their info to the backend and persisting their Apple user ID locally.
	/// - Parameters:
	///   - email: The email address returned by Sign in with Apple (only on first sign-in).
	///   - appleUserID: The stable `sub` identifier from the Apple identity token.
	///   - firstName: Given name, only present on first sign-in.
	///   - lastName: Family name, only present on first sign-in.
	///   - identityToken: Signed JWT from Apple, decoded to extract `is_private_email`.
	///   - realUserStatus: Apple's assessment of whether this is a real person.
	func register(
		email: String,
		appleUserID: String,
		firstName: String?,
		lastName: String?,
		identityToken: Data?,
		realUserStatus: String
	) async throws {
		guard let token = bearerToken else {
			Self.logger.error("No bearer token available")
			throw AuthError.missingToken
		}

		let tokenClaims = identityToken.flatMap { decodeJWTPayload($0) }
		// `is_private_email` can be Bool or String in the JWT depending on Apple's implementation.
		let isPrivateEmail: Bool = {
			if let value = tokenClaims?["is_private_email"] as? Bool { return value }
			if let value = tokenClaims?["is_private_email"] as? String { return value == "true" }
			return false
		}()

		var request = URLRequest(url: manageUserURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

		var body: [String: Any] = [
			"apple_user_id": appleUserID,
			"email": email,
			"is_private_email": isPrivateEmail,
			"real_user_status": realUserStatus,
			"operation": "creation"
		]
		if let firstName { body["first_name"] = firstName }
		if let lastName { body["last_name"] = lastName }

		request.httpBody = try JSONSerialization.data(withJSONObject: body)

		let (data, response) = try await URLSession.shared.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse else {
			throw AuthError.invalidResponse
		}

		guard (200...299).contains(httpResponse.statusCode) else {
			let rawBody = String(data: data, encoding: .utf8) ?? "(empty)"
			Self.logger.error("Registration failed [\(httpResponse.statusCode)]: \(rawBody)")
			throw AuthError.serverError(statusCode: httpResponse.statusCode, body: Self.webhookMessage(from: data))
		}

		// Persist the Apple user ID locally only after a successful server response.
		keychainWrite(key: appleUserIDKey, value: appleUserID)
		isExplicitlyDisconnected = false
		Self.logger.info("User registered successfully")
	}

	/// Marks the user as disconnected without erasing the stored identity.
	/// The identity is preserved so the user can reconnect without Sign in with Apple.
	func disconnect() {
		isExplicitlyDisconnected = true
		Self.logger.info("User disconnected")
	}

	/// Reconnects using a stored or freshly-obtained Apple user ID.
	/// - Parameter overrideAppleUserID: When provided (e.g. from a new Sign in with Apple flow),
	///   this ID is used instead of the Keychain value and is persisted on success.
	///   When nil, falls back to the stored Keychain identity.
	func reconnect(overrideAppleUserID: String? = nil) async throws {
		let idToUse = overrideAppleUserID ?? appleUserID
		guard let storedID = idToUse else {
			throw AuthError.noStoredIdentity
		}
		guard let token = bearerToken else {
			throw AuthError.missingToken
		}

		var request = URLRequest(url: manageUserURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

		let body: [String: Any] = ["apple_user_id": storedID, "operation": "reconnection"]
		request.httpBody = try JSONSerialization.data(withJSONObject: body)

		let (data, response) = try await URLSession.shared.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse else {
			throw AuthError.invalidResponse
		}
		guard (200...299).contains(httpResponse.statusCode) else {
			let rawBody = String(data: data, encoding: .utf8) ?? "(empty)"
			Self.logger.error("Reconnect failed [\(httpResponse.statusCode)]: \(rawBody)")
			throw AuthError.serverError(statusCode: httpResponse.statusCode, body: Self.webhookMessage(from: data))
		}

		// Persist the ID when reconnecting via a fresh Apple sign-in (no prior Keychain entry).
		if overrideAppleUserID != nil {
			keychainWrite(key: appleUserIDKey, value: storedID)
		}
		isExplicitlyDisconnected = false
		Self.logger.info("User reconnected successfully")
	}

	/// Sends a delete request to the backend and wipes the local identity.
	/// This is non-recoverable: the user will need to create a new account.
	func deleteAccount() async throws {
		guard let storedID = appleUserID else {
			throw AuthError.noStoredIdentity
		}
		guard let token = bearerToken else {
			throw AuthError.missingToken
		}

		var request = URLRequest(url: manageUserURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

		let body: [String: Any] = ["apple_user_id": storedID, "operation": "deletion"]
		request.httpBody = try JSONSerialization.data(withJSONObject: body)

		let (data, response) = try await URLSession.shared.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse else {
			throw AuthError.invalidResponse
		}
		guard (200...299).contains(httpResponse.statusCode) else {
			let rawBody = String(data: data, encoding: .utf8) ?? "(empty)"
			Self.logger.error("Delete account failed [\(httpResponse.statusCode)]: \(rawBody)")
			throw AuthError.serverError(statusCode: httpResponse.statusCode, body: Self.webhookMessage(from: data))
		}

		clearStoredIdentity()
		Self.logger.info("Account deleted successfully")
	}

	/// Removes the stored Apple user ID from the Keychain (full sign-out, cannot auto-reconnect).
	func clearStoredIdentity() {
		keychainDelete(key: appleUserIDKey)
		isExplicitlyDisconnected = false
	}

	// MARK: - Error helpers

	/// Extracts the `"message"` field from a JSON webhook error body.
	/// Falls back to the raw UTF-8 body if the field is absent or unparseable.
	private static func webhookMessage(from data: Data) -> String {
		if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		   let message = json["message"] as? String {
			return message
		}
		return String(data: data, encoding: .utf8) ?? "Unknown error"
	}

	// MARK: - Bearer token

	private var bearerToken: String? {
		guard let tokenURL = Bundle.main.url(forResource: "podcast_token", withExtension: "txt"),
			  let token = try? String(contentsOf: tokenURL, encoding: .utf8) else {
			Self.logger.error("Failed to load bearer token from file")
			return nil
		}
		return token.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: - JWT

	/// Decodes the payload of a JWT without verifying the signature.
	/// iOS has already verified the token before handing it to us.
	private func decodeJWTPayload(_ tokenData: Data) -> [String: Any]? {
		guard let tokenString = String(data: tokenData, encoding: .utf8) else {
			return nil
		}
		let parts = tokenString.split(separator: ".", omittingEmptySubsequences: false)
		guard parts.count == 3 else {
			return nil
		}
		var base64 = String(parts[1])
		// Base64url → Base64: replace URL-safe chars and pad to a multiple of 4.
		base64 = base64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
		let remainder = base64.count % 4
		if remainder > 0 {
			base64 += String(repeating: "=", count: 4 - remainder)
		}
		guard let data = Data(base64Encoded: base64),
			  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			return nil
		}
		return json
	}

	// MARK: - Keychain helpers

	private func keychainRead(key: String) -> String? {
		let query: [CFString: Any] = [
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: keychainService,
			kSecAttrAccount: key,
			kSecReturnData: true,
			kSecMatchLimit: kSecMatchLimitOne
		]
		var result: AnyObject?
		let status = SecItemCopyMatching(query as CFDictionary, &result)
		guard status == errSecSuccess,
			  let data = result as? Data,
			  let value = String(data: data, encoding: .utf8) else {
			return nil
		}
		return value
	}

	private func keychainWrite(key: String, value: String) {
		guard let data = value.data(using: .utf8) else {
			return
		}
		keychainDelete(key: key)
		let attributes: [CFString: Any] = [
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: keychainService,
			kSecAttrAccount: key,
			kSecValueData: data
		]
		let status = SecItemAdd(attributes as CFDictionary, nil)
		if status != errSecSuccess {
			Self.logger.error("Failed to write to Keychain: \(status)")
		}
	}

	private func keychainDelete(key: String) {
		let query: [CFString: Any] = [
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: keychainService,
			kSecAttrAccount: key
		]
		SecItemDelete(query as CFDictionary)
	}
}

// MARK: - AuthError

enum AuthError: LocalizedError {
	case missingToken
	case invalidResponse
	case noStoredIdentity
	case serverError(statusCode: Int, body: String)

	var errorDescription: String? {
		switch self {
		case .missingToken:
			return "Authentication token not found."
		case .invalidResponse:
			return "Received an invalid response from the server."
		case .noStoredIdentity:
			return "No stored account identity found."
		case .serverError(_, let body):
			return body
		}
	}
}
