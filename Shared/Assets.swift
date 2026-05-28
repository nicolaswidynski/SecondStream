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
		static var accountCloudKit: RSImage { RSImage(named: "accountCloudKit")! }

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
		}
	}

	struct Colors {
#if os(macOS)
		static var primaryAccent: RSColor { RSColor(named: "AccentColor")! }
		static var timelineSeparator: RSColor { NSColor(named: "timelineSeparatorColor")! }
		static var iconLightBackground: RSColor { RSColor(named: "iconLightBackgroundColor")! }
		static var iconDarkBackground: RSColor { RSColor(named: "iconDarkBackgroundColor")! }
		static var star: RSColor { RSColor(named: "StarColor")! }
#else // iOS

		// MARK: - Core Palette
		// Single source of truth for base colors. Scene variables below reference these.
		
		nonisolated(unsafe) static var theme = "gradients" // plain, gradients

		static var primaryAccent: RSColor {
			RSColor { tc in
				tc.userInterfaceStyle == .dark
				? RSColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1)
				: RSColor(red: 0.0,  green: 0.48, blue: 1.0, alpha: 1)
			}
		}

		static var secondaryAccent: RSColor { primaryAccent	}

		static var background: RSColor {
			RSColor { tc in
				tc.userInterfaceStyle == .dark
				? RSColor(red:  27/255, green:  26/255, blue:  30/255, alpha: 1)
				: RSColor(red: 236/255, green: 238/255, blue: 245/255, alpha: 1)
			}
		}

		static var foreground: RSColor {
			RSColor { tc in
				tc.userInterfaceStyle == .dark
				? RSColor(red:  39/255, green:  39/255, blue: 43/255, alpha: 1)
				: RSColor(red: 247/255, green: 248/255, blue: 255/255, alpha: 1)
			}
		}

		static var foreground2: RSColor { //foreground
			RSColor { tc in
				tc.userInterfaceStyle == .dark
				? RSColor(red:  33/255, green:  32/255, blue:  36/255, alpha: 1)
				: RSColor(red: 244/255, green: 246/255, blue: 253/255, alpha: 1)
			}
		}
		
		// MARK: - Debug
		
		static func dbg(dbgColor: RSColor, color: RSColor) -> RSColor {
			AppDefaults.shared.debugColorHighlightEnabled ? dbgColor : color
		}
		
		// MARK: - Feed Scene
		
		nonisolated(unsafe) static var foregroundTheme = theme == "plain" ? background : foreground;
		nonisolated(unsafe) static var foreground2Theme = theme == "plain" ? background : foreground2;

		static var FeedSceneNavBarColor: RSColor          { dbg(dbgColor: .blue, color: foregroundTheme) }
		static var FeedSceneNavBarContourColor: RSColor?   { theme == "plain" ? nil : .opaqueSeparator }
		static var FeedSceneRecentlyUpdatedLabelColor: RSColor { dbg(dbgColor: .purple, color: background) }
		static var FeedSceneRecentlyUpdatedColor: RSColor { dbg(dbgColor: .red, color: background).withAlphaComponent(0.85) }
		static var FeedSceneContentBgColor: RSColor       { dbg(dbgColor: .yellow, color: background) }
		static var FeedSceneContentTableColor: RSColor    { dbg(dbgColor: .green, color: background) }

		// MARK: - Timeline Scene

		static var TimelineSceneNavBarColor: RSColor       { FeedSceneNavBarColor }
		static var TimelineSceneContentBgColor: RSColor    { FeedSceneContentBgColor }
		static var TimelineSceneContentTableColor: RSColor { FeedSceneContentTableColor }

		// MARK: - Article Scene

		static var ArticleSceneNavBarColor: RSColor        { FeedSceneNavBarColor }
		static var ArticleSceneContentBgColor: RSColor     { FeedSceneContentBgColor }
		static var ArticleSceneContentBoxesColor: RSColor { dbg(dbgColor: .cyan, color: foreground2Theme) }
		
		// MARK: - Settings

		static var SettingsNavBarColor: RSColor       { FeedSceneContentBgColor }
		static var SettingsContentBgColor: RSColor    { FeedSceneContentBgColor }
		static var SettingsContentTableColor: RSColor { FeedSceneContentBgColor }

		// MARK: - Add

		static var AddNavBarColor: RSColor    { FeedSceneNavBarColor }
		static var AddContentBgColor: RSColor { FeedSceneContentTableColor }

		// MARK: - Utility Colors

		static var sectionHeader: RSColor        { background }
		static var iconBackground: RSColor       { foreground }
		static var fullScreenBackground: RSColor { background }

		static var star: RSColor { RSColor(red: 249/255, green: 198/255, blue: 52/255, alpha: 1) }

		static var vibrantText: RSColor {
			RSColor { tc in tc.userInterfaceStyle == .dark ? .label : .white }
		}

		/// Background colour applied to feed and article rows when tapped / selected.
		/// Set to nil to fall back to the default UIKit grey highlight.
		static var cellSelectionColor: RSColor? { RSColor.systemGray5 }

		static var readArticleTitle: RSColor {
			RSColor { tc in tc.userInterfaceStyle == .dark ? .secondaryLabel : .secondaryLabel }
		}

		static var controlBackground: RSColor {
			RSColor { tc in
				tc.userInterfaceStyle == .dark
				? RSColor.white.withAlphaComponent(0.25)
				: RSColor.black.withAlphaComponent(0.25)
			}
		}

		/// Background for interactive input elements (text fields, search bars, icon tiles).
		static var interactionBackground: RSColor {
			RSColor { tc in tc.userInterfaceStyle == .dark ? .black : .white }
		}

		// MARK: - Separators

		static var separator: RSColor {
			RSColor { tc in
				tc.userInterfaceStyle == .dark
				? RSColor(red:  27/255, green:  26/255, blue:  25/255, alpha: 0)
				: RSColor(red: 235/255, green: 237/255, blue: 242/255, alpha: 0)
			}
		}

		static var separatorSection: RSColor { separator }

		/// Separator inside article reading cards (between paragraphs).
		static var separatorArticle: RSColor {
			RSColor { tc in
				tc.userInterfaceStyle == .dark
				? RSColor(red: 61/255, green: 59/255, blue: 54/255, alpha: 153/255)
				: RSColor(red: 198/255, green: 198/255, blue: 200/255, alpha: 1)
			}
		}

		// MARK: - Geometry

		static let shadowTablesCornerRadius: CGFloat = 10
		static let scenePaneCornerRadius: CGFloat    = 0//24
		static let menuOpenCornerRadius: CGFloat     = 28

		// MARK: - Layout Spacing — Feeds Scene

		static let feedCellVerticalPadding: CGFloat      = 10
		static let feedSeparatorVerticalPadding: CGFloat = 0
		static let feedSectionSpacingTop: CGFloat        = 0
		static let feedSectionSpacingBottom: CGFloat     = 15

		// MARK: - Layout Spacing — Timeline Scene

		static let cellCornerRadius: CGFloat                 = 6
		static let timelineCellVerticalPadding: CGFloat      = 8
		static let timelineCellMinimumHeight: CGFloat        = 35
		static let timelineSeparatorVerticalPadding: CGFloat = 0
		static let timelineSectionSpacingTop: CGFloat        = 0
		static let timelineSectionSpacingBottom: CGFloat     = 15

		/// Storyboard constraint IDs: arj-Vg-UZ3 (IconFeedCell), nQe-AM-26Q (FeedCell).
		static let timelineCellBottomPadding: CGFloat = 6
		/// Fixed width of the date column — all titles left-align at the same offset.
		static let timelineDateColumnWidth: CGFloat   = 44

		// MARK: - Layout Spacing — Article Scene

		static let articleBoxCornerRadius: CGFloat       = 12  // top corners
		static let articleBoxBottomCornerRadius: CGFloat = 12  // bottom corners (0 = flat)
		static let articleBoxSpacingVertical: CGFloat    = 18  // margin between boxes
		static let articleBoxSpacingHorizontal: CGFloat  = 2   // margin left/right of boxes
		static let articleBoxPaddingTop: CGFloat         = 6
		static let articleBoxPaddingHorizontal: CGFloat  = 14
		static let articleBoxPaddingBottom: CGFloat      = 10

		// MARK: - Shadow System
		// All native shadow appearances derive from these constants.

		private static let tableShadowColorLight      = UIColor.black
		private static let tableShadowColorDark       = UIColor.clear
		private static let tableShadowOpacityLight: Float = 0//0.03
		private static let tableShadowOpacityDark:  Float = 0
		private static let tableShadowRadius:  CGFloat    = 2
		private static let tableShadowOffsetX: CGFloat    = 3
		private static let tableShadowOffsetY: CGFloat    = 3

		private static let boxShadowOpacityLight: Float   = 0//0.1
		private static let boxShadowOpacityDark:  Float   = 0
		private static let boxShadowRadius:  CGFloat      = 3
		private static let boxShadowOffsetX: CGFloat      = 3
		private static let boxShadowOffsetY: CGFloat      = 3

		private static func cssBoxShadow(opacity: Float) -> String {
			"\(Int(boxShadowOffsetX))px \(Int(boxShadowOffsetY))px \(Int(boxShadowRadius * 2))px rgba(0,0,0,\(opacity))"
		}

		/// CSS box-shadow injected via [[groupbox-box-shadow]] (light mode).
		static let groupboxBoxShadow:     String = cssBoxShadow(opacity: boxShadowOpacityLight)
		/// CSS box-shadow injected via [[groupbox-box-shadow-dark]] (dark mode).
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

	/// Like `hexString(forStyle:)` but emits an 8-digit `#RRGGBBAA` string when alpha < 1.
	func cssHexString(forStyle style: InterfaceStyle) -> String {
		let tc = UITraitCollection(userInterfaceStyle: style == .dark ? .dark : .light)
		let resolved = resolvedColor(with: tc)
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
		if abs(a - 1.0) < 0.001 {
			return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
		}
		return String(format: "#%02X%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))
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
