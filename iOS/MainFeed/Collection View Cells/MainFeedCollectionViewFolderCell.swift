//
//  MainFeedCollectionViewFolderCell.swift
//  NetNewsWire-iOS
//
//  Created by Stuart Breckenridge on 14/07/2025.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import UIKit

@MainActor protocol MainFeedCollectionViewFolderCellDelegate: AnyObject {
	func mainFeedCollectionFolderViewCellDisclosureDidToggle(_ sender: MainFeedCollectionViewFolderCell, expanding: Bool)
}

class MainFeedCollectionViewFolderCell: UICollectionViewCell {
	@IBOutlet var folderTitle: UILabel!
	@IBOutlet var faviconView: IconView!
	@IBOutlet var unreadCountLabel: UILabel!
	@IBOutlet var disclosureButton: UIButton!

	var delegate: MainFeedCollectionViewFolderCellDelegate?

	private var _unreadCount: Int = 0
	var unreadCount: Int {
		get {
			return _unreadCount
		}
		set {
			_unreadCount = newValue
			if newValue == 0 {
				unreadCountLabel.isHidden = true
			} else {
				unreadCountLabel.isHidden = false
				updateUnreadCountVisibility()
			}
			unreadCountLabel.text = newValue.formatted()
		}
	}

	var iconImage: IconImage? {
		didSet {
			faviconView.iconImage = iconImage
			if let preferredColor = iconImage?.preferredColor {
				faviconView.tintColor = UIColor(cgColor: preferredColor)
			} else {
				faviconView.tintColor = Assets.Colors.secondaryAccent
			}
		}
	}

	var disclosureExpanded = true {
		didSet {
			updateExpandedState(animate: true)
			updateUnreadCountVisibility()
		}
	}

	override func awakeFromNib() {
		MainActor.assumeIsolated {
			super.awakeFromNib()
			disclosureButton.addInteraction(UIPointerInteraction())
			applyVerticalPadding()
		}
	}

	private func applyVerticalPadding() {
		let padding = Assets.Colors.feedCellVerticalPadding
		let safeArea = contentView.safeAreaLayoutGuide
		for c in contentView.constraints {
			if (c.firstItem as? UIView) === folderTitle,
			   c.firstAttribute == .top,
			   (c.secondItem as? UILayoutGuide) === safeArea,
			   c.secondAttribute == .top {
				c.constant = padding
			}
			if (c.firstItem as? UILayoutGuide) === safeArea,
			   c.firstAttribute == .bottom,
			   (c.secondItem as? UIView) === folderTitle,
			   c.secondAttribute == .bottom {
				c.constant = padding
			}
		}
	}

	func updateExpandedState(animate: Bool) {
		let angle: CGFloat = disclosureExpanded ? 0 : -.pi / 2
		let transform = CGAffineTransform(rotationAngle: angle)
		let animations = {
			self.disclosureButton.transform = transform
		}
		if animate {
			UIView.animate(withDuration: 0.3, animations: animations)
		} else {
			animations()
		}
	}

	func updateUnreadCountVisibility() {
		if !disclosureExpanded && unreadCount > 0 {
			UIView.animate {
				self.unreadCountLabel.alpha = 1
			}
		} else {
			UIView.animate {
				self.unreadCountLabel.alpha = 0
			}
		}
	}

	@IBAction
	func toggleDisclosure() {
		setDisclosure(isExpanded: !disclosureExpanded, animated: true)
		delegate?.mainFeedCollectionFolderViewCellDisclosureDidToggle(self, expanding: disclosureExpanded)
	}

	func setDisclosure(isExpanded: Bool, animated: Bool) {
		disclosureExpanded = isExpanded
	}

	override var accessibilityLabel: String? {
		get {
			if unreadCount > 0 {
				let unreadLabel = NSLocalizedString("unread", comment: "Unread label for accessibility")
				return "\(String(describing: folderTitle.text)) \(unreadCount) \(unreadLabel)"
			} else {
				return (String(describing: folderTitle.text))
			}
		}
		set {}
	}

	override func updateConfiguration(using state: UICellConfigurationState) {
		var backgroundConfig = UIBackgroundConfiguration.listCell().updated(for: state)

		let selectionColor = Assets.Colors.cellSelectionColor
		let normalBg: UIColor = Assets.Colors.FeedSceneContentTableColor
		if state.isHighlighted || state.isSelected || state.isFocused {
			backgroundConfig.backgroundColor = selectionColor ?? normalBg
			folderTitle.textColor = .label
			unreadCountLabel.textColor = .secondaryLabel
			faviconView.tintColor = Assets.Colors.primaryAccent
		} else {
			backgroundConfig.backgroundColor = Assets.Colors.FeedSceneContentTableColor
			folderTitle.textColor = .label
			unreadCountLabel.textColor = Assets.Colors.primaryAccent
			faviconView.tintColor = Assets.Colors.primaryAccent
			folderTitle.font = UIFont.preferredFont(forTextStyle: .body)
			unreadCountLabel.font = UIFont.preferredFont(forTextStyle: .body)
		}

		if state.cellDropState == .targeted {
			backgroundConfig.backgroundColor = (Assets.Colors.cellSelectionColor ?? Assets.Colors.primaryAccent).withAlphaComponent(0.18)
		}

		backgroundConfig.cornerRadius = Assets.Colors.cellCornerRadius
		self.backgroundConfiguration = backgroundConfig
	}

}
