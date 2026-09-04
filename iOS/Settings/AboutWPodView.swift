//
//  AboutWPodView.swift
//  NetNewsWire-iOS
//
//  Created by Claude on 2026-01-26.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import SwiftUI

struct AboutWPodView: View {
	var body: some View {
		List {
			Section {
				if SettingsSidebarItem.donationsEnabled {
					Text("Second Stream is free, please read Donation for more information.")
						.font(.body)
						.foregroundStyle(.secondary)
						.padding(.vertical, 4)
				}
				Text("Second Stream builds on NetNewsWire, an open-source RSS reader. Many thanks to its contributors for their outstanding work.")
					.font(.body)
					.foregroundStyle(.secondary)
					.padding(.vertical, 4)
			}
			.listRowBackground(Color(uiColor: Assets.Colors.foreground))
			.listRowSeparator(.hidden)

			Section {
				Button {
					rateApp()
				} label: {
					Text("Rate this App")
				}
			}
			.listRowBackground(Color(uiColor: Assets.Colors.foreground))
			.listRowSeparator(.hidden)

			Section {
				NavigationLink(destination: LegalView()) {
					Text("Legal")
				}
			}
			.listRowBackground(Color(uiColor: Assets.Colors.foreground))
			.listRowSeparator(.hidden)
		}
		.listStyle(.insetGrouped)
		.scrollContentBackground(.hidden)
		.background(Color(uiColor: Assets.Colors.SettingsContentBgColor))
		.navigationTitle("About Second Stream")
	}

	private func rateApp() {
		guard let url = URL(string: "itms-apps://itunes.apple.com/app/id6760979035?action=write-review") else {
			return
		}
		UIApplication.shared.open(url)
	}
}

#Preview {
	NavigationView {
		AboutWPodView()
	}
}
