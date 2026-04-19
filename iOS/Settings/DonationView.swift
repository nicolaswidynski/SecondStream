//
//  DonationView.swift
//  NetNewsWire-iOS
//
//  Created by Claude on 2026-04-18.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import SwiftUI
import os.log

private let donationLogger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DonationView")

private struct Costs {
	let priorInvestment: Int
	let priorDonation: Int
	let priorGrossTarget: Int
	let monthlyInvestment: Int
	let monthlyDonation: Int
	let monthlyGrossTarget: Int
	let totalGrossTarget: Int
	let totalGrossDonation: Int

	/// Parse from a flat dictionary (snake_case keys).
	init?(dict: [String: Any]) {
		guard
			let priorInv = dict["prior_investment"] as? Int,
			let priorDon = dict["prior_donation"] as? Int,
			let priorTarget = dict["prior_gross_target"] as? Int,
			let monthlyInv = dict["monthly_investment"] as? Int,
			let monthlyDon = dict["monthly_donation"] as? Int,
			let monthlyTarget = dict["monthly_gross_target"] as? Int,
			let totalTarget = dict["total_gross_target"] as? Int,
			let totalDon = dict["total_gross_donation"] as? Int
		else {
			return nil
		}
		priorInvestment = priorInv
		priorDonation = priorDon
		priorGrossTarget = priorTarget
		monthlyInvestment = monthlyInv
		monthlyDonation = monthlyDon
		monthlyGrossTarget = monthlyTarget
		totalGrossTarget = totalTarget
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

	// Pattern 1: [{..., "costs": {...}}, ...] — n8n array with costs key
	if let arr = json as? [[String: Any]], let first = arr.first,
	   let costsDict = first["costs"] as? [String: Any] {
		return Costs(dict: costsDict)
	}

	// Pattern 2: {"costs": {...}} — top-level object with costs key
	if let dict = json as? [String: Any],
	   let costsDict = dict["costs"] as? [String: Any] {
		return Costs(dict: costsDict)
	}

	// Pattern 3: [{...}] — n8n array where the item IS the costs object
	if let arr = json as? [[String: Any]], let first = arr.first {
		return Costs(dict: first)
	}

	// Pattern 4: {...} — the object IS the costs object
	if let dict = json as? [String: Any] {
		return Costs(dict: dict)
	}

	donationLogger.error("costs_and_donations: unrecognized response shape")
	return nil
}

private enum LoadState {
	case loading
	case loaded(Costs)
	case failed(String)
}

struct DonationView: View {

	@State private var state: LoadState = .loading

	var body: some View {
		List {
			switch state {
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

			case .failed(let message):
				Section {
					Text(message)
						.font(.body)
						.foregroundStyle(.secondary)
						.padding(.vertical, 4)
				}
				.listRowBackground(Color(uiColor: Assets.Colors.foreground))
				.listRowSeparator(.hidden)

			case .loaded(let costs):
				Section {
					Text("Second Stream is free and I intend to keep it that way. Below are the running infrastructure costs. Donations help cover server hosting, AI APIs, and other services that power the app.")
						.font(.body)
						.foregroundStyle(.secondary)
						.padding(.vertical, 4)
				}
				.listRowBackground(Color(uiColor: Assets.Colors.foreground))
				.listRowSeparator(.hidden)

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
		.navigationTitle("Donation")
		.task { await loadCosts() }
	}

	private func loadCosts() async {
		let body: [String: Any] = [
			"request_id": UUID().uuidString,
			"operation": "get-costs",
			"apple_user_id": AuthManager.shared.appleUserID ?? ""
		]
		do {
			let (data, statusCode) = try await SecondStreamAPIClient.shared.post(to: .costsAndDonations, body: body)
			donationLogger.debug("costs_and_donations HTTP \(statusCode, privacy: .public)")
			guard let costs = parseCosts(from: data) else {
				state = .failed("Could not load costs. Please try again later.")
				return
			}
			state = .loaded(costs)
		} catch {
			donationLogger.error("costs_and_donations error: \(error.localizedDescription, privacy: .public)")
			state = .failed("Could not load costs. Please try again later.")
		}
	}
}

private struct CostScaleRow: View {

	let donated: Double
	let target: Double

	private var donatedFraction: Double {
		guard target > 0 else { return 0 }
		return min(donated / target, 1)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			// Scale bar
			GeometryReader { geo in
				ZStack(alignment: .leading) {
					// Background track
					RoundedRectangle(cornerRadius: 6, style: .continuous)
						.fill(Color(uiColor: Assets.Colors.SettingsContentBgColor))
						.frame(height: 12)

					// Donation fill (accent)
					if donatedFraction > 0 {
						RoundedRectangle(cornerRadius: 6, style: .continuous)
							.fill(Color(uiColor: Assets.Colors.primaryAccent))
							.frame(width: geo.size.width * donatedFraction, height: 12)
					}
				}
			}
			.frame(height: 12)

			// Legend
			VStack(alignment: .leading, spacing: 4) {
				LegendRow(color: Color(uiColor: Assets.Colors.primaryAccent), label: "Donations", amount: donated)
				LegendRow(color: .secondary.opacity(0.4), label: "Funding target", amount: target)
			}
		}
		.padding(.vertical, 8)
	}
}

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
