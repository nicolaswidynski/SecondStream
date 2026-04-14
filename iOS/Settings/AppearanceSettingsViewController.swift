//
//  AppearanceSettingsViewController.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-14.
//  Copyright © 2026 STDN. All rights reserved.
//

import UIKit

final class AppearanceSettingsViewController: UITableViewController {

	private enum Row: CaseIterable {
		case appearance
		case timelineUnreadFirst
		case timelineReadStyling
		case sectionHeaderIcons
		case collapsibleSections
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		title = NSLocalizedString("Appearance", comment: "Appearance")
		tableView.backgroundColor = Assets.Colors.background
		UISwitch.appearance(whenContainedInInstancesOf: [AppearanceSettingsViewController.self]).onTintColor = Assets.Colors.primaryAccent
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		tableView.reloadData()
	}

	// MARK: - Table view

	override func numberOfSections(in tableView: UITableView) -> Int { 1 }

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		Row.allCases.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		switch Row.allCases[indexPath.row] {
		case .appearance:
			return makeAppearanceSegmentedCell()
		case .timelineUnreadFirst:
			return makeToggleCell(
				title: NSLocalizedString("Unread First", comment: "Timeline ordering toggle"),
				isOn: AppDefaults.shared.timelineUnreadFirst,
				action: #selector(switchTimelineUnreadFirst(_:))
			)
		case .timelineReadStyling:
			return makeToggleCell(
				title: NSLocalizedString("Gray Read Articles", comment: "Timeline styling toggle"),
				isOn: AppDefaults.shared.timelineDimReadArticles,
				action: #selector(switchTimelineReadStyling(_:))
			)
		case .sectionHeaderIcons:
			return makeToggleCell(
				title: NSLocalizedString("Show Category Icons", comment: "Section header icons toggle"),
				isOn: AppDefaults.shared.showSectionHeaderIcons,
				action: #selector(switchSectionHeaderIcons(_:))
			)
		case .collapsibleSections:
			return makeToggleCell(
				title: NSLocalizedString("Collapsible Article Sections", comment: "Article sections collapsible toggle"),
				isOn: AppDefaults.shared.collapsibleArticleSectionsEnabled,
				action: #selector(switchCollapsibleSections(_:))
			)
		}
	}

	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		cell.backgroundColor = Assets.Colors.foreground
	}

	// MARK: - Helpers

	private func makeAppearanceSegmentedCell() -> UITableViewCell {
		let cell = UITableViewCell(style: .default, reuseIdentifier: "AppearanceSegmentedCell")
		cell.textLabel?.text = NSLocalizedString("Appearance", comment: "Appearance")
		cell.textLabel?.adjustsFontForContentSizeCategory = true
		cell.selectionStyle = .none
		let items = UserInterfaceColorPalette.allCases.map { $0.description }
		let control = UISegmentedControl(items: items)
		control.selectedSegmentIndex = AppDefaults.userInterfaceColorPalette.rawValue
		control.addTarget(self, action: #selector(appearanceSegmentedChanged(_:)), for: .valueChanged)
		cell.accessoryView = control
		return cell
	}

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

	// MARK: - Actions

	@objc private func appearanceSegmentedChanged(_ sender: UISegmentedControl) {
		AppDefaults.userInterfaceColorPalette = UserInterfaceColorPalette(rawValue: sender.selectedSegmentIndex) ?? .automatic
	}

	@objc private func switchTimelineUnreadFirst(_ sender: UISwitch) {
		AppDefaults.shared.timelineUnreadFirst = sender.isOn
	}

	@objc private func switchTimelineReadStyling(_ sender: UISwitch) {
		AppDefaults.shared.timelineDimReadArticles = sender.isOn
	}

	@objc private func switchSectionHeaderIcons(_ sender: UISwitch) {
		AppDefaults.shared.showSectionHeaderIcons = sender.isOn
	}

	@objc private func switchCollapsibleSections(_ sender: UISwitch) {
		AppDefaults.shared.collapsibleArticleSectionsEnabled = sender.isOn
	}
}
