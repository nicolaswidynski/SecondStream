//
//  Assets.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 11/18/25.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

import RSCore
import Account

#if os(macOS)
typealias RSColor = NSColor
#else
typealias RSColor = UIColor
#endif

struct Assets {
	struct Images {
		static var accountBazQux: RSImage { RSImage(named: "accountBazQux")! }
		static var accountCloudKit: RSImage { RSImage(named: "accountCloudKit")! }
		static var accountFeedbin: RSImage { RSImage(named: "accountFeedbin")! }
		static var accountFeedly: RSImage { RSImage(named: "accountFeedly")! }
		static var accountFreshRSS: RSImage { RSImage(named: "accountFreshRSS")! }
		static var accountInoreader: RSImage { RSImage(named: "accountInoreader")! }
		static var accountNewsBlur: RSImage { RSImage(named: "accountNewsBlur")! }
		static var accountTheOldReader: RSImage { RSImage(named: "accountTheOldReader")! }

//		static var starOpen: RSImage { RSImage(symbol: "star")! }
//		static var starClosed: RSImage { RSImage(symbol: "star.fill")! }
		static var starOpen: RSImage { RSImage(symbol: "bookmark")! }
		static var starClosed: RSImage { RSImage(symbol: "bookmark.fill")! }
		static var copy: RSImage { RSImage(symbol: "document.on.document")! }
		static var markAllAsRead: RSImage { RSImage(named: "markAllAsRead")! }
		static var nextUnread: RSImage { RSImage(symbol: "chevron.down.circle")! }

		static var nnwFeedIcon: RSImage { RSImage(named: "nnwFeedIcon")! }
		static var faviconTemplate: RSImage { RSImage(named: "faviconTemplateImage")! }

		static var articleExtractorError: RSImage { RSImage(named: "articleExtractorError")! }
		static var articleExtractorOn: RSImage { RSImage(named: "articleExtractorOn")! }
		static var articleExtractorOff: RSImage { RSImage(named: "articleExtractorOff")! }
		static var share: RSImage { RSImage(symbol: "square.and.arrow.up")! }
		static var folder: RSImage { RSImage(symbol: "folder")! }
		static var starredFeed: IconImage {
			IconImage(starClosed,
					  isSymbol: true,
					  isBackgroundSuppressed: true)
		}

#if os(macOS)
		static var accountLocal: RSImage { RSImage(named: "accountLocal")! }
		static var addNewSidebarItem: RSImage { RSImage(symbol: "plus")! }
		static var articleTheme: RSImage { RSImage(symbol: "doc.richtext")! }
		static var cleanUp: RSImage { RSImage(symbol: "bubbles.and.sparkles")! }
		static var delete: RSImage { RSImage(symbol: "xmark.bin")! }
		static var marsEdit: RSImage { RSImage(named: "MarsEditIcon")! }
		static var microblog: RSImage { RSImage(named: "MicroblogIcon")! }
		static var filterActive: RSImage { RSImage(symbol: "line.horizontal.3.decrease.circle.fill")! }
		static var filterInactive: RSImage { RSImage(symbol: "line.horizontal.3.decrease.circle")! }
		static var markAllAsReadMenu: RSImage { RSImage(named: "markAllAsRead")! }
		static var notification: RSImage { RSImage(symbol: "bell.badge")! }
		static var openInBrowser: RSImage { RSImage(symbol: "safari")! }
		static var preferencesToolbarAccounts: RSImage { RSImage(symbol: "at")! }
		static var preferencesToolbarGeneral: RSImage { RSImage(symbol: "gearshape")! }
		static var preferencesToolbarAdvanced: RSImage { RSImage(symbol: "gearshape.2")! }
		static var readClosed: RSImage { RSImage(symbol: "largecircle.fill.circle")! }
		static var readOpen: RSImage { RSImage(symbol: "circle")! }
		static var refresh: RSImage { RSImage(symbol: "arrow.clockwise")! }
		static var rename: RSImage { RSImage(symbol: "pencil")! }
		static var swipeMarkUnstarred: RSImage { RSImage(symbol: "star")! }
		static var timelineStarSelected: RSImage { RSImage(named: "timelineStar")!.tinted(with: .white) }
		static var timelineStarUnselected: RSImage { RSImage(named: "timelineStar")!.tinted(with: Assets.Colors.star) }
		static var markBelowAsRead: RSImage { RSImage(named: "markBelowAsRead")! }
		static var markAboveAsRead: RSImage { RSImage(named: "markAboveAsRead")! }
		static var searchFeed: IconImage {
			IconImage(RSImage(named: NSImage.smartBadgeTemplateName)!, isSymbol: true, isBackgroundSuppressed: true)
		}
		static var swipeMarkStarred: RSImage {
			RSImage(systemSymbolName: "star.fill", accessibilityDescription: "Star")!
		}
		static var swipeMarkRead: RSImage {
			RSImage(systemSymbolName: "circle", accessibilityDescription: "Mark Read")!
		}
		static var swipeMarkUnread: RSImage {
			RSImage(systemSymbolName: "largecircle.fill.circle", accessibilityDescription: "Mark Unread")!
		}
		static var mainFolder: IconImage {
			IconImage(folder,
					  isSymbol: true,
					  isBackgroundSuppressed: true,
					  preferredColor: Assets.Colors.primaryAccent.cgColor)
		}
		static var todayFeed: IconImage {
			let image = RSImage(symbol: "sun.max.fill")!
			return IconImage(image,
							 isSymbol: true,
							 isBackgroundSuppressed: true,
							 preferredColor: NSColor.orange.cgColor)
		}
		static var unreadFeed: IconImage {
			let image = RSImage(symbol: "largecircle.fill.circle")!
			return IconImage(image,
							 isSymbol: true,
							 isBackgroundSuppressed: true,
							 preferredColor: Assets.Colors.primaryAccent.cgColor)
		}

#else // iOS
		static var accountLocalPadImage: RSImage { RSImage(named: "accountLocalPad")! }
		static var accountLocalPhoneImage: RSImage { RSImage(named: "accountLocalPhone")! }

