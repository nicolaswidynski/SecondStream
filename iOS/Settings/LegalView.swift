//
//  LegalView.swift
//  NetNewsWire-iOS
//
//  Created by Claude on 2026-01-26.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import SwiftUI

struct LegalView: View {
	private let mitLicense = """
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
"""

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				NavigationLink(destination: AboutView()) {
					Text("NetNewsWire")
						.font(.title)
						.foregroundColor(.accentColor)
				}

				Text("Copyright © 2002–2025 Brent Simmons")
					.font(.subheadline)
					.foregroundStyle(.secondary)

				Text("Licensed under the MIT License.")
					.font(.subheadline)
					.foregroundStyle(.secondary)

				Divider()
					.padding(.vertical, 8)

				Text(mitLicense)
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
			.padding()
		}
		.background(Color(uiColor: Assets.Colors.SettingsContentBgColor))
		.navigationTitle("Legal")
	}
}

#Preview {
	NavigationView {
		LegalView()
	}
}
