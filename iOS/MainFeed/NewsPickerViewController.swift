//
//  NewsPickerViewController.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-27.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit

@MainActor protocol NewsPickerDelegate: AnyObject {
	func newsPickerDidSelectNewsURL(_ picker: NewsPickerViewController)
	func newsPickerDidCancel(_ picker: NewsPickerViewController)
}

final class NewsPickerViewController: UITableViewController {

	weak var delegate: NewsPickerDelegate?

	override func viewDidLoad() {
		super.viewDidLoad()

		title = NSLocalizedString("Add News Source", comment: "Add News Source")

		navigationItem.leftBarButtonItem = UIBarButtonItem(
			barButtonSystemItem: .cancel,
			target: self,
			action: #selector(cancelTapped)
		)

		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "NewsCell")
	}

	@objc private func cancelTapped() {
		delegate?.newsPickerDidCancel(self)
	}

	// MARK: - Table View Data Source

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "NewsCell", for: indexPath)
		cell.textLabel?.text = NSLocalizedString("Enter News RSS URL...", comment: "Enter News RSS URL...")
		cell.textLabel?.textColor = Assets.Colors.primaryAccent
		cell.accessoryType = .disclosureIndicator
		return cell
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		return NSLocalizedString("Enter a news website RSS feed URL to subscribe.", comment: "News picker footer")
	}

	// MARK: - Table View Delegate

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		delegate?.newsPickerDidSelectNewsURL(self)
	}
}
