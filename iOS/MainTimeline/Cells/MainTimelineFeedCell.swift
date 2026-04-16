//
//  MainTimelineFeedCell.swift
//  NetNewsWire-iOS
//
//  Created by Stuart Breckenridge on 20/07/2025.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import UIKit

class MainTimelineFeedCell: UITableViewCell {
	@IBOutlet var articleTitle: UILabel!
	@IBOutlet var authorByLine: UILabel!
	@IBOutlet var indicatorView: IconView!
	@IBOutlet var articleDate: UILabel!
	@IBOutlet var metaDataStackView: UIStackView!

	private let chevronView: UIImageView = {
		let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
		let image = UIImage(systemName: "chevron.right", withConfiguration: config)
		let view = UIImageView(image: image)
		view.tintColor = .tertiaryLabel
		view.translatesAutoresizingMaskIntoConstraints = false
		view.contentMode = .center
		return view
	}()

	private let inlineDateLabel: UILabel = {
		let label = UILabel()
		label.numberOfLines = 2
		label.font = UIFont.preferredFont(forTextStyle: .caption1)
		label.textColor = .secondaryLabel
		label.textAlignment = .center
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}()

	var cellData: MainTimelineCellData! {
		didSet {
			configure(cellData)
		}
	}

	var isPreview: Bool = false

	// The date column anchors everything. The indicator is not in the layout chain —
	// it's positioned relative to the date label without consuming horizontal space:
	//   - bookmark   → centered in the date column (date hidden)
	//   - unread dot → just to the left of the date column
	private var dateLabelLeadingConstraint: NSLayoutConstraint?
	private var indicatorCenterXConstraint: NSLayoutConstraint?
	private var chevronTrailingConstraint: NSLayoutConstraint?
	private var isStarred = false

	override func awakeFromNib() {
		MainActor.assumeIsolated {
			super.awakeFromNib()
			indicatorView.alpha = 0.0
			configureStackView()
			articleDate.isHidden = true
			contentView.addSubview(inlineDateLabel)
			contentView.addSubview(chevronView)
			setupConstraints()
		}
	}

