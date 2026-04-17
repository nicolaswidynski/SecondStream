//
//  ColorPaletteTableViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 3/15/20.
//  Copyright © 2020 Ranchero Software. All rights reserved.
//

import UIKit

final class ColorPaletteTableViewController: UITableViewController {

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		applySettingsNavBarAppearance()
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		tableView.backgroundColor = Assets.Colors.SettingsContentBgColor
	}

	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		var bg = UIBackgroundConfiguration.listCell()
		bg.backgroundColor = Assets.Colors.SettingsContentTableColor
		cell.backgroundConfiguration = bg
	}

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return UserInterfaceColorPalette.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
		let rowColorPalette = UserInterfaceColorPalette.allCases[indexPath.row]
		cell.textLabel?.text = String(describing: rowColorPalette)
		if rowColorPalette == AppDefaults.userInterfaceColorPalette {
			cell.accessoryType = .checkmark
		} else {
			cell.accessoryType = .none
		}
        return cell
    }

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if let colorPalette = UserInterfaceColorPalette(rawValue: indexPath.row) {
			AppDefaults.userInterfaceColorPalette = colorPalette
		}
		navigationController?.popViewController(animated: true)
	}

}
