//
//  MainFeedFooterView.swift
//  NetNewsWire-iOS
//
//  Created by Claude on 2026-01-27.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit

final class MainFeedFooterView: UICollectionReusableView {

	static let reuseIdentifier = "MainFeedFooterView"

	private let updateLabel: UILabel = {
		let label = UILabel()
		label.font = .preferredFont(forTextStyle: .footnote)
		label.textColor = .secondaryLabel
		label.textAlignment = .center
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}()

	var updateText: String? {
		didSet {
			updateLabel.text = updateText
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		setupViews()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setupViews()
	}

	private func setupViews() {
		addSubview(updateLabel)

		NSLayoutConstraint.activate([
			updateLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
			updateLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			updateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
			updateLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
		])
	}
}
