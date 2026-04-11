//
//  BootstrapProgressManager.swift
//  NetNewsWire
//
//  Created by Claude on 2026-04-02.
//  Copyright © 2026 STDN. All rights reserved.
//

import Foundation
import os.log

extension Notification.Name {
	static let bootstrapProgressDidUpdate = Notification.Name("bootstrapProgressDidUpdate")
}

/// Represents an in-progress bootstrap job for a newly added show.
struct BootstrapJob: Codable, Equatable {
	let type: String        // "pod" or "yt"
	let show: String
	let author: String
	let feedURL: String     // also the summary JSON URL, e.g. https://files.nwidynski.com/pod/aaa/show.json
	let startedAt: Date
}

/// Tracks the in-memory state of a single bootstrap job.
///
/// Replaces the raw `Double` in the previous `progressByFeedURL` dictionary,
/// making the three observable sub-states explicit and correct-by-construction.
enum BootstrapJobState: Equatable {
	/// Polling is in progress. `progress` is in the range 0.0–1.0.
	case polling(progress: Double)
	/// Backend finished; the feed is ready. The progress ring shows 100% briefly before removal.
	case complete
	/// Polling timed out without completing. No progress ring should be shown.
	case timedOut
}

/// Manages polling for bootstrap progress on newly added shows that returned 202.
///
/// Jobs are persisted in `UserDefaults` so they survive app restarts.
/// Each job polls `query-bootstrap-progress` every 10 s (first poll after 10 s),
/// and stops when progress reaches 100 or the job is older than 1 hour.
///
/// Job state is keyed by feed URL for easy lookup from the sidebar.
@MainActor final class BootstrapProgressManager {

	static let shared = BootstrapProgressManager()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Bootstrap")

	private let queryURL = URL(string: "https://n8n.nwidynski.com/webhook/query-bootstrap-progress")!
	private let jobsKey = "bootstrapProgressJobs"
	private let pollInterval: TimeInterval = 10
	private let maxDuration: TimeInterval = 3600        // 1 hour absolute cap
	private let maxProgressDuration: TimeInterval = 420 // 7 minutes from first progress > 0

	// MARK: - State

	/// Keyed by `feedURL`. Tracks the explicit state of each in-progress bootstrap job.
	/// Before the first poll result, holds `.polling(progress: 0.0)` so the cell shows
	/// an empty ring immediately.
	///
	/// The setter is `internal` to allow unit tests to seed state directly without
	/// triggering network polling.
	var jobStates: [String: BootstrapJobState] = [:]

	/// Running poll tasks, keyed by feedURL.
	private var tasksByFeedURL: [String: Task<Void, Never>] = [:]

	/// When the first pct > 0 was observed for each feed. Used for the 7-minute hard cap.
	private var progressStartedAt: [String: Date] = [:]

	// MARK: - Bearer token

