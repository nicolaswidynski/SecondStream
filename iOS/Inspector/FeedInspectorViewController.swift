//
//  FeedInspectorViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 11/6/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import SafariServices
import UserNotifications
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

	private let homePageIndexPath = IndexPath(row: 0, section: 1)
	private let feedURLSectionIndex = 2

	private var shouldHideHomePageSection: Bool {
		return feed.homePageURL == nil
	}

	private var shouldHideFeedURLSection: Bool {
		return feed.feedCategory == .news
	}

	private var authorizationStatus: UNAuthorizationStatus?

	override func viewDidLoad() {
		tableView.register(InspectorIconHeaderView.self, forHeaderFooterViewReuseIdentifier: "SectionHeader")

		navigationItem.title = feed.nameForDisplay
		nameTextField.text = feed.nameForDisplay

		notifyAboutNewArticlesSwitch.setOn(feed.isNotifyAboutNewArticles ?? false, animated: false)

		alwaysShowReaderViewSwitch.setOn(feed.isArticleExtractorAlwaysOn ?? false, animated: false)

		homePageLabel.text = feed.homePageURL

		// For podcast/youtube, show the homePageURL (channel/show link); for RSS, show feed URL
		if feed.feedCategory == .podcast || feed.feedCategory == .youtube {
			feedURLLabel.text = feed.homePageURL ?? feed.url
		} else {
			feedURLLabel.text = feed.displayFeedURL ?? feed.url
		}

		obsidianSubfolderTextField.text = feed.obsidianSubfolder ?? ""
		// Show the default subfolder path as placeholder (CategoryPrefix/FeedName)
		let categoryPrefix = ObsidianFileManager.getDefaultSubfolderPrefix(for: feed)
		obsidianSubfolderTextField.placeholder = "\(categoryPrefix)/\(feed.nameForDisplay)"

		NotificationCenter.default.addObserver(self, selector: #selector(feedIconDidBecomeAvailable(_:)), name: .feedIconDidBecomeAvailable, object: nil)

		NotificationCenter.default.addObserver(self, selector: #selector(updateNotificationSettings), name: UIApplication.willEnterForegroundNotification, object: nil)

	}

	override func viewDidAppear(_ animated: Bool) {
		updateNotificationSettings()
	}

	override func viewDidDisappear(_ animated: Bool) {
		if nameTextField.text != feed.nameForDisplay {
			let nameText = nameTextField.text ?? ""
			let newName = nameText.isEmpty ? (feed.name ?? NSLocalizedString("Untitled", comment: "Feed name")) : nameText
			feed.rename(to: newName) { _ in }
		}

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

	@IBAction func notifyAboutNewArticlesChanged(_ sender: Any) {
		guard let authorizationStatus else {
			notifyAboutNewArticlesSwitch.isOn = !notifyAboutNewArticlesSwitch.isOn
			return
		}
		if authorizationStatus == .denied {
			notifyAboutNewArticlesSwitch.isOn = !notifyAboutNewArticlesSwitch.isOn
			present(notificationUpdateErrorAlert(), animated: true, completion: nil)
		} else if authorizationStatus == .authorized {
			feed.isNotifyAboutNewArticles = notifyAboutNewArticlesSwitch.isOn
		} else {
			UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert]) { granted, _ in
				Task { @MainActor in
					self.updateNotificationSettings()
					if granted {
						self.feed.isNotifyAboutNewArticles = self.notifyAboutNewArticlesSwitch.isOn
						UIApplication.shared.registerForRemoteNotifications()
					} else {
						self.notifyAboutNewArticlesSwitch.isOn = !self.notifyAboutNewArticlesSwitch.isOn
					}
				}
			}
		}
	}

	@IBAction func alwaysShowReaderViewChanged(_ sender: Any) {
		feed.isArticleExtractorAlwaysOn = alwaysShowReaderViewSwitch.isOn
	}

	@IBAction func done(_ sender: Any) {
		dismiss(animated: true)
	}

	/// Returns a new indexPath, taking into consideration any
	/// conditions that may require the tableView to be
	/// displayed differently than what is setup in the storyboard.
	private func shift(_ indexPath: IndexPath) -> IndexPath {
		return IndexPath(row: indexPath.row, section: shift(indexPath.section))
	}

	/// Returns a new section, taking into consideration any
	/// conditions that may require the tableView to be
	/// displayed differently than what is setup in the storyboard.
	private func shift(_ section: Int) -> Int {
		var shifted = section
		if shifted >= homePageIndexPath.section && shouldHideHomePageSection {
			shifted += 1
		}
		if shouldHideFeedURLSection && shifted >= feedURLSectionIndex {
			shifted += 1
		}
		return shifted
	}
}

// MARK: Table View

extension FeedInspectorViewController {

	override func numberOfSections(in tableView: UITableView) -> Int {
		var numberOfSections = super.numberOfSections(in: tableView)
		if shouldHideHomePageSection { numberOfSections -= 1 }
		if shouldHideFeedURLSection { numberOfSections -= 1 }
		return numberOfSections
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return super.tableView(tableView, numberOfRowsInSection: shift(section))
	}

	override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		return section == 0 ? ImageHeaderView.rowHeight : super.tableView(tableView, heightForHeaderInSection: shift(section))
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = super.tableView(tableView, cellForRowAt: shift(indexPath))
		if indexPath.section == 0 && indexPath.row == 1 {
			guard let label = cell.contentView.subviews.filter({ $0.isKind(of: UILabel.self) })[0] as? UILabel else {
				return cell
			}
			label.numberOfLines = 2
			label.text = feed.notificationDisplayName.capitalized
		}
		return cell
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		super.tableView(tableView, titleForHeaderInSection: shift(section))
	}

	override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		if shift(section) == 0 {
			headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "SectionHeader") as? InspectorIconHeaderView
			headerView?.iconView.iconImage = iconImage
			return headerView
		} else {
			return super.tableView(tableView, viewForHeaderInSection: shift(section))
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if shift(indexPath) == homePageIndexPath,
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

// MARK: UNUserNotificationCenter

extension FeedInspectorViewController {

	@objc func updateNotificationSettings() {
		UNUserNotificationCenter.current().getNotificationSettings { (settings) in
			let updatedAuthorizationStatus = settings.authorizationStatus
			DispatchQueue.main.async {
				self.authorizationStatus = updatedAuthorizationStatus
				if self.authorizationStatus == .authorized {
					UIApplication.shared.registerForRemoteNotifications()
				}
			}
		}
	}

	func notificationUpdateErrorAlert() -> UIAlertController {
		let alert = UIAlertController(title: NSLocalizedString("Enable Notifications", comment: "Notifications"),
									  message: NSLocalizedString("Notifications need to be enabled in the Settings app.", comment: "Notifications need to be enabled in the Settings app."), preferredStyle: .alert)
		let openSettings = UIAlertAction(title: NSLocalizedString("Open Settings", comment: "Open Settings"), style: .default) { _ in
			UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [UIApplication.OpenExternalURLOptionsKey.universalLinksOnly: false], completionHandler: nil)
		}
		let dismiss = UIAlertAction(title: NSLocalizedString("Dismiss", comment: "Dismiss"), style: .cancel, handler: nil)
		alert.addAction(openSettings)
		alert.addAction(dismiss)
		alert.preferredAction = openSettings
		return alert
	}

}
