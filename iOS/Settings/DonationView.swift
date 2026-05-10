//
//  DonationView.swift
//  NetNewsWire-iOS
//
//  Created by Claude on 2026-04-18.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import SwiftUI
import StoreKit
import os.log

private let donationLogger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DonationView")

// MARK: - Costs model

private struct Costs {
	let priorInvestment: Int
	let priorDonation: Int
	let priorGrossTarget: Int
	let monthlyInvestment: Int
	let monthlyDonation: Int
	let monthlyGrossTarget: Int
	let totalGrossTarget: Int
	let totalGrossDonation: Int

	init?(dict: [String: Any]) {
		guard
			let priorInv    = dict["prior_investment"]    as? Int,
			let priorDon    = dict["prior_donations"]      as? Int,
			let priorTarget = dict["prior_gross_target"]  as? Int,
			let monthlyInv  = dict["monthly_investment"]  as? Int,
			let monthlyDon  = dict["monthly_donations"]    as? Int,
			let monthlyTarget = dict["monthly_gross_target"] as? Int,
			let totalTarget = dict["total_gross_target"]  as? Int,
			let totalDon    = dict["total_gross_donations"] as? Int
		else {
			return nil
		}
		priorInvestment   = priorInv
		priorDonation     = priorDon
		priorGrossTarget  = priorTarget
		monthlyInvestment = monthlyInv
		monthlyDonation   = monthlyDon
		monthlyGrossTarget = monthlyTarget
		totalGrossTarget  = totalTarget
		totalGrossDonation = totalDon
	}
}

private func parseCosts(from data: Data) -> Costs? {
	let raw = String(data: data, encoding: .utf8) ?? "<binary>"
	donationLogger.debug("costs_and_donations raw response: \(raw, privacy: .public)")

	guard let json = try? JSONSerialization.jsonObject(with: data) else {
		donationLogger.error("costs_and_donations: failed to parse JSON")
		return nil
	}

	// Pattern 1: [{..., "costs": {...}}, ...]
	if let arr = json as? [[String: Any]], let first = arr.first,
	   let costsDict = first["costs"] as? [String: Any] {
		return Costs(dict: costsDict)
	}
	// Pattern 2: {"costs": {...}}
	if let dict = json as? [String: Any],
	   let costsDict = dict["costs"] as? [String: Any] {
		return Costs(dict: costsDict)
	}
	// Pattern 3: [{...}]
	if let arr = json as? [[String: Any]], let first = arr.first {
		return Costs(dict: first)
	}
	// Pattern 4: {...}
	if let dict = json as? [String: Any] {
		return Costs(dict: dict)
	}

	donationLogger.error("costs_and_donations: unrecognized response shape")
	return nil
}

private enum CostsLoadState {
	case loading
	case loaded(Costs)
	case failed
}

// MARK: - DonationView

struct DonationView: View {

	@StateObject private var store = StoreManager()
	@State private var costsState: CostsLoadState = .loading
	@State private var purchaseSucceeded = false

	var body: some View {
		List {
			// Description
			Section {
				Text("Second Stream is free. Tips help cover server hosting, AI APIs, and other services that power the app.")
					.font(.body)
					.foregroundStyle(.secondary)
					.padding(.vertical, 4)
			}
			.listRowBackground(Color(uiColor: Assets.Colors.foreground))
			.listRowSeparator(.hidden)

			// IAP tip options
			Section(header: Text("Tip Jar")) {
				TipJarContent(store: store)
			}
			.listRowBackground(Color(uiColor: Assets.Colors.foreground))
			.listRowSeparator(.hidden)

			if let error = store.lastError {
				Section {
					Text(error)
						.font(.footnote)
						.foregroundStyle(.red)
						.padding(.vertical, 4)
				}
				.listRowBackground(Color(uiColor: Assets.Colors.foreground))
				.listRowSeparator(.hidden)
			}

			// Cost scales
			switch costsState {
			case .loading:
				Section {
					HStack {
						Spacer()
						ProgressView()
						Spacer()
					}
					.padding(.vertical, 8)
				}
				.listRowBackground(Color(uiColor: Assets.Colors.foreground))
				.listRowSeparator(.hidden)

			case .failed:
				EmptyView()

			case .loaded(let costs):
				Section(header: Text("Monthly Costs")) {
					CostScaleRow(
						donated: Double(costs.monthlyDonation),
						target: Double(costs.monthlyGrossTarget)
					)
				}
				.listRowBackground(Color(uiColor: Assets.Colors.foreground))
				.listRowSeparator(.hidden)

				Section(header: Text("Running Yearly Costs")) {
					CostScaleRow(
						donated: Double(costs.priorDonation),
						target: Double(costs.priorGrossTarget)
					)
				}
				.listRowBackground(Color(uiColor: Assets.Colors.foreground))
				.listRowSeparator(.hidden)
			}
		}
		.listStyle(.insetGrouped)
		.scrollContentBackground(.hidden)
		.background(Color(uiColor: Assets.Colors.SettingsContentBgColor))
		.navigationTitle("Donations")
		.task { await loadCosts() }
		.onChange(of: store.donationCount) {
			purchaseSucceeded = true
			Task { await loadCosts() }
		}
		.alert("Thank you for your support!", isPresented: $purchaseSucceeded) {
			Button("Done", role: .cancel) { }
		}
	}

