//
//  AccountInspectorViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 5/17/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import SafariServices
import RSCore
import Account

final class AccountInspectorViewController: UITableViewController {
	static let preferredContentSizeForFormSheetDisplay = CGSize(width: 460.0, height: 400.0)

	@IBOutlet var nameTextField: UITextField!
	@IBOutlet var activeSwitch: UISwitch!
	@IBOutlet var deleteAccountButton: VibrantButton!
	@IBOutlet var limitationsAndSolutionsButton: UIButton!

	var isModal = false
	weak var account: Account?

    override func viewDidLoad() {
        super.viewDidLoad()

		guard let account = account else { return }

		nameTextField.placeholder = account.defaultName
		nameTextField.text = account.name
		nameTextField.delegate = self
		activeSwitch.isOn = account.isActive

		navigationItem.title = account.nameForDisplay

		if account.type != .onMyMac {
			deleteAccountButton.setTitle(NSLocalizedString("Remove Account", comment: "Remove Account"), for: .normal)
		}

		if account.type != .cloudKit {
			limitationsAndSolutionsButton.isHidden = true
		}

		if isModal {
			let doneBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
			navigationItem.leftBarButtonItem = doneBarButtonItem
		}

		tableView.register(ImageHeaderView.self, forHeaderFooterViewReuseIdentifier: "SectionHeader")

	}

	override func viewWillDisappear(_ animated: Bool) {
		account?.name = nameTextField.text
		account?.isActive = activeSwitch.isOn
	}

	@objc func done() {
		dismiss(animated: true)
	}

	@IBAction func credentials(_ sender: Any) {
	}

	@IBAction func deleteAccount(_ sender: Any) {
		guard account != nil else {
			return
		}

		let title = NSLocalizedString("Remove Account", comment: "Remove Account")
		let message = NSLocalizedString("Are you sure you want to remove this account? This cannot be undone.", comment: "Remove Account")
		let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel")
		let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel)
		alertController.addAction(cancelAction)

		let markTitle = NSLocalizedString("Remove", comment: "Remove")
		let markAction = UIAlertAction(title: markTitle, style: .destructive) { [weak self] _ in
			guard let self, let account = self.account else {
				return
			}
			AccountManager.shared.deleteAccount(account)
			if self.isModal {
				self.dismiss(animated: true)
			} else {
				self.navigationController?.popViewController(animated: true)
			}
		}
		alertController.addAction(markAction)
		alertController.preferredAction = markAction

		present(alertController, animated: true)
	}

	@IBAction func openLimitationsAndSolutions(_ sender: Any) {
		let vc = SFSafariViewController(url: CloudKitWebDocumentation.limitationsAndSolutionsURL)
		vc.modalPresentationStyle = .pageSheet
		present(vc, animated: true)
	}
}

// MARK: Table View

extension AccountInspectorViewController {

	var hidesCredentialsSection: Bool {
		return true
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		guard let account = account else { return 0 }

		if account == AccountManager.shared.defaultAccount {
			return 1
		} else if hidesCredentialsSection {
			return 2
		} else {
			return super.numberOfSections(in: tableView)
		}
	}

	override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		return section == 0 ? ImageHeaderView.rowHeight : super.tableView(tableView, heightForHeaderInSection: section)
	}

	override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		guard let account = account else { return nil }

		if section == 0 {
			let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "SectionHeader") as! ImageHeaderView
			headerView.imageView.image = Assets.accountImage(account.type)
			return headerView
		} else {
			return super.tableView(tableView, viewForHeaderInSection: section)
		}
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell: UITableViewCell

		if indexPath.section == 1, hidesCredentialsSection {
			cell = super.tableView(tableView, cellForRowAt: IndexPath(row: 0, section: 2))
		} else {
			cell = super.tableView(tableView, cellForRowAt: indexPath)
		}

		return cell
	}

	override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
		if indexPath.section > 0 {
			return true
		}
		return false
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
	}
}

// MARK: UITextFieldDelegate

extension AccountInspectorViewController: UITextFieldDelegate {

	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}
}
