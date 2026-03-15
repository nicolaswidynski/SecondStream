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

	private let createUserURL = URL(string: "https://n8n.nwidynski.com/webhook/create-user")!

	// MARK: - Keychain keys

	private let keychainService = Bundle.main.bundleIdentifier ?? "com.ranchero.NetNewsWire"
	private let appleUserIDKey = "appleUserID"

	// MARK: - Public state

	/// Whether the user has already completed registration on this device.
	var isRegistered: Bool {
		appleUserID != nil
	}

	/// The stored Apple `sub` identifier, or `nil` if the user hasn't registered yet.
	var appleUserID: String? {
		keychainRead(key: appleUserIDKey)
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

		var request = URLRequest(url: createUserURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

		var body: [String: Any] = [
			"apple_user_id": appleUserID,
			"email": email,
			"is_private_email": isPrivateEmail,
			"real_user_status": realUserStatus
		]
		if let firstName { body["first_name"] = firstName }
		if let lastName { body["last_name"] = lastName }

		request.httpBody = try JSONSerialization.data(withJSONObject: body)

		let (data, response) = try await URLSession.shared.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse else {
			throw AuthError.invalidResponse
		}

		guard (200...299).contains(httpResponse.statusCode) else {
			let body = String(data: data, encoding: .utf8) ?? "(empty)"
			Self.logger.error("Registration failed [\(httpResponse.statusCode)]: \(body)")
			throw AuthError.serverError(statusCode: httpResponse.statusCode, body: body)
		}

		// Persist the Apple user ID locally only after a successful server response.
		keychainWrite(key: appleUserIDKey, value: appleUserID)
		Self.logger.info("User registered successfully")
	}

	/// Removes the stored Apple user ID from the Keychain (e.g. on sign-out).
	func clearStoredIdentity() {
		keychainDelete(key: appleUserIDKey)
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
	case serverError(statusCode: Int, body: String)

	var errorDescription: String? {
		switch self {
		case .missingToken:
			return "Authentication token not found."
		case .invalidResponse:
			return "Received an invalid response from the server."
		case .serverError(let code, let body):
			return "Server returned \(code):\n\(body)"
		}
	}
}
