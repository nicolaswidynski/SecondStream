//
//  SettingsViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 4/24/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import CoreServices
import SafariServices
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import LocalAuthentication
import RSCore
import Account
import UserNotifications

final class SettingsViewController: UITableViewController {

	private enum DocumentPickerMode {
		case opmlImport
		case obsidianVault
	}

	private weak var opmlAccount: Account?
	private var documentPickerMode: DocumentPickerMode = .opmlImport

	@IBOutlet var timelineSortOrderSwitch: UISwitch!
	@IBOutlet var groupByFeedSwitch: UISwitch!
	@IBOutlet var refreshClearsReadArticlesSwitch: UISwitch!
	@IBOutlet var articleThemeDetailLabel: UILabel!
	@IBOutlet var confirmMarkAllAsReadSwitch: UISwitch!
	@IBOutlet var showFullscreenArticlesSwitch: UISwitch!
	@IBOutlet var colorPaletteDetailLabel: UILabel!
	@IBOutlet var openLinksInNetNewsWire: UISwitch!
	@IBOutlet var enableJavaScriptSwitch: UISwitch!
	@IBOutlet var notifyFeedsSwitch: UISwitch!
	@IBOutlet var notifyPodcastsSwitch: UISwitch!
	@IBOutlet var notifyYouTubeSwitch: UISwitch!
	@IBOutlet var notifyWeeklyNewsSwitch: UISwitch!
	@IBOutlet var obsidianSyncSwitch: UISwitch!
	@IBOutlet var obsidianVaultLabel: UILabel!
	@IBOutlet var obsidianVaultCell: UITableViewCell!
	@IBOutlet var obsidianSubfolderFeedTypeSwitch: UISwitch!
	@IBOutlet var obsidianSubfolderFeedNameSwitch: UISwitch!
	@IBOutlet var obsidianSubfolderPreviewLabel: UILabel!
	@IBOutlet var obsidianRemoveOnUnbookmarkSwitch: UISwitch!
	@IBOutlet var ttsVoiceDetailLabel: UILabel!

	private var devOptionsUnlocked = false
	private let displaySection = 5
	private let ttsSection = 6
	private let debugSection = 8
	private let aboutSection = 9
	private let ttsEnabledRow = 0
	private let ttsVoiceRow = 1
	private let timelineUnreadFirstRow = 1
	private let timelineReadStylingRow = 2
	private let sectionHeaderIconsRow = 3
	private let collapsibleSectionsRow = 4
	private let displayFaceIDRow = 5
	// Debug section rows
	private let debugCleanTempRow = 0
	private let debugDialogRow = 1
	private let debugLandingPageRow = 2
	private let debugIOSSignOutRow = 3
	private let debugColorHighlightRow = 4
	// More section rows
	private let aboutAppRow = 0
	private let aboutDisconnectRow = 1
	private let aboutDeleteRow = 2

	var scrollToArticlesSection = false
	var openWithDevOptionsUnlocked = false
	weak var presentingParentController: UIViewController?