	private func setupConstraints() {
		// Demote all storyboard leading/trailing constraints.
		// Also demote indicatorView vertical constraints so we control its centerY.
		for c in contentView.constraints {
			if c.firstAttribute == .leading || c.firstAttribute == .trailing {
				c.priority = UILayoutPriority(1)
			}
			let touchesIndicator = c.firstItem as? UIView === indicatorView
				|| c.secondItem as? UIView === indicatorView
			if touchesIndicator,
			   c.firstAttribute == .top || c.firstAttribute == .bottom || c.firstAttribute == .centerY {
				c.priority = UILayoutPriority(1)
			}
		}

		// Date label anchors the entire layout. Initial constant updated in layoutSubviews.
		let dateLeading = inlineDateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
		// Indicator starts at the date column center (bookmark) or to its left (unread dot).
		// Default to bookmark position; updateIndicatorView switches it.
		let indCenterX = indicatorView.centerXAnchor.constraint(equalTo: inlineDateLabel.centerXAnchor)
		let chevTrailing = chevronView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
		dateLabelLeadingConstraint = dateLeading
		indicatorCenterXConstraint = indCenterX
		chevronTrailingConstraint = chevTrailing

		NSLayoutConstraint.activate([
			dateLeading,
			inlineDateLabel.widthAnchor.constraint(equalToConstant: Assets.Colors.timelineDateColumnWidth),
			inlineDateLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			indCenterX,
			indicatorView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			articleTitle.leadingAnchor.constraint(equalTo: inlineDateLabel.trailingAnchor, constant: 8),
			articleTitle.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -6),
			metaDataStackView.leadingAnchor.constraint(equalTo: articleTitle.leadingAnchor),
			metaDataStackView.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -6),
			chevTrailing,
			chevronView.widthAnchor.constraint(equalToConstant: 10),
			chevronView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
		])
	}

	private func configureStackView() {
		switch traitCollection.preferredContentSizeCategory {
		case .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge, .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge:
			metaDataStackView.axis = .vertical
			metaDataStackView.alignment = .leading
			metaDataStackView.distribution = .fill
		default:
			metaDataStackView.axis = .horizontal
			metaDataStackView.alignment = .center
			metaDataStackView.distribution = .fill
		}
	}

	private func configure(_ cellData: MainTimelineCellData) {
		updateIndicatorView(cellData)
		articleTitle.numberOfLines = cellData.numberOfLines

		applyTitleTextWithAttributes(configurationState)

		if cellData.showFeedName == .feed {
			authorByLine.text = cellData.feedName
			authorByLine.isHidden = false
		} else if cellData.showFeedName == .byline {
			authorByLine.text = cellData.byline
			authorByLine.isHidden = false
		} else if cellData.showFeedName == .none {
			authorByLine.text = ""
			authorByLine.isHidden = true
		}

		articleDate.text = cellData.dateString
		inlineDateLabel.text = cellData.inlineDateString
	}

	private func updateIndicatorView(_ cellData: MainTimelineCellData) {
		let dimReadArticles = AppDefaults.shared.timelineDimReadArticles
		if cellData.starred {
			isStarred = true
			setIndicatorViewSize(22)
			indicatorView.iconImage = Assets.Images.starredCellIndicator
			indicatorView.tintColor = .label
			// Bookmark: center indicator in the date column
			indicatorCenterXConstraint?.isActive = false
			indicatorCenterXConstraint = indicatorView.centerXAnchor.constraint(equalTo: inlineDateLabel.centerXAnchor)
			indicatorCenterXConstraint?.isActive = true
			UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
				self.indicatorView.alpha = 1.0
				self.inlineDateLabel.alpha = 0.0
				self.contentView.layoutIfNeeded()
			} completion: { _ in
				self.inlineDateLabel.isHidden = true
				self.inlineDateLabel.alpha = 1.0
			}
		} else if cellData.read == false && !dimReadArticles {
			isStarred = false
			setIndicatorViewSize(10)
			indicatorView.iconImage = Assets.Images.unreadCellIndicator
			indicatorView.tintColor = Assets.Colors.secondaryAccent
			// Unread dot: just to the left of the date column, no layout space consumed
			indicatorCenterXConstraint?.isActive = false
			indicatorCenterXConstraint = indicatorView.centerXAnchor.constraint(equalTo: inlineDateLabel.leadingAnchor, constant: -6)
			indicatorCenterXConstraint?.isActive = true
			inlineDateLabel.isHidden = false
			UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
				self.indicatorView.alpha = 1.0
				self.inlineDateLabel.alpha = 1.0
				self.contentView.layoutIfNeeded()
			}
		} else {
			isStarred = false
			setIndicatorViewSize(10)
			inlineDateLabel.isHidden = false
			UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
				self.indicatorView.alpha = 0.0
				self.inlineDateLabel.alpha = 1.0
			} completion: { _ in
				self.indicatorView.iconImage = nil
			}
		}
	}

	private func setIndicatorViewSize(_ size: CGFloat) {
		for constraint in indicatorView.constraints where constraint.firstAttribute == .width || constraint.firstAttribute == .height {
			constraint.constant = size
		}
	}

	private func applyTitleTextWithAttributes(_ state: UICellConfigurationState) {
		guard cellData != nil else { return }
		articleTitle.text = cellData.title
		articleTitle.font = UIFont.preferredFont(forTextStyle: .body)
		articleTitle.textColor = titleTextColor(for: state)
		articleTitle.lineBreakMode = .byTruncatingTail
	}

	func titleTextColor(for state: UICellConfigurationState) -> UIColor {
		let isSelected = state.isSelected || state.isHighlighted || state.isFocused || state.isSwiped
		if isSelected {
			return .white
		} else if AppDefaults.shared.timelineDimReadArticles, cellData?.read == true {
			return Assets.Colors.readArticleTitle
		} else {
			return .label
		}
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		guard traitCollection.userInterfaceIdiom == .phone else { return }
		let inset = (bounds.width * 0.05).rounded()
		dateLabelLeadingConstraint?.constant = inset + 6
		chevronTrailingConstraint?.constant = -(inset + 12)
	}

	override func updateConfiguration(using state: UICellConfigurationState) {
		super.updateConfiguration(using: state)

		var backgroundConfig = UIBackgroundConfiguration.listCell().updated(for: state)
		if traitCollection.userInterfaceIdiom == .phone {
			backgroundConfig.edgesAddingLayoutMarginsToBackgroundInsets = []
			let hInset = (bounds.width * 0.05).rounded()
			backgroundConfig.backgroundInsets = NSDirectionalEdgeInsets(top: 0, leading: hInset, bottom: 0, trailing: hInset)
		}
		if traitCollection.userInterfaceIdiom == .pad {
			backgroundConfig.edgesAddingLayoutMarginsToBackgroundInsets = [.leading, .trailing]
			backgroundConfig.backgroundInsets = NSDirectionalEdgeInsets(top: 0, leading: !isPreview ? -4 : -12, bottom: 0, trailing: !isPreview ? -4 : -12)
		}

		if state.isSelected || state.isHighlighted || state.isFocused || state.isSwiped {
			backgroundConfig.backgroundColor = Assets.Colors.primaryAccent
			applyTitleTextWithAttributes(state)
			articleDate.textColor = .lightText
			authorByLine.textColor = .lightText
			inlineDateLabel.textColor = .lightText
			chevronView.tintColor = UIColor.white.withAlphaComponent(0.6)
		} else {
			backgroundConfig.backgroundColor = traitCollection.userInterfaceIdiom == .phone
				? Assets.Colors.TimelineSceneContentTableColor
				: Assets.Colors.foreground
			applyTitleTextWithAttributes(state)
			articleDate.textColor = .secondaryLabel
			authorByLine.textColor = .secondaryLabel
			inlineDateLabel.textColor = .secondaryLabel
			chevronView.tintColor = .tertiaryLabel
		}

		self.backgroundConfiguration = backgroundConfig
	}

}
