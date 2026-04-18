//
//  MainFeedCollectionViewCell.swift
//  NetNewsWire-iOS
//
//  Created by Stuart Breckenridge on 23/06/2025.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import UIKit
import RSCore
import Account
import RSTree

final class MainFeedCollectionViewCell: UICollectionViewCell {
	@IBOutlet var feedTitle: UILabel!
	@IBOutlet var faviconView: IconView!
	@IBOutlet var unreadCountLabel: UILabel!
	private var faviconLeadingConstraint: NSLayoutConstraint?
	var useWideUnreadChevronSpacing = false

	// MARK: - Bootstrap progress

	private lazy var circularProgressView: CircularProgressView = {
		let view = CircularProgressView()
		view.translatesAutoresizingMaskIntoConstraints = false
		view.isHidden = true
		return view
	}()

	/// When non-nil the cell is in "bootstrapping" mode: grayed out, not tappable,
	/// unread count replaced by a circular progress ring.
	var bootstrapProgress: Double? {
		didSet {
			applyBootstrapState()
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

	private var _unreadCount: Int = 0

	var unreadCount: Int {
		get {
			return _unreadCount
		}
		set {
			_unreadCount = newValue
			// Only show the label if we're not in bootstrap mode
			if bootstrapProgress == nil {
				unreadCountLabel.isHidden = false
			}
			updateUnreadDisclosureText()
		}
	}

	/// If the feed is contained in a folder, the indentation level is 1
	/// and the cell's favicon leading constrain is increased. Otherwise,
	/// it has the standard leading constraint.
	///
	/// On the storyboard, no leading constraint is set.
	var indentationLevel: Int = 0 {
		didSet {
			if indentationLevel == 1 {
				faviconLeadingConstraint?.constant = 32
			} else {
				faviconLeadingConstraint?.constant = 16
			}
		}
	}

	override var accessibilityLabel: String? {
		get {
			if unreadCount > 0 {
				let unreadLabel = NSLocalizedString("unread", comment: "Unread label for accessibility")
				return "\(String(describing: feedTitle.text)) \(unreadCount) \(unreadLabel)"
			} else {
				return (String(describing: feedTitle.text))
			}
		}
		set {}
	}

    override func awakeFromNib() {
		MainActor.assumeIsolated {
			super.awakeFromNib()
			faviconLeadingConstraint = faviconView.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor)
			faviconLeadingConstraint?.isActive = true

			applyVerticalPadding()

			// Overlay the circular progress view on top of the unreadCountLabel area
			unreadCountLabel.superview?.addSubview(circularProgressView)
			NSLayoutConstraint.activate([
				circularProgressView.centerYAnchor.constraint(equalTo: unreadCountLabel.centerYAnchor),
				circularProgressView.trailingAnchor.constraint(equalTo: unreadCountLabel.trailingAnchor),
				circularProgressView.widthAnchor.constraint(equalToConstant: 22),
				circularProgressView.heightAnchor.constraint(equalToConstant: 22),
			])
		}
    }

	private func applyVerticalPadding() {
		let padding = Assets.Colors.feedCellVerticalPadding
		let safeArea = contentView.safeAreaLayoutGuide
		for c in contentView.constraints {
			if (c.firstItem as? UIView) === feedTitle,
			   c.firstAttribute == .top,
			   (c.secondItem as? UILayoutGuide) === safeArea,
			   c.secondAttribute == .top {
				c.constant = padding
			}
			if (c.firstItem as? UILayoutGuide) === safeArea,
			   c.firstAttribute == .bottom,
			   (c.secondItem as? UIView) === feedTitle,
			   c.secondAttribute == .bottom {
				c.constant = padding
			}
		}
	}

	override func updateConfiguration(using state: UICellConfigurationState) {
		var backgroundConfig = UIBackgroundConfiguration.listCell().updated(for: state)

		switch (state.isHighlighted || state.isSelected || state.isFocused, traitCollection.userInterfaceIdiom) {
		case (true, .pad):
			if let selectionColor = Assets.Colors.cellSelectionColor {
				backgroundConfig.backgroundColor = selectionColor.withAlphaComponent(0.12)
				feedTitle.textColor = selectionColor
			}
			feedTitle.font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
											   weight: .semibold)
			unreadCountLabel.font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .semibold)
		case (true, .phone):
			if let selectionColor = Assets.Colors.cellSelectionColor {
				backgroundConfig.backgroundColor = selectionColor
			}
			feedTitle.textColor = .white
			unreadCountLabel.textColor = .white
			if feedTitle.text == "All Unread" {
				faviconView.tintColor = .white
			}
		default:
			backgroundConfig.backgroundColor = traitCollection.userInterfaceIdiom == .phone
				? Assets.Colors.FeedSceneContentTableColor
				: Assets.Colors.foreground
			feedTitle.textColor = .label
			feedTitle.font = UIFont.preferredFont(forTextStyle: .body)
			unreadCountLabel.font = UIFont.preferredFont(forTextStyle: .body)
			unreadCountLabel.textColor = .secondaryLabel
			if traitCollection.userInterfaceIdiom == .phone {
				if feedTitle.text == "All Unread" {
					if let preferredColor = iconImage?.preferredColor {
						faviconView.tintColor = UIColor(cgColor: preferredColor)
					} else {
						faviconView.tintColor = Assets.Colors.secondaryAccent
					}
				}
			}
		}
		updateUnreadDisclosureText()
		applyBootstrapState()
		self.backgroundConfiguration = backgroundConfig
	}

	private func applyBootstrapState() {
		if let progress = bootstrapProgress {
			// Bootstrapping: show ring, hide count label, gray out cell
			circularProgressView.progress = CGFloat(progress)
			circularProgressView.isHidden = false
			unreadCountLabel.isHidden = true
			contentView.alpha = 0.45
			isUserInteractionEnabled = false
		} else {
			// Normal: hide ring, restore count label and appearance
			circularProgressView.isHidden = true
			unreadCountLabel.isHidden = false
			contentView.alpha = 1.0
			isUserInteractionEnabled = true
		}
	}

	private func updateUnreadDisclosureText() {
		// During bootstrap, the label is hidden — no need to update it
		guard bootstrapProgress == nil else { return }

		let textColor = unreadCountLabel.textColor ?? .secondaryLabel
		let font = unreadCountLabel.font ?? UIFont.preferredFont(forTextStyle: .body)
		let symbolConfig = UIImage.SymbolConfiguration(pointSize: max(10, font.pointSize * 0.68), weight: .semibold)
		let symbolImage = UIImage(systemName: "chevron.right", withConfiguration: symbolConfig)?
			.withTintColor(textColor, renderingMode: .alwaysOriginal)

		let result = NSMutableAttributedString()
		if _unreadCount > 0 {
			result.append(NSAttributedString(string: _unreadCount.formatted(), attributes: [
				.font: font,
				.foregroundColor: textColor
			]))
			let spacer = useWideUnreadChevronSpacing ? "  " : ""
			result.append(NSAttributedString(string: spacer, attributes: [
				.font: font,
				.foregroundColor: textColor
			]))
		}

		if let symbolImage {
			let attachment = NSTextAttachment()
			attachment.image = symbolImage
			let baselineOffset = (font.capHeight - symbolImage.size.height) / 2
			attachment.bounds = CGRect(x: 0, y: baselineOffset, width: symbolImage.size.width, height: symbolImage.size.height)
			result.append(NSAttributedString(attachment: attachment))
		}

		unreadCountLabel.attributedText = result
	}
}