	override func viewDidLoad() {
		// This hack mostly works around a bug in static tables with dynamic type.  See: https://spin.atomicobject.com/2018/10/15/dynamic-type-static-uitableview/
		NotificationCenter.default.removeObserver(tableView!, name: UIContentSizeCategory.didChangeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChange), name: UIContentSizeCategory.didChangeNotification, object: nil)
		registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: SettingsViewController, _: UITraitCollection) in
			guard let self else { return }
			tableView.layoutSectionCardShadows(in: &sectionShadowViews)
		}

		NotificationCenter.default.addObserver(self, selector: #selector(accountsDidChange), name: .UserDidAddAccount, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(accountsDidChange), name: .UserDidDeleteAccount, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(displayNameDidChange), name: .DisplayNameDidChange, object: nil)

		tableView.register(UINib(nibName: "SettingsComboTableViewCell", bundle: nil), forCellReuseIdentifier: "SettingsComboTableViewCell")
		tableView.register(UINib(nibName: "SettingsTableViewCell", bundle: nil), forCellReuseIdentifier: "SettingsTableViewCell")
		UISwitch.appearance(whenContainedInInstancesOf: [SettingsViewController.self]).onTintColor = Assets.Colors.primaryAccent

		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 44
		tableView.backgroundColor = Assets.Colors.SettingsContentBgColor
	}

	private var sectionShadowViews: [UIView] = []

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		tableView.layoutSectionCardShadows(in: &sectionShadowViews)
	}

	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		var bg = UIBackgroundConfiguration.listCell()
		bg.backgroundColor = Assets.Colors.SettingsContentTableColor
		cell.backgroundConfiguration = bg
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		applySettingsNavBarAppearance()

		if openWithDevOptionsUnlocked {
			devOptionsUnlocked = true
		}

		if AppDefaults.shared.timelineSortDirection == .orderedAscending {
			timelineSortOrderSwitch.isOn = true
		} else {
			timelineSortOrderSwitch.isOn = false
		}

		if AppDefaults.shared.timelineGroupByFeed {
			groupByFeedSwitch.isOn = true
		} else {
			groupByFeedSwitch.isOn = false
		}

		if AppDefaults.shared.refreshClearsReadArticles {
			refreshClearsReadArticlesSwitch.isOn = true
		} else {
			refreshClearsReadArticlesSwitch.isOn = false
		}

		articleThemeDetailLabel.text = ArticleThemesManager.shared.currentTheme.name

		if AppDefaults.shared.confirmMarkAllAsRead {
			confirmMarkAllAsReadSwitch.isOn = true
		} else {
			confirmMarkAllAsReadSwitch.isOn = false
		}

		if AppDefaults.shared.articleFullscreenAvailable {
			showFullscreenArticlesSwitch.isOn = true
		} else {
			showFullscreenArticlesSwitch.isOn = false
		}

		if AppDefaults.shared.isArticleContentJavascriptEnabled {
			enableJavaScriptSwitch.isOn = true
		} else {
			enableJavaScriptSwitch.isOn = false
		}

		colorPaletteDetailLabel.text = String(describing: AppDefaults.userInterfaceColorPalette)

		openLinksInNetNewsWire.isOn = !AppDefaults.shared.useSystemBrowser

		// Obsidian switches are still connected in the storyboard; keep them in sync
		// even though the Obsidian section is now a sub-page (they live in memory).
		obsidianSyncSwitch.isOn = AppDefaults.shared.isObsidianSyncEnabled
		obsidianSubfolderFeedTypeSwitch.isOn = AppDefaults.shared.obsidianSubfolderFeedType
		obsidianSubfolderFeedNameSwitch.isOn = AppDefaults.shared.obsidianSubfolderFeedName
		obsidianRemoveOnUnbookmarkSwitch.isOn = AppDefaults.shared.obsidianRemoveOnUnbookmark

		updateTTSVoiceLabel()

		let buildLabel = NonIntrinsicLabel()
		buildLabel.font = UIFont.systemFont(ofSize: 11.0)
		buildLabel.textColor = UIColor.gray
		buildLabel.text = "\(Bundle.main.appName) \(Bundle.main.versionNumber) (Build \(Bundle.main.buildNumber))"
		buildLabel.sizeToFit()
		buildLabel.translatesAutoresizingMaskIntoConstraints = false

		let wrapperView = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: buildLabel.frame.height + 10.0))
		wrapperView.addSubview(buildLabel)
		NSLayoutConstraint.activate([
			buildLabel.leadingAnchor.constraint(equalTo: wrapperView.leadingAnchor, constant: 32),
			buildLabel.centerYAnchor.constraint(equalTo: wrapperView.centerYAnchor),
		])
		tableView.tableFooterView = wrapperView

		let tripleTap = UITapGestureRecognizer(target: self, action: #selector(buildLabelTripleTapped))
		tripleTap.numberOfTapsRequired = 3
		wrapperView.isUserInteractionEnabled = true
		wrapperView.addGestureRecognizer(tripleTap)

	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		self.tableView.selectRow(at: nil, animated: true, scrollPosition: .none)

		if scrollToArticlesSection {
			tableView.scrollToRow(at: IndexPath(row: 0, section: 4), at: .top, animated: true)
			scrollToArticlesSection = false
		}

	}

	// MARK: UITableView

	// Permanently hidden sections: 1 = Accounts, 2 = Feeds, 3 = Timeline, 4 = Articles
	// Dev-only sections (6 = TTS, 8 = Debug) are hidden until triple-tap on build label.
	private var hiddenSections: Set<Int> {
		var hidden: Set<Int> = [1, 2, 3, 4]
		if !devOptionsUnlocked {
			hidden.insert(ttsSection)
			hidden.insert(debugSection)
		}
		return hidden
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		return super.numberOfSections(in: tableView)
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		// Hide specified sections
		if hiddenSections.contains(section) {
			return 0
		}

		switch section {
		case 0:
			// Single "Notifications >" navigation row
			return 1
		case 1:
			return AccountManager.shared.accounts.count + 1
		case 4:
			return traitCollection.userInterfaceIdiom == .phone ? 5 : 4
		case 7:
			// Single "Obsidian >" navigation row
			return 1
		case ttsSection:
			return super.tableView(tableView, numberOfRowsInSection: section) + 1
		case displaySection:
			// When dev options are locked, show only the Appearance row.
			if !devOptionsUnlocked { return 1 }
			// Adds Unread First, Gray Read Articles, Show Category Icons, Collapsible Sections, and Face ID rows
			return super.tableView(tableView, numberOfRowsInSection: section) + 5
		case debugSection:
			// Clear Temporary Files, Debug Dialog, Start Landing Page, Simulate iOS Sign Out, Color Highlight
			return 5
		case aboutSection:
			// About Second Stream, Disconnect Account, Delete Account
			return 3
		default:
			return super.tableView(tableView, numberOfRowsInSection: section)
		}
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if hiddenSections.contains(section) { return nil }
		if section == debugSection { return NSLocalizedString("Debug", comment: "Debug section header") }
		if section == aboutSection { return NSLocalizedString("More", comment: "More section header") }
		if section == displaySection { return NSLocalizedString("Settings", comment: "Settings section header") }
		return super.tableView(tableView, titleForHeaderInSection: section)
	}

	override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		if hiddenSections.contains(section) { return nil }
		return super.tableView(tableView, viewForHeaderInSection: section)
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		if hiddenSections.contains(section) { return nil }
		return super.tableView(tableView, titleForFooterInSection: section)
	}

	override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
		if hiddenSections.contains(section) { return nil }
		return super.tableView(tableView, viewForFooterInSection: section)
	}

	override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		if hiddenSections.contains(section) { return CGFloat.leastNormalMagnitude }
		return super.tableView(tableView, heightForHeaderInSection: section)
	}

	override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
		if hiddenSections.contains(section) { return CGFloat.leastNormalMagnitude }
		return super.tableView(tableView, heightForFooterInSection: section)
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell: UITableViewCell
		switch indexPath.section {
		case 0:
			cell = UITableViewCell(style: .default, reuseIdentifier: "NotificationsNavCell")
			cell.textLabel?.text = NSLocalizedString("Notifications", comment: "Notifications")
			cell.accessoryType = .disclosureIndicator
		case 1:
			let sortedAccounts = AccountManager.shared.sortedAccounts
			if indexPath.row == sortedAccounts.count {
				cell = tableView.dequeueReusableCell(withIdentifier: "SettingsTableViewCell", for: indexPath)
				cell.textLabel?.text = NSLocalizedString("Add Account", comment: "Accounts")
			} else {
				let acctCell = tableView.dequeueReusableCell(withIdentifier: "SettingsComboTableViewCell", for: indexPath) as! SettingsComboTableViewCell
				acctCell.applyThemeProperties()
				let account = sortedAccounts[indexPath.row]
				acctCell.comboImage?.image = Assets.accountImage(account.type)
				acctCell.comboNameLabel?.text = account.nameForDisplay
				cell = acctCell
			}
		case 7:
			cell = UITableViewCell(style: .default, reuseIdentifier: "ObsidianNavCell")
			cell.textLabel?.text = NSLocalizedString("Obsidian", comment: "Obsidian")
			cell.accessoryType = .disclosureIndicator
		case displaySection where indexPath.row == 0:
			cell = makeAppearanceSegmentedCell(tableView)
		case displaySection where indexPath.row == timelineReadStylingRow:
			cell = makeTimelineReadStylingCell(tableView)
		case displaySection where indexPath.row == sectionHeaderIconsRow:
			cell = makeSectionHeaderIconsCell(tableView)
		case displaySection where indexPath.row == collapsibleSectionsRow:
			cell = makeCollapsibleSectionsCell(tableView)
		case displaySection where indexPath.row == timelineUnreadFirstRow:
			cell = makeTimelineUnreadFirstCell(tableView)
		case displaySection where indexPath.row == displayFaceIDRow:
			cell = makeFaceIDCell(tableView)
		case ttsSection where indexPath.row == ttsEnabledRow:
			cell = makeTTSEnabledCell(tableView)
		case debugSection:
			switch indexPath.row {
			case debugCleanTempRow:
				cell = UITableViewCell(style: .default, reuseIdentifier: "CleanTempFilesCell")
				cell.textLabel?.text = NSLocalizedString("Clear Temporary Files", comment: "Clear Temporary Files")
			case debugDialogRow:
				cell = makeDebugDialogCell(tableView)
			case debugLandingPageRow:
				cell = makeDebugLandingPageCell(tableView)
			case debugIOSSignOutRow:
				cell = UITableViewCell(style: .default, reuseIdentifier: "DebugIOSSignOutCell")
				cell.textLabel?.text = "Simulate iOS Sign Out"
				cell.textLabel?.textColor = .systemOrange
			case debugColorHighlightRow:
				cell = makeDebugColorHighlightCell(tableView)
			default:
				cell = super.tableView(tableView, cellForRowAt: indexPath)
			}
		case aboutSection:
			switch indexPath.row {
			case aboutAppRow:
				cell = UITableViewCell(style: .default, reuseIdentifier: "AboutAppCell")
				cell.textLabel?.text = NSLocalizedString("About Second Stream", comment: "About Second Stream")
				cell.accessoryType = .disclosureIndicator
			case aboutDisconnectRow:
				cell = UITableViewCell(style: .default, reuseIdentifier: "DisconnectAccountCell")
				cell.textLabel?.text = NSLocalizedString("Log Out", comment: "Log Out")
			case aboutDeleteRow:
				cell = UITableViewCell(style: .default, reuseIdentifier: "DeleteAccountCell")
				cell.textLabel?.text = NSLocalizedString("Delete Account", comment: "Delete Account")
				cell.textLabel?.textColor = .systemRed
			default:
				cell = super.tableView(tableView, cellForRowAt: indexPath)
			}
		default:
			if indexPath.section == ttsSection && indexPath.row > ttsEnabledRow {
				let originalIndexPath = IndexPath(row: indexPath.row - 1, section: indexPath.section)
				cell = super.tableView(tableView, cellForRowAt: originalIndexPath)
			} else {
				cell = super.tableView(tableView, cellForRowAt: indexPath)
			}
		}
		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

		switch indexPath.section {
		case 0:
			navigationController?.pushViewController(NotificationsSettingsViewController(), animated: true)
		case 7:
			navigationController?.pushViewController(ObsidianSettingsViewController(), animated: true)
		case 1:
			break
		case 2:
			switch indexPath.row {
			case 0:
				tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
				if let sourceView = tableView.cellForRow(at: indexPath) {
					let sourceRect = tableView.rectForRow(at: indexPath)
					importOPML(sourceView: sourceView, sourceRect: sourceRect)
				}
			case 1:
				tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
				if let sourceView = tableView.cellForRow(at: indexPath) {
					let sourceRect = tableView.rectForRow(at: indexPath)
					exportOPML(sourceView: sourceView, sourceRect: sourceRect)
				}
			default:
				break
			}
		case 3:
			switch indexPath.row {
			case 3:
				let timeline = UIStoryboard.settings.instantiateController(ofType: TimelineCustomizerTableViewController.self)
				self.navigationController?.pushViewController(timeline, animated: true)
			default:
				break
			}
		case 4:
			switch indexPath.row {
			case 0:
				let articleThemes = UIStoryboard.settings.instantiateController(ofType: ArticleThemesTableViewController.self)
				self.navigationController?.pushViewController(articleThemes, animated: true)
			default:
				break
			}
		case 5:
			tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
		case 6:
			// Text-to-Speech section
			if indexPath.row == ttsVoiceRow {
				presentTTSVoicePicker()
			}
			tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
		case debugSection:
			switch indexPath.row {
			case debugCleanTempRow:
				cleanTemporaryFiles()
			case debugDialogRow:
				break // handled by switch
			case debugLandingPageRow:
				showDebugLandingPage()
			case debugIOSSignOutRow:
				simulateIOSSignOut()
			default:
				break
			}
			tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
		case aboutSection:
			switch indexPath.row {
			case aboutAppRow:
				let hosting = UIHostingController(rootView: AboutWPodView())
				hosting.view.backgroundColor = Assets.Colors.SettingsContentBgColor
				self.navigationController?.pushViewController(hosting, animated: true)
			case aboutDisconnectRow:
				confirmDisconnect()
				tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
				return
			case aboutDeleteRow:
				confirmDeleteAccount()
			default:
				break
			}
			tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
		default:
			tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
		}
	}

	override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		return false
	}

	override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
		return false
	}

	override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
		return .none
	}

	override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		return UITableView.automaticDimension
	}

	override func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
		if indexPath.section == debugSection || indexPath.section == aboutSection { return 0 }
		return super.tableView(tableView, indentationLevelForRowAt: IndexPath(row: 0, section: 1))
	}

	// MARK: Actions

	@IBAction func done(_ sender: Any) {
		dismiss(animated: true)
	}

	@IBAction func switchTimelineOrder(_ sender: Any) {
		if timelineSortOrderSwitch.isOn {
			AppDefaults.shared.timelineSortDirection = .orderedAscending
		} else {
			AppDefaults.shared.timelineSortDirection = .orderedDescending
		}
	}

	@IBAction func switchGroupByFeed(_ sender: Any) {
		if groupByFeedSwitch.isOn {
			AppDefaults.shared.timelineGroupByFeed = true
		} else {
			AppDefaults.shared.timelineGroupByFeed = false
		}
	}

	@IBAction func switchClearsReadArticles(_ sender: Any) {
		if refreshClearsReadArticlesSwitch.isOn {
			AppDefaults.shared.refreshClearsReadArticles = true
		} else {
			AppDefaults.shared.refreshClearsReadArticles = false
		}
	}

	@IBAction func switchConfirmMarkAllAsRead(_ sender: Any) {
		if confirmMarkAllAsReadSwitch.isOn {
			AppDefaults.shared.confirmMarkAllAsRead = true
		} else {
			AppDefaults.shared.confirmMarkAllAsRead = false
		}
	}

	@IBAction func switchFullscreenArticles(_ sender: Any) {
		if showFullscreenArticlesSwitch.isOn {
			AppDefaults.shared.articleFullscreenAvailable = true
		} else {
			AppDefaults.shared.articleFullscreenAvailable = false
		}
	}

	@IBAction func switchBrowserPreference(_ sender: Any) {
		if openLinksInNetNewsWire.isOn {
			AppDefaults.shared.useSystemBrowser = false
		} else {
			AppDefaults.shared.useSystemBrowser = true
		}
	}

	@IBAction func switchJavaScriptPreference(_ sender: Any) {
		AppDefaults.shared.isArticleContentJavascriptEnabled = enableJavaScriptSwitch.isOn
 	}

	@IBAction func switchObsidianSync(_ sender: Any) {
		AppDefaults.shared.isObsidianSyncEnabled = obsidianSyncSwitch.isOn
		updateObsidianVaultLabel()
		tableView.reloadSections(IndexSet(integer: 7), with: .none)
	}

	@IBAction func switchObsidianSubfolderFeedType(_ sender: Any) {
		AppDefaults.shared.obsidianSubfolderFeedType = obsidianSubfolderFeedTypeSwitch.isOn
		updateObsidianSubfolderPreview()
	}

	@IBAction func switchObsidianSubfolderFeedName(_ sender: Any) {
		AppDefaults.shared.obsidianSubfolderFeedName = obsidianSubfolderFeedNameSwitch.isOn
		updateObsidianSubfolderPreview()
	}

	@IBAction func switchObsidianRemoveOnUnbookmark(_ sender: Any) {
		AppDefaults.shared.obsidianRemoveOnUnbookmark = obsidianRemoveOnUnbookmarkSwitch.isOn
	}

	@IBAction func switchNotifyFeeds(_ sender: Any) {
		AppDefaults.shared.notifyFeeds = notifyFeedsSwitch.isOn
	}

	@IBAction func switchNotifyPodcasts(_ sender: Any) {
		AppDefaults.shared.notifyPodcasts = notifyPodcastsSwitch.isOn
	}

	@IBAction func switchNotifyYouTube(_ sender: Any) {
		AppDefaults.shared.notifyYouTube = notifyYouTubeSwitch.isOn
	}

	@IBAction func switchNotifyWeeklyNews(_ sender: Any) {
		AppDefaults.shared.notifyWeeklyNews = notifyWeeklyNewsSwitch.isOn
	}

	@objc func appearanceSegmentedChanged(_ sender: UISegmentedControl) {
		if let palette = UserInterfaceColorPalette(rawValue: sender.selectedSegmentIndex) {
			AppDefaults.userInterfaceColorPalette = palette
		}
	}

	@objc func switchTimelineReadStyling(_ sender: UISwitch) {
		AppDefaults.shared.timelineDimReadArticles = sender.isOn
	}

	@objc func switchTimelineUnreadFirst(_ sender: UISwitch) {
		AppDefaults.shared.timelineUnreadFirst = sender.isOn
	}

	@objc func switchSectionHeaderIcons(_ sender: UISwitch) {
		AppDefaults.shared.showSectionHeaderIcons = sender.isOn
		NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
	}

	@objc func switchCollapsibleSections(_ sender: UISwitch) {
		AppDefaults.shared.collapsibleArticleSectionsEnabled = sender.isOn
	}

	@objc func switchDebugDialog(_ sender: UISwitch) {
		AppDefaults.shared.showHomepageResolutionDebugDialog = sender.isOn
	}

	@objc func switchDebugColorHighlight(_ sender: UISwitch) {
		AppDefaults.shared.debugColorHighlightEnabled = sender.isOn
	}

	func showDebugLandingPage() {
		dismiss(animated: true) {
			guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
				  let sceneDelegate = windowScene.delegate as? SceneDelegate else {
				return
			}
			sceneDelegate.presentOnboarding(isDebug: true)
		}
	}

	func simulateIOSSignOut() {
		AuthManager.shared.simulateIOSSignOut()
		dismiss(animated: true) {
			guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
				  let sceneDelegate = windowScene.delegate as? SceneDelegate else {
				return
			}
			sceneDelegate.presentRegistration()
		}
	}


	@objc func switchTTSEnabled(_ sender: UISwitch) {
		AppDefaults.shared.ttsEnabled = sender.isOn
		NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
	}

	@objc func switchFaceID(_ sender: UISwitch) {
		guard sender.isOn else {
			AppDefaults.shared.faceIDEnabled = false
			return
		}
		let context = LAContext()
		var error: NSError?
		guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
			sender.setOn(false, animated: true)
			let message = error?.localizedDescription ?? NSLocalizedString("Face ID is not available on this device.", comment: "Face ID unavailable")
			presentError(title: NSLocalizedString("Face ID Unavailable", comment: "Face ID unavailable title"), message: message)
			return
		}
		let reason = NSLocalizedString("Enable Face ID for Second Stream", comment: "Face ID enrollment reason")
		context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, authError in
			DispatchQueue.main.async {
				if success {
					AppDefaults.shared.faceIDEnabled = true
				} else {
					sender.setOn(false, animated: true)
					if let authError, (authError as NSError).code != LAError.userCancel.rawValue {
						self?.presentError(title: NSLocalizedString("Face ID Failed", comment: "Face ID failed title"), message: authError.localizedDescription)
					}
				}
			}
		}
	}

	// MARK: - Notifications

	@objc func buildLabelTripleTapped() {
		devOptionsUnlocked.toggle()
		tableView.reloadSections(IndexSet([ttsSection, debugSection, displaySection]), with: .fade)
	}

	@objc func contentSizeCategoryDidChange() {
		tableView.reloadData()
	}

	@objc func accountsDidChange() {
		tableView.reloadData()
	}

	@objc func displayNameDidChange() {
		tableView.reloadData()
	}

	@objc func browserPreferenceDidChange() {
		tableView.reloadData()
	}

}

