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

	private var notificationsAuthorized = false
	private let displaySection = 5
	private let ttsSection = 6
	private let debugSection = 8
	private let aboutSection = 9
	private let ttsEnabledRow = 0
	private let ttsVoiceRow = 1
	private let timelineUnreadFirstRow = 1
	private let timelineReadStylingRow = 2
	private let sectionHeaderIconsRow = 3
	// Debug section rows
	private let debugCleanTempRow = 0
	private let debugDialogRow = 1
	// About section rows
	private let aboutAppRow = 0
	private let aboutCreditsRow = 1
	private let aboutFaceIDRow = 2
	private let aboutDisconnectRow = 3
	private let aboutDeleteRow = 4

	var scrollToArticlesSection = false
	weak var presentingParentController: UIViewController?

	override func viewDidLoad() {
		// This hack mostly works around a bug in static tables with dynamic type.  See: https://spin.atomicobject.com/2018/10/15/dynamic-type-static-uitableview/
		NotificationCenter.default.removeObserver(tableView!, name: UIContentSizeCategory.didChangeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChange), name: UIContentSizeCategory.didChangeNotification, object: nil)

		NotificationCenter.default.addObserver(self, selector: #selector(accountsDidChange), name: .UserDidAddAccount, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(accountsDidChange), name: .UserDidDeleteAccount, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(displayNameDidChange), name: .DisplayNameDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(creditsDidUpdate), name: .creditsDidUpdate, object: nil)

		tableView.register(UINib(nibName: "SettingsComboTableViewCell", bundle: nil), forCellReuseIdentifier: "SettingsComboTableViewCell")
		tableView.register(UINib(nibName: "SettingsTableViewCell", bundle: nil), forCellReuseIdentifier: "SettingsTableViewCell")

		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 44
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

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

		updateNotificationSwitches()

		obsidianSyncSwitch.isOn = AppDefaults.shared.isObsidianSyncEnabled
		obsidianSubfolderFeedTypeSwitch.isOn = AppDefaults.shared.obsidianSubfolderFeedType
		obsidianSubfolderFeedNameSwitch.isOn = AppDefaults.shared.obsidianSubfolderFeedName
		obsidianRemoveOnUnbookmarkSwitch.isOn = AppDefaults.shared.obsidianRemoveOnUnbookmark
		updateObsidianVaultLabel()
		updateObsidianSubfolderPreview()

		updateTTSVoiceLabel()

		let buildLabel = NonIntrinsicLabel(frame: CGRect(x: 32.0, y: 0.0, width: 0.0, height: 0.0))
		buildLabel.font = UIFont.systemFont(ofSize: 11.0)
		buildLabel.textColor = UIColor.gray
		buildLabel.text = "\(Bundle.main.appName) \(Bundle.main.versionNumber) (Build \(Bundle.main.buildNumber))"
		buildLabel.sizeToFit()
		buildLabel.translatesAutoresizingMaskIntoConstraints = false

		let wrapperView = UIView(frame: CGRect(x: 0, y: 0, width: buildLabel.frame.width, height: buildLabel.frame.height + 10.0))
		wrapperView.translatesAutoresizingMaskIntoConstraints = false
		wrapperView.addSubview(buildLabel)
		tableView.tableFooterView = wrapperView

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

	// Hidden sections: 1 = Accounts, 2 = Feeds, 3 = Timeline, 4 = Articles
	private let hiddenSections: Set<Int> = [1, 2, 3, 4]

	/// Returns whether sub-options should be hidden for a section
	private func shouldHideSubOptions(for section: Int) -> Bool {
		switch section {
		case 0:
			return !notificationsAuthorized
		case 7:
			return !AppDefaults.shared.isObsidianSyncEnabled
		default:
			return false
		}
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
			// Section 0: row 0 = Open System Settings, rows 1-4 = notify toggles
			return shouldHideSubOptions(for: 0) ? 1 : super.tableView(tableView, numberOfRowsInSection: section)
		case 1:
			return AccountManager.shared.accounts.count + 1
		case 4:
			return traitCollection.userInterfaceIdiom == .phone ? 5 : 4
		case 7:
			// Section 7: row 0 = sync toggle, rows 1-5 = vault/subfolder/preview/remove
			return shouldHideSubOptions(for: 7) ? 1 : super.tableView(tableView, numberOfRowsInSection: section)
		case ttsSection:
			return super.tableView(tableView, numberOfRowsInSection: section) + 1
		case displaySection:
			// Adds Unread First, Gray Read Articles, and Show Category Icons rows
			return super.tableView(tableView, numberOfRowsInSection: section) + 3
		case debugSection:
			// Clean Temporary Files, Debug Dialog
			return 2
		case aboutSection:
			// About Second Stream, Credits remaining, Enable Face ID, Disconnect Account, Delete Account
			return 5
		default:
			return super.tableView(tableView, numberOfRowsInSection: section)
		}
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if hiddenSections.contains(section) { return nil }
		if section == debugSection { return NSLocalizedString("Debug", comment: "Debug section header") }
		if section == aboutSection { return NSLocalizedString("About", comment: "About section header") }
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
		case displaySection where indexPath.row == timelineReadStylingRow:
			cell = makeTimelineReadStylingCell(tableView)
		case displaySection where indexPath.row == sectionHeaderIconsRow:
			cell = makeSectionHeaderIconsCell(tableView)
		case displaySection where indexPath.row == timelineUnreadFirstRow:
			cell = makeTimelineUnreadFirstCell(tableView)
		case ttsSection where indexPath.row == ttsEnabledRow:
			cell = makeTTSEnabledCell(tableView)
		case debugSection:
			switch indexPath.row {
			case debugCleanTempRow:
				cell = UITableViewCell(style: .default, reuseIdentifier: "CleanTempFilesCell")
				cell.textLabel?.text = NSLocalizedString("Clean Temporary Files", comment: "Clean Temporary Files")
			case debugDialogRow:
				cell = makeDebugDialogCell(tableView)
			default:
				cell = super.tableView(tableView, cellForRowAt: indexPath)
			}
		case aboutSection:
			switch indexPath.row {
			case aboutAppRow:
				cell = UITableViewCell(style: .default, reuseIdentifier: "AboutAppCell")
				cell.textLabel?.text = NSLocalizedString("About Second Stream", comment: "About Second Stream")
				cell.accessoryType = .disclosureIndicator
			case aboutCreditsRow:
				cell = UITableViewCell(style: .value1, reuseIdentifier: "CreditsCell")
				cell.textLabel?.text = NSLocalizedString("Credits remaining", comment: "Credits remaining")
				cell.selectionStyle = .none
				if let credits = FeedStatsManager.shared.cachedCredits {
					cell.detailTextLabel?.text = "\(credits)"
				} else {
					cell.detailTextLabel?.text = "—"
				}
			case aboutFaceIDRow:
				cell = makeFaceIDCell(tableView)
			case aboutDisconnectRow:
				cell = UITableViewCell(style: .default, reuseIdentifier: "DisconnectAccountCell")
				cell.textLabel?.text = NSLocalizedString("Disconnect Account", comment: "Disconnect Account")
				cell.textLabel?.textColor = .systemRed
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
			UIApplication.shared.open(URL(string: "\(UIApplication.openSettingsURLString)")!)
			tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
		case 1:
			let sortedAccounts = AccountManager.shared.sortedAccounts
			if indexPath.row == sortedAccounts.count {
				let controller = UIStoryboard.settings.instantiateController(ofType: AddAccountViewController.self)
				self.navigationController?.pushViewController(controller, animated: true)
			} else {
				let controller = UIStoryboard.inspector.instantiateController(ofType: AccountInspectorViewController.self)
				controller.account = sortedAccounts[indexPath.row]
				self.navigationController?.pushViewController(controller, animated: true)
			}
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
			if indexPath.row == 0 {
				let colorPalette = UIStoryboard.settings.instantiateController(ofType: ColorPaletteTableViewController.self)
				self.navigationController?.pushViewController(colorPalette, animated: true)
			} else {
				tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
			}
		case 6:
			// Text-to-Speech section
			if indexPath.row == ttsVoiceRow {
				presentTTSVoicePicker()
			}
			tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
		case 7:
			// Obsidian section
			switch indexPath.row {
			case 1:
				// Only allow vault picker when sync is enabled
				if obsidianSyncSwitch.isOn {
					presentObsidianVaultPicker()
				}
			default:
				break
			}
			tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
		case debugSection:
			switch indexPath.row {
			case debugCleanTempRow:
				cleanTemporaryFiles()
			case debugDialogRow:
				break // handled by switch
			default:
				break
			}
			tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
		case aboutSection:
			switch indexPath.row {
			case aboutAppRow:
				let hosting = UIHostingController(rootView: AboutWPodView())
				self.navigationController?.pushViewController(hosting, animated: true)
			case aboutDisconnectRow:
				confirmDisconnect()
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

	@objc func switchDebugDialog(_ sender: UISwitch) {
		AppDefaults.shared.showHomepageResolutionDebugDialog = sender.isOn
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

	@objc func contentSizeCategoryDidChange() {
		tableView.reloadData()
	}

	@objc func accountsDidChange() {
		tableView.reloadData()
	}

	@objc func displayNameDidChange() {
		tableView.reloadData()
	}

	@objc func creditsDidUpdate() {
		let creditsIndexPath = IndexPath(row: aboutCreditsRow, section: aboutSection)
		tableView.reloadRows(at: [creditsIndexPath], with: .none)
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
			title: NSLocalizedString("Clean Temporary Files", comment: "Clean Temporary Files"),
			message: NSLocalizedString("This will remove cached icons/images and cached source lists. They will be re-downloaded when needed.", comment: "Clean temp files message"),
			preferredStyle: .alert
		)

			alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel))
			alert.addAction(UIAlertAction(title: NSLocalizedString("Clean", comment: "Clean"), style: .destructive) { _ in
				SourceImageCache.shared.clearCache()
				FaviconDownloader.shared.resetCache()
				IconImageCache.shared.emptyCache()
				Task {
					await SourceFileFetcher.clearLastModifiedCache()
				}
				PodcastSourcesManager.shared.podcastSources = []
				PodcastSourcesManager.shared.podcastLibrarySources = []
				YoutubeSourcesManager.shared.youtubeSources = []
				YoutubeSourcesManager.shared.youtubeLibrarySources = []
				NewsSourcesManager.shared.newsSources = []
				RSSSourcesManager.shared.rssSources = []
				SourcesRefreshManager.shared.forceRefresh()
			})

		present(alert, animated: true)
	}

	func updateNotificationSwitches() {
		UNUserNotificationCenter.current().getNotificationSettings { settings in
			let authorized = settings.authorizationStatus == .authorized
			DispatchQueue.main.async {
				let previouslyAuthorized = self.notificationsAuthorized
				self.notificationsAuthorized = authorized

				// Initialize defaults on first check if notifications are authorized
				if authorized {
					let store = AppDefaults.store
					if store.object(forKey: AppDefaults.Key.notifyFeeds) == nil {
						AppDefaults.shared.notifyFeeds = true
					}
					if store.object(forKey: AppDefaults.Key.notifyPodcasts) == nil {
						AppDefaults.shared.notifyPodcasts = true
					}
					if store.object(forKey: AppDefaults.Key.notifyYouTube) == nil {
						AppDefaults.shared.notifyYouTube = true
					}
					if store.object(forKey: AppDefaults.Key.notifyWeeklyNews) == nil {
						AppDefaults.shared.notifyWeeklyNews = true
					}
				}

				let switches = [
					self.notifyPodcastsSwitch,
					self.notifyYouTubeSwitch,
					self.notifyWeeklyNewsSwitch,
					self.notifyFeedsSwitch
				]

				let values = [
					AppDefaults.shared.notifyPodcasts,
					AppDefaults.shared.notifyYouTube,
					AppDefaults.shared.notifyWeeklyNews,
					AppDefaults.shared.notifyFeeds
				]

				for (toggle, value) in zip(switches, values) {
					toggle?.isOn = authorized && value
					toggle?.isEnabled = authorized
					toggle?.alpha = authorized ? 1.0 : 0.5
				}

				if previouslyAuthorized != authorized {
					self.tableView.reloadData()
				}
			}
		}
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
