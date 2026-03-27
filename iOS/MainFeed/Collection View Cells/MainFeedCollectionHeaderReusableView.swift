//
//  MainFeedCollectionHeaderReusableView.swift
//  NetNewsWire-iOS
//
//  Created by Stuart Breckenridge on 12/07/2025.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import UIKit

@MainActor protocol MainFeedCollectionHeaderReusableViewDelegate: AnyObject {
	func mainFeedCollectionHeaderReusableViewDidTapDisclosureIndicator(_ view: MainFeedCollectionHeaderReusableView)
}

final class MainFeedCollectionHeaderReusableView: UICollectionReusableView {
	var delegate: MainFeedCollectionHeaderReusableViewDelegate?
	var sectionID: String?

	@IBOutlet var headerTitle: UILabel!
	@IBOutlet var disclosureIndicator: UIImageView!
	@IBOutlet var unreadCountLabel: UILabel!

	private var unreadLabelWidthConstraint: NSLayoutConstraint?

	override var accessibilityLabel: String? {
		get {
			if unreadCount > 0 {
				let unreadLabel = NSLocalizedString("unread", comment: "Unread label for accessibility")
				return "\(headerTitle.text ?? "") \(unreadCount) \(unreadLabel) \(expandedStateMessage) "
			} else {
				return "\(headerTitle.text ?? "") \(expandedStateMessage) "
			}
		}
		set {}
	}

	private var expandedStateMessage: String {
		if disclosureExpanded {
			return NSLocalizedString("Expanded", comment: "Disclosure button expanded state for accessibility")
		}
		return NSLocalizedString("Collapsed", comment: "Disclosure button collapsed state for accessibility")
	}

	private var _unreadCount: Int = 0
	private var hasBeenConfigured = false
	private var sectionTitleText: String = ""

	var sectionIcon: UIImage? {
		didSet { updateAttributedTitle() }
	}

	var unreadCount: Int {
		get {
			return _unreadCount
		}
		set {
			_unreadCount = newValue
			unreadCountLabel.text = newValue.formatted()
			//			unreadCountLabel.textColor = .white
			// Update visibility when count changes (for collapsed sections)
			if hasBeenConfigured {
				updateUnreadCount(animated: false)
			}
		}
	}

	var disclosureExpanded = true {
		didSet {
			let shouldAnimate = hasBeenConfigured && (oldValue != disclosureExpanded)
			updateExpandedState(animate: shouldAnimate)
			updateUnreadCount(animated: shouldAnimate)
			hasBeenConfigured = true
		}
	}

	override func awakeFromNib() {
		MainActor.assumeIsolated {
			super.awakeFromNib()
			unreadLabelWidthConstraint = unreadCountLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 80)
			unreadLabelWidthConstraint?.isActive = true
			tightenUnreadChevronSpacing()
			unreadCountLabel.alpha = 0  // Start hidden
			configureUI()
			addTapGesture()
		}
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		_unreadCount = 0
		disclosureExpanded = true
		unreadCountLabel.alpha = 0
		hasBeenConfigured = false
		sectionID = nil
		sectionTitleText = ""
		sectionIcon = nil
		headerTitle.attributedText = nil
	}

	func configureUI() {
		let accentColor = UIColor(named: "secondaryAccentColor") ?? .systemBlue
		headerTitle.textColor = accentColor
		disclosureIndicator.tintColor = accentColor
		updateAttributedTitle()
	}

	private func tightenUnreadChevronSpacing() {
		// Keep category headers tight: "count >" should not have a large visual gap.
		for constraint in constraints {
			let isUnreadToDisclosure =
				constraint.firstItem as AnyObject? === disclosureIndicator &&
				constraint.firstAttribute == .leading &&
				constraint.secondItem as AnyObject? === unreadCountLabel &&
				constraint.secondAttribute == .trailing
			if isUnreadToDisclosure {
				constraint.constant = 2
			}
		}

		for constraint in disclosureIndicator.constraints {
			if constraint.firstAttribute == .width || constraint.firstAttribute == .height {
				constraint.constant = 26
			}
		}
	}

	private func addTapGesture() {
		let tapGesture = UITapGestureRecognizer(target: self, action: #selector(containerHeaderTapped))
		self.addGestureRecognizer(tapGesture)
		self.isUserInteractionEnabled = true
	}

	@objc private func containerHeaderTapped() {
		delegate?.mainFeedCollectionHeaderReusableViewDidTapDisclosureIndicator(self)
	}

	func configure(title: String, icon: UIImage? = nil) {
		sectionTitleText = title
		sectionIcon = icon
		disclosureIndicator.transform = .identity
	}

	func configureContainer(withTitle title: String) {
		configure(title: title)
	}

	private func updateAttributedTitle() {
		guard !sectionTitleText.isEmpty else {
			return
		}
		guard let icon = sectionIcon else {
			headerTitle.attributedText = nil
			headerTitle.text = sectionTitleText
			return
		}

		let font = headerTitle.font ?? UIFont.systemFont(ofSize: 15, weight: .semibold)
		let color = headerTitle.textColor ?? .label
		let height = font.pointSize * 1.4
		let config = UIImage.SymbolConfiguration(pointSize: font.pointSize, weight: .semibold)
		let scaledIcon = icon.applyingSymbolConfiguration(config) ?? icon
		let imgSize = scaledIcon.size
		let width = imgSize.height > 0 ? height * (imgSize.width / imgSize.height) : height

		let attachment = NSTextAttachment()
		attachment.bounds = CGRect(x: 0, y: (font.capHeight - height) / 2, width: width, height: height)
		attachment.image = scaledIcon.withTintColor(color, renderingMode: .alwaysOriginal)

		let attrs: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: color
		]
		let iconString = NSAttributedString(attachment: attachment)
		let space = NSAttributedString(string: "  ", attributes: attrs)
		let title = NSAttributedString(string: sectionTitleText, attributes: attrs)

		let result = NSMutableAttributedString()
		result.append(iconString)
		result.append(space)
		result.append(title)

		headerTitle.attributedText = result
	}

	func updateExpandedState(animate: Bool) {
		// Update constraint constant - use 80 when collapsed (to show count), 0 when expanded (hidden)
		unreadLabelWidthConstraint?.constant = disclosureExpanded ? 0 : 80

		let angle: CGFloat = disclosureExpanded ? 0 : -.pi / 2
		let transform = CGAffineTransform(rotationAngle: angle)
		let animations = {
			self.disclosureIndicator.transform = transform
		}
		if animate {
			UIView.animate(withDuration: 0.3, animations: animations)
		} else {
			animations()
		}
	}

	func updateUnreadCount(animated: Bool = true) {
		let targetAlpha: CGFloat = (!disclosureExpanded && unreadCount > 0) ? 1 : 0
		if animated {
			UIView.animate(withDuration: 0.3) {
				self.unreadCountLabel.alpha = targetAlpha
			}
		} else {
			self.unreadCountLabel.alpha = targetAlpha
		}
	}

}
