//
//  FloatingVideoPlayerView.swift
//  NetNewsWire
//
//  Created by Claude on 2026-02-12.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit
import WebKit

final class FloatingVideoPlayerView: UIView {

	private let webView: WKWebView = {
		let config = WKWebViewConfiguration()
		config.allowsInlineMediaPlayback = true
		config.mediaTypesRequiringUserActionForPlayback = []
		let webView = WKWebView(frame: .zero, configuration: config)
		webView.scrollView.isScrollEnabled = false
		webView.backgroundColor = .black
		return webView
	}()

	private let closeButton: UIButton = {
		let button = UIButton(type: .system)
		let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
		button.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: config), for: .normal)
		button.tintColor = .white
		button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
		button.layer.cornerRadius = 14
		return button
	}()

	private var currentVideoID: String?

	override init(frame: CGRect) {
		super.init(frame: frame)
		setupView()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setupView()
	}

	private func setupView() {
		backgroundColor = .black
		layer.cornerRadius = 8
		layer.masksToBounds = true

		// Add shadow to the container
		layer.shadowColor = UIColor.black.cgColor
		layer.shadowOffset = CGSize(width: 0, height: 2)
		layer.shadowOpacity = 0.3
		layer.shadowRadius = 4
		layer.masksToBounds = false

		addSubview(webView)
		addSubview(closeButton)

		webView.translatesAutoresizingMaskIntoConstraints = false
		closeButton.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			webView.topAnchor.constraint(equalTo: topAnchor),
			webView.leadingAnchor.constraint(equalTo: leadingAnchor),
			webView.trailingAnchor.constraint(equalTo: trailingAnchor),
			webView.bottomAnchor.constraint(equalTo: bottomAnchor),

			closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
			closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
			closeButton.widthAnchor.constraint(equalToConstant: 28),
			closeButton.heightAnchor.constraint(equalToConstant: 28),
		])

		closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

		// Clip the webView content
		webView.layer.cornerRadius = 8
		webView.layer.masksToBounds = true
	}

	func loadYouTubeVideo(videoID: String) {
		currentVideoID = videoID

		// Use YouTube's embed URL with autoplay
		let embedHTML = """
		<!DOCTYPE html>
		<html>
		<head>
			<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
			<style>
				* { margin: 0; padding: 0; }
				html, body { width: 100%; height: 100%; background: black; overflow: hidden; }
				iframe { width: 100%; height: 100%; border: none; }
			</style>
		</head>
		<body>
			<iframe
				src="https://www.youtube.com/embed/\(videoID)?autoplay=1&playsinline=1&rel=0&modestbranding=1"
				allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
				allowfullscreen>
			</iframe>
		</body>
		</html>
		"""

		webView.loadHTMLString(embedHTML, baseURL: URL(string: "https://www.youtube.com"))
		isHidden = false
	}

	func stop() {
		webView.loadHTMLString("", baseURL: nil)
		currentVideoID = nil
		isHidden = true
	}

	@objc private func closeTapped() {
		stop()
	}
}
