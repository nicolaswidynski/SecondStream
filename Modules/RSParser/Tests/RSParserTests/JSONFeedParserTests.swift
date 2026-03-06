//
//  JSONFeedParserTests.swift
//  RSParser
//
//  Created by Brent Simmons on 6/26/17.
//  Copyright © 2017 Ranchero Software, LLC. All rights reserved.
//

import XCTest
import RSParser

final class JSONFeedParserTests: XCTestCase {

	func testInessentialPerformance() {

		// 0.001 sec on my 2012 iMac.
		let d = parserData("inessential", "json", "http://inessential.com/")
		self.measure {
			_ = try! FeedParser.parse(d)
		}
	}

	func testDaringFireballPerformance() {

		// 0.009 sec on my 2012 iMac.
		let d = parserData("DaringFireball", "json", "http://daringfireball.net/")
		self.measure {
			_ = try! FeedParser.parse(d)
		}
	}

	func testGettingFaviconAndIconURLs() {

		let d = parserData("DaringFireball", "json", "http://daringfireball.net/")
		let parsedFeed = try! FeedParser.parse(d)!

		XCTAssert(parsedFeed.faviconURL == "https://daringfireball.net/graphics/favicon-64.png")
		XCTAssert(parsedFeed.iconURL == "https://daringfireball.net/graphics/apple-touch-icon.png")
	}

	func testAllThis() {

		let d = parserData("allthis", "json", "http://leancrew.com/allthis/")
		let parsedFeed = try! FeedParser.parse(d)!

		XCTAssertEqual(parsedFeed.items.count, 12)
	}

	func testCurt() {

		let d = parserData("curt", "json", "http://curtclifton.net/")
		let parsedFeed = try! FeedParser.parse(d)!

		XCTAssertEqual(parsedFeed.items.count, 26)

		var didFindTwitterQuitterArticle = false
		for article in parsedFeed.items {
			if article.title == "Twitter Quitter" {
				didFindTwitterQuitterArticle = true
				XCTAssertTrue(article.contentHTML!.hasPrefix("<p>I&#8217;ve decided to close my Twitter account. William Van Hecke <a href=\"https://tinyletter.com/fet/letters/microcosmographia-xlxi-reasons-to-stay-on-twitter\">makes a convincing case</a>"))
			}
		}

		XCTAssertTrue(didFindTwitterQuitterArticle)
	}

	func testPixelEnvy() {

		let d = parserData("pxlnv", "json", "http://pxlnv.com/")
		let parsedFeed = try! FeedParser.parse(d)!
		XCTAssertEqual(parsedFeed.items.count, 20)

	}

	func testRose() {
		let d = parserData("rose", "json", "http://www.rosemaryorchard.com/")
		let parsedFeed = try! FeedParser.parse(d)!
		XCTAssertEqual(parsedFeed.items.count, 84)
	}

	func test3960() {
		let d = parserData("3960", "json", "http://journal.3960.org/")
		let parsedFeed = try! FeedParser.parse(d)!
		XCTAssertEqual(parsedFeed.items.count, 20)
		XCTAssertEqual(parsedFeed.language, "de-DE")

		for item in parsedFeed.items {
			XCTAssertEqual(item.language, "de-DE")
		}
	}

	func testAuthors() {
		let d = parserData("authors", "json", "https://example.com/")
		let parsedFeed = try! FeedParser.parse(d)!
		XCTAssertEqual(parsedFeed.items.count, 4)

		let rootAuthors = Set([
			ParsedAuthor(name: "Root Author 1", url: nil, avatarURL: nil, emailAddress: nil),
			ParsedAuthor(name: "Root Author 2", url: nil, avatarURL: nil, emailAddress: nil)
		])
		let itemAuthors = Set([
			ParsedAuthor(name: "Item Author 1", url: nil, avatarURL: nil, emailAddress: nil),
			ParsedAuthor(name: "Item Author 2", url: nil, avatarURL: nil, emailAddress: nil)
		])
		let legacyItemAuthors = Set([
			ParsedAuthor(name: "Legacy Item Author", url: nil, avatarURL: nil, emailAddress: nil)
		])

		XCTAssertEqual(parsedFeed.authors?.count, 2)
		XCTAssertEqual(parsedFeed.authors, rootAuthors)

		let noAuthorsItem = parsedFeed.items.first { $0.uniqueID == "Item without authors" }!
		XCTAssertEqual(noAuthorsItem.authors, nil)

		let legacyAuthorItem = parsedFeed.items.first { $0.uniqueID == "Item with legacy author" }!
		XCTAssertEqual(legacyAuthorItem.authors, legacyItemAuthors)

		let modernAuthorsItem = parsedFeed.items.first { $0.uniqueID == "Item with modern authors" }!
		XCTAssertEqual(modernAuthorsItem.authors, itemAuthors)

		let bothAuthorsItem = parsedFeed.items.first { $0.uniqueID == "Item with both" }!
		XCTAssertEqual(bothAuthorsItem.authors, itemAuthors)
	}

	func testGeneratedShowJSONFeed() {
		let d = parserData("generated-show", "json", "https://files.nwidynski.com/pod/aaa/crime-junkie.json")
		let parsedFeed = try! FeedParser.parse(d)!

		XCTAssertEqual(parsedFeed.title, "Crime Junkie")
		XCTAssertEqual(parsedFeed.homePageURL, "https://podcast.example/")
		XCTAssertEqual(parsedFeed.iconURL, "https://example.com/crime-junkie.png")
		XCTAssertEqual(parsedFeed.items.count, 1)

		let item = parsedFeed.items.first!
		XCTAssertEqual(item.uniqueID, "pod/crime-junkie/2026-03-01-episode-one.json")
		XCTAssertEqual(item.mp3URL, "https://example.com/episode-one.mp3")
		XCTAssertEqual(item.title, "Episode One")
		XCTAssertNotNil(item.contentJSON)
	}

	func testGeneratedTopicsJSONFeed() {
		let d = parserData("generated-topics", "json", "https://files.nwidynski.com/topics/aaa/artificial-intelligence.json")
		let parsedFeed = try! FeedParser.parse(d)!

		XCTAssertEqual(parsedFeed.title, "Artificial Intelligence")
		XCTAssertEqual(parsedFeed.iconURL, "https://example.com/artificial-intelligence.png")
		XCTAssertEqual(parsedFeed.items.count, 1)

		let item = parsedFeed.items.first!
		XCTAssertEqual(item.uniqueID, "topics/artificial-intelligence/2026-03-02.json")
		XCTAssertEqual(item.title, "How AI can read our scrambled inner thoughts")
		XCTAssertNotNil(item.contentJSON)
	}
}
