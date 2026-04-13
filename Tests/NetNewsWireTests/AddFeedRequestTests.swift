//
//  AddFeedRequestTests.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-10.
//  Copyright © 2026 STDN. All rights reserved.
//

import XCTest
import Account
@testable import NetNewsWire

final class AddFeedRequestTests: XCTestCase {

	// MARK: - Defaults

	func testDefaultsAreCorrect() {
		let req = AddFeedRequest(urlString: "https://example.com/feed.xml", category: .rss)
		XCTAssertEqual(req.urlString, "https://example.com/feed.xml")
		XCTAssertEqual(req.category, .rss)
		XCTAssertNil(req.name)
		XCTAssertNil(req.author)
		XCTAssertNil(req.imageURL)
		XCTAssertNil(req.imageURLLight)
		XCTAssertTrue(req.validateFeed)
		XCTAssertNil(req.summaryURL)
		XCTAssertFalse(req.skipLoadingIndicator)
	}

	// MARK: - Full initialisation

	func testAllFieldsStoredCorrectly() {
		let req = AddFeedRequest(
			urlString: "https://pod.example.com/feed",
			category: .podcast,
			name: "My Podcast",
			author: "Jane Doe",
			imageURL: "https://example.com/dark.png",
			imageURLLight: "https://example.com/light.png",
			validateFeed: false,
			summaryURL: "https://example.com/summary.json",
			skipLoadingIndicator: true
		)

		XCTAssertEqual(req.urlString, "https://pod.example.com/feed")
		XCTAssertEqual(req.category, .podcast)
		XCTAssertEqual(req.name, "My Podcast")
		XCTAssertEqual(req.author, "Jane Doe")
		XCTAssertEqual(req.imageURL, "https://example.com/dark.png")
		XCTAssertEqual(req.imageURLLight, "https://example.com/light.png")
		XCTAssertFalse(req.validateFeed)
		XCTAssertEqual(req.summaryURL, "https://example.com/summary.json")
		XCTAssertTrue(req.skipLoadingIndicator)
	}

	// MARK: - Category variants

	func testCategoryRSS() {
		XCTAssertEqual(AddFeedRequest(urlString: "x", category: .rss).category, .rss)
	}

	func testCategoryPodcast() {
		XCTAssertEqual(AddFeedRequest(urlString: "x", category: .podcast).category, .podcast)
	}

	func testCategoryYoutube() {
		XCTAssertEqual(AddFeedRequest(urlString: "x", category: .youtube).category, .youtube)
	}

	func testCategoryNews() {
		XCTAssertEqual(AddFeedRequest(urlString: "x", category: .news).category, .news)
	}
}
