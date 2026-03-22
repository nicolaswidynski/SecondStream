//
//  SectionIndexView.swift
//  NetNewsWire
//
//  Created by Claude on 2026-02-13.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit

final class SectionIndexView: UIView {

	var onSelectLetter: ((String) -> Void)?

	private var letters: [String] = []
	private var letterLabels: [UILabel] = []
	private let stackView: UIStackView = {
		let sv = UIStackView()
		sv.axis = .vertical
		sv.alignment = .center
		sv.distribution = .equalSpacing
		sv.spacing = 0
		sv.translatesAutoresizingMaskIntoConstraints = false
		return sv
	}()

	private let feedbackGenerator = UISelectionFeedbackGenerator()

	override init(frame: CGRect) {
		super.init(frame: frame)
		addSubview(stackView)
		NSLayoutConstraint.activate([
			stackView.topAnchor.constraint(equalTo: topAnchor),
			stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
			stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
			stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
		])

		let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
		addGestureRecognizer(pan)

		let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
		addGestureRecognizer(tap)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(letters: [String]) {
		self.letters = letters
		letterLabels.forEach { $0.removeFromSuperview() }
		letterLabels.removeAll()

		for letter in letters {
			let label = UILabel()
			label.text = letter
			label.font = .systemFont(ofSize: 11, weight: .medium)
			label.textColor = Assets.Colors.primaryAccent
			label.textAlignment = .center
			stackView.addArrangedSubview(label)
			letterLabels.append(label)
		}
	}

	@objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
		if gesture.state == .began {
			feedbackGenerator.prepare()
		}
		selectLetter(at: gesture.location(in: self))
	}

	@objc private func handleTap(_ gesture: UITapGestureRecognizer) {
		selectLetter(at: gesture.location(in: self))
	}

	private func selectLetter(at point: CGPoint) {
		guard !letters.isEmpty else {
			return
		}
		let fraction = max(0, min(point.y / bounds.height, 1.0))
		let index = Int(fraction * CGFloat(letters.count - 1))
		let clampedIndex = max(0, min(index, letters.count - 1))
		feedbackGenerator.selectionChanged()
		onSelectLetter?(letters[clampedIndex])
	}
}
