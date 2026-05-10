//
//  StoreManager.swift
//  Second Stream
//
//  Created by Claude on 2026-04-19.
//  Copyright © 2026 STDN. All rights reserved.
//

import StoreKit
import UIKit
import os.log

private let storeLogger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "StoreManager")

// MARK: - StoreManager

@MainActor
final class StoreManager: ObservableObject {

	private let productIDs = [
		"secondstream_2_dollars",
		"secondstream_5_dollars",
		"secondstream_10_dollars",
		"secondstream_30_dollars",
	]

	@Published var products: [Product] = []
	@Published var isLoading = true
	@Published var isPurchasing = false
	@Published var lastError: String?
	@Published private(set) var donationCount = 0

	private var updatesTask: Task<Void, Never>?

	init() {
		storeLogger.debug("INIT start")
		Task { @MainActor [weak self] in
			guard let self else { return }
			// Drain any unfinished transactions from previous sessions before starting
			// Transaction.updates. Without this, StoreKit immediately delivers them on
			// the cooperative pool, which crashes the @MainActor listener continuation.
			storeLogger.debug("DRAIN start")
			for await result in Transaction.unfinished {
				if case .verified(let tx) = result {
					storeLogger.debug("DRAIN finishing: \(tx.productID, privacy: .public)")
					await tx.finish()
				}
			}
			storeLogger.debug("DRAIN done")
			self.updatesTask = Task { @MainActor [weak self] in
				storeLogger.debug("LISTENER started on thread \(Thread.current.description, privacy: .public)")
				for await result in Transaction.updates {
					storeLogger.debug("LISTENER got result")
					guard let self else { return }
					do {
						let transaction = try self.checkVerified(result)
						storeLogger.debug("LISTENER verified: \(transaction.productID, privacy: .public)")
						await transaction.finish()
						await self.handleTransactionUpdate(transaction)
					} catch {
						storeLogger.error("LISTENER error: \(error.localizedDescription, privacy: .public)")
					}
				}
				storeLogger.debug("LISTENER ended")
			}
		}
		storeLogger.debug("INIT drain+listener scheduled")
		Task { await self.fetchProducts() }
		storeLogger.debug("INIT done")
	}

	deinit {
		updatesTask?.cancel()
	}

	// MARK: - Fetch

	func fetchProducts() async {
		storeLogger.debug("FETCH start")
		isLoading = true
		do {
			let fetched = try await Product.products(for: productIDs)
			if fetched.isEmpty {
				storeLogger.error("FETCH returned 0 products — bundle ID: \(Bundle.main.bundleIdentifier ?? "nil", privacy: .public), expected IDs: \(self.productIDs.joined(separator: ", "), privacy: .public)")
				lastError = "Could not load tip options. Tap to retry."
			} else {
				storeLogger.info("FETCH got \(fetched.count, privacy: .public) products")
			}
			products = fetched.sorted { $0.price < $1.price }
			isLoading = false
		} catch {
			storeLogger.error("FETCH failed: \(error.localizedDescription, privacy: .public)")
			lastError = "Could not load tip options. Tap to retry."
			isLoading = false
		}
		storeLogger.debug("FETCH done")
	}

	// MARK: - Purchase

	func purchase(_ product: Product) async {
		isPurchasing = true
		lastError = nil
		storeLogger.debug("PURCHASE start: \(product.id, privacy: .public)")
		do {
			guard let scene = UIApplication.shared.connectedScenes
				.compactMap({ $0 as? UIWindowScene })
				.first(where: { $0.activationState == .foregroundActive }) else {
				storeLogger.error("PURCHASE no active scene")
				lastError = "No active window."
				isPurchasing = false
				return
			}
			storeLogger.debug("PURCHASE calling purchase(confirmIn:) on thread \(Thread.current.description, privacy: .public)")
			let result = try await product.purchase(confirmIn: scene)
			storeLogger.debug("PURCHASE got result")
			switch result {
			case .success(let verification):
				storeLogger.debug("PURCHASE success — \(product.id, privacy: .public)")
				let transaction = try checkVerified(verification)
				await transaction.finish()
				storeLogger.debug("PURCHASE finished transaction")
				await recordDonation(product: product, transaction: transaction)
			case .userCancelled:
				storeLogger.debug("PURCHASE user cancelled")
			case .pending:
				storeLogger.debug("PURCHASE pending")
			@unknown default:
				storeLogger.debug("PURCHASE unknown result")
			}
		} catch {
			storeLogger.error("PURCHASE threw: \(error.localizedDescription, privacy: .public)")
			lastError = error.localizedDescription
		}
		isPurchasing = false
		storeLogger.debug("PURCHASE done")
	}

	// MARK: - Transaction update handler

	private func handleTransactionUpdate(_ transaction: Transaction) async {
		let matched = products.first { $0.id == transaction.productID }
		if let product = matched {
			await recordDonation(product: product, transaction: transaction)
		}
	}

	// MARK: - Verification

	nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
		switch result {
		case .unverified(_, let error):
			throw error
		case .verified(let safe):
			return safe
		}
	}

	// MARK: - Webhook

	private func recordDonation(product: Product, transaction: Transaction) async {
		let storefront = await Storefront.current?.countryCode ?? "unknown"
		let currency: String
		if #available(iOS 16, *) {
			currency = transaction.currency?.identifier ?? "USD"
		} else {
			currency = Locale.current.currencyCode ?? "USD"
		}
		let body: [String: Any] = [
			"request_id":    UUID().uuidString,
			"operation":     "donations",
			"apple_user_id": AuthManager.shared.appleUserID ?? "",
			"product_id":    product.id,
			"amount":        "\(product.price)",
			"currency":      currency,
			"storefront":    storefront,
		]
		storeLogger.debug("WEBHOOK sending: \(product.id, privacy: .public) \(currency, privacy: .public) \(storefront, privacy: .public)")
		do {
			let (_, statusCode) = try await SecondStreamAPIClient.shared.post(to: .costsAndDonations, body: body)
			storeLogger.debug("WEBHOOK HTTP \(statusCode, privacy: .public)")
			if statusCode == 201 {
				donationCount += 1
			}
		} catch {
			storeLogger.error("WEBHOOK failed: \(error.localizedDescription, privacy: .public)")
			lastError = "Purchase succeeded but failed to notify server: \(error.localizedDescription)"
		}
	}
}
