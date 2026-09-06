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

	// The date column anchors everything. The indicator is not in the layout chain —
	// it's positioned relative to the date label without consuming horizontal space:
	//   - bookmark   → centered in the date column (date hidden)
	//   - unread dot → just to the left of the date column
	private var dateLabelLeadingConstraint: NSLayoutConstraint?
	private var dateLabelWidthConstraint: NSLayoutConstraint?
	private var topPaddingConstraint: NSLayoutConstraint?
	private var bottomPaddingConstraint: NSLayoutConstraint?
	private var indicatorCenterXConstraint: NSLayoutConstraint?
	private var titleTrailingConstraint: NSLayoutConstraint?
	private var minimumHeightConstraint: NSLayoutConstraint?
	private var isStarred = false


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
			registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: MainTimelineFeedCell, _: UITraitCollection) in
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
			// Indicatorview vertical constraints — we control its position via centerX/centerY.
			let touchesIndicator = c.firstItem as? UIView === indicatorView
				|| c.secondItem as? UIView === indicatorView
			if touchesIndicator,
			   c.firstAttribute == .top || c.firstAttribute == .bottom || c.firstAttribute == .centerY {
				toDeactivate.append(c)
			}
			// Storyboard top/bottom anchors that pin articleTitle/metaDataStackView to the
			// safe area — replaced by a UILayoutGuide centering constraint below.
			let involvesSafeArea = c.firstItem as? UILayoutGuide === safeArea
				|| c.secondItem as? UILayoutGuide === safeArea
			let touchesGroup = c.firstItem as? UIView === articleTitle
				|| c.secondItem as? UIView === articleTitle
				|| c.firstItem as? UIView === metaDataStackView
				|| c.secondItem as? UIView === metaDataStackView
			if involvesSafeArea && touchesGroup
				&& (c.firstAttribute == .top || c.firstAttribute == .bottom) {
				toDeactivate.append(c)
			}
		}
		NSLayoutConstraint.deactivate(toDeactivate)

		let dateLeading = inlineDateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
		let indCenterX = indicatorView.centerXAnchor.constraint(equalTo: inlineDateLabel.centerXAnchor)
		let titleTrailing = articleTitle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
		dateLabelLeadingConstraint = dateLeading
		indicatorCenterXConstraint = indCenterX
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
			dateLeading,
			dateWidth,
			inlineDateLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			indCenterX,
			indicatorView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			articleTitle.leadingAnchor.constraint(equalTo: inlineDateLabel.trailingAnchor, constant: 8),
			titleTrailing,
			metaDataStackView.leadingAnchor.constraint(equalTo: articleTitle.leadingAnchor),
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

		articleDate.text = cellData.dateString
		inlineDateLabel.text = cellData.inlineDateString

		if let minutes = cellData.readingTimeMinutes {
			readingTimeMinLabel.text = "\(minutes) min"
			readingTimeMinLabel.isHidden = false
		} else {
			readingTimeMinLabel.isHidden = true
		}
	}

	private func updateIndicatorView(_ cellData: MainTimelineCellData) {
		let wasStarred = isStarred

		if cellData.starred {
			isStarred = true
			setIndicatorViewSize(22)
			indicatorView.iconImage = Assets.Images.starredCellIndicator
			indicatorView.tintColor = .label
			indicatorCenterXConstraint?.isActive = false
			indicatorCenterXConstraint = indicatorView.centerXAnchor.constraint(equalTo: inlineDateLabel.centerXAnchor)
			indicatorCenterXConstraint?.isActive = true
			UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
				self.indicatorView.alpha = 1.0
				self.inlineDateLabel.alpha = 0.0
				self.readingTimeView.alpha = 0.0
				self.contentView.layoutIfNeeded()
			} completion: { _ in
				self.inlineDateLabel.isHidden = true
				self.inlineDateLabel.alpha = 1.0
				self.readingTimeView.isHidden = true
				self.readingTimeView.alpha = 1.0
			}

		} else if cellData.read == false {
			// Unread: book icon + reading time replaces the date entirely.
			isStarred = false
			indicatorCenterXConstraint?.isActive = false
			indicatorCenterXConstraint = indicatorView.centerXAnchor.constraint(equalTo: inlineDateLabel.centerXAnchor)
			indicatorCenterXConstraint?.isActive = true

			inlineDateLabel.isHidden = true
			readingTimeView.isHidden = false

			if wasStarred {
				readingTimeView.alpha = 0.0
				UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
					self.indicatorView.alpha = 0.0
					self.contentView.layoutIfNeeded()
				} completion: { _ in
					UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
						self.readingTimeView.alpha = 1.0
					}
				}
			} else {
				UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
					self.indicatorView.alpha = 0.0
					self.contentView.layoutIfNeeded()
				}
			}

		} else {
			// Read (or dimmed): show date, hide indicator and reading time.
			isStarred = false
			readingTimeView.isHidden = true

			if wasStarred {
				// Phase 1: fade out bookmark.
				inlineDateLabel.alpha = 0.0
				inlineDateLabel.isHidden = false
				UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
					self.indicatorView.alpha = 0.0
				} completion: { _ in
					self.indicatorView.iconImage = nil
					// Phase 2: fade in date.
					UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
						self.inlineDateLabel.alpha = 1.0
					}
				}
			} else {
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
		dateLabelLeadingConstraint?.constant = inset + 6
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
