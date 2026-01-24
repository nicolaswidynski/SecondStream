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

	private var player: AVPlayer?
	private var playerItem: AVPlayerItem?
	private var timeObserver: Any?
	private var boundaryObserver: Any?
	private var pendingStartTime: Double?
	private var endTime: Double?

	private override init() {
		super.init()
		setupAudioSession()
		setupRemoteCommandCenter()
	}

	// MARK: - Audio Session

	private func setupAudioSession() {
		#if os(iOS)
		do {
			try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
			try AVAudioSession.sharedInstance().setActive(true)
		} catch {
			Self.logger.error("Failed to setup audio session: \(error.localizedDescription)")
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
	}

	private func updateNowPlayingInfo() {
		var nowPlayingInfo = [String: Any]()
		nowPlayingInfo[MPMediaItemPropertyTitle] = currentTitle ?? "Podcast"
		nowPlayingInfo[MPMediaItemPropertyArtist] = "NetNewsWire"

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
		if let boundaryObserver, let player {
			player.removeTimeObserver(boundaryObserver)
		}
		boundaryObserver = nil
		playerItem?.removeObserver(self, forKeyPath: "status")
		NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
		player = nil
		playerItem = nil
		pendingStartTime = nil
		endTime = nil
		state = .idle
		MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
