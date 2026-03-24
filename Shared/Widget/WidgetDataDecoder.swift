//
//  WidgetDataDecoder.swift
//  NetNewsWire
//
//  Created by Stuart Breckenridge on 18/11/20.
//  Copyright © 2020 Ranchero Software. All rights reserved.
//

import Foundation

struct WidgetDataDecoder {

	static func decodeWidgetData() throws -> WidgetData {
		guard let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String,
			  let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
			return WidgetData(totalUnreadCount: 0, totalTodayCount: 0, totalTodayUnreadCount: 0, totalStarredCount: 0, unreadArticles: [], starredArticles: [], todayArticles: [], lastUpdateTime: Date())
		}
		let dataURL = containerURL.appendingPathComponent("widget-data.json")
		if FileManager.default.fileExists(atPath: dataURL.path) {
			let decodedWidgetData = try JSONDecoder().decode(WidgetData.self, from: Data(contentsOf: dataURL))
			return decodedWidgetData
		} else {
			return WidgetData(totalUnreadCount: 0, totalTodayCount: 0, totalTodayUnreadCount: 0, totalStarredCount: 0, unreadArticles: [], starredArticles: [], todayArticles: [], lastUpdateTime: Date())
		}
	}

	static func sampleData() -> WidgetData {
		guard let pathToSample = Bundle.main.url(forResource: "widget-sample", withExtension: "json"),
			  let data = try? Data(contentsOf: pathToSample),
			  let decoded = try? JSONDecoder().decode(WidgetData.self, from: data) else {
			return WidgetData(totalUnreadCount: 0, totalTodayCount: 0, totalTodayUnreadCount: 0, totalStarredCount: 0, unreadArticles: [], starredArticles: [], todayArticles: [], lastUpdateTime: Date())
		}
		return decoded
	}

}
