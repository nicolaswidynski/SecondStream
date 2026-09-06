//
//  UIViewController+SettingsAppearance.swift
//  NetNewsWire-iOS
//
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import UIKit

extension UIViewController {

	/// Applies the standard settings nav bar appearance (opaque background, settings color, separator).
	/// Call from `viewWillAppear(_:)` in every settings VC so the look is consistent regardless of
	/// how the VC was pushed.
	func applySettingsNavBarAppearance() {
		let appearance = UINavigationBarAppearance()
		appearance.configureWithOpaqueBackground()
		appearance.backgroundColor = Assets.Colors.SettingsNavBarColor
		navigationController?.navigationBar.standardAppearance = appearance
		navigationController?.navigationBar.scrollEdgeAppearance = appearance
		navigationController?.navigationBar.compactAppearance = appearance
	}
}