	private var bearerToken: String? {
		guard let tokenURL = Bundle.main.url(forResource: "podcast_token", withExtension: "txt"),
			  let token = try? String(contentsOf: tokenURL, encoding: .utf8) else {
			Self.logger.error("Failed to load bearer token from file")
			return nil
		}
		return token.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: - Persisted Jobs

	private var jobs: [BootstrapJob] {
		get {
			guard let data = UserDefaults.standard.data(forKey: jobsKey),
				  let decoded = try? JSONDecoder().decode([BootstrapJob].self, from: data) else {
				return []
			}
			return decoded
		}
		set {
			if let data = try? JSONEncoder().encode(newValue) {
				UserDefaults.standard.set(data, forKey: jobsKey)
			} else {
				UserDefaults.standard.removeObject(forKey: jobsKey)
			}
		}
	}

	// MARK: - Public API

	/// Call this once at app launch to resume any jobs that survived a restart.
	func resumePendingJobs() {
		for job in jobs {
			guard tasksByFeedURL[job.feedURL] == nil else { continue }
			let elapsed = Date().timeIntervalSince(job.startedAt)
			if elapsed >= maxDuration {
				removeJob(job)
				continue
			}
			jobStates[job.feedURL] = .polling(progress: 0.0)
			// Align the initial delay to the next 10-second boundary
			let remaining = pollInterval - elapsed.truncatingRemainder(dividingBy: pollInterval)
			startPolling(job: job, initialDelay: max(0, remaining))
		}
	}

	/// Call this when the app returns to foreground to restart any stalled polling tasks.
	/// Cancels all in-flight tasks and re-schedules them with a short initial delay so
	/// progress updates resume quickly after the app was backgrounded.
	func resumeFromBackground() {
		guard !tasksByFeedURL.isEmpty || !jobs.isEmpty else { return }
		Self.logger.info("resumeFromBackground — restarting \(self.jobs.count) job(s)")
		for (_, task) in tasksByFeedURL { task.cancel() }
		tasksByFeedURL.removeAll()
		for job in jobs {
			let elapsed = Date().timeIntervalSince(job.startedAt)
			if elapsed >= maxDuration {
				removeJob(job)
				continue
			}
			if jobStates[job.feedURL] == nil {
				jobStates[job.feedURL] = .polling(progress: 0.0)
			}
			startPolling(job: job, initialDelay: 2)
		}
	}

	/// Start tracking bootstrap progress for a newly added show (202 response).
	/// - Parameters:
	///   - type: "pod" or "yt"
	///   - show: show/channel name
	///   - author: show author (may be empty)
	///   - feedURL: the feed URL that was just added — used as the stable lookup key
	func startBootstrap(type: String, show: String, author: String, feedURL: String) {
		// Avoid duplicates
		guard tasksByFeedURL[feedURL] == nil else {
			Self.logger.info("startBootstrap skipped — already tracking \(feedURL)")
			return
		}

		Self.logger.info("startBootstrap — type:\(type) show:\(show) feedURL:\(feedURL)")
		let job = BootstrapJob(type: type, show: show, author: author, feedURL: feedURL, startedAt: Date())
		var current = jobs
		current.removeAll { $0.feedURL == feedURL }
		current.append(job)
		jobs = current

		jobStates[feedURL] = .polling(progress: 0.0)
		notifyUpdate(feedURL: feedURL)
		startPolling(job: job, initialDelay: pollInterval)
	}

	/// Current progress fraction (0.0–1.0) for a given feed URL, or `nil` if not bootstrapping.
	///
	/// Returns `nil` when no job exists or the job has timed out. Returns `1.0` when complete
	/// (the ring briefly shows full before the entry is removed).
	func progress(forFeedURL feedURL: String) -> Double? {
		switch jobStates[feedURL] {
		case .polling(let p): return p
		case .complete: return 1.0
		case .timedOut, nil: return nil
		}
	}

	/// Cancels and removes any active or persisted bootstrap job for the given feed URL.
	/// Call this when a feed is confirmed to already exist (201 response) so stale jobs
	/// from a previous 202 session don't leave the ring on screen.
	func cancelBootstrap(feedURL: String) {
		guard jobStates[feedURL] != nil || jobs.contains(where: { $0.feedURL == feedURL }) else {
			return
		}
		tasksByFeedURL[feedURL]?.cancel()
		tasksByFeedURL.removeValue(forKey: feedURL)
		jobStates.removeValue(forKey: feedURL)
		progressStartedAt.removeValue(forKey: feedURL)
		var current = jobs
		current.removeAll { $0.feedURL == feedURL }
		jobs = current
		notifyUpdate(feedURL: feedURL)
	}

	// MARK: - Polling

	private func startPolling(job: BootstrapJob, initialDelay: TimeInterval) {
		Self.logger.info("startPolling — feedURL:\(job.feedURL) initialDelay:\(initialDelay)s")
		let task = Task { [weak self] in
			guard let self else {
				Self.logger.error("startPolling task fired but self is nil")
				return
			}
			try? await Task.sleep(for: .seconds(initialDelay))
			if Task.isCancelled {
				Self.logger.info("startPolling task cancelled after sleep for \(job.feedURL)")
				return
			}
			await self.poll(job: job)
		}
		tasksByFeedURL[job.feedURL] = task
	}

	/// Returns `true` if the summary JSON at `feedURL` already has at least one entry,
	/// meaning the backend has finished populating the feed.
	private func feedEntriesExist(job: BootstrapJob) async -> Bool {
		guard let url = URL(string: job.feedURL) else { return false }
		var request = URLRequest(url: url)
		request.timeoutInterval = 10
		do {
			let (data, response) = try await URLSession.shared.data(for: request)
			guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
			guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
				  let entries = json["entries"] as? [Any] else { return false }
			let hasEntries = !entries.isEmpty
			Self.logger.info("feedEntriesExist: \(hasEntries, privacy: .public) (\(entries.count, privacy: .public) entries) for \(job.feedURL)")
			return hasEntries
		} catch {
			return false
		}
	}

	private func poll(job: BootstrapJob) async {
		let elapsed = Date().timeIntervalSince(job.startedAt)
		Self.logger.info("poll fired — feedURL:\(job.feedURL) elapsed:\(Int(elapsed))s")
		if elapsed >= maxDuration {
			Self.logger.info("poll timeout for \(job.feedURL)")
			finish(job: job, atFull: false)
			return
		}

		// Fast-path: if the summary JSON already has entries, the backend is done.
		if await feedEntriesExist(job: job) {
			Self.logger.info("feed entries present — finishing at 100% for \(job.feedURL)")
			finish(job: job, atFull: true)
			return
		}

		let pct = await queryProgress(job: job)
		if Task.isCancelled {
			Self.logger.info("poll task cancelled after queryProgress for \(job.feedURL)")
			return
		}

		if let pct {
			let fraction = min(1.0, max(0.0, Double(pct) / 100.0))
			jobStates[job.feedURL] = .polling(progress: fraction)
			notifyUpdate(feedURL: job.feedURL)

			if pct >= 100 {
				finish(job: job, atFull: true)
				return
			}

			// Protection: once any progress > 0 is observed, allow at most 7 more minutes.
			if pct > 0 {
				if progressStartedAt[job.feedURL] == nil {
					progressStartedAt[job.feedURL] = Date()
					Self.logger.info("Progress first seen for \(job.feedURL) — 7-min cap starts")
				} else if let start = progressStartedAt[job.feedURL],
						  Date().timeIntervalSince(start) > maxProgressDuration {
					Self.logger.info("7-min cap reached for \(job.feedURL) — finishing at 100")
					finish(job: job, atFull: true)
					return
				}
			}
		}

		// Schedule next poll
		let nextTask = Task { [weak self] in
			guard let self else { return }
			try? await Task.sleep(for: .seconds(self.pollInterval))
			guard !Task.isCancelled else { return }
			await self.poll(job: job)
		}
		tasksByFeedURL[job.feedURL] = nextTask
	}

	private func finish(job: BootstrapJob, atFull: Bool) {
		tasksByFeedURL.removeValue(forKey: job.feedURL)
		progressStartedAt.removeValue(forKey: job.feedURL)
		if atFull {
			jobStates[job.feedURL] = .complete
			notifyUpdate(feedURL: job.feedURL)
			// Brief pause so the UI can show 100% before clearing.
			Task { [weak self] in
				try? await Task.sleep(for: .seconds(1))
				self?.jobStates.removeValue(forKey: job.feedURL)
				self?.notifyUpdate(feedURL: job.feedURL)
			}
		} else {
			jobStates[job.feedURL] = .timedOut
			jobStates.removeValue(forKey: job.feedURL)
			notifyUpdate(feedURL: job.feedURL)
		}
		removeJob(job)
	}

	// MARK: - Network

	private func queryProgress(job: BootstrapJob) async -> Int? {
		Self.logger.info("queryProgress — feedURL:\(job.feedURL)")
		guard let appleUserID = AuthManager.shared.appleUserID else {
			Self.logger.error("queryProgress aborted — appleUserID is nil")
			return nil
		}
		guard let token = bearerToken else {
			Self.logger.error("queryProgress aborted — bearerToken is nil")
			return nil
		}

		var body: [String: Any] = [
			"apple_user_id": appleUserID,
			"type": job.type,
			"show": job.show,
		]
		if !job.author.isEmpty {
			body["author"] = job.author
		}

		guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

		var request = URLRequest(url: queryURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.httpBody = jsonData
		request.timeoutInterval = 15

		do {
			Self.logger.info("queryProgress — sending POST to \(self.queryURL) for \(job.feedURL)")
			let (data, response) = try await URLSession.shared.data(for: request)
			guard let http = response as? HTTPURLResponse else {
				Self.logger.error("queryProgress — non-HTTP response")
				return nil
			}
			Self.logger.info("queryProgress — HTTP \(http.statusCode) for \(job.feedURL)")

			// 551 = feed not found on server — consider bootstrap complete
			if http.statusCode == 551 {
				Self.logger.info("Bootstrap got 551 (feed not found) for \(job.feedURL) — treating as 100")
				return 100
			}

			guard http.statusCode == 200 else {
				let rawBody = String(data: data, encoding: .utf8) ?? "(empty)"
				Self.logger.error("queryProgress unexpected status \(http.statusCode, privacy: .public): \(rawBody, privacy: .public)")
				return nil
			}

			// Response: {"percentage": 42} or [{"percentage": 42}]
			let rawBody = String(data: data, encoding: .utf8) ?? "(empty)"
			Self.logger.info("queryProgress response body: \(rawBody, privacy: .public)")
			if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			   let pct = obj["percentage"] as? Int {
				return pct
			}
			if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
			   let pct = arr.first?["percentage"] as? Int {
				return pct
			}
			Self.logger.error("queryProgress — could not parse percentage from: \(rawBody, privacy: .public)")
			return nil
		} catch {
			Self.logger.error("Bootstrap query failed for \(job.feedURL): \(error.localizedDescription)")
			return nil
		}
	}

	// MARK: - Helpers

	private func removeJob(_ job: BootstrapJob) {
		var current = jobs
		current.removeAll { $0.feedURL == job.feedURL }
		jobs = current
	}

	private func notifyUpdate(feedURL: String) {
		NotificationCenter.default.post(
			name: .bootstrapProgressDidUpdate,
			object: self,
			userInfo: ["feedURL": feedURL]
		)
	}
}
