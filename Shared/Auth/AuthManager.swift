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

	private let client = SecondStreamAPIClient.shared

	// MARK: - Keychain keys

	private let keychainService = Bundle.main.bundleIdentifier ?? "com.ranchero.NetNewsWire"
	private let appleUserIDKey = "appleUserID"
	private let sessionTokenKey = "userSessionToken"

	// MARK: - Public state

	/// Whether the user has a stored Apple user ID (identity) on this device.
	var isRegistered: Bool {
		if isSimulatingIOSSignOut { return false }
		return appleUserID != nil
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

	/// Per-user session token issued by the server after `manage-user`.
	/// Used as the bearer token on all non-auth requests. `nil` until the user
	/// has gone through registration or reconnect with a server that issues tokens.
	var sessionToken: String? {
		keychainRead(key: sessionTokenKey)
	}

	// MARK: - Disconnect flag

	private let disconnectedKey = "authIsDisconnected"

	private var isExplicitlyDisconnected: Bool {
		get { UserDefaults.standard.bool(forKey: disconnectedKey) }
		set { UserDefaults.standard.set(newValue, forKey: disconnectedKey) }
	}

	// MARK: - Debug: iOS sign-out simulation

	private let simulatingIOSSignOutKey = "authSimulatingIOSSignOut"

	private var isSimulatingIOSSignOut: Bool {
		get { UserDefaults.standard.bool(forKey: simulatingIOSSignOutKey) }
		set { UserDefaults.standard.set(newValue, forKey: simulatingIOSSignOutKey) }
	}

	/// Simulates the state where iOS has revoked the user session: `isRegistered` returns false,
	/// `isConnected` returns false, but the real Keychain identity is untouched.
	/// Cleared automatically on the next successful reconnect or registration.
	func simulateIOSSignOut() {
		isSimulatingIOSSignOut = true
		isExplicitlyDisconnected = false
		Self.logger.info("DEBUG: simulating iOS-forced sign-out")
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
		let tokenClaims = identityToken.flatMap { decodeJWTPayload($0) }
		let isPrivateEmail: Bool = {
			if let value = tokenClaims?["is_private_email"] as? Bool { return value }
			if let value = tokenClaims?["is_private_email"] as? String { return value == "true" }
			return false
		}()

		let requestID = UUID().uuidString
		var body: [String: Any] = [
			"apple_user_id":    appleUserID,
			"email":            email,
			"is_private_email": isPrivateEmail,
			"real_user_status": realUserStatus,
			"operation":        "creation",
			"request_id":       requestID
		]
		if let firstName { body["first_name"] = firstName }
		if let lastName  { body["last_name"]  = lastName }

		do {
			let (data, statusCode) = try await client.post(to: .manageUser, body: body)
			guard (200...299).contains(statusCode) else {
				throw AuthError.serverError(statusCode: statusCode, body: Self.webhookMessage(from: data))
			}
			let json = Self.firstJSON(from: data)
			if let echoed = json?["request_id"] as? String, echoed != requestID {
				Self.logger.warning("request_id mismatch: sent \(requestID), received \(echoed)")
			}
			if let token = json?["user_token"] as? String, !token.isEmpty {
				saveSessionToken(token)
			} else {
				Self.logger.warning("No user_token in registration response — body: \(String(data: data, encoding: .utf8) ?? "(empty)", privacy: .public)")
			}
		} catch let error as AuthError {
			throw error
		} catch {
			throw AuthError.serverError(statusCode: 0, body: error.localizedDescription)
		}

		keychainWrite(key: appleUserIDKey, value: appleUserID)
		isExplicitlyDisconnected = false
		isSimulatingIOSSignOut = false
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

		let requestID = UUID().uuidString
		let body: [String: Any] = ["apple_user_id": storedID, "operation": "reconnection", "request_id": requestID]

		do {
			let (data, statusCode) = try await client.post(to: .manageUser, body: body)
			guard (200...299).contains(statusCode) else {
				throw AuthError.serverError(statusCode: statusCode, body: Self.webhookMessage(from: data))
			}
			let rawBody = String(data: data, encoding: .utf8) ?? "(empty)"
			Self.logger.info("manage-user reconnect response: \(rawBody, privacy: .public)")
			let json = Self.firstJSON(from: data)
			if let echoed = json?["request_id"] as? String, echoed != requestID {
				Self.logger.warning("request_id mismatch: sent \(requestID), received \(echoed)")
			}
			if let token = json?["user_token"] as? String, !token.isEmpty {
				saveSessionToken(token)
			} else {
				Self.logger.warning("No user_token in reconnect response — body: \(rawBody, privacy: .public)")
			}
		} catch let error as AuthError {
			throw error
		} catch {
			throw AuthError.serverError(statusCode: 0, body: error.localizedDescription)
		}

		if overrideAppleUserID != nil {
			keychainWrite(key: appleUserIDKey, value: storedID)
		}
		isExplicitlyDisconnected = false
		isSimulatingIOSSignOut = false
		Self.logger.info("User reconnected successfully")
	}

	/// Sends a delete request to the backend and wipes the local identity.
	/// This is non-recoverable: the user will need to create a new account.
	func deleteAccount() async throws {
		guard let storedID = appleUserID else {
			throw AuthError.noStoredIdentity
		}

		let requestID = UUID().uuidString
		let body: [String: Any] = ["apple_user_id": storedID, "operation": "deletion", "request_id": requestID]

		do {
			let (data, statusCode) = try await client.post(to: .manageUser, body: body)
			guard (200...299).contains(statusCode) else {
				throw AuthError.serverError(statusCode: statusCode, body: Self.webhookMessage(from: data))
			}
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
			if let echoed = json?["request_id"] as? String, echoed != requestID {
				Self.logger.warning("request_id mismatch: sent \(requestID), received \(echoed)")
			}
		} catch let error as AuthError {
			throw error
		} catch {
			throw AuthError.serverError(statusCode: 0, body: error.localizedDescription)
		}

		clearStoredIdentity()
		Self.logger.info("Account deleted successfully")
	}

	/// Removes the stored Apple user ID and session token from the Keychain (full sign-out).
	func clearStoredIdentity() {
		keychainDelete(key: appleUserIDKey)
		keychainDelete(key: sessionTokenKey)
		isExplicitlyDisconnected = false
	}

	/// Saves the session token to the Keychain.
	private func saveSessionToken(_ token: String) {
		keychainWrite(key: sessionTokenKey, value: token)
		Self.logger.info("Session token saved (length: \(token.count, privacy: .public))")
	}

	// MARK: - Response helpers

	/// Extracts the first JSON object from a webhook response, handling both
	/// a bare object `{...}` and n8n's typical array wrapper `[{...}]`.
	private static func firstJSON(from data: Data) -> [String: Any]? {
		if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
			return obj
		}
		if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
			return arr.first
		}
		return nil
	}

	/// Extracts the `"message"` field from a JSON webhook error body.
	/// Falls back to the raw UTF-8 body if the field is absent or unparseable.
	private static func webhookMessage(from data: Data) -> String {
		if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		   let message = json["message"] as? String {
			return message
		}
		return String(data: data, encoding: .utf8) ?? "Unknown error"
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
		if status != errSecSuccess {
			Self.logger.warning("Keychain read failed for key '\(key)': status \(status) (errSecInteractionNotAllowed=\(status == errSecInteractionNotAllowed))")
		}
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
