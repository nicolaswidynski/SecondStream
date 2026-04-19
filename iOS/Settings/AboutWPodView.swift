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
				Text("I intend to keep Second Stream free, please read Donation for more information.")
					.font(.body)
					.foregroundStyle(.secondary)
					.padding(.vertical, 4)
				Text("Second Stream code is based on NetNewsWire — I wish to thank their numerous contributors for their excellent work.")
					.font(.body)
					.foregroundStyle(.secondary)
					.padding(.vertical, 4)
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
}

#Preview {
	NavigationView {
		AboutWPodView()
	}
}
