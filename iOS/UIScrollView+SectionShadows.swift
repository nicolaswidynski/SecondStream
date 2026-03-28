//
//  UIScrollView+SectionShadows.swift
//  NetNewsWire
//
//  One shadow view per section, positioned behind cells using frame unions.
//  Views are subviews of the scroll view so they scroll with content automatically.

import UIKit

extension UITableView {

	/// Creates / updates one shadow `UIView` per section, placed behind all cells.
	/// Call from `viewDidLayoutSubviews()` and `traitCollectionDidChange(_:)`.
	func layoutSectionCardShadows(in views: inout [UIView]) {
		let sectionCount = numberOfSections

		while views.count < sectionCount {
			let v = UIView()
			v.backgroundColor = .clear
			v.isUserInteractionEnabled = false
			views.append(v)
		}

		for section in 0..<sectionCount {
			let rowCount = numberOfRows(inSection: section)
			let v = views[section]

			guard rowCount > 0 else {
				v.removeFromSuperview()
				continue
			}

			let firstRect = rectForRow(at: IndexPath(row: 0, section: section))
			let lastRect = rectForRow(at: IndexPath(row: rowCount - 1, section: section))
			v.frame = firstRect.union(lastRect)

			Assets.Colors.applyForegroundShadow(to: v.layer, traitCollection: traitCollection)
			v.layer.shadowPath = UIBezierPath(
				roundedRect: v.bounds,
				cornerRadius: Assets.Colors.shadowTablesCornerRadius
			).cgPath

			if v.superview == nil {
				insertSubview(v, at: 0)
			}
			sendSubviewToBack(v)
		}
	}
}

extension UICollectionView {

	/// Creates / updates one shadow `UIView` per section, placed behind all cells.
	/// Call from `viewDidLayoutSubviews()` and `traitCollectionDidChange(_:)`.
	func layoutSectionCardShadows(in views: inout [UIView]) {
		let sectionCount = numberOfSections

		while views.count < sectionCount {
			let v = UIView()
			v.backgroundColor = .clear
			v.isUserInteractionEnabled = false
			views.append(v)
		}

		for section in 0..<sectionCount {
			let itemCount = numberOfItems(inSection: section)
			let v = views[section]

			guard itemCount > 0,
				  let firstAttrs = layoutAttributesForItem(at: IndexPath(item: 0, section: section)),
				  let lastAttrs  = layoutAttributesForItem(at: IndexPath(item: itemCount - 1, section: section))
			else {
				v.removeFromSuperview()
				continue
			}

			v.frame = firstAttrs.frame.union(lastAttrs.frame)

			Assets.Colors.applyForegroundShadow(to: v.layer, traitCollection: traitCollection)
			v.layer.shadowPath = UIBezierPath(
				roundedRect: v.bounds,
				cornerRadius: Assets.Colors.shadowTablesCornerRadius
			).cgPath

			if v.superview == nil {
				insertSubview(v, at: 0)
			}
			sendSubviewToBack(v)
		}
	}
}
