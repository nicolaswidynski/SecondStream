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

	private var sources: [NewsSource] = []

	override func viewDidLoad() {
		super.viewDidLoad()

		title = NSLocalizedString("Add Topic", comment: "Add Topic")

		navigationItem.leftBarButtonItem = UIBarButtonItem(
			barButtonSystemItem: .cancel,
			target: self,
			action: #selector(cancelTapped)
		)

		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TopicCell")

		// Load sources from manager
		sources = NewsSourcesManager.shared.newsSources
	}

	@objc private func cancelTapped() {
		delegate?.newsPickerDidCancel(self)
	}

	// MARK: - Table View Data Source

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return sources.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "TopicCell", for: indexPath)
		let source = sources[indexPath.row]
		cell.textLabel?.text = source.name
		cell.textLabel?.textColor = .label
		cell.accessoryType = .none
		return cell
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		if sources.isEmpty {
			return NSLocalizedString("No topics available. Topics are managed externally.", comment: "Empty topics footer")
		}
		return nil
	}

	// MARK: - Table View Delegate

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		let source = sources[indexPath.row]
		delegate?.newsPicker(self, didSelectSource: source)
	}
}
