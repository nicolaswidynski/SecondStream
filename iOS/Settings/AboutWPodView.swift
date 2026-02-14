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
		}
		.navigationTitle("About Second Stream")
	}
}

#Preview {
	NavigationView {
		AboutWPodView()
	}
}
