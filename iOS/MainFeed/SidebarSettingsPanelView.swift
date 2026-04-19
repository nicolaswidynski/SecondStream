//
//  SidebarSettingsPanelView.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-14.
//  Copyright © 2026 STDN. All rights reserved.
//

import UIKit

// MARK: - SettingsSidebarItem

enum SettingsSidebarItem: CaseIterable {
	case notifications
	case appearance
	case faceID
	case obsidian
	case donation
	case about
	case logOut
	case deleteAccount

	var title: String {
		switch self {
		case .notifications: return NSLocalizedString("Notifications", comment: "Notifications")
		case .appearance: return NSLocalizedString("Appearance", comment: "Appearance")
		case .faceID: return NSLocalizedString("Face ID", comment: "Face ID")
		case .obsidian: return NSLocalizedString("Obsidian", comment: "Obsidian")
		case .donation: return NSLocalizedString("Donation", comment: "Donation")
		case .about: return NSLocalizedString("About", comment: "About")
		case .logOut: return NSLocalizedString("Log Out", comment: "Log Out")
		case .deleteAccount: return NSLocalizedString("Delete Account", comment: "Delete Account")
		}
	}

	var icon: UIImage? {
		switch self {
		case .notifications: return UIImage(systemName: "bell")
		case .appearance: return UIImage(systemName: "sun.max")
		case .faceID: return UIImage(systemName: "faceid")
		case .obsidian: return UIImage(named: "obsidian-symbol")
		case .donation: return UIImage(systemName: "heart")
		case .about: return UIImage(systemName: "info.circle")
		case .logOut: return UIImage(systemName: "rectangle.portrait.and.arrow.right")
		case .deleteAccount: return UIImage(systemName: "trash")
		}
	}

	var iconWidth: CGFloat {
		switch self {
		default: return 22
		}
	}

	var iconHeight: CGFloat {
		switch self {
		default: return 22
		}
	}

	var isDestructive: Bool {
		return self == .deleteAccount
	}

	var showsChevron: Bool {
		switch self {
		case .notifications, .appearance, .faceID, .obsidian, .donation, .about:
			return true
		case .logOut, .deleteAccount:
			return false
		}
	}
}

// MARK: - SidebarSettingsPanelView

/// A fixed-position panel that sits at the bottom of the sidebar, showing settings navigation items.
/// Install it into the collection view's view hierarchy; it stays pinned to the safe-area bottom.
final class SidebarSettingsPanelView: UIView {

	/// Called when the user taps a settings item row.
	var onSelectItem: ((SettingsSidebarItem) -> Void)?

	/// Height of the panel (separator + rows). Pass this as `contentInset.bottom` on the collection view.
	static let panelHeight: CGFloat = 1 + CGFloat(SettingsSidebarItem.allCases.count) * rowHeight

	private static let rowHeight: CGFloat = 44

	private let separator = UIView()
	private var rowButtons: [UIControl] = []

	init() {
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		setupViews()
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	// MARK: - Setup

	private func setupViews() {
		backgroundColor = Assets.Colors.background

		separator.backgroundColor = .separator
		separator.translatesAutoresizingMaskIntoConstraints = false
		addSubview(separator)

		var previousAnchor: NSLayoutYAxisAnchor = separator.bottomAnchor

		for item in SettingsSidebarItem.allCases {
			let rowControl = makeRowControl(for: item)
			addSubview(rowControl)

			NSLayoutConstraint.activate([
				rowControl.leadingAnchor.constraint(equalTo: leadingAnchor),
				rowControl.trailingAnchor.constraint(equalTo: trailingAnchor),
				rowControl.topAnchor.constraint(equalTo: previousAnchor),
				rowControl.heightAnchor.constraint(equalToConstant: SidebarSettingsPanelView.rowHeight),
			])

			previousAnchor = rowControl.bottomAnchor
			rowButtons.append(rowControl)
		}

		NSLayoutConstraint.activate([
			separator.leadingAnchor.constraint(equalTo: leadingAnchor),
			separator.trailingAnchor.constraint(equalTo: trailingAnchor),
			separator.topAnchor.constraint(equalTo: topAnchor),
			separator.heightAnchor.constraint(equalToConstant: 0.5),
		])
	}

	private func makeRowControl(for item: SettingsSidebarItem) -> UIControl {
		let control = SidebarSettingsRowControl(item: item)
		control.translatesAutoresizingMaskIntoConstraints = false
		control.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
		return control
	}

	// MARK: - Actions

	@objc private func rowTapped(_ sender: SidebarSettingsRowControl) {
		onSelectItem?(sender.item)
	}

	// MARK: - Installation

	/// Installs the panel into the collection view. Pin the panel to the
	/// safe-area bottom of the collection view so it stays fixed during scrolling.
	func install(in collectionView: UICollectionView) {
		collectionView.addSubview(self)
		NSLayoutConstraint.activate([
			leadingAnchor.constraint(equalTo: collectionView.leadingAnchor),
			trailingAnchor.constraint(equalTo: collectionView.trailingAnchor),
			bottomAnchor.constraint(equalTo: collectionView.safeAreaLayoutGuide.bottomAnchor),
			heightAnchor.constraint(equalToConstant: SidebarSettingsPanelView.panelHeight),
		])
	}
}

// MARK: - SidebarSettingsRowControl

private final class SidebarSettingsRowControl: UIControl {

	let item: SettingsSidebarItem

	private let iconView = UIImageView()
	private let titleLabel = UILabel()
	private let chevronView = UIImageView()
	private let rowSeparator = UIView()

	override var isHighlighted: Bool {
		didSet {
			backgroundColor = isHighlighted ? .systemFill : .clear
		}
	}

	init(item: SettingsSidebarItem) {
		self.item = item
		super.init(frame: .zero)
		setupViews()
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) not supported")
	}

	private func setupViews() {
		// Icon
		iconView.image = item.icon
		if item == .obsidian {
			iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)
		}
		iconView.contentMode = .scaleAspectFit
		iconView.tintColor = item.isDestructive ? .systemRed : Assets.Colors.primaryAccent
		iconView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(iconView)

		// Title
		titleLabel.text = item.title
		titleLabel.font = .preferredFont(forTextStyle: .body)
		titleLabel.adjustsFontForContentSizeCategory = true
		titleLabel.textColor = item.isDestructive ? .systemRed : .label
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(titleLabel)

		// Chevron
		if item.showsChevron {
			chevronView.image = UIImage(systemName: "chevron.right")
			chevronView.contentMode = .scaleAspectFit
			chevronView.tintColor = .tertiaryLabel
			chevronView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
			chevronView.translatesAutoresizingMaskIntoConstraints = false
			addSubview(chevronView)
		}

		// Row separator
		rowSeparator.backgroundColor = .separator
		rowSeparator.translatesAutoresizingMaskIntoConstraints = false
		addSubview(rowSeparator)

		var constraints: [NSLayoutConstraint] = [
			iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: item.iconWidth),
			iconView.heightAnchor.constraint(equalToConstant: item.iconHeight),

			titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
			titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

			rowSeparator.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
			rowSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
			rowSeparator.bottomAnchor.constraint(equalTo: bottomAnchor),
			rowSeparator.heightAnchor.constraint(equalToConstant: 0.5),
		]

		if item.showsChevron {
			constraints += [
				titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -8),
				chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
				chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
				chevronView.widthAnchor.constraint(equalToConstant: 12),
				chevronView.heightAnchor.constraint(equalToConstant: 18),
			]
		} else {
			constraints.append(titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20))
		}

		NSLayoutConstraint.activate(constraints)
	}
}
