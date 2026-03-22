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
	// We always hide sections 0 (settings), 2 (URL), and 3 (Obsidian)
	// Only show section 1 (HomePage) if homePageURL exists
	private let homePageStoryboardSection = 1

	private var shouldShowHomePageSection: Bool {
		return feed.homePageURL != nil
	}

	override func viewDidLoad() {
		navigationItem.title = feed.nameForDisplay

		let iconHeader = InspectorIconHeaderView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: ImageHeaderView.rowHeight))
		iconHeader.iconView.iconImage = iconImage
		tableView.tableHeaderView = iconHeader
		headerView = iconHeader

		homePageLabel.text = feed.homePageURL

		NotificationCenter.default.addObserver(self, selector: #selector(feedIconDidBecomeAvailable(_:)), name: .feedIconDidBecomeAvailable, object: nil)
	}

	// MARK: Notifications
	@objc func feedIconDidBecomeAvailable(_ notification: Notification) {
		headerView?.iconView.iconImage = iconImage
	}

	@IBAction func done(_ sender: Any) {
		dismiss(animated: true)
	}
}

// MARK: Table View

extension FeedInspectorViewController {

	override func numberOfSections(in tableView: UITableView) -> Int {
		return shouldShowHomePageSection ? 1 : 0
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return super.tableView(tableView, numberOfRowsInSection: homePageStoryboardSection)
	}

	override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		return super.tableView(tableView, heightForHeaderInSection: homePageStoryboardSection)
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		return super.tableView(tableView, cellForRowAt: IndexPath(row: indexPath.row, section: homePageStoryboardSection))
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		super.tableView(tableView, titleForHeaderInSection: homePageStoryboardSection)
	}

	override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		return super.tableView(tableView, viewForHeaderInSection: homePageStoryboardSection)
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if let homePageUrlString = feed.homePageURL,
		   let homePageUrl = URL(string: homePageUrlString) {

			let safari = SFSafariViewController(url: homePageUrl)
			safari.modalPresentationStyle = .pageSheet
			present(safari, animated: true) {
				tableView.deselectRow(at: indexPath, animated: true)
			}
		}
	}

}