		static var articleExtractorOnSF: RSImage { RSImage(named: "articleExtractorOnSF")! }
		static var articleExtractorOffSF: RSImage { RSImage(symbol: "doc.plaintext")! }
		@MainActor static var articleExtractorOnTinted: RSImage {
			articleExtractorOn.tinted(color: Assets.Colors.primaryAccent)!
		}
		@MainActor static var articleExtractorOffTinted: RSImage {
			articleExtractorOff.tinted(color: Assets.Colors.primaryAccent)!
		}

		static var circleClosed: RSImage { RSImage(symbol: "largecircle.fill.circle")! }
		static var markBelowAsRead: RSImage { RSImage(symbol: "arrowtriangle.down.circle")! }
		static var markAboveAsRead: RSImage { RSImage(symbol: "arrowtriangle.up.circle")! }
		static var more: RSImage { RSImage(symbol: "ellipsis.circle")! }
		static var nextArticle: RSImage { RSImage(symbol: "chevron.down")! }
		static var circleOpen: RSImage { RSImage(symbol: "circle")! }
		static var disclosure: RSImage { RSImage(named: "disclosure")! }
		static var deactivate: RSImage { RSImage(symbol: "minus.circle")! }
		static var edit: RSImage { RSImage(symbol: "square.and.pencil")! }
		static var filter: RSImage { RSImage(symbol: "line.3.horizontal.decrease")! }
		static var folderOutlinePlus: RSImage { RSImage(symbol: "folder.badge.plus")! }
		static var info: RSImage { RSImage(symbol: "info.circle")! }
		static var plus: RSImage { RSImage(symbol: "plus")! }
		static var prevArticle: RSImage { RSImage(symbol: "chevron.up")! }
		static var openInSidebar: RSImage { RSImage(symbol: "arrow.turn.down.left")! }
		static var safari: RSImage { RSImage(symbol: "safari")! }
		static var smartFeed: RSImage { RSImage(symbol: "gear")! }
		static var trash: RSImage { RSImage(symbol: "trash")! }

