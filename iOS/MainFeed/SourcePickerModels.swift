//
//  SourcePickerModels.swift
//  NetNewsWire
//
//  Created by Claude on 2026-02-13.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import Foundation

enum SourcePickerSection: Hashable {
	case customEntry
	case sources(String) // section title
	case paidSources     // stable identity for the credits-gated section
	case findResults     // remote search results appended inline
}

enum SourcePickerItem: Hashable {
	case customEntryName
	case customEntryURL
	case podcastSource(PodcastSource)
	case youtubeSource(YoutubeSource)
	case newsSource(NewsSource)
	case rssSource(RSSSource)
	case findCandidate(FindShowCandidate)
	case findLoading
}
