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
		NSLocalizedString("account.name.on-my-device", tableName: "DefaultAccountNames", comment: "Device specific default account name, e.g: On my iPhone")
	}

	// MARK: - SwiftUI Images
	@MainActor func image() -> Image {
		#if os(macOS)
		return Image("accountLocal")
		#else
		return Image("accountLocalPhone")
		#endif
	}

}
