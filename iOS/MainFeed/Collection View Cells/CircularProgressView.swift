//
//  CircularProgressView.swift
//  NetNewsWire-iOS
//
//  Created by Claude on 2026-04-02.
//  Copyright © 2026 STDN. All rights reserved.
//

import UIKit

/// A small deterministic circular progress ring.
///
/// Set `progress` (0.0–1.0) to update the fill. The ring always shows the track
/// (background circle) and the filled arc rotates from 12 o'clock clockwise.
final class CircularProgressView: UIView {

	// MARK: - Public

	/// Progress fraction, 0.0 to 1.0. Animates the stroke end.
	var progress: CGFloat = 0 {
		didSet {
			let clamped = max(0, min(1, progress))
			progressLayer.strokeEnd = clamped
		}
	}

	/// Color of the filled arc. Defaults to the app's secondary accent.
	var progressColor: UIColor = Assets.Colors.secondaryAccent {
		didSet { progressLayer.strokeColor = progressColor.cgColor }
	}

	/// Color of the unfilled track. Defaults to a light gray.
	var trackColor: UIColor = UIColor.systemGray4 {
		didSet { trackLayer.strokeColor = trackColor.cgColor }
	}

	// MARK: - Layers

	private let trackLayer = CAShapeLayer()
	private let progressLayer = CAShapeLayer()

	// MARK: - Init

	override init(frame: CGRect) {
		super.init(frame: frame)
		setup()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setup()
	}

	private func setup() {
		backgroundColor = .clear
		isOpaque = false

		for layer in [trackLayer, progressLayer] {
			layer.fillColor = UIColor.clear.cgColor
			layer.lineWidth = 2.5
			layer.lineCap = .round
			self.layer.addSublayer(layer)
		}

		trackLayer.strokeColor = trackColor.cgColor
		trackLayer.strokeEnd = 1

		progressLayer.strokeColor = progressColor.cgColor
		progressLayer.strokeEnd = 0
		// Start at 12 o'clock (top) and go clockwise
		progressLayer.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		let center = CGPoint(x: bounds.midX, y: bounds.midY)
		let radius = (min(bounds.width, bounds.height) - trackLayer.lineWidth) / 2
		let path = UIBezierPath(arcCenter: center,
								radius: radius,
								startAngle: 0,
								endAngle: .pi * 2,
								clockwise: true)
		trackLayer.path = path.cgPath
		trackLayer.frame = bounds

		progressLayer.path = path.cgPath
		progressLayer.frame = bounds
		progressLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
		progressLayer.position = center
	}

	override var intrinsicContentSize: CGSize {
		CGSize(width: 22, height: 22)
	}
}
