//
//  NewsPickerViewController.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-27.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit

@MainActor protocol NewsPickerDelegate: AnyObject {
	func newsPickerDidCancel(_ picker: NewsPickerViewController)
	func newsPicker(_ picker: NewsPickerViewController, didSelectSource source: NewsSource)
}

final class NewsPickerViewController: UITableViewController {

	weak var delegate: NewsPickerDelegate?

	private var sections: [(letter: String, sources: [NewsSource])] = []
	private var sectionIndexTitles: [String] = []

	override func viewDidLoad() {
		super.viewDidLoad()

		title = NSLocalizedString("Add Topic", comment: "Add Topic")

		navigationItem.leftBarButtonItem = UIBarButtonItem(
			barButtonSystemItem: .cancel,
			target: self,
			action: #selector(cancelTapped)
		)

		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TopicCell")
		tableView.sectionIndexColor = Assets.Colors.primaryAccent

		loadSources()
	}

	private func loadSources() {
		let sources = NewsSourcesManager.shared.newsSources.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

		// Group by first letter
		var grouped: [String: [NewsSource]] = [:]
		for source in sources {
			let firstChar = source.name.first.map { String($0).uppercased() } ?? "#"
			let letter = firstChar.first?.isLetter == true ? firstChar : "#"
			grouped[letter, default: []].append(source)
		}

		// Sort sections alphabetically
		sections = grouped.map { (letter: $0.key, sources: $0.value) }
			.sorted { $0.letter < $1.letter }

		// Build section index titles
		sectionIndexTitles = sections.map { $0.letter }

		tableView.reloadData()
	}

	@objc private func cancelTapped() {
		delegate?.newsPickerDidCancel(self)
	}

	// MARK: - Table View Data Source

	override func numberOfSections(in tableView: UITableView) -> Int {
		return sections.count
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return sections[section].sources.count
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return sections[section].letter
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "TopicCell", for: indexPath)
		let source = sections[indexPath.section].sources[indexPath.row]
		cell.textLabel?.text = source.name
		cell.textLabel?.textColor = .label
		cell.accessoryType = .none
		return cell
	}

	override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
		guard !sectionIndexTitles.isEmpty else {
			return nil
		}
		return sectionIndexTitles
	}

	override func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
		return index
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		// Show footer only if there are no topics at all (last section check)
		if sections.isEmpty {
			return NSLocalizedString("No topics available. Topics are managed externally.", comment: "Empty topics footer")
		}
		return nil
	}

	// MARK: - Table View Delegate

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		let source = sections[indexPath.section].sources[indexPath.row]
		delegate?.newsPicker(self, didSelectSource: source)
	}
}
