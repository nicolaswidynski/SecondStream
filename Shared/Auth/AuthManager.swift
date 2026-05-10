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
/// assigned by Apple per user per developer team. It is not a secret so it is
/// stored in `UserDefaults` (wiped on reinstall, preserved on update). The
/// session token IS a secret and lives in the Keychain. The server uses the
/// Apple user ID as the primary key for the user record.
@MainActor final class AuthManager {

	static let shared = AuthManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Auth")

	private let client = SecondStreamAPIClient.shared

	// MARK: - Storage keys

	private let keychainService = Bundle.main.bundleIdentifier ?? "com.stdn.SecondStream"
	/// Legacy Keychain key — kept only for one-time migration to UserDefaults.
	private let appleUserIDKeychainKey = "appleUserID"
	private let appleUserIDDefaultsKey = "appleUserID"
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
	///
	/// Stored in `UserDefaults` (not secret, wiped on reinstall). On first access after
	/// an update from an older build, migrates any value found in the legacy Keychain slot.
	var appleUserID: String? {
		if let id = UserDefaults.standard.string(forKey: appleUserIDDefaultsKey) {
			return id
		}
		// One-time migration from legacy Keychain storage.
		if let id = keychainRead(key: appleUserIDKeychainKey) {
			UserDefaults.standard.set(id, forKey: appleUserIDDefaultsKey)
			keychainDelete(key: appleUserIDKeychainKey)
			Self.logger.info("Migrated appleUserID from Keychain to UserDefaults")
			return id
		}
		return nil
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

	// MARK: - Sign In

	/// Handles a Sign in with Apple credential. Sends whatever Apple provided to the server;
	/// the server decides new (202) vs existing (201) via the HTTP status code.
	/// - Parameters:
	///   - appleUserID: The stable `sub` identifier from Apple (always present).
	///   - email: The email Apple returned — only present on the user's first authorization or
	///     after revoking and re-authorizing Sign in with Apple.
	///   - firstName: Given name from the Apple credential (only on first auth).
	///   - lastName: Family name from the Apple credential (only on first auth).
	///   - identityToken: Signed JWT from Apple, decoded to extract `is_private_email`.
	///   - realUserStatus: Apple's assessment of whether this is a real person.
	func signIn(
		appleUserID: String,
		email: String?,
		firstName: String?,
		lastName: String?,
		identityToken: Data?,
		realUserStatus: String
	) async throws -> ManageUserOutcome {
		let requestID = UUID().uuidString
		// Send "creation" if Apple provided an email (first authorization) OR if we have no
		// stored session token (e.g. app was deleted — server doesn't know us yet).
		// Send "reconnection" only when we're certain the server already has our account.
		let hasSessionToken = sessionToken != nil
		let hasEmail = email != nil && !email!.isEmpty
		let operation = (hasEmail || !hasSessionToken) ? "creation" : "reconnection"
		var body: [String: Any] = [
			"apple_user_id": appleUserID,
			"operation":     operation,
			"request_id":    requestID
		]

		if let email, !email.isEmpty {
			let tokenClaims = identityToken.flatMap { decodeJWTPayload($0) }
			let isPrivateEmail: Bool = {
				if let value = tokenClaims?["is_private_email"] as? Bool { return value }
				if let value = tokenClaims?["is_private_email"] as? String { return value == "true" }
				return false
			}()
			body["email"]            = email
			body["is_private_email"] = isPrivateEmail
			body["real_user_status"] = realUserStatus
			if let firstName { body["first_name"] = firstName }
			if let lastName  { body["last_name"]  = lastName }
		}

		var responseStatusCode = 200
		do {
			let (data, statusCode) = try await client.post(to: .manageUser, body: body)
			responseStatusCode = statusCode
			guard (200...299).contains(statusCode) else {
				throw AuthError.serverError(statusCode: statusCode, body: Self.webhookMessage(from: data))
			}
			let rawBody = String(data: data, encoding: .utf8) ?? "(empty)"
			Self.logger.info("manage-user \(operation) response: \(rawBody, privacy: .public)")
			let json = Self.firstJSON(from: data)
			if let echoed = json?["request_id"] as? String, echoed != requestID {
				Self.logger.warning("request_id mismatch: sent \(requestID), received \(echoed)")
			}
			if let token = json?["user_token"] as? String, !token.isEmpty {
				saveSessionToken(token)
			} else {
				Self.logger.warning("No user_token in \(operation) response — body: \(rawBody, privacy: .public)")
			}
		} catch let error as AuthError {
			throw error
		} catch {
			throw AuthError.serverError(statusCode: 0, body: error.localizedDescription)
		}

		UserDefaults.standard.set(appleUserID, forKey: appleUserIDDefaultsKey)
		isExplicitlyDisconnected = false
		isSimulatingIOSSignOut = false
		Self.logger.info("Sign-in successful (status: \(responseStatusCode, privacy: .public))")
		switch responseStatusCode {
		case 201: return .existingUser
		case 202: return .newUser
		default:  return .existingUser
		}
	}

	/// Reconnects using the stored Apple user ID without a new Apple credential.
	/// Used by the Face ID fast path — the user's identity is already in the Keychain.
	func reconnect() async throws -> ManageUserOutcome {
		guard let storedID = appleUserID else {
			throw AuthError.noStoredIdentity
		}

		let requestID = UUID().uuidString
		let body: [String: Any] = ["apple_user_id": storedID, "operation": "reconnection", "request_id": requestID]

		var responseStatusCode = 200
		do {
			let (data, statusCode) = try await client.post(to: .manageUser, body: body)
			responseStatusCode = statusCode
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

		isExplicitlyDisconnected = false
		isSimulatingIOSSignOut = false
		Self.logger.info("Reconnect successful (status: \(responseStatusCode, privacy: .public))")
		switch responseStatusCode {
		case 202: return .newUser
		default:  return .existingUser
		}
	}

	/// Marks the user as disconnected without erasing the stored identity.
	/// The identity is preserved so the user can reconnect without Sign in with Apple.
	func disconnect() {
		isExplicitlyDisconnected = true
		Self.logger.info("User disconnected")
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

	/// Removes the stored Apple user ID and session token (full sign-out).
	func clearStoredIdentity() {
		UserDefaults.standard.removeObject(forKey: appleUserIDDefaultsKey)
		keychainDelete(key: sessionTokenKey)
		isExplicitlyDisconnected = false
		isSimulatingIOSSignOut = false
	}

	/// Saves the session token to the Keychain.
	func saveSessionToken(_ token: String) {
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

// MARK: - ManageUserOutcome

/// The semantic result returned by `register()` and `reconnect()` after a successful server call.
enum ManageUserOutcome {
	/// HTTP 201 — the server found an existing account. Feeds should be restored from the server.
	case existingUser
	/// HTTP 202 — the server created a new account. Onboarding / source selection should proceed.
	case newUser
	/// Other 2xx — standard reconnect without email context. No onboarding action needed.
	case reconnected
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
