//
//  PseudoFeedTableViewCell.swift
//  NetNewsWire
//
//  Created by Stuart Breckenridge on 19/07/2025.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import UIKit

class MainTimelineIconFeedCell: UITableViewCell {
	@IBOutlet var articleTitle: UILabel!
	@IBOutlet var authorByLine: UILabel!
	@IBOutlet var iconView: IconView!
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

	private var contentLeadingConstraint: NSLayoutConstraint?
	private var chevronTrailingConstraint: NSLayoutConstraint?

	override func awakeFromNib() {
		MainActor.assumeIsolated {
			super.awakeFromNib()
			indicatorView.alpha = 0.0
			configureStackView()
			articleDate.isHidden = true
			contentView.addSubview(inlineDateLabel)
			contentView.addSubview(chevronView)
			setupConstraints()
			applyVerticalPadding()
		}
	}

	private func applyVerticalPadding() {
		let padding = Assets.Colors.timelineCellVerticalPadding
		let safeArea = contentView.safeAreaLayoutGuide
		for c in contentView.constraints {
			let safeIsFirst  = c.firstItem  as? UILayoutGuide === safeArea
			let safeIsSecond = c.secondItem as? UILayoutGuide === safeArea
			guard safeIsFirst || safeIsSecond else { continue }
			if c.firstAttribute == .top || c.firstAttribute == .bottom {
				c.constant = padding
			}
		}
	}

	private func setupConstraints() {
		let safeArea = contentView.safeAreaLayoutGuide
		// Collect storyboard constraints to deactivate. Priority mutation of required
		// constraints while active is a no-op in UIKit; deactivation is the correct approach.
		var toDeactivate: [NSLayoutConstraint] = []
		for c in contentView.constraints {
			// Horizontal constraints — replaced by our explicit leading/trailing anchors.
			if c.firstAttribute == .leading || c.firstAttribute == .trailing {
				toDeactivate.append(c)
			}
			// Storyboard top/bottom anchors that pin views to the safe area — replaced
			// by UILayoutGuide centering and explicit centerY constraints below.
			let involvesSafeArea = c.firstItem as? UILayoutGuide === safeArea
				|| c.secondItem as? UILayoutGuide === safeArea
			let touchesCentered = c.firstItem as? UIView === articleTitle
				|| c.secondItem as? UIView === articleTitle
				|| c.firstItem as? UIView === metaDataStackView
				|| c.secondItem as? UIView === metaDataStackView
				|| c.firstItem as? UIView === iconView
				|| c.secondItem as? UIView === iconView
				|| c.firstItem as? UIView === indicatorView
				|| c.secondItem as? UIView === indicatorView
			if involvesSafeArea && touchesCentered
				&& (c.firstAttribute == .top || c.firstAttribute == .bottom) {
				toDeactivate.append(c)
			}
		}
		NSLayoutConstraint.deactivate(toDeactivate)

		let iconLeading = iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
		let chevTrailing = chevronView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
		contentLeadingConstraint = iconLeading
		chevronTrailingConstraint = chevTrailing

		// Center the title+metadata group as a unit within the cell.
		let groupGuide = UILayoutGuide()
		contentView.addLayoutGuide(groupGuide)

		NSLayoutConstraint.activate([
			iconLeading,
			iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			indicatorView.trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
			indicatorView.topAnchor.constraint(equalTo: iconView.topAnchor, constant: -4),
			inlineDateLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
			inlineDateLabel.widthAnchor.constraint(equalToConstant: Assets.Colors.timelineDateColumnWidth),
			inlineDateLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			articleTitle.leadingAnchor.constraint(equalTo: inlineDateLabel.trailingAnchor, constant: 8),
			articleTitle.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -6),
			metaDataStackView.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -6),
			chevTrailing,
			chevronView.widthAnchor.constraint(equalToConstant: 10),
			chevronView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			groupGuide.topAnchor.constraint(equalTo: articleTitle.topAnchor),
			groupGuide.bottomAnchor.constraint(equalTo: metaDataStackView.bottomAnchor),
			groupGuide.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: Assets.Colors.timelineCellMinimumHeight),
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

		setIconImage(cellData.iconImage, with: cellData.iconSize)

		articleDate.text = cellData.dateString
		inlineDateLabel.text = cellData.inlineDateString
	}

	private func setIconImage(_ iconImage: IconImage?, with size: IconSize) {
		iconView.iconImage = iconImage
		updateIconViewSizeConstraints(to: size.size)
	}

	func setIconImage(_ iconImage: IconImage?) {
		iconView.iconImage = iconImage
	}

	private func updateIconViewSizeConstraints(to size: CGSize) {
		for constraint in iconView.constraints {
			constraint.isActive = false
		}

		NSLayoutConstraint.activate([
			iconView.widthAnchor.constraint(equalToConstant: size.width),
			iconView.heightAnchor.constraint(equalToConstant: size.height)
		])

		setNeedsLayout()
	}

	private func updateIndicatorView(_ cellData: MainTimelineCellData) {
		let dimReadArticles = AppDefaults.shared.timelineDimReadArticles
		if cellData.starred {
			if indicatorView.alpha == 0.0 {
				indicatorView.alpha = 1.0
			}
			setIndicatorViewSize(22)
			UIView.animate(withDuration: 0.25) {
				self.indicatorView.iconImage = Assets.Images.starredCellIndicator
				self.indicatorView.tintColor = .label
			}
			return
		} else if cellData.read == false && !dimReadArticles {
			if indicatorView.alpha == 0.0 {
				indicatorView.alpha = 1.0
			}
			setIndicatorViewSize(16)
			UIView.animate(withDuration: 0.25) {
				self.indicatorView.iconImage = Assets.Images.unreadCellIndicator
				self.indicatorView.tintColor = Assets.Colors.secondaryAccent
			}
			return
		} else if indicatorView.alpha == 1.0 {
			setIndicatorViewSize(16)
			UIView.animate(withDuration: 0.25) {
				self.indicatorView.alpha = 0.0
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
		contentLeadingConstraint?.constant = inset + 6
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
			if let selectionColor = Assets.Colors.cellSelectionColor {
				backgroundConfig.backgroundColor = selectionColor
			}
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
