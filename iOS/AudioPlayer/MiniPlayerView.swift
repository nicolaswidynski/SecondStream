//
//  MiniPlayerView.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-23.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import UIKit
import Combine

final class MiniPlayerView: UIView {

	private let titleLabel: UILabel = {
		let label = UILabel()
		label.font = .systemFont(ofSize: 14, weight: .medium)
		label.textColor = .label
		label.numberOfLines = 1
		label.lineBreakMode = .byTruncatingTail
		return label
	}()

	private let playPauseButton: UIButton = {
		let button = UIButton(type: .system)
		button.tintColor = Assets.Colors.primaryAccent
		return button
	}()

	private let closeButton: UIButton = {
		let button = UIButton(type: .system)
		button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
		button.tintColor = .secondaryLabel
		return button
	}()

	private let activityIndicator: UIActivityIndicatorView = {
		let indicator = UIActivityIndicatorView(style: .medium)
		indicator.hidesWhenStopped = true
		return indicator
	}()

	private var cancellables = Set<AnyCancellable>()

	override init(frame: CGRect) {
		super.init(frame: frame)
		setupView()
		setupBindings()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setupView()
		setupBindings()
	}

	private func setupView() {
		backgroundColor = .secondarySystemBackground

		// Add shadow
		layer.shadowColor = UIColor.black.cgColor
		layer.shadowOffset = CGSize(width: 0, height: -2)
		layer.shadowOpacity = 0.1
		layer.shadowRadius = 4

		// Add subviews
		addSubview(playPauseButton)
		addSubview(titleLabel)
		addSubview(closeButton)
		addSubview(activityIndicator)

		// Layout
		playPauseButton.translatesAutoresizingMaskIntoConstraints = false
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		closeButton.translatesAutoresizingMaskIntoConstraints = false
		activityIndicator.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			playPauseButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			playPauseButton.centerYAnchor.constraint(equalTo: centerYAnchor),
			playPauseButton.widthAnchor.constraint(equalToConstant: 44),
			playPauseButton.heightAnchor.constraint(equalToConstant: 44),

			activityIndicator.centerXAnchor.constraint(equalTo: playPauseButton.centerXAnchor),
			activityIndicator.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),

			titleLabel.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 12),
			titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12),

			closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
			closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
			closeButton.widthAnchor.constraint(equalToConstant: 44),
			closeButton.heightAnchor.constraint(equalToConstant: 44),
		])

		// Actions
		playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
		closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

		updatePlayPauseButton(isPlaying: false)
	}

	private func setupBindings() {
		AudioPlayerManager.shared.$state
			.receive(on: DispatchQueue.main)
			.sink { [weak self] state in
				self?.updateForState(state)
			}
			.store(in: &cancellables)

		AudioPlayerManager.shared.$currentTitle
			.receive(on: DispatchQueue.main)
			.sink { [weak self] title in
				self?.titleLabel.text = title ?? "Playing..."
			}
			.store(in: &cancellables)
	}

	private func updateForState(_ state: AudioPlayerState) {
		switch state {
		case .idle:
			isHidden = true
		case .loading:
			isHidden = false
			playPauseButton.isHidden = true
			activityIndicator.startAnimating()
		case .playing:
			isHidden = false
			playPauseButton.isHidden = false
			activityIndicator.stopAnimating()
			updatePlayPauseButton(isPlaying: true)
		case .paused:
			isHidden = false
			playPauseButton.isHidden = false
			activityIndicator.stopAnimating()
			updatePlayPauseButton(isPlaying: false)
		case .error:
			isHidden = true
		}
	}

	private func updatePlayPauseButton(isPlaying: Bool) {
		let imageName = isPlaying ? "pause.fill" : "play.fill"
		let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
		playPauseButton.setImage(UIImage(systemName: imageName, withConfiguration: config), for: .normal)
	}

	@objc private func playPauseTapped() {
		AudioPlayerManager.shared.togglePlayPause()
	}

	@objc private func closeTapped() {
		AudioPlayerManager.shared.stop()
	}
}
