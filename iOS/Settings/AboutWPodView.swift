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
			NavigationLink(destination: LegalView()) {
				Text("Legal")
			}
			.listRowBackground(Color(uiColor: Assets.Colors.foreground))
			.listRowSeparator(.hidden)
		}
		.listStyle(.plain)
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