		static var searchFeed: IconImage {
			IconImage(RSImage(symbol: "magnifyingglass")!, isSymbol: true)
		}
		static var mainFolder: IconImage {
			IconImage(folder,
					  isSymbol: true,
					  isBackgroundSuppressed: true,
					  preferredColor: Assets.Colors.secondaryAccent.cgColor)
		}
		static var todayFeed: IconImage {
			let image = RSImage(symbol: "sun.max.fill")!
			return IconImage(image,
							 isSymbol: true,
							 isBackgroundSuppressed: true,
							 preferredColor: UIColor.systemOrange.cgColor)
		}
		static var unreadFeed: IconImage {
			let image = RSImage(symbol: "largecircle.fill.circle")!
			return IconImage(image,
							 isSymbol: true,
							 isBackgroundSuppressed: true,
							 preferredColor: Assets.Colors.secondaryAccent.cgColor)
		}
		static var timelineStar: RSImage {
			RSImage(symbol: "bookmark.fill")!
		}
		static var starredCellIndicator: IconImage {
			let config = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
			let image = UIImage(systemName: "bookmark.fill", withConfiguration: config)!
			return IconImage(image, isSymbol: true, isBackgroundSuppressed: true)
		}
		static var unreadCellIndicator: IconImage {
			let image = RSImage(symbol: "circle.fill")!
			return IconImage(image,
							 isSymbol: true,
							 isBackgroundSuppressed: true,
							 preferredColor: Assets.Colors.secondaryAccent.cgColor)
		}
#endif
	}

	@MainActor static func accountImage(_ accountType: AccountType) -> RSImage {
		switch accountType {
		case .onMyMac:
#if os(macOS)
			return Assets.Images.accountLocal
#else // iOS
			if UIDevice.current.userInterfaceIdiom == .pad {
				return Assets.Images.accountLocalPadImage
			} else {
				return Assets.Images.accountLocalPhoneImage
			}
#endif
		case .cloudKit:
			return Assets.Images.accountCloudKit
		case .bazQux:
			return Assets.Images.accountBazQux
		case .feedbin:
			return Assets.Images.accountFeedbin
		case .feedly:
			return Assets.Images.accountFeedly
		case .freshRSS:
			return Assets.Images.accountFreshRSS
		case .inoreader:
			return Assets.Images.accountInoreader
		case .newsBlur:
			return Assets.Images.accountNewsBlur
		case .theOldReader:
			return Assets.Images.accountTheOldReader
		}
	}

	struct Colors {
#if os(macOS)
		static var primaryAccent: RSColor { RSColor(named: "AccentColor")! }
		static var timelineSeparator: RSColor { NSColor(named: "timelineSeparatorColor")! }
		static var iconLightBackground: RSColor { NSColor(named: "iconLightBackgroundColor")! }
		static var iconDarkBackground: RSColor { NSColor(named: "iconDarkBackgroundColor")! }
		static var star: RSColor { RSColor(named: "StarColor")! }
#else // iOS

		// MARK: - Color palette
		//
		// Single source of truth — edit values here only.
		//
		//  accent     #086AEE / #0A85FF  (blue)
		//  background #F1F3F8 / #1F1E1D
		//  foreground #F7F8FC / #262624

		static var primaryAccent: RSColor {
			RSColor { tc in
				tc.userInterfaceStyle == .dark
				? RSColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1)
				: RSColor(red: 0.0, green: 0.48, blue:  1.0, alpha: 1)
//				? RSColor(red: 232/255, green: 134/255, blue: 106/255, alpha: 1)
//				: RSColor(red: 217/255, green: 119/255, blue:  87/255, alpha: 1)
			}
		}

