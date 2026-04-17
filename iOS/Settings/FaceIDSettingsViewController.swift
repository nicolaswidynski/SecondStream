//
//  FaceIDSettingsViewController.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-14.
//  Copyright © 2026 STDN. All rights reserved.
//

import UIKit
import LocalAuthentication

final class FaceIDSettingsViewController: UITableViewController {

	override func viewDidLoad() {
		super.viewDidLoad()
		title = NSLocalizedString("Face ID", comment: "Face ID")
		tableView.backgroundColor = Assets.Colors.SettingsContentBgColor
		tableView.separatorStyle = .none
		UISwitch.appearance(whenContainedInInstancesOf: [FaceIDSettingsViewController.self]).onTintColor = Assets.Colors.primaryAccent
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		applySettingsNavBarAppearance()
		tableView.reloadData()
	}

	// MARK: - Table view

	override func numberOfSections(in tableView: UITableView) -> Int { 1 }
	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = UITableViewCell(style: .default, reuseIdentifier: "FaceIDCell")
		cell.textLabel?.text = NSLocalizedString("Enable Face ID", comment: "Enable Face ID")
		cell.textLabel?.adjustsFontForContentSizeCategory = true
		cell.selectionStyle = .none
		cell.backgroundColor = Assets.Colors.SettingsContentTableColor
		let toggle = UISwitch()
		toggle.isOn = AppDefaults.shared.faceIDEnabled
		toggle.addTarget(self, action: #selector(switchFaceID(_:)), for: .valueChanged)
		cell.accessoryView = toggle
		return cell
	}

	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		cell.backgroundColor = Assets.Colors.SettingsContentTableColor
	}

	// MARK: - Actions

	@objc private func switchFaceID(_ sender: UISwitch) {
		guard sender.isOn else {
			AppDefaults.shared.faceIDEnabled = false
			return
		}
		let context = LAContext()
		var error: NSError?
		guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
			sender.setOn(false, animated: true)
			let message = error?.localizedDescription ?? NSLocalizedString("Face ID is not available on this device.", comment: "Face ID unavailable")
			presentError(title: NSLocalizedString("Face ID Unavailable", comment: "Face ID unavailable title"), message: message)
			return
		}
		let reason = NSLocalizedString("Enable Face ID for Second Stream", comment: "Face ID enrollment reason")
		context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, authError in
			DispatchQueue.main.async {
				if success {
					AppDefaults.shared.faceIDEnabled = true
				} else {
					sender.setOn(false, animated: true)
					if let authError, (authError as NSError).code != LAError.userCancel.rawValue {
						self?.presentError(title: NSLocalizedString("Face ID Failed", comment: "Face ID failed title"), message: authError.localizedDescription)
					}
				}
			}
		}
	}
}
