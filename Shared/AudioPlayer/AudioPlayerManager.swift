//
//  AudioPlayerManager.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-23.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import AVFoundation
import MediaPlayer
import os.log

enum AudioPlayerState {
	case idle
	case loading
	case playing
	case paused
	case error(String)
}

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {

	static let shared = AudioPlayerManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AudioPlayer")

	@Published private(set) var state: AudioPlayerState = .idle
	@Published private(set) var currentTitle: String?
	@Published private(set) var currentMP3URL: String?
	@Published private(set) var currentPlaybackTime: Double = 0
	@Published private(set) var totalDuration: Double = 0

	private var player: AVPlayer?
	private var playerItem: AVPlayerItem?
	private var periodicTimeObserver: Any?
	private var boundaryObserver: Any?
	private var pendingStartTime: Double?
	private var endTime: Double?

	private override init() {
		super.init()
		setupRemoteCommandCenter()
	}

	// MARK: - Audio Session

	private func activateAudioSession() {
		#if os(iOS)
		do {
			try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
			try AVAudioSession.sharedInstance().setActive(true)
		} catch {
			Self.logger.error("Failed to activate audio session: \(error.localizedDescription)")
		}
		#endif
	}

	private func deactivateAudioSession() {
		#if os(iOS)
		do {
			try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
		} catch {
			Self.logger.error("Failed to deactivate audio session: \(error.localizedDescription)")
		}
		#endif
	}

	// MARK: - Remote Command Center (Lock Screen Controls)

	private func setupRemoteCommandCenter() {
		let commandCenter = MPRemoteCommandCenter.shared()

		commandCenter.playCommand.addTarget { [weak self] _ in
			self?.play()
			return .success
		}

		commandCenter.pauseCommand.addTarget { [weak self] _ in
			self?.pause()
			return .success
		}

		commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
			self?.togglePlayPause()
			return .success
		}

		commandCenter.skipForwardCommand.preferredIntervals = [10]
		commandCenter.skipForwardCommand.addTarget { [weak self] _ in
			self?.skipForward(10)
			return .success
		}

		commandCenter.skipBackwardCommand.preferredIntervals = [10]
		commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
			self?.skipBackward(10)
			return .success
		}
	}

	private func updateNowPlayingInfo() {
		var nowPlayingInfo = [String: Any]()
		nowPlayingInfo[MPMediaItemPropertyTitle] = currentTitle ?? "Podcast"
		nowPlayingInfo[MPMediaItemPropertyArtist] = "Second Stream"

		if let player, let currentItem = player.currentItem {
			let duration = currentItem.duration
			if duration.isNumeric {
				nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = CMTimeGetSeconds(duration)
			}
			nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = CMTimeGetSeconds(player.currentTime())
			nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
		}

		MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
	}

	// MARK: - Playback Controls

	func loadAndPlay(url: String, title: String?, startTime: Double = 0, endTime: Double? = nil) {
		guard let audioURL = URL(string: url) else {
			state = .error("Invalid URL")
			return
		}

		// Stop current playback
		stop()

		// Activate audio session when starting playback
		activateAudioSession()

		currentMP3URL = url
		currentTitle = title
		self.pendingStartTime = startTime > 0 ? startTime : nil
		self.endTime = endTime
		state = .loading

		Self.logger.info("Loading audio: \(url) startTime: \(startTime)")

		playerItem = AVPlayerItem(url: audioURL)
		player = AVPlayer(playerItem: playerItem)

		// Observe when ready to play
		playerItem?.addObserver(self, forKeyPath: "status", options: [.new], context: nil)

		// Observe playback end
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(playerDidFinishPlaying),
			name: .AVPlayerItemDidPlayToEndTime,
			object: playerItem
		)
	}

	func play() {
		player?.play()
		state = .playing
		setupPeriodicTimeObserver()
		updateNowPlayingInfo()
	}

	func pause() {
		player?.pause()
		state = .paused
		updateNowPlayingInfo()
	}

	func togglePlayPause() {
		switch state {
		case .playing:
			pause()
		case .paused:
			play()
		case .idle:
			if let url = currentMP3URL {
				loadAndPlay(url: url, title: currentTitle)
			}
		default:
			break
		}
	}

	func stop() {
		player?.pause()
		removeTimeObservers()
		playerItem?.removeObserver(self, forKeyPath: "status")
		NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
		player = nil
		playerItem = nil
		pendingStartTime = nil
		endTime = nil
		currentPlaybackTime = 0
		totalDuration = 0
		state = .idle
		MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

		// Deactivate audio session to allow other apps to resume
		deactivateAudioSession()
	}

	private func removeTimeObservers() {
		if let periodicTimeObserver, let player {
			player.removeTimeObserver(periodicTimeObserver)
		}
		periodicTimeObserver = nil
		if let boundaryObserver, let player {
			player.removeTimeObserver(boundaryObserver)
		}
		boundaryObserver = nil
	}

	private func setupPeriodicTimeObserver() {
		guard let player else {
			return
		}

		// Update every 0.5 seconds
		let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
		periodicTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
			Task { @MainActor in
				guard let self else {
					return
				}
				self.currentPlaybackTime = CMTimeGetSeconds(time)
				if let duration = self.playerItem?.duration, duration.isNumeric {
					self.totalDuration = CMTimeGetSeconds(duration)
				}
			}
		}
	}

	func seek(to time: Double, completion: (@Sendable () -> Void)? = nil) {
		guard let player else {
			completion?()
			return
		}
		let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
		player.seek(to: cmTime) { [weak self] finished in
			Task { @MainActor in
				self?.updateNowPlayingInfo()
				// If we were at the end and seek back, resume playing
				if finished, case .paused = self?.state {
					// Check if we seeked away from the end
					if let duration = self?.totalDuration, duration > 0, time < duration - 1 {
						self?.play()
					}
				}
				completion?()
			}
		}
	}

	func skipForward(_ seconds: Double = 10) {
		guard let player else {
			return
		}
		let currentTime = CMTimeGetSeconds(player.currentTime())
		let newTime = currentTime + seconds
		let time = CMTime(seconds: newTime, preferredTimescale: 1000)
		player.seek(to: time)
		updateNowPlayingInfo()
	}

	func skipBackward(_ seconds: Double = 10) {
		guard let player else {
			return
		}
		let currentTime = CMTimeGetSeconds(player.currentTime())
		let newTime = max(0, currentTime - seconds)
		let time = CMTime(seconds: newTime, preferredTimescale: 1000)
		player.seek(to: time)
		updateNowPlayingInfo()
	}

	var currentTime: Double {
		guard let player else {
			return 0
		}
		return CMTimeGetSeconds(player.currentTime())
	}

	var duration: Double {
		guard let playerItem, playerItem.duration.isNumeric else {
			return 0
		}
		return CMTimeGetSeconds(playerItem.duration)
	}

	var isPlaying: Bool {
		if case .playing = state {
			return true
		}
		return false
	}

	var hasContent: Bool {
		return currentMP3URL != nil
	}

	// MARK: - KVO

	override nonisolated func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
		if keyPath == "status" {
			Task { @MainActor in
				handlePlayerItemStatusChange()
			}
		}
	}

	private func handlePlayerItemStatusChange() {
		guard let playerItem else {
			return
		}

		switch playerItem.status {
		case .readyToPlay:
			Self.logger.info("Audio ready to play")

			// Seek to start time if specified
			if let startTime = pendingStartTime {
				let time = CMTime(seconds: startTime, preferredTimescale: 1000)
				player?.seek(to: time) { [weak self] _ in
					Task { @MainActor in
						self?.pendingStartTime = nil
						self?.setupEndTimeBoundary()
						self?.play()
					}
				}
			} else {
				setupEndTimeBoundary()
				play()
			}
		case .failed:
			let errorMessage = playerItem.error?.localizedDescription ?? "Unknown error"
			Self.logger.error("Failed to load audio: \(errorMessage)")
			state = .error(errorMessage)
		case .unknown:
			break
		@unknown default:
			break
		}
	}

	private func setupEndTimeBoundary() {
		guard let player, let endTime else {
			return
		}

		// Remove existing boundary observer
		if let boundaryObserver {
			player.removeTimeObserver(boundaryObserver)
			self.boundaryObserver = nil
		}

		let boundaryTime = CMTime(seconds: endTime, preferredTimescale: 1000)
		boundaryObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: boundaryTime)], queue: .main) { [weak self] in
			Task { @MainActor in
				Self.logger.info("Reached end time boundary, pausing")
				self?.pause()
			}
		}
	}

	@objc private func playerDidFinishPlaying() {
		Self.logger.info("Audio playback finished")
		state = .paused
		// Reset to beginning
		player?.seek(to: .zero)
		updateNowPlayingInfo()
	}
}
