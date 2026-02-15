//
//  FeedInspectorViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 11/6/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import SafariServices
import RSCore
import Account

final class FeedInspectorViewController: UITableViewController {

	static let preferredContentSizeForFormSheetDisplay = CGSize(width: 460.0, height: 500.0)

	var feed: Feed!

	@IBOutlet var nameTextField: UITextField!
	@IBOutlet var notifyAboutNewArticlesSwitch: UISwitch!
	@IBOutlet var alwaysShowReaderViewSwitch: UISwitch!
	@IBOutlet var homePageLabel: InteractiveLabel!
	@IBOutlet var feedURLLabel: InteractiveLabel!
	@IBOutlet var obsidianSubfolderTextField: UITextField!

	private var headerView: InspectorIconHeaderView?
	private var iconImage: IconImage? {
		return IconImageCache.shared.imageForFeed(feed)
	}

	// Storyboard sections: 0=Name/Notify/Reader, 1=HomePage, 2=URL, 3=Obsidian
	// We always hide sections 0 (settings) and 2 (URL), plus section 1 if homePageURL is nil
	private let homePageStoryboardSection = 1

	private var shouldHideHomePageSection: Bool {
		return feed.homePageURL == nil
	}

	override func viewDidLoad() {
		navigationItem.title = feed.nameForDisplay

		// Show the feed icon as a table header view above all sections
		let iconHeader = InspectorIconHeaderView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: ImageHeaderView.rowHeight))
		iconHeader.iconView.iconImage = iconImage
		tableView.tableHeaderView = iconHeader
		headerView = iconHeader

		homePageLabel.text = feed.homePageURL

		obsidianSubfolderTextField.text = feed.obsidianSubfolder ?? ""
		let categoryPrefix = ObsidianFileManager.getDefaultSubfolderPrefix(for: feed)
		obsidianSubfolderTextField.placeholder = "\(categoryPrefix)/\(feed.nameForDisplay)"

		NotificationCenter.default.addObserver(self, selector: #selector(feedIconDidBecomeAvailable(_:)), name: .feedIconDidBecomeAvailable, object: nil)
	}

	override func viewDidDisappear(_ animated: Bool) {
		// Save Obsidian subfolder if changed
		let subfolder = obsidianSubfolderTextField.text?.isEmpty == false ? obsidianSubfolderTextField.text : nil
		if subfolder != feed.obsidianSubfolder {
			feed.obsidianSubfolder = subfolder
		}
	}

	// MARK: Notifications
	@objc func feedIconDidBecomeAvailable(_ notification: Notification) {
		headerView?.iconView.iconImage = iconImage
	}

	@IBAction func done(_ sender: Any) {
		dismiss(animated: true)
	}

	/// Maps a displayed section index to the storyboard section index,
	/// skipping hidden sections (0=settings, 2=URL, and optionally 1=homePage).
	private func shift(_ indexPath: IndexPath) -> IndexPath {
		return IndexPath(row: indexPath.row, section: shift(indexPath.section))
	}

	private func shift(_ section: Int) -> Int {
		// Hidden storyboard sections: always 0 and 2, optionally 1
		// If homePage is visible: displayed 0→storyboard 1, displayed 1→storyboard 3
		// If homePage is hidden: displayed 0→storyboard 3
		if shouldHideHomePageSection {
			// Only Obsidian is shown: displayed 0 → storyboard 3
			return section + 3
		} else {
			// HomePage + Obsidian: displayed 0→storyboard 1, displayed 1→storyboard 3
			if section == 0 {
				return 1
			} else {
				return 3
			}
		}
	}
}

// MARK: Table View

extension FeedInspectorViewController {

	override func numberOfSections(in tableView: UITableView) -> Int {
		// HomePage + Obsidian, or just Obsidian
		return shouldHideHomePageSection ? 1 : 2
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return super.tableView(tableView, numberOfRowsInSection: shift(section))
	}

	override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		return super.tableView(tableView, heightForHeaderInSection: shift(section))
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		return super.tableView(tableView, cellForRowAt: shift(indexPath))
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		super.tableView(tableView, titleForHeaderInSection: shift(section))
	}

	override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		return super.tableView(tableView, viewForHeaderInSection: shift(section))
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let storyboardSection = shift(indexPath.section)
		if storyboardSection == homePageStoryboardSection,
			let homePageUrlString = feed.homePageURL,
			let homePageUrl = URL(string: homePageUrlString) {

			let safari = SFSafariViewController(url: homePageUrl)
			safari.modalPresentationStyle = .pageSheet
			present(safari, animated: true) {
				tableView.deselectRow(at: indexPath, animated: true)
			}
		}
	}

}

// MARK: UITextFieldDelegate

extension FeedInspectorViewController: UITextFieldDelegate {

	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}

}
