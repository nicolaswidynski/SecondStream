//
//  YoutubePickerViewController.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-27.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit

@MainActor protocol YoutubePickerDelegate: AnyObject {
	func youtubePickerDidSelectChannelURL(_ picker: YoutubePickerViewController)
	func youtubePickerDidCancel(_ picker: YoutubePickerViewController)
}

final class YoutubePickerViewController: UITableViewController {

	weak var delegate: YoutubePickerDelegate?

	override func viewDidLoad() {
		super.viewDidLoad()

		title = NSLocalizedString("Add YouTube Channel", comment: "Add YouTube Channel")

		navigationItem.leftBarButtonItem = UIBarButtonItem(
			barButtonSystemItem: .cancel,
			target: self,
			action: #selector(cancelTapped)
		)

		tableView.register(UITableViewCell.self, forCellReuseIdentifier: "YouTubeCell")
	}

	@objc private func cancelTapped() {
		delegate?.youtubePickerDidCancel(self)
	}

	// MARK: - Table View Data Source

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "YouTubeCell", for: indexPath)
		cell.textLabel?.text = NSLocalizedString("Enter Channel URL...", comment: "Enter Channel URL...")
		cell.textLabel?.textColor = Assets.Colors.primaryAccent
		cell.accessoryType = .disclosureIndicator
		return cell
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		return NSLocalizedString("Enter a YouTube channel URL to subscribe to its RSS feed.", comment: "YouTube picker footer")
	}

	// MARK: - Table View Delegate

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		delegate?.youtubePickerDidSelectChannelURL(self)
	}
}