	private func loadCosts() async {
		let body: [String: Any] = [
			"request_id":    UUID().uuidString,
			"operation":     "get-costs",
			"apple_user_id": AuthManager.shared.appleUserID ?? "",
		]
		do {
			let (data, statusCode) = try await SecondStreamAPIClient.shared.post(to: .costsAndDonations, body: body)
			donationLogger.debug("costs_and_donations HTTP \(statusCode, privacy: .public)")
			guard let costs = parseCosts(from: data) else {
				costsState = .failed
				return
			}
			costsState = .loaded(costs)
		} catch {
			donationLogger.error("costs_and_donations error: \(error.localizedDescription, privacy: .public)")
			costsState = .failed
		}
	}
}

// MARK: - TipJarContent

private struct TipJarContent: View {
	@ObservedObject var store: StoreManager

	var body: some View {
		if store.isLoading {
			HStack {
				Spacer()
				ProgressView()
				Spacer()
			}
			.padding(.vertical, 8)
		} else if store.products.isEmpty {
			Button {
				Task { await store.fetchProducts() }
			} label: {
				Text("Could not load options. Tap to retry.")
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
			.padding(.vertical, 4)
		} else {
			ForEach(store.products) { product in
				TipRow(product: product, store: store)
			}
		}
	}
}

// MARK: - TipRow

private struct TipRow: View {
	let product: Product
	let store: StoreManager

	var body: some View {
		Button {
			Task { await store.purchase(product) }
		} label: {
			HStack {
				Text(product.displayName)
					.font(.body)
					.foregroundStyle(.primary)
				Spacer()
				Text(product.displayPrice)
					.font(.body.monospacedDigit())
					.foregroundStyle(Color(uiColor: Assets.Colors.primaryAccent))
			}
		}
		.disabled(store.isPurchasing)
	}
}

// MARK: - CostScaleRow

private struct CostScaleRow: View {

	let donated: Double
	let target: Double

	private var donatedFraction: Double {
		guard target > 0 else { return 0 }
		return min(donated / target, 1)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			GeometryReader { geo in
				ZStack(alignment: .leading) {
					RoundedRectangle(cornerRadius: 6, style: .continuous)
						.fill(Color(uiColor: Assets.Colors.SettingsContentBgColor))
						.frame(height: 12)
					if donatedFraction > 0 {
						RoundedRectangle(cornerRadius: 6, style: .continuous)
							.fill(Color(uiColor: Assets.Colors.primaryAccent))
							.frame(width: geo.size.width * donatedFraction, height: 12)
					}
				}
			}
			.frame(height: 12)

			VStack(alignment: .leading, spacing: 4) {
				LegendRow(color: Color(uiColor: Assets.Colors.primaryAccent), label: "Donations", amount: donated)
				LegendRow(color: .secondary.opacity(0.4), label: "Funding target", amount: target)
			}
		}
		.padding(.vertical, 8)
	}
}

// MARK: - LegendRow

private struct LegendRow: View {
	let color: Color
	let label: String
	let amount: Double

	var body: some View {
		HStack(spacing: 8) {
			RoundedRectangle(cornerRadius: 3, style: .continuous)
				.fill(color)
				.frame(width: 12, height: 12)
			Text(label)
				.font(.footnote)
				.foregroundStyle(.secondary)
			Spacer()
			Text(formatted(amount))
				.font(.footnote.monospacedDigit())
				.foregroundStyle(.secondary)
		}
	}

	private func formatted(_ value: Double) -> String {
		let formatter = NumberFormatter()
		formatter.numberStyle = .currency
		formatter.maximumFractionDigits = 0
		return formatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
	}
}

#Preview {
	NavigationView {
		DonationView()
	}
}
