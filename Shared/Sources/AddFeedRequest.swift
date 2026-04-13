//
//  AddFeedRequest.swift
//  Second Stream
//
//  Created by Nicolas Widynski on 2026-04-10.
//  Copyright © 2026 STDN. All rights reserved.
//

import Account

/// Captures all parameters needed to subscribe to a feed, replacing the long
/// `addFeedDirectly` parameter list. Adding new metadata fields here costs
/// zero callsite churn — callers that don't need the field omit it.
struct AddFeedRequest {
	let urlString: String
	let category: FeedCategory
	let name: String?
	let author: String?
	let imageURL: String?
	let imageURLLight: String?
	/// When `false`, skip feed validation (used for webhook-generated feeds whose URL is
	/// already known to be well-formed).
	let validateFeed: Bool
	/// Server-side JSON summary URL; used to fetch the canonical feed icon when `validateFeed`
	/// is `false`.
	let summaryURL: String?
	/// When `true`, omit the "Adding…" loading indicator (caller already shows one).
	let skipLoadingIndicator: Bool

	init(
		urlString: String,
		category: FeedCategory,
		name: String? = nil,
		author: String? = nil,
		imageURL: String? = nil,
		imageURLLight: String? = nil,
		validateFeed: Bool = true,
		summaryURL: String? = nil,
		skipLoadingIndicator: Bool = false
	) {
		self.urlString = urlString
		self.category = category
		self.name = name
		self.author = author
		self.imageURL = imageURL
		self.imageURLLight = imageURLLight
		self.validateFeed = validateFeed
		self.summaryURL = summaryURL
		self.skipLoadingIndicator = skipLoadingIndicator
	}
}
