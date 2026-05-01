//
//  ObsidianSettingsViewController.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-14.
//  Copyright © 2026 STDN. All rights reserved.
//

import UIKit
import UniformTypeIdentifiers

final class ObsidianSettingsViewController: UITableViewController, UIDocumentPickerDelegate {

	// MARK: - Row model

	private enum Row {
		case sync
		case vault
		case subfolderFeedType
		case subfolderFeedName
		case preview
		case removeOnUnbookmark
	}

	private var rows: [Row] = []

	// Weak references to live switch/label views so we can update them after picks.
	private weak var syncSwitch: UISwitch?
	private weak var vaultDetailLabel: UILabel?
	private weak var previewLabel: UILabel?

	// MARK: - Lifecycle

	override func viewDidLoad() {
		super.viewDidLoad()
		title = NSLocalizedString("Obsidian", comment: "Obsidian")
		tableView.backgroundColor = Assets.Colors.SettingsContentBgColor
		tableView.separatorStyle = .none
		UISwitch.appearance(whenContainedInInstancesOf: [ObsidianSettingsViewController.self]).onTintColor = Assets.Colors.primaryAccent
		rebuildRows()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		applySettingsNavBarAppearance()
		tableView.reloadData()
	}

	private func rebuildRows() {
		rows = AppDefaults.shared.isObsidianSyncEnabled
			? [.sync, .vault, .subfolderFeedType, .subfolderFeedName, .preview, .removeOnUnbookmark]
			: [.sync]
	}

	// MARK: - Table view

	override func numberOfSections(in tableView: UITableView) -> Int { 1 }

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		rows.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		switch rows[indexPath.row] {
		case .sync:
			let cell = makeToggleCell(
				title: NSLocalizedString("Sync Bookmark Articles", comment: "Obsidian sync toggle"),
				isOn: AppDefaults.shared.isObsidianSyncEnabled,
				action: #selector(switchSync(_:))
			)
			syncSwitch = cell.accessoryView as? UISwitch
			return cell

		case .vault:
			let cell = UITableViewCell(style: .value1, reuseIdentifier: "vault")
			cell.textLabel?.text = NSLocalizedString("Obsidian Vault", comment: "Obsidian vault")
			cell.textLabel?.adjustsFontForContentSizeCategory = true
			let displayPath = ObsidianFileManager.vaultDisplayPath()
			let notSet = NSLocalizedString("Not Set", comment: "Obsidian vault not configured")
			cell.detailTextLabel?.text = displayPath ?? notSet
			cell.accessoryType = .disclosureIndicator
			cell.isUserInteractionEnabled = AppDefaults.shared.isObsidianSyncEnabled
			cell.textLabel?.isEnabled = AppDefaults.shared.isObsidianSyncEnabled
			cell.detailTextLabel?.isEnabled = AppDefaults.shared.isObsidianSyncEnabled
			vaultDetailLabel = cell.detailTextLabel
			cell.backgroundColor = Assets.Colors.SettingsContentTableColor
			return cell

		case .subfolderFeedType:
			return makeToggleCell(
				title: NSLocalizedString("Subfolder: FeedType/", comment: "Obsidian subfolder feed type"),
				isOn: AppDefaults.shared.obsidianSubfolderFeedType,
				action: #selector(switchSubfolderFeedType(_:))
			)

		case .subfolderFeedName:
			return makeToggleCell(
				title: NSLocalizedString("Subfolder: FeedName/", comment: "Obsidian subfolder feed name"),
				isOn: AppDefaults.shared.obsidianSubfolderFeedName,
				action: #selector(switchSubfolderFeedName(_:))
			)

		case .preview:
			let cell = UITableViewCell(style: .default, reuseIdentifier: "preview")
			cell.textLabel?.text = ObsidianFileManager.subfolderPreviewWithVault()
			cell.textLabel?.textColor = .secondaryLabel
			cell.textLabel?.font = .preferredFont(forTextStyle: .subheadline)
			cell.textLabel?.adjustsFontForContentSizeCategory = true
			cell.selectionStyle = .none
			cell.backgroundColor = Assets.Colors.SettingsContentTableColor
			previewLabel = cell.textLabel
			return cell

		case .removeOnUnbookmark:	
			return makeToggleCell(
				title: NSLocalizedString("Remove Unbookmarked", comment: "Obsidian remove on unbookmark"),
				isOn: AppDefaults.shared.obsidianRemoveOnUnbookmark,
				action: #selector(switchRemoveOnUnbookmark(_:))
			)
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		if rows[indexPath.row] == .vault, AppDefaults.shared.isObsidianSyncEnabled {
			presentVaultPicker()
		}
	}

	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		cell.backgroundColor = Assets.Colors.SettingsContentTableColor
	}

	// MARK: - Switch actions

	@objc private func switchSync(_ sender: UISwitch) {
		let wasExpanded = rows.count > 1
		AppDefaults.shared.isObsidianSyncEnabled = sender.isOn
		let nowExpanded = AppDefaults.shared.isObsidianSyncEnabled
		let oldCount = rows.count
		rebuildRows()
		if nowExpanded && !wasExpanded {
			let inserted = (1..<rows.count).map { IndexPath(row: $0, section: 0) }
			tableView.insertRows(at: inserted, with: .fade)
		} else if !nowExpanded && wasExpanded {
			let deleted = (1..<oldCount).map { IndexPath(row: $0, section: 0) }
			tableView.deleteRows(at: deleted, with: .fade)
		}
	}

	@objc private func switchSubfolderFeedType(_ sender: UISwitch) {
		AppDefaults.shared.obsidianSubfolderFeedType = sender.isOn
		updatePreview()
	}

	@objc private func switchSubfolderFeedName(_ sender: UISwitch) {
		AppDefaults.shared.obsidianSubfolderFeedName = sender.isOn
		updatePreview()
	}

	@objc private func switchRemoveOnUnbookmark(_ sender: UISwitch) {
		AppDefaults.shared.obsidianRemoveOnUnbookmark = sender.isOn
	}

	// MARK: - Vault picker

	private func presentVaultPicker() {
		let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
		picker.delegate = self
		picker.allowsMultipleSelection = false
		present(picker, animated: true)
	}

	func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
		guard let url = urls.first else { return }
		do {
			try ObsidianFileManager.storeVaultBookmark(for: url)
			vaultDetailLabel?.text = ObsidianFileManager.vaultDisplayPath() ?? NSLocalizedString("Not Set", comment: "Obsidian vault not configured")
		} catch {
			let alert = UIAlertController(
				title: NSLocalizedString("Error", comment: "Error"),
				message: NSLocalizedString("Unable to access the selected folder. Please try again.", comment: "Obsidian vault access error"),
				preferredStyle: .alert
			)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default))
			present(alert, animated: true)
		}
	}

	// MARK: - Helpers

	private func makeToggleCell(title: String, isOn: Bool, action: Selector) -> UITableViewCell {
		let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
		cell.textLabel?.text = title
		cell.textLabel?.adjustsFontForContentSizeCategory = true
		cell.selectionStyle = .none
		let toggle = UISwitch()
		toggle.isOn = isOn
		toggle.addTarget(self, action: action, for: .valueChanged)
		cell.accessoryView = toggle
		return cell
	}

	private func updatePreview() {
		previewLabel?.text = ObsidianFileManager.subfolderPreviewWithVault()
	}
}
