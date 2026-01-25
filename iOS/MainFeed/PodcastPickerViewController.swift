//
//  PodcastPickerViewController.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-23.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit

@MainActor protocol PodcastPickerDelegate: AnyObject {
	func podcastPickerDidSelectPodcastName(_ picker: PodcastPickerViewController)
	func podcastPickerDidSelectCustomURL(_ picker: PodcastPickerViewController)
	func podcastPicker(_ picker: PodcastPickerViewController, didSelectPodcast source: PodcastSource)
	func podcastPickerDidCancel(_ picker: PodcastPickerViewController)
}

final class PodcastPickerViewController: UITableViewController {

	weak var delegate: PodcastPickerDelegate?

	private var sections: [(letter: String, sources: [PodcastSource])] = []
	private var sectionIndexTitles: [String] = []

	private let customURLSection = 0

	override func viewDidLoad() {
		super.viewDidLoad()

		title = NSLocalizedString("Add Podcast", comment: "Add Podcast")

		navigationItem.leftBarButtonItem = UIBarButtonItem(
			barButtonSystemItem: .cancel,
			target: self,
			action: #selector(cancelTapped)
		)

		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PodcastCell")
		tableView.sectionIndexColor = Assets.Colors.primaryAccent

		loadPodcastSources()
	}

	private func loadPodcastSources() {
		let sources = PodcastSourcesManager.shared.podcastSources.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

		// Group by first letter
		var grouped: [String: [PodcastSource]] = [:]
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
		delegate?.podcastPickerDidCancel(self)
	}

	// MARK: - Table View Data Source

	override func numberOfSections(in tableView: UITableView) -> Int {
		// +1 for the "Enter RSS URL" section at the top
		return sections.count + 1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if section == customURLSection {
			return 2  // "Enter Podcast Name..." and "Enter RSS URL..."
		}
		return sections[section - 1].sources.count
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if section == customURLSection {
			return nil
		}
		return sections[section - 1].letter
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "PodcastCell", for: indexPath)

		if indexPath.section == customURLSection {
			if indexPath.row == 0 {
				cell.textLabel?.text = NSLocalizedString("Enter Podcast Name...", comment: "Enter Podcast Name...")
			} else {
				cell.textLabel?.text = NSLocalizedString("Enter RSS URL...", comment: "Enter RSS URL...")
			}
			cell.textLabel?.textColor = Assets.Colors.primaryAccent
			cell.accessoryType = .disclosureIndicator
		} else {
			let source = sections[indexPath.section - 1].sources[indexPath.row]
			cell.textLabel?.text = source.name
			cell.textLabel?.textColor = .label
			cell.accessoryType = .none
		}

		return cell
	}

	override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
		guard !sectionIndexTitles.isEmpty else {
			return nil
		}
		return sectionIndexTitles
	}

	override func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
		// +1 to account for the custom URL section at the top
		return index + 1
	}

	// MARK: - Table View Delegate

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)

		if indexPath.section == customURLSection {
			if indexPath.row == 0 {
				delegate?.podcastPickerDidSelectPodcastName(self)
			} else {
				delegate?.podcastPickerDidSelectCustomURL(self)
			}
		} else {
			let source = sections[indexPath.section - 1].sources[indexPath.row]
			delegate?.podcastPicker(self, didSelectPodcast: source)
		}
	}
}
