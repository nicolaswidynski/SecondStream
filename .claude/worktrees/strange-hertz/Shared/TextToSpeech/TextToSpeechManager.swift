//
//  TextToSpeechManager.swift
//  NetNewsWire
//
//  Created by Claude on 2026-01-25.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation
import AVFoundation
import os.log

enum TTSState {
	case idle
	case speaking
	case paused
}

@MainActor
final class TextToSpeechManager: NSObject, ObservableObject {

	static let shared = TextToSpeechManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "TextToSpeech")

	@Published private(set) var state: TTSState = .idle

	private let synthesizer = AVSpeechSynthesizer()
	private var currentUtterance: AVSpeechUtterance?

	private override init() {
		super.init()
		synthesizer.delegate = self
	}

	// MARK: - Voice Selection

	private func selectVoice(identifier: String?) -> AVSpeechSynthesisVoice? {
		// If a specific voice identifier is provided, use it
		if let identifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
			Self.logger.info("Using selected voice: \(voice.name)")
			return voice
		}

		// Fallback: select best available voice for the device language
		let preferredLanguage = Locale.preferredLanguages.first ?? "en-US"
		let languagePrefix = String(preferredLanguage.prefix(2))

		Self.logger.info("No voice selected, finding best voice for language: \(preferredLanguage)")

		let allVoices = AVSpeechSynthesisVoice.speechVoices()
		let voicesForLanguage = allVoices.filter { $0.language.hasPrefix(languagePrefix) }

		// Priority 1: Premium voices
		if let voice = voicesForLanguage.first(where: { $0.quality == .premium }) {
			Self.logger.info("Using premium voice: \(voice.name)")
			return voice
		}

		// Priority 2: Enhanced voices
		if let voice = voicesForLanguage.first(where: { $0.quality == .enhanced }) {
			Self.logger.info("Using enhanced voice: \(voice.name)")
			return voice
		}

		// Priority 3: Any voice for the language
		if let voice = voicesForLanguage.first {
			Self.logger.info("Using fallback voice: \(voice.name)")
			return voice
		}

		Self.logger.info("Using system default voice")
		return AVSpeechSynthesisVoice(language: preferredLanguage)
	}

	/// Returns available enhanced/premium voices for the device's preferred language, sorted by quality
	static func availableVoices() -> [AVSpeechSynthesisVoice] {
		let preferredLanguage = Locale.preferredLanguages.first ?? "en-US"
		let languagePrefix = String(preferredLanguage.prefix(2))

		let allVoices = AVSpeechSynthesisVoice.speechVoices()
		let voicesForLanguage = allVoices.filter { $0.language.hasPrefix(languagePrefix) }

		// Only include enhanced and premium voices
		let qualityVoices = voicesForLanguage.filter { $0.quality == .premium || $0.quality == .enhanced }

		// Sort by quality (premium first, then enhanced)
		return qualityVoices.sorted { v1, v2 in
			if v1.quality != v2.quality {
				return v1.quality.rawValue > v2.quality.rawValue
			}
			return v1.name < v2.name
		}
	}

	// MARK: - Playback Controls

	func speak(text: String, voiceIdentifier: String? = nil) {
		// Stop any current speech
		stop()

		#if os(iOS)
		// Activate audio session
		do {
			try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
			try AVAudioSession.sharedInstance().setActive(true)
		} catch {
			Self.logger.error("Failed to activate audio session: \(error.localizedDescription)")
		}
		#endif

		let utterance = AVSpeechUtterance(string: text)
		utterance.voice = selectVoice(identifier: voiceIdentifier)

		// Slightly slower rate for more natural speech (default is 0.5)
		utterance.rate = 0.45

		// Natural pitch
		utterance.pitchMultiplier = 1.0

		// Add slight pauses for more natural flow
		utterance.preUtteranceDelay = 0.1
		utterance.postUtteranceDelay = 0.1

		currentUtterance = utterance
		state = .speaking

		Self.logger.info("Starting TTS with voice: \(utterance.voice?.name ?? "default")")
		synthesizer.speak(utterance)
	}

	func pause() {
		guard state == .speaking else {
			return
		}
		synthesizer.pauseSpeaking(at: .word)
		state = .paused
	}

	func resume() {
		guard state == .paused else {
			return
		}
		synthesizer.continueSpeaking()
		state = .speaking
	}

	func togglePlayPause() {
		switch state {
		case .speaking:
			pause()
		case .paused:
			resume()
		case .idle:
			break
		}
	}

	func stop() {
		synthesizer.stopSpeaking(at: .immediate)
		currentUtterance = nil
		state = .idle

		#if os(iOS)
		// Deactivate audio session
		do {
			try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
		} catch {
			Self.logger.error("Failed to deactivate audio session: \(error.localizedDescription)")
		}
		#endif
	}

	var isSpeaking: Bool {
		return state == .speaking
	}

	var isPaused: Bool {
		return state == .paused
	}

	var isActive: Bool {
		return state != .idle
	}
}

// MARK: - AVSpeechSynthesizerDelegate

extension TextToSpeechManager: AVSpeechSynthesizerDelegate {

	nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
		Task { @MainActor in
			Self.logger.info("TTS started")
			state = .speaking
		}
	}

	nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
		Task { @MainActor in
			Self.logger.info("TTS finished")
			state = .idle
			currentUtterance = nil

			#if os(iOS)
			do {
				try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
			} catch {
				Self.logger.error("Failed to deactivate audio session: \(error.localizedDescription)")
			}
			#endif
		}
	}

	nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
		Task { @MainActor in
			Self.logger.info("TTS paused")
			state = .paused
		}
	}

	nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
		Task { @MainActor in
			Self.logger.info("TTS resumed")
			state = .speaking
		}
	}

	nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
		Task { @MainActor in
			Self.logger.info("TTS cancelled")
			state = .idle
			currentUtterance = nil
		}
	}
}
