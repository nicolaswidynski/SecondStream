//
//  NotificationsSettingsViewController.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-14.
//  Copyright © 2026 STDN. All rights reserved.
//

import UIKit
import UserNotifications

final class NotificationsSettingsViewController: UITableViewController {

	private var isAuthorized = false

	private enum Row: CaseIterable {
		case openSettings
		case podcasts
		case youtube
		case news
		case rssFeeds
	}

	private var rows: [Row] = [.openSettings]

	override func viewDidLoad() {
		super.viewDidLoad()
		title = NSLocalizedString("Notifications", comment: "Notifications")
		tableView.backgroundColor = Assets.Colors.SettingsContentBgColor
		tableView.separatorStyle = .none
		UISwitch.appearance(whenContainedInInstancesOf: [NotificationsSettingsViewController.self]).onTintColor = Assets.Colors.primaryAccent
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		applySettingsNavBarAppearance()
		refreshAuthorization()
	}

	private func refreshAuthorization() {
		UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
			let authorized = settings.authorizationStatus == .authorized
			DispatchQueue.main.async {
				guard let self else { return }
				self.isAuthorized = authorized
				self.rows = self.isAuthorized
					? [.openSettings, .podcasts, .youtube, .news, .rssFeeds]
					: [.openSettings]

				// Set defaults on first authorization
				if self.isAuthorized {
					let store = AppDefaults.store
					if store.object(forKey: AppDefaults.Key.notifyPodcasts) == nil { AppDefaults.shared.notifyPodcasts = true }
					if store.object(forKey: AppDefaults.Key.notifyYouTube) == nil { AppDefaults.shared.notifyYouTube = true }
					if store.object(forKey: AppDefaults.Key.notifyWeeklyNews) == nil { AppDefaults.shared.notifyWeeklyNews = true }
					if store.object(forKey: AppDefaults.Key.notifyFeeds) == nil { AppDefaults.shared.notifyFeeds = true }
				}

				self.tableView.reloadData()
			}
		}
	}

	// MARK: - Table view

	override func numberOfSections(in tableView: UITableView) -> Int { 1 }

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		rows.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		switch rows[indexPath.row] {
		case .openSettings:
			let cell = UITableViewCell(style: .default, reuseIdentifier: "OpenSettings")
			cell.textLabel?.text = NSLocalizedString("Open System Settings", comment: "Open System Settings")
			cell.textLabel?.adjustsFontForContentSizeCategory = true
			cell.backgroundColor = Assets.Colors.SettingsContentTableColor
			return cell
		case .podcasts:
			return makeToggleCell(title: NSLocalizedString("Notify Podcasts", comment: "Notify Podcasts"),
								  isOn: AppDefaults.shared.notifyPodcasts,
								  action: #selector(switchPodcasts(_:)))
		case .youtube:
			return makeToggleCell(title: NSLocalizedString("Notify YouTube", comment: "Notify YouTube"),
								  isOn: AppDefaults.shared.notifyYouTube,
								  action: #selector(switchYouTube(_:)))
		case .news:
			return makeToggleCell(title: NSLocalizedString("Notify Weekly News", comment: "Notify Weekly News"),
								  isOn: AppDefaults.shared.notifyWeeklyNews,
								  action: #selector(switchNews(_:)))
		case .rssFeeds:
			return makeToggleCell(title: NSLocalizedString("Notify RSS Feeds", comment: "Notify RSS Feeds"),
								  isOn: AppDefaults.shared.notifyFeeds,
								  action: #selector(switchFeeds(_:)))
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		if rows[indexPath.row] == .openSettings {
			UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
		}
	}

	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		cell.backgroundColor = Assets.Colors.SettingsContentTableColor
	}

	// MARK: - Helpers

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

	// MARK: - Switch actions

	@objc private func switchPodcasts(_ sender: UISwitch) {
		AppDefaults.shared.notifyPodcasts = sender.isOn
	}

	@objc private func switchYouTube(_ sender: UISwitch) {
		AppDefaults.shared.notifyYouTube = sender.isOn
	}

	@objc private func switchNews(_ sender: UISwitch) {
		AppDefaults.shared.notifyWeeklyNews = sender.isOn
	}

	@objc private func switchFeeds(_ sender: UISwitch) {
		AppDefaults.shared.notifyFeeds = sender.isOn
	}
}
