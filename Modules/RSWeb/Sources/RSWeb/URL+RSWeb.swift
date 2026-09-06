//
//  NSURL+RSWeb.swift
//  RSWeb
//
//  Created by Brent Simmons on 12/26/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//

import Foundation

private struct URLConstants {
	static let schemeHTTP = "http"
	static let schemeHTTPS = "https"
}

public extension URL {

	func isHTTPSURL() -> Bool {
		return self.scheme?.lowercased(with: localeForLowercasing) == URLConstants.schemeHTTPS
	}

	func isHTTPURL() -> Bool {
		return self.scheme?.lowercased(with: localeForLowercasing) == URLConstants.schemeHTTP
	}

	func isHTTPOrHTTPSURL() -> Bool {
		return self.isHTTPSURL() || self.isHTTPURL()
	}

	func appendingQueryItems(_ queryItems: [URLQueryItem]) -> URL? {
		guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
			return nil
		}

		var newQueryItems = components.queryItems ?? []
		newQueryItems.append(contentsOf: queryItems)
		components.queryItems = newQueryItems

		return components.url
	}

	func preparedForOpeningInBrowser() -> URL? {
		var urlString = absoluteString.replacingOccurrences(of: " ", with: "%20")
		urlString = urlString.replacingOccurrences(of: "^", with: "%5E")
		urlString = urlString.replacingOccurrences(of: "&amp;", with: "&")
		urlString = urlString.replacingOccurrences(of: "&#38;", with: "&")

		return URL(string: urlString)
	}
}
