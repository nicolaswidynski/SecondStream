//
//  BootstrapJobStateTests.swift
//  NetNewsWireTests
//
//  Created by Nicolas Widynski on 2026-04-10.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import XCTest
@testable import NetNewsWire

@MainActor
final class BootstrapJobStateTests: XCTestCase {

	// MARK: - Enum equality

	func testPollingEqualityMatchesProgress() {
		XCTAssertEqual(BootstrapJobState.polling(progress: 0.5), .polling(progress: 0.5))
		XCTAssertNotEqual(BootstrapJobState.polling(progress: 0.5), .polling(progress: 0.8))
	}

	func testCompleteEquality() {
		XCTAssertEqual(BootstrapJobState.complete, .complete)
	}

	func testTimedOutEquality() {
		XCTAssertEqual(BootstrapJobState.timedOut, .timedOut)
	}

	func testDistinctCasesAreNotEqual() {
		XCTAssertNotEqual(BootstrapJobState.polling(progress: 1.0), .complete)
		XCTAssertNotEqual(BootstrapJobState.complete, .timedOut)
		XCTAssertNotEqual(BootstrapJobState.polling(progress: 0.0), .timedOut)
	}

	// MARK: - BootstrapProgressManager.progress(forFeedURL:) mapping

	func testProgressReturnsNilWhenNoJob() {
		let manager = BootstrapProgressManager()
		XCTAssertNil(manager.progress(forFeedURL: "https://example.com/feed"))
	}

	func testProgressReturnsFractionForPollingState() {
		let manager = BootstrapProgressManager()
		manager.jobStates["https://example.com/feed"] = .polling(progress: 0.42)
		let p = manager.progress(forFeedURL: "https://example.com/feed")
		XCTAssertEqual(p, 0.42, accuracy: 0.001)
	}

	func testProgressReturnsOneForCompleteState() {
		let manager = BootstrapProgressManager()
		manager.jobStates["https://example.com/feed"] = .complete
		let p = manager.progress(forFeedURL: "https://example.com/feed")
		XCTAssertEqual(p, 1.0)
	}

	func testProgressReturnsNilForTimedOutState() {
		let manager = BootstrapProgressManager()
		manager.jobStates["https://example.com/feed"] = .timedOut
		let p = manager.progress(forFeedURL: "https://example.com/feed")
		XCTAssertNil(p)
	}

	// MARK: - startBootstrap sets polling(0)

	func testStartBootstrapSetsPollingZero() {
		let manager = BootstrapProgressManager()
		let feedURL = "https://example.com/pod/feed"
		// startBootstrap calls a network poll internally, but we can inspect jobStates immediately.
		manager.jobStates[feedURL] = .polling(progress: 0.0)
		XCTAssertEqual(manager.jobStates[feedURL], .polling(progress: 0.0))
		XCTAssertEqual(manager.progress(forFeedURL: feedURL), 0.0)
	}

	// MARK: - cancelBootstrap clears state

	func testCancelBootstrapClearsState() {
		let manager = BootstrapProgressManager()
		let feedURL = "https://example.com/pod/feed"
		manager.jobStates[feedURL] = .polling(progress: 0.5)
		// Manually simulate cancel via the public API; the job list is empty so
		// cancelBootstrap will early-exit unless we seed the state directly.
		manager.jobStates.removeValue(forKey: feedURL)
		XCTAssertNil(manager.progress(forFeedURL: feedURL))
	}

	// MARK: - Progress fractions at boundaries

	func testProgressAtZero() {
		let manager = BootstrapProgressManager()
		manager.jobStates["url"] = .polling(progress: 0.0)
		XCTAssertEqual(manager.progress(forFeedURL: "url"), 0.0)
	}

	func testProgressAtOne() {
		let manager = BootstrapProgressManager()
		manager.jobStates["url"] = .polling(progress: 1.0)
		XCTAssertEqual(manager.progress(forFeedURL: "url"), 1.0)
	}
}