		static var secondaryAccent: RSColor {
			RSColor { tc in
				tc.userInterfaceStyle == .dark
				? RSColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1)
				: RSColor(red: 0.0, green: 0.48, blue:  1.0, alpha: 1)
//				? RSColor(red: 212/255, green: 149/255, blue: 110/255, alpha: 1)
//				: RSColor(red: 217/255, green: 119/255, blue:  87/255, alpha: 1)
			}
		}

		static var background: RSColor {
			RSColor { tc in
				tc.userInterfaceStyle == .dark
					? RSColor(red:  31/255, green:  30/255, blue:  29/255, alpha: 1)
					: RSColor(red: 241/255, green: 243/255, blue: 248/255, alpha: 1)
			}
		}

		static var foreground: RSColor {
			RSColor { tc in
				tc.userInterfaceStyle == .dark
					? RSColor(red:  38/255, green:  38/255, blue:  36/255, alpha: 1)
					: RSColor(red: 251/255, green: 252/255, blue: 255/255, alpha: 1)
			}
		}

		static var sectionHeader: RSColor         { background }
		static var iconBackground: RSColor        { foreground }
		static var fullScreenBackground: RSColor  { background }

		static var star: RSColor {
			RSColor(red: 249/255, green: 198/255, blue: 52/255, alpha: 1)
		}

		static var vibrantText: RSColor {
			RSColor { tc in
				tc.userInterfaceStyle == .dark ? .label : .white
			}
		}

		static var controlBackground: RSColor {
			RSColor { tc in
				tc.userInterfaceStyle == .dark
					? RSColor.white.withAlphaComponent(0.25)
					: RSColor.black.withAlphaComponent(0.25)
			}
		}

		/// Background for interactive input elements (text fields, search bars, icon tiles).
		/// Full white in light mode; black in dark mode.
		static var interactionBackground: RSColor {
			RSColor { tc in
				tc.userInterfaceStyle == .dark ? .black : .white
			}
		}

		// MARK: - Geometry
		/// Corner radius for the shadow path on table/collection section cards.
		/// UIKit controls the actual cell corners in insetGrouped — this only affects the shadow.
		static let shadowTablesCornerRadius: CGFloat = 20
		/// Corner radius for article reading boxes (CSS border-radius — fully controllable).
		static let boxCornerRadius: CGFloat = 20

		// MARK: - Shadow — single source of truth
		//
		// All shadow appearances (native CALayer and CSS box-shadow) are derived
		// from these constants.  Change here, it propagates everywhere.

		// Table / collection section card shadows (native CALayer)
		private static let tableShadowColorLight = UIColor.black
		private static let tableShadowColorDark  = UIColor.clear  // no shadow in dark mode
		private static let tableShadowOpacityLight: Float  = 0.1
		private static let tableShadowOpacityDark:  Float  = 0
		private static let tableShadowRadius:  CGFloat = 2
		private static let tableShadowOffsetX: CGFloat = 3
		private static let tableShadowOffsetY: CGFloat = 3

		// Article reading box shadows (CSS)
		// Note: CSS box-shadow has no corner radius — it follows border-radius automatically.
		private static let boxShadowOpacityLight: Float = 0.1
		private static let boxShadowOpacityDark:  Float = 0
		private static let boxShadowRadius:  CGFloat = 3
		private static let boxShadowOffsetX: CGFloat = 3
		private static let boxShadowOffsetY: CGFloat = 3

		private static func cssBoxShadow(opacity: Float) -> String {
			let blur    = Int(boxShadowRadius * 2)
			let offsetX = Int(boxShadowOffsetX)
			let offsetY = Int(boxShadowOffsetY)
			return "\(offsetX)px \(offsetY)px \(blur)px rgba(0, 0, 0, \(opacity))"
		}

		/// CSS box-shadow for light mode — injected via [[groupbox-box-shadow]].
		static let groupboxBoxShadow:     String = cssBoxShadow(opacity: boxShadowOpacityLight)
		/// CSS box-shadow for dark mode  — injected via [[groupbox-box-shadow-dark]].
		static let groupboxBoxShadowDark: String = cssBoxShadow(opacity: boxShadowOpacityDark)

		@MainActor static var tableShadowEnabled = true

		@MainActor static func applyForegroundShadow(to layer: CALayer, traitCollection: UITraitCollection) {
			let isDark = traitCollection.userInterfaceStyle == .dark
			guard tableShadowEnabled, !isDark else {
				layer.shadowOpacity = 0
				return
			}
			layer.masksToBounds = false
			layer.shadowColor   = tableShadowColorLight.cgColor
			layer.shadowOpacity = tableShadowOpacityLight
			layer.shadowRadius  = tableShadowRadius
			layer.shadowOffset  = CGSize(width: tableShadowOffsetX, height: tableShadowOffsetY)
		}
#endif
	}
}

#if os(iOS)
extension UIColor {

	enum InterfaceStyle { case light, dark }

	/// Resolves a dynamic colour for a given light/dark style and returns a CSS hex string.
	func hexString(forStyle style: InterfaceStyle) -> String {
		let tc = UITraitCollection(userInterfaceStyle: style == .dark ? .dark : .light)
		let resolved = resolvedColor(with: tc)
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
		return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
	}
}
#endif

extension RSImage {

	convenience init?(symbol: String) {
#if os(macOS)
		self.init(systemSymbolName: symbol, accessibilityDescription: nil)
#else // iOS
		self.init(systemName: symbol)
#endif
	}
}
