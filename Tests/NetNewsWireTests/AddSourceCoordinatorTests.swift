//
//  AddSourceCoordinatorTests.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-10.
//  Copyright © 2026 STDN. All rights reserved.
//

import XCTest
import Account
@testable import NetNewsWire

// MARK: - Mock

@MainActor
final class MockWebhookSourcesManager: WebhookSourcesManaging {

	/// Preset the result that `add` will return.
	var stubbedResult: AddSourceResult = .existsOnServer(summaryURL: "https://example.com/feed")

	var addCallCount = 0
	var lastAddName: String?
	var lastAddAuthor: String?

	var fetchFreshCallCount = 0

	func add(name: String, author: String?) async -> AddSourceResult {
		addCallCount += 1
		lastAddName = name
		lastAddAuthor = author
		return stubbedResult
	}

	func fetchFresh() async {
		fetchFreshCallCount += 1
	}
}

// MARK: - Tests

@MainActor
final class AddSourceCoordinatorTests: XCTestCase {

	// MARK: - Initial state

	func testInitialStateIsIdle() {
		let manager = MockWebhookSourcesManager()
		let coordinator = AddSourceCoordinator(manager: manager, category: .podcast)
		XCTAssertEqual(coordinator.state, .idle)
	}

	// MARK: - existsOnServer (201)

	func testExistsOnServerTransition() async {
		let manager = MockWebhookSourcesManager()
		manager.stubbedResult = .existsOnServer(summaryURL: "https://example.com/show.json")

		let coordinator = AddSourceCoordinator(manager: manager, category: .podcast)
		await coordinator.add(name: "Test Show", author: "Alice")

		XCTAssertEqual(coordinator.state, .existsOnServer(summaryURL: "https://example.com/show.json"))
	}

	// MARK: - newOnServer (202)

	func testNewOnServerTransition() async {
		let manager = MockWebhookSourcesManager()
		manager.stubbedResult = .newOnServer(summaryURL: "https://example.com/show.json", message: "Processing!")

		let coordinator = AddSourceCoordinator(manager: manager, category: .youtube)
		await coordinator.add(name: "My Channel", author: nil)

		XCTAssertEqual(coordinator.state, .newOnServer(summaryURL: "https://example.com/show.json", message: "Processing!"))
	}

	// MARK: - failure

	func testFailureTransition() async {
		let manager = MockWebhookSourcesManager()
		manager.stubbedResult = .failure(message: "Server error")

		let coordinator = AddSourceCoordinator(manager: manager, category: .news)
		await coordinator.add(name: "Topic", author: nil)

		XCTAssertEqual(coordinator.state, .failed(message: "Server error"))
	}

	// MARK: - onStateChange callback

	func testOnStateChangeCalledWithWebhookPendingThenResult() async {
		let manager = MockWebhookSourcesManager()
		manager.stubbedResult = .existsOnServer(summaryURL: "https://example.com")

		let coordinator = AddSourceCoordinator(manager: manager, category: .podcast)

		var observedStates: [AddSourceCoordinator.State] = []
		coordinator.onStateChange = { observedStates.append($0) }

		await coordinator.add(name: "Show", author: nil)

		XCTAssertEqual(observedStates.count, 2)
		XCTAssertEqual(observedStates[0], .webhookPending)
		XCTAssertEqual(observedStates[1], .existsOnServer(summaryURL: "https://example.com"))
	}

	// MARK: - Manager is called with correct arguments

	func testManagerReceivesCorrectNameAndAuthor() async {
		let manager = MockWebhookSourcesManager()
		let coordinator = AddSourceCoordinator(manager: manager, category: .podcast)

		await coordinator.add(name: "Serial", author: "This American Life")

		XCTAssertEqual(manager.addCallCount, 1)
		XCTAssertEqual(manager.lastAddName, "Serial")
		XCTAssertEqual(manager.lastAddAuthor, "This American Life")
	}

	func testManagerCalledOncePerAdd() async {
		let manager = MockWebhookSourcesManager()
		let coordinator = AddSourceCoordinator(manager: manager, category: .podcast)

		await coordinator.add(name: "A", author: nil)
		await coordinator.add(name: "B", author: nil)

		XCTAssertEqual(manager.addCallCount, 2)
	}

	// MARK: - bootstrapType

	func testBootstrapTypeForPodcast() {
		let coordinator = AddSourceCoordinator(manager: MockWebhookSourcesManager(), category: .podcast)
		XCTAssertEqual(coordinator.bootstrapType, "pod")
	}

	func testBootstrapTypeForYoutube() {
		let coordinator = AddSourceCoordinator(manager: MockWebhookSourcesManager(), category: .youtube)
		XCTAssertEqual(coordinator.bootstrapType, "yt")
	}

	func testBootstrapTypeForNewsIsEmpty() {
		let coordinator = AddSourceCoordinator(manager: MockWebhookSourcesManager(), category: .news)
		XCTAssertEqual(coordinator.bootstrapType, "")
	}

	func testBootstrapTypeForRSSIsEmpty() {
		let coordinator = AddSourceCoordinator(manager: MockWebhookSourcesManager(), category: .rss)
		XCTAssertEqual(coordinator.bootstrapType, "")
	}
}
