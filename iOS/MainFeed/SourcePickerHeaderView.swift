//
//  SourcePickerHeaderView.swift
//  NetNewsWire
//
//  Created by Claude on 2026-02-13.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit

final class SourcePickerHeaderView: UICollectionReusableView {

	static let reuseIdentifier = "SourcePickerHeaderView"

	private var onInfoTapped: (() -> Void)?

	private let label: UILabel = {
		let label = UILabel()
		label.font = .preferredFont(forTextStyle: .headline)
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}()

	private let infoButton: UIButton = {
		let symbolConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .regular)
		let button = UIButton(type: .system)
		button.setImage(UIImage(systemName: "info.circle", withConfiguration: symbolConfig), for: .normal)
		button.tintColor = .secondaryLabel
		button.translatesAutoresizingMaskIntoConstraints = false
		button.isHidden = true
		return button
	}()

	private let stackView: UIStackView = {
		let stack = UIStackView()
		stack.axis = .horizontal
		stack.alignment = .top
		stack.spacing = 4
		stack.translatesAutoresizingMaskIntoConstraints = false
		return stack
	}()

	override init(frame: CGRect) {
		super.init(frame: frame)

		stackView.addArrangedSubview(label)
		stackView.addArrangedSubview(infoButton)
		addSubview(stackView)

		NSLayoutConstraint.activate([
			stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
			stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
		])

		infoButton.addAction(UIAction { [weak self] _ in
			self?.onInfoTapped?()
		}, for: .touchUpInside)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(title: String, showsInfoButton: Bool = false, onInfoTapped: (() -> Void)? = nil) {
		label.text = title
		infoButton.isHidden = !showsInfoButton
		self.onInfoTapped = onInfoTapped
	}
}