// MARK: - Document Picker

extension SettingsViewController: UIDocumentPickerDelegate {

	func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
		switch documentPickerMode {
		case .opmlImport:
			for url in urls {
				opmlAccount?.importOPML(url) { result in
					switch result {
					case .success:
						break
					case .failure:
						let title = NSLocalizedString("Import Failed", comment: "Import Failed")
						let message = NSLocalizedString("We were unable to process the selected file.  Please ensure that it is a properly formatted OPML file.", comment: "Import Failed Message")
						self.presentError(title: title, message: message)
					}
				}
			}

		case .obsidianVault:
			guard let url = urls.first else {
				return
			}
			do {
				try ObsidianFileManager.storeVaultBookmark(for: url)
				updateObsidianVaultLabel()
			} catch {
				let title = NSLocalizedString("Error", comment: "Error")
				let message = NSLocalizedString("Unable to access the selected folder. Please try again.", comment: "Obsidian vault access error")
				presentError(title: title, message: message)
			}
		}
	}

}

// MARK: - Private

private extension SettingsViewController {

	func makeAppearanceSegmentedCell(_ tableView: UITableView) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "AppearanceSegmentedCell") ??
			UITableViewCell(style: .default, reuseIdentifier: "AppearanceSegmentedCell")
		cell.selectionStyle = .none
		cell.textLabel?.text = NSLocalizedString("Appearance", comment: "Appearance")
		let items = UserInterfaceColorPalette.allCases.map { $0.description }
		let control = (cell.accessoryView as? UISegmentedControl) ?? UISegmentedControl(items: items)
		control.selectedSegmentIndex = AppDefaults.userInterfaceColorPalette.rawValue
		control.removeTarget(self, action: #selector(appearanceSegmentedChanged(_:)), for: .valueChanged)
		control.addTarget(self, action: #selector(appearanceSegmentedChanged(_:)), for: .valueChanged)
		cell.accessoryView = control
		return cell
	}

	func makeTimelineUnreadFirstCell(_ tableView: UITableView) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "TimelineUnreadFirstCell") ??
			UITableViewCell(style: .default, reuseIdentifier: "TimelineUnreadFirstCell")
		var content = cell.defaultContentConfiguration()
		content.text = NSLocalizedString("Unread First", comment: "Timeline ordering toggle")
		cell.contentConfiguration = content
		cell.selectionStyle = .none
		let toggle = (cell.accessoryView as? UISwitch) ?? UISwitch(frame: .zero)
		toggle.removeTarget(self, action: #selector(switchTimelineUnreadFirst(_:)), for: .valueChanged)
		toggle.addTarget(self, action: #selector(switchTimelineUnreadFirst(_:)), for: .valueChanged)
		toggle.isOn = AppDefaults.shared.timelineUnreadFirst
		cell.accessoryView = toggle
		return cell
	}

	func makeSectionHeaderIconsCell(_ tableView: UITableView) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "SectionHeaderIconsCell") ??
			UITableViewCell(style: .default, reuseIdentifier: "SectionHeaderIconsCell")
		var content = cell.defaultContentConfiguration()
		content.text = NSLocalizedString("Show Category Icons", comment: "Section header icons toggle")
		cell.contentConfiguration = content
		cell.selectionStyle = .none
		let toggle = (cell.accessoryView as? UISwitch) ?? UISwitch(frame: .zero)
		toggle.removeTarget(self, action: #selector(switchSectionHeaderIcons(_:)), for: .valueChanged)
		toggle.addTarget(self, action: #selector(switchSectionHeaderIcons(_:)), for: .valueChanged)
		toggle.isOn = AppDefaults.shared.showSectionHeaderIcons
		cell.accessoryView = toggle
		return cell
	}

	func makeTimelineReadStylingCell(_ tableView: UITableView) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "TimelineReadStylingCell") ??
			UITableViewCell(style: .default, reuseIdentifier: "TimelineReadStylingCell")
		var content = cell.defaultContentConfiguration()
		content.text = NSLocalizedString("Gray Read Articles", comment: "Timeline styling toggle")
		cell.contentConfiguration = content
		cell.selectionStyle = .none
		let toggle = (cell.accessoryView as? UISwitch) ?? UISwitch(frame: .zero)
		toggle.removeTarget(self, action: #selector(switchTimelineReadStyling(_:)), for: .valueChanged)
		toggle.addTarget(self, action: #selector(switchTimelineReadStyling(_:)), for: .valueChanged)
		toggle.isOn = AppDefaults.shared.timelineDimReadArticles
		cell.accessoryView = toggle
		return cell
	}

	func makeCollapsibleSectionsCell(_ tableView: UITableView) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "CollapsibleSectionsCell") ??
			UITableViewCell(style: .default, reuseIdentifier: "CollapsibleSectionsCell")
		var content = cell.defaultContentConfiguration()
		content.text = NSLocalizedString("Collapsible Article Sections", comment: "Article sections collapsible toggle")
		cell.contentConfiguration = content
		cell.selectionStyle = .none
		let toggle = (cell.accessoryView as? UISwitch) ?? UISwitch(frame: .zero)
		toggle.removeTarget(self, action: #selector(switchCollapsibleSections(_:)), for: .valueChanged)
		toggle.addTarget(self, action: #selector(switchCollapsibleSections(_:)), for: .valueChanged)
		toggle.isOn = AppDefaults.shared.collapsibleArticleSectionsEnabled
		cell.accessoryView = toggle
		return cell
	}

	func makeDebugDialogCell(_ tableView: UITableView) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "DebugDialogCell") ??
			UITableViewCell(style: .default, reuseIdentifier: "DebugDialogCell")
		var content = cell.defaultContentConfiguration()
		content.text = NSLocalizedString("Debug Dialog", comment: "Debug dialog toggle")
		cell.contentConfiguration = content
		cell.selectionStyle = .none
		let toggle = (cell.accessoryView as? UISwitch) ?? UISwitch(frame: .zero)
		toggle.removeTarget(self, action: #selector(switchDebugDialog(_:)), for: .valueChanged)
		toggle.addTarget(self, action: #selector(switchDebugDialog(_:)), for: .valueChanged)
		toggle.isOn = AppDefaults.shared.showHomepageResolutionDebugDialog
		cell.accessoryView = toggle
		return cell
	}

	func makeDebugColorHighlightCell(_ tableView: UITableView) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "DebugColorHighlightCell") ??
			UITableViewCell(style: .default, reuseIdentifier: "DebugColorHighlightCell")
		var content = cell.defaultContentConfiguration()
		content.text = "Color Highlight"
		cell.contentConfiguration = content
		cell.selectionStyle = .none
		let toggle = (cell.accessoryView as? UISwitch) ?? UISwitch(frame: .zero)
		toggle.removeTarget(self, action: #selector(switchDebugColorHighlight(_:)), for: .valueChanged)
		toggle.addTarget(self, action: #selector(switchDebugColorHighlight(_:)), for: .valueChanged)
		toggle.isOn = AppDefaults.shared.debugColorHighlightEnabled
		cell.accessoryView = toggle
		return cell
	}

	func makeDebugLandingPageCell(_ tableView: UITableView) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "DebugLandingPageCell") ??
			UITableViewCell(style: .default, reuseIdentifier: "DebugLandingPageCell")
		var content = cell.defaultContentConfiguration()
		content.text = NSLocalizedString("Start Landing Page", comment: "Debug: show landing page")
		cell.contentConfiguration = content
		cell.accessoryView = nil
		cell.selectionStyle = .default
		return cell
	}


	func makeFaceIDCell(_ tableView: UITableView) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "FaceIDCell") ??
			UITableViewCell(style: .default, reuseIdentifier: "FaceIDCell")
		var content = cell.defaultContentConfiguration()
		content.text = NSLocalizedString("Enable Face ID", comment: "Face ID toggle")
		cell.contentConfiguration = content
		cell.selectionStyle = .none
		let toggle = (cell.accessoryView as? UISwitch) ?? UISwitch(frame: .zero)
		toggle.removeTarget(self, action: #selector(switchFaceID(_:)), for: .valueChanged)
		toggle.addTarget(self, action: #selector(switchFaceID(_:)), for: .valueChanged)
		toggle.isOn = AppDefaults.shared.faceIDEnabled
		cell.accessoryView = toggle
		return cell
	}

	func makeTTSEnabledCell(_ tableView: UITableView) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "TTSEnabledCell") ??
			UITableViewCell(style: .default, reuseIdentifier: "TTSEnabledCell")
		var content = cell.defaultContentConfiguration()
		content.text = NSLocalizedString("Enable Text-to-Speech", comment: "Text-to-Speech enabled toggle")
		cell.contentConfiguration = content
		cell.selectionStyle = .none
		let toggle = (cell.accessoryView as? UISwitch) ?? UISwitch(frame: .zero)
		toggle.removeTarget(self, action: #selector(switchTTSEnabled(_:)), for: .valueChanged)
		toggle.addTarget(self, action: #selector(switchTTSEnabled(_:)), for: .valueChanged)
		toggle.isOn = AppDefaults.shared.ttsEnabled
		cell.accessoryView = toggle
		return cell
	}

	func importOPML(sourceView: UIView, sourceRect: CGRect) {
		switch AccountManager.shared.activeAccounts.count {
		case 0:
			presentError(title: "Error", message: NSLocalizedString("You must have at least one active account.", comment: "Missing active account"))
		case 1:
			opmlAccount = AccountManager.shared.activeAccounts.first
			importOPMLDocumentPicker()
		default:
			importOPMLAccountPicker(sourceView: sourceView, sourceRect: sourceRect)
		}
	}

	func importOPMLAccountPicker(sourceView: UIView, sourceRect: CGRect) {
		let title = NSLocalizedString("Choose an account to receive the imported feeds and folders", comment: "Import Account")
		let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)

		if let popoverController = alert.popoverPresentationController {
			popoverController.sourceView = view
			popoverController.sourceRect = sourceRect
		}

		for account in AccountManager.shared.sortedActiveAccounts {
			let action = UIAlertAction(title: account.nameForDisplay, style: .default) { [weak self] _ in
				self?.opmlAccount = account
				self?.importOPMLDocumentPicker()
			}
			alert.addAction(action)
		}

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel")
		alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))

		self.present(alert, animated: true)
	}

	func importOPMLDocumentPicker() {
		documentPickerMode = .opmlImport

		var contentTypes: [UTType] = []

		// Create UTType for .opml files by extension, without requiring conformance.
		// This ensures files ending in .opml can be selected no matter how OPML is registered.
		// <https://github.com/Ranchero-Software/NetNewsWire/issues/4858>
		if let opmlByExtension = UTType(filenameExtension: "opml") {
			contentTypes.append(opmlByExtension)
		}

		// Also try the registered org.opml.opml UTI if it exists
		if let registeredOPML = UTType("org.opml.opml") {
			contentTypes.append(registeredOPML)
		}

		// Include XML as a fallback
		contentTypes.append(.xml)

		let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
		documentPicker.delegate = self
		documentPicker.modalPresentationStyle = .formSheet
		self.present(documentPicker, animated: true)
	}

	func presentObsidianVaultPicker() {
		documentPickerMode = .obsidianVault

		let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
		documentPicker.delegate = self
		documentPicker.modalPresentationStyle = .formSheet
		self.present(documentPicker, animated: true)
	}

	func presentTTSVoicePicker() {
		let voices = TextToSpeechManager.availableVoices()

		// If no enhanced/premium voices available, show instructions
		if voices.isEmpty {
			let title = NSLocalizedString("No Enhanced Voices Available", comment: "No enhanced voices title")
			let message = NSLocalizedString("Download enhanced or premium voices from Settings → Accessibility → Spoken Content → Voices", comment: "Download voices instructions")
			let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default))
			present(alert, animated: true)
			return
		}

		let title = NSLocalizedString("Select Voice", comment: "Select Voice")
		let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)

		if let popoverController = alert.popoverPresentationController {
			popoverController.sourceView = view
			popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
			popoverController.permittedArrowDirections = []
		}

		let currentIdentifier = AppDefaults.shared.ttsVoiceIdentifier

		for voice in voices {
			let qualityLabel: String
			switch voice.quality {
			case .premium:
				qualityLabel = " (Premium)"
			case .enhanced:
				qualityLabel = " (Enhanced)"
			default:
				qualityLabel = ""
			}

			let action = UIAlertAction(title: voice.name + qualityLabel, style: .default) { [weak self] _ in
				AppDefaults.shared.ttsVoiceIdentifier = voice.identifier
				self?.updateTTSVoiceLabel()
			}
			if voice.identifier == currentIdentifier {
				action.setValue(true, forKey: "checked")
			}
			alert.addAction(action)
		}

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel")
		alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))

		present(alert, animated: true)
	}

	func updateTTSVoiceLabel() {
		if let identifier = AppDefaults.shared.ttsVoiceIdentifier,
		   let voice = AVSpeechSynthesisVoice(identifier: identifier) {
			ttsVoiceDetailLabel.text = voice.name
		} else {
			ttsVoiceDetailLabel.text = NSLocalizedString("System Default", comment: "System default voice")
		}
	}


	func confirmDisconnect() {
		let alert = UIAlertController(
			title: NSLocalizedString("Disconnect Account", comment: "Disconnect Account"),
			message: NSLocalizedString("You will be signed out of your Second Stream account. Sign in again to reconnect.", comment: "Disconnect confirmation"),
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel))
		alert.addAction(UIAlertAction(title: NSLocalizedString("Disconnect", comment: "Disconnect"), style: .destructive) { [weak self] _ in
			AuthManager.shared.disconnect()
			self?.dismiss(animated: true) {
				guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
					  let sceneDelegate = windowScene.delegate as? SceneDelegate else {
					return
				}
				sceneDelegate.presentRegistration()
			}
		})
		present(alert, animated: true)
	}

	func confirmDeleteAccount() {
		let alert = UIAlertController(
			title: NSLocalizedString("Delete Account", comment: "Delete Account"),
			message: NSLocalizedString("This will permanently delete your Second Stream account and all associated data. This action cannot be undone.", comment: "Delete account confirmation"),
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel))
		alert.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: "Delete"), style: .destructive) { [weak self] _ in
			Task {
				do {
					try await AuthManager.shared.deleteAccount()
					await MainActor.run {
						self?.dismiss(animated: true) {
							guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
								  let sceneDelegate = windowScene.delegate as? SceneDelegate else {
								return
							}
							sceneDelegate.presentRegistration()
						}
					}
				} catch {
					await MainActor.run {
						self?.presentError(title: NSLocalizedString("Error", comment: "Error"), message: error.localizedDescription)
					}
				}
			}
		})
		present(alert, animated: true)
	}

	func cleanTemporaryFiles() {
		let alert = UIAlertController(
			title: NSLocalizedString("Clear Temporary Files", comment: "Clear Temporary Files"),
			message: NSLocalizedString("This will remove cached icons/images and cached source lists. They will be re-downloaded when needed.", comment: "Clear temp files message"),
			preferredStyle: .alert
		)

			alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel))
			alert.addAction(UIAlertAction(title: NSLocalizedString("Clean", comment: "Clean"), style: .destructive) { _ in
				SourceImageCache.shared.clearCache()
				FaviconDownloader.shared.resetCache()
				IconImageCache.shared.emptyCache()
				Task {
					await SourceFileFetcher.clearHeadersCache()
				}
				MediaSourcesManager.podcast.topSources = []
				MediaSourcesManager.podcast.librarySources = []
				MediaSourcesManager.youtube.topSources = []
				MediaSourcesManager.youtube.librarySources = []
				NewsSourcesManager.shared.newsSources = []
				RSSSourcesManager.shared.rssSources = []

				// Drop the content hash and conditional-GET info (ETag/Last-Modified) for
				// all JSON feeds (podcast, youtube, news) so the next refresh re-downloads
				// and re-parses them, picking up any server-side content changes.
				for account in AccountManager.shared.activeAccounts {
					for feed in account.flattenedFeeds() {
						if feed.feedCategory != .rss {
							feed.dropConditionalGetInfo()
						}
					}
				}

				SourcesRefreshManager.shared.forceRefresh()
				AccountManager.shared.refreshAllWithoutWaiting(errorHandler: ErrorHandler.log)
			})

		present(alert, animated: true)
	}


	func updateObsidianSubfolderPreview() {
		obsidianSubfolderPreviewLabel.text = ObsidianFileManager.subfolderPreviewWithVault()
	}

	func updateObsidianVaultLabel() {
		let displayPath = ObsidianFileManager.vaultDisplayPath()
		let notSet = NSLocalizedString("Not Set", comment: "Obsidian vault not configured")
		obsidianVaultLabel.text = displayPath ?? notSet

		// Enable/disable vault cell based on sync toggle
		let isEnabled = obsidianSyncSwitch.isOn
		obsidianVaultCell?.isUserInteractionEnabled = isEnabled
		obsidianVaultCell?.textLabel?.isEnabled = isEnabled
		obsidianVaultLabel.isEnabled = isEnabled
		obsidianVaultLabel.textColor = isEnabled ? .label : .secondaryLabel

		// Refresh preview to reflect updated vault name
		updateObsidianSubfolderPreview()
	}

	func exportOPML(sourceView: UIView, sourceRect: CGRect) {
		if AccountManager.shared.accounts.count == 1 {
			opmlAccount = AccountManager.shared.accounts.first!
			exportOPMLDocumentPicker()
		} else {
			exportOPMLAccountPicker(sourceView: sourceView, sourceRect: sourceRect)
		}
	}

	func exportOPMLAccountPicker(sourceView: UIView, sourceRect: CGRect) {
		let title = NSLocalizedString("Choose an account with the subscriptions to export", comment: "Export Account")
		let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)

		if let popoverController = alert.popoverPresentationController {
			popoverController.sourceView = view
			popoverController.sourceRect = sourceRect
		}

		for account in AccountManager.shared.sortedAccounts {
			let action = UIAlertAction(title: account.nameForDisplay, style: .default) { [weak self] _ in
				self?.opmlAccount = account
				self?.exportOPMLDocumentPicker()
			}
			alert.addAction(action)
		}

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel")
		alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))

		self.present(alert, animated: true)
	}

	func exportOPMLDocumentPicker() {
		guard let account = opmlAccount else { return }

		let accountName = account.nameForDisplay.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespaces)
		let filename = "Subscriptions-\(accountName).opml"
		let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
		let opmlString = OPMLExporter.OPMLString(with: account, title: filename)
		do {
			try opmlString.write(to: tempFile, atomically: true, encoding: String.Encoding.utf8)
		} catch {
			self.presentError(title: "OPML Export Error", message: error.localizedDescription)
		}

		let docPicker = UIDocumentPickerViewController(forExporting: [tempFile])
		docPicker.modalPresentationStyle = .formSheet
		self.present(docPicker, animated: true)
	}

	func openURL(_ urlString: String) {
		let vc = SFSafariViewController(url: URL(string: urlString)!)
		vc.modalPresentationStyle = .pageSheet
		present(vc, animated: true)
	}
}

extension UIViewController {

	/// Applies the standard settings nav bar appearance (opaque background, settings color, separator).
	/// Call from `viewWillAppear(_:)` in every settings VC so the look is consistent regardless of
	/// how the VC was pushed (from SettingsViewController, from LeftSideMenuViewController, or on iPad
	/// in a fresh navigation controller).
	func applySettingsNavBarAppearance() {
		let appearance = UINavigationBarAppearance()
		appearance.configureWithOpaqueBackground()
		appearance.backgroundColor = Assets.Colors.SettingsNavBarColor
		navigationController?.navigationBar.standardAppearance = appearance
		navigationController?.navigationBar.scrollEdgeAppearance = appearance
		navigationController?.navigationBar.compactAppearance = appearance
	}
}
