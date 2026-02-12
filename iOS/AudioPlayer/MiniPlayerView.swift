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
		label.textAlignment = .center
		return label
	}()

	private let currentTimeLabel: UILabel = {
		let label = UILabel()
		label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
		label.textColor = .secondaryLabel
		label.text = "0:00"
		return label
	}()

	private let durationLabel: UILabel = {
		let label = UILabel()
		label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
		label.textColor = .secondaryLabel
		label.text = "0:00"
		label.textAlignment = .right
		return label
	}()

	private let timeSlider: UISlider = {
		let slider = UISlider()
		slider.minimumValue = 0
		slider.maximumValue = 1
		slider.value = 0
		slider.minimumTrackTintColor = Assets.Colors.primaryAccent
		slider.maximumTrackTintColor = .systemGray4
		return slider
	}()

	private let skipBackwardButton: UIButton = {
		let button = UIButton(type: .system)
		let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
		button.setImage(UIImage(systemName: "gobackward.10", withConfiguration: config), for: .normal)
		button.tintColor = Assets.Colors.primaryAccent
		return button
	}()

	private let playPauseButton: UIButton = {
		let button = UIButton(type: .system)
		button.tintColor = Assets.Colors.primaryAccent
		return button
	}()

	private let skipForwardButton: UIButton = {
		let button = UIButton(type: .system)
		let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
		button.setImage(UIImage(systemName: "goforward.10", withConfiguration: config), for: .normal)
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

	private let controlsStack: UIStackView = {
		let stack = UIStackView()
		stack.axis = .horizontal
		stack.alignment = .center
		stack.distribution = .equalSpacing
		stack.spacing = 16
		return stack
	}()

	private var cancellables = Set<AnyCancellable>()
	private var isSeeking = false

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

		// Setup controls stack
		controlsStack.addArrangedSubview(skipBackwardButton)
		controlsStack.addArrangedSubview(playPauseButton)
		controlsStack.addArrangedSubview(skipForwardButton)

		// Add subviews
		addSubview(titleLabel)
		addSubview(currentTimeLabel)
		addSubview(timeSlider)
		addSubview(durationLabel)
		addSubview(controlsStack)
		addSubview(closeButton)
		addSubview(activityIndicator)

		// Layout
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		currentTimeLabel.translatesAutoresizingMaskIntoConstraints = false
		timeSlider.translatesAutoresizingMaskIntoConstraints = false
		durationLabel.translatesAutoresizingMaskIntoConstraints = false
		controlsStack.translatesAutoresizingMaskIntoConstraints = false
		closeButton.translatesAutoresizingMaskIntoConstraints = false
		activityIndicator.translatesAutoresizingMaskIntoConstraints = false
		skipBackwardButton.translatesAutoresizingMaskIntoConstraints = false
		playPauseButton.translatesAutoresizingMaskIntoConstraints = false
		skipForwardButton.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			// Title at top
			titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
			titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),

			// Time slider row
			currentTimeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
			currentTimeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			currentTimeLabel.widthAnchor.constraint(equalToConstant: 45),

			timeSlider.centerYAnchor.constraint(equalTo: currentTimeLabel.centerYAnchor),
			timeSlider.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: 8),
			timeSlider.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -8),

			durationLabel.centerYAnchor.constraint(equalTo: currentTimeLabel.centerYAnchor),
			durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
			durationLabel.widthAnchor.constraint(equalToConstant: 45),

			// Controls below slider
			controlsStack.centerXAnchor.constraint(equalTo: centerXAnchor),
			controlsStack.topAnchor.constraint(equalTo: timeSlider.bottomAnchor, constant: 8),
			controlsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

			// Button sizes
			skipBackwardButton.widthAnchor.constraint(equalToConstant: 44),
			skipBackwardButton.heightAnchor.constraint(equalToConstant: 44),
			playPauseButton.widthAnchor.constraint(equalToConstant: 44),
			playPauseButton.heightAnchor.constraint(equalToConstant: 44),
			skipForwardButton.widthAnchor.constraint(equalToConstant: 44),
			skipForwardButton.heightAnchor.constraint(equalToConstant: 44),

			// Activity indicator
			activityIndicator.centerXAnchor.constraint(equalTo: playPauseButton.centerXAnchor),
			activityIndicator.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),

			// Close button at top right
			closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
			closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
			closeButton.widthAnchor.constraint(equalToConstant: 36),
			closeButton.heightAnchor.constraint(equalToConstant: 36),
		])

		// Actions
		playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
		skipBackwardButton.addTarget(self, action: #selector(skipBackwardTapped), for: .touchUpInside)
		skipForwardButton.addTarget(self, action: #selector(skipForwardTapped), for: .touchUpInside)
		closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
		timeSlider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
		timeSlider.addTarget(self, action: #selector(sliderTouchBegan), for: .touchDown)
		timeSlider.addTarget(self, action: #selector(sliderTouchEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])

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

		AudioPlayerManager.shared.$currentPlaybackTime
			.receive(on: DispatchQueue.main)
			.sink { [weak self] time in
				guard let self, !self.isSeeking else {
					return
				}
				self.currentTimeLabel.text = self.formatTime(time)
				let duration = AudioPlayerManager.shared.totalDuration
				if duration > 0 {
					self.timeSlider.value = Float(time / duration)
				}
			}
			.store(in: &cancellables)

		AudioPlayerManager.shared.$totalDuration
			.receive(on: DispatchQueue.main)
			.sink { [weak self] duration in
				self?.durationLabel.text = self?.formatTime(duration) ?? "0:00"
			}
			.store(in: &cancellables)
	}

	private func formatTime(_ seconds: Double) -> String {
		guard seconds.isFinite && seconds >= 0 else {
			return "0:00"
		}
		let totalSeconds = Int(seconds)
		let hours = totalSeconds / 3600
		let minutes = (totalSeconds % 3600) / 60
		let secs = totalSeconds % 60

		if hours > 0 {
			return String(format: "%d:%02d:%02d", hours, minutes, secs)
		} else {
			return String(format: "%d:%02d", minutes, secs)
		}
	}

	private func updateForState(_ state: AudioPlayerState) {
		switch state {
		case .idle:
			isHidden = true
		case .loading:
			isHidden = false
			playPauseButton.isHidden = true
			skipBackwardButton.isEnabled = false
			skipForwardButton.isEnabled = false
			timeSlider.isEnabled = false
			activityIndicator.startAnimating()
		case .playing:
			isHidden = false
			playPauseButton.isHidden = false
			skipBackwardButton.isEnabled = true
			skipForwardButton.isEnabled = true
			timeSlider.isEnabled = true
			activityIndicator.stopAnimating()
			updatePlayPauseButton(isPlaying: true)
		case .paused:
			isHidden = false
			playPauseButton.isHidden = false
			skipBackwardButton.isEnabled = true
			skipForwardButton.isEnabled = true
			timeSlider.isEnabled = true
			activityIndicator.stopAnimating()
			updatePlayPauseButton(isPlaying: false)
		case .error:
			isHidden = true
		}
	}

	private func updatePlayPauseButton(isPlaying: Bool) {
		let imageName = isPlaying ? "pause.fill" : "play.fill"
		let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
		playPauseButton.setImage(UIImage(systemName: imageName, withConfiguration: config), for: .normal)
	}

	@objc private func playPauseTapped() {
		AudioPlayerManager.shared.togglePlayPause()
	}

	@objc private func skipBackwardTapped() {
		AudioPlayerManager.shared.skipBackward(10)
	}

	@objc private func skipForwardTapped() {
		AudioPlayerManager.shared.skipForward(10)
	}

	@objc private func closeTapped() {
		AudioPlayerManager.shared.stop()
	}

	@objc private func sliderTouchBegan() {
		isSeeking = true
	}

	@objc private func sliderValueChanged() {
		let duration = AudioPlayerManager.shared.totalDuration
		let newTime = Double(timeSlider.value) * duration
		currentTimeLabel.text = formatTime(newTime)
	}

	@objc private func sliderTouchEnded() {
		let duration = AudioPlayerManager.shared.totalDuration
		let newTime = Double(timeSlider.value) * duration
		AudioPlayerManager.shared.seek(to: newTime)
		isSeeking = false
	}
}
