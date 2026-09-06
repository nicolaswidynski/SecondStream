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

	private let inlineDateLabel: UILabel = {
		let label = UILabel()
		label.numberOfLines = 2
		label.font = UIFont.preferredFont(forTextStyle: .caption1)
		label.textColor = .secondaryLabel
		label.textAlignment = .center
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}()

	private let readingTimeMinLabel: UILabel = {
		let label = UILabel()
		label.font = UIFont.preferredFont(forTextStyle: .caption2)
		label.textColor = .label
		label.textAlignment = .center
		return label
	}()

	private lazy var readingTimeView: UIStackView = {
		let iconConfig = UIImage.SymbolConfiguration(pointSize: 10, weight: .regular)
		let icon = UIImageView(image: UIImage(systemName: "book", withConfiguration: iconConfig))
		icon.tintColor = .label
		icon.contentMode = .center
		let stack = UIStackView(arrangedSubviews: [icon, readingTimeMinLabel])
		stack.axis = .vertical
		stack.spacing = 2
		stack.alignment = .center
		stack.translatesAutoresizingMaskIntoConstraints = false
		return stack
	}()

	var cellData: MainTimelineCellData! {
		didSet {
			configure(cellData)
		}
	}

	var isPreview: Bool = false

	private var contentLeadingConstraint: NSLayoutConstraint?
	private var dateLabelWidthConstraint: NSLayoutConstraint?
	private var topPaddingConstraint: NSLayoutConstraint?
	private var bottomPaddingConstraint: NSLayoutConstraint?
	private var titleTrailingConstraint: NSLayoutConstraint?
	private var minimumHeightConstraint: NSLayoutConstraint?


	private func scaledDateColumnWidth() -> CGFloat {
		let base = Assets.Colors.timelineDateColumnWidth
		return max(base, UIFontMetrics(forTextStyle: .caption1).scaledValue(for: base))
	}

	private func scaledVerticalPadding() -> CGFloat {
		let base = Assets.Colors.timelineCellVerticalPadding
		return max(base, UIFontMetrics(forTextStyle: .caption1).scaledValue(for: base))
	}

	override func awakeFromNib() {
		MainActor.assumeIsolated {
			super.awakeFromNib()
			indicatorView.alpha = 0.0
			configureStackView()
			articleDate.isHidden = true
			contentView.addSubview(inlineDateLabel)
			contentView.addSubview(readingTimeView)
			readingTimeView.isHidden = true
			setupConstraints()
			registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: MainTimelineIconFeedCell, _: UITraitCollection) in
				self.configureStackView()
				self.dateLabelWidthConstraint?.constant = self.scaledDateColumnWidth()
				let vPad = self.scaledVerticalPadding()
				self.topPaddingConstraint?.constant = vPad
				self.bottomPaddingConstraint?.constant = vPad
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
		let titleTrailing = articleTitle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
		contentLeadingConstraint = iconLeading
		titleTrailingConstraint = titleTrailing

		let dateWidth = inlineDateLabel.widthAnchor.constraint(equalToConstant: scaledDateColumnWidth())
		dateLabelWidthConstraint = dateWidth

		// Center the title+metadata group as a unit within the cell.
		let groupGuide = UILayoutGuide()
		contentView.addLayoutGuide(groupGuide)

		let topPad = groupGuide.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: scaledVerticalPadding())
		let bottomPad = contentView.bottomAnchor.constraint(greaterThanOrEqualTo: groupGuide.bottomAnchor, constant: scaledVerticalPadding())
		topPaddingConstraint = topPad
		bottomPaddingConstraint = bottomPad

		NSLayoutConstraint.activate([
			iconLeading,
			iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			indicatorView.trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
			indicatorView.topAnchor.constraint(equalTo: iconView.topAnchor, constant: -4),
			inlineDateLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
			dateWidth,
			inlineDateLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			articleTitle.leadingAnchor.constraint(equalTo: inlineDateLabel.trailingAnchor, constant: 8),
			titleTrailing,
			metaDataStackView.trailingAnchor.constraint(equalTo: articleTitle.trailingAnchor),
			groupGuide.topAnchor.constraint(equalTo: articleTitle.topAnchor),
			groupGuide.bottomAnchor.constraint(equalTo: metaDataStackView.bottomAnchor),
			groupGuide.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			topPad,
			bottomPad,
		])

		NSLayoutConstraint.activate([
			readingTimeView.centerXAnchor.constraint(equalTo: inlineDateLabel.centerXAnchor),
			readingTimeView.centerYAnchor.constraint(equalTo: inlineDateLabel.centerYAnchor),
		])

		let minH = contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: Assets.Colors.timelineCellMinimumHeight)
		minH.isActive = true
		minimumHeightConstraint = minH
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

		if let minutes = cellData.readingTimeMinutes {
			readingTimeMinLabel.text = "\(minutes) min"
			readingTimeMinLabel.isHidden = false
		} else {
			readingTimeMinLabel.isHidden = true
		}
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
		if cellData.starred {
			if indicatorView.alpha == 0.0 { indicatorView.alpha = 1.0 }
			setIndicatorViewSize(22)
			UIView.animate(withDuration: 0.25) {
				self.indicatorView.iconImage = Assets.Images.starredCellIndicator
				self.indicatorView.tintColor = .label
			}
			inlineDateLabel.isHidden = false
			readingTimeView.isHidden = true
		} else if cellData.read == false {
			// Unread: book icon + reading time replaces the date entirely.
			if indicatorView.alpha == 0.0 { indicatorView.alpha = 1.0 }
			setIndicatorViewSize(16)
			UIView.animate(withDuration: 0.25) {
				self.indicatorView.iconImage = Assets.Images.unreadCellIndicator
				self.indicatorView.tintColor = Assets.Colors.secondaryAccent
			}
			inlineDateLabel.isHidden = true
			readingTimeView.isHidden = false
		} else {
			if indicatorView.alpha == 1.0 {
				setIndicatorViewSize(16)
				UIView.animate(withDuration: 0.25) {
					self.indicatorView.alpha = 0.0
					self.indicatorView.iconImage = nil
				}
			}
			inlineDateLabel.isHidden = false
			readingTimeView.isHidden = true
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
		if isSelected && Assets.Colors.cellSelectionColor != nil {
			return .label
		} else if AppDefaults.shared.timelineDimReadArticles, cellData?.read == true {
			return Assets.Colors.readArticleTitle
		} else {
			return .label
		}
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		let inset = (bounds.width * 0.05).rounded()
		contentLeadingConstraint?.constant = inset + 6
		titleTrailingConstraint?.constant = -(inset + 12)
	}

	override func systemLayoutSizeFitting(
		_ targetSize: CGSize,
		withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
		verticalFittingPriority: UILayoutPriority
	) -> CGSize {
		// Force layout so articleTitle.frame reflects actual rendered height.
		setNeedsLayout()
		layoutIfNeeded()
		let font = UIFont.preferredFont(forTextStyle: .body)
		let isMultiLine = articleTitle.frame.height > ceil(font.lineHeight) * 1.5
		if minimumHeightConstraint?.isActive != !isMultiLine {
			minimumHeightConstraint?.isActive = !isMultiLine
		}
		return super.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: horizontalFittingPriority, verticalFittingPriority: verticalFittingPriority)
	}

	override func updateConfiguration(using state: UICellConfigurationState) {
		super.updateConfiguration(using: state)

		var backgroundConfig = UIBackgroundConfiguration.listCell().updated(for: state)
		backgroundConfig.edgesAddingLayoutMarginsToBackgroundInsets = []
		let hInset = (bounds.width * 0.05).rounded()
		backgroundConfig.backgroundInsets = NSDirectionalEdgeInsets(top: 0, leading: hInset, bottom: 0, trailing: hInset)
		backgroundConfig.cornerRadius = Assets.Colors.cellCornerRadius

		let normalBg: UIColor = Assets.Colors.TimelineSceneContentTableColor
		if state.isSelected || state.isHighlighted || state.isFocused || state.isSwiped {
			backgroundConfig.backgroundColor = Assets.Colors.cellSelectionColor ?? normalBg
			applyTitleTextWithAttributes(state)
			articleDate.textColor = .secondaryLabel
			authorByLine.textColor = .secondaryLabel
			inlineDateLabel.textColor = .secondaryLabel
			readingTimeMinLabel.textColor = titleTextColor(for: state)
			readingTimeView.tintColor = titleTextColor(for: state)
		} else {
			backgroundConfig.backgroundColor = normalBg
			applyTitleTextWithAttributes(state)
			articleDate.textColor = .secondaryLabel
			authorByLine.textColor = .secondaryLabel
			inlineDateLabel.textColor = .secondaryLabel
			readingTimeMinLabel.textColor = titleTextColor(for: state)
			readingTimeView.tintColor = titleTextColor(for: state)
		}

		self.backgroundConfiguration = backgroundConfig
	}

}
