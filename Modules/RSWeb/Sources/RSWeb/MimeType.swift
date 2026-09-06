//
//  MimeType.swift
//  RSWeb
//
//  Created by Brent Simmons on 12/26/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//

import Foundation

nonisolated public struct MimeType: Sendable {

	// This could certainly use expansion.

	public static let png = "image/png"
	public static let jpeg = "image/jpeg"
	public static let jpg = "image/jpg"
	public static let gif = "image/gif"
	public static let tiff = "image/tiff"

	public static let formURLEncoded = "application/x-www-form-urlencoded"
}
