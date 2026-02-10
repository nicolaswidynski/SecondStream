//
//  NewsPickerViewController.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-27.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit

@MainActor protocol NewsPickerDelegate: AnyObject {
	func newsPickerDidSelectTopicName(_ picker: NewsPickerViewController)
	func newsPickerDidSelectNewsURL(_ picker: NewsPickerViewController)
	func newsPickerDidCancel(_ picker: NewsPickerViewController)
	func newsPicker(_ picker: NewsPickerViewController, didSelectSource source: NewsSource)
}

final class NewsPickerViewController: UITableViewController {

	weak var delegate: NewsPickerDelegate?

	private var sources: [NewsSource] = []

	private enum Section: Int, CaseIterable {
		case addOptions
		case sources
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		title = NSLocalizedString("Add News Topic", comment: "Add News Topic")

		navigationItem.leftBarButtonItem = UIBarButtonItem(
			barButtonSystemItem: .cancel,
			target: self,
			action: #selector(cancelTapped)
		)

		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "NewsCell")
		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SourceCell")

		// Load sources from manager
		sources = NewsSourcesManager.shared.newsSources
	}

	@objc private func cancelTapped() {
		delegate?.newsPickerDidCancel(self)
	}

	// MARK: - Table View Data Source

	override func numberOfSections(in tableView: UITableView) -> Int {
		return Section.allCases.count
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		guard let sectionType = Section(rawValue: section) else {
			return 0
		}

		switch sectionType {
		case .addOptions:
			return 2 // Add by topic name, Add by URL
		case .sources:
			return sources.count
		}
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		guard let sectionType = Section(rawValue: indexPath.section) else {
			return UITableViewCell()
		}

		switch sectionType {
		case .addOptions:
			let cell = tableView.dequeueReusableCell(withIdentifier: "NewsCell", for: indexPath)
			if indexPath.row == 0 {
				cell.textLabel?.text = NSLocalizedString("Add by Topic Name...", comment: "Add by Topic Name...")
			} else {
				cell.textLabel?.text = NSLocalizedString("Add by RSS URL...", comment: "Add by RSS URL...")
			}
			cell.textLabel?.textColor = Assets.Colors.primaryAccent
			cell.accessoryType = .disclosureIndicator
			return cell

		case .sources:
			let cell = tableView.dequeueReusableCell(withIdentifier: "SourceCell", for: indexPath)
			let source = sources[indexPath.row]
			cell.textLabel?.text = source.name
			cell.textLabel?.textColor = .label
			cell.accessoryType = .none
			return cell
		}
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		guard let sectionType = Section(rawValue: section) else {
			return nil
		}

		switch sectionType {
		case .addOptions:
			return nil
		case .sources:
			return sources.isEmpty ? nil : NSLocalizedString("Your News Topics", comment: "Your News Topics")
		}
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		guard let sectionType = Section(rawValue: section) else {
			return nil
		}

		switch sectionType {
		case .addOptions:
			return NSLocalizedString("Enter a topic name or RSS URL to add a news source.", comment: "News picker footer")
		case .sources:
			return nil
		}
	}

	// MARK: - Table View Delegate

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)

		guard let sectionType = Section(rawValue: indexPath.section) else {
			return
		}

		switch sectionType {
		case .addOptions:
			if indexPath.row == 0 {
				delegate?.newsPickerDidSelectTopicName(self)
			} else {
				delegate?.newsPickerDidSelectNewsURL(self)
			}

		case .sources:
			let source = sources[indexPath.row]
			delegate?.newsPicker(self, didSelectSource: source)
		}
	}
}
