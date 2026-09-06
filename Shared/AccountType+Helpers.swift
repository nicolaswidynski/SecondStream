//
//  AccountType+Helpers.swift
//  NetNewsWire
//
//  Created by Stuart Breckenridge on 27/10/20.
//  Copyright © 2020 Ranchero Software. All rights reserved.
//

import Foundation
import Account
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

extension AccountType {

	// TODO: Move this to the Account Package.

	func localizedAccountName() -> String {

		switch self {
		case .onMyMac:
			return NSLocalizedString("account.name.on-my-device", tableName: "DefaultAccountNames", comment: "Device specific default account name, e.g: On my iPhone")
		case .cloudKit:
			return NSLocalizedString("iCloud", comment: "Account name")
		}
	}

	// MARK: - SwiftUI Images
	@MainActor func image() -> Image {
		switch self {
		case .onMyMac:
			#if os(macOS)
			return Image("accountLocal")
			#else
			return Image("accountLocalPhone")
			#endif
		case .cloudKit:
			return Image("accountCloudKit")
		}
	}

}
