# Second Stream

An iOS-only, personal fork of [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire), reworked around a private n8n backend for account sync, podcast/news/YouTube sources, and bootstrap progress.

## Structure

- `iOS/` — app target (views, controllers, storyboards)
- `Shared/` — code shared across the app (API client, auth, sources, settings)
- `Modules/` — local Swift packages (Account, Articles, ArticlesDatabase, RSCore, RSParser, RSWeb, RSDatabase, RSTree, Secrets, SyncDatabase, FeedFinder)

## Building

Open `SecondStream.xcodeproj` in Xcode and build the `SecondStream-iOS` scheme. Two bundled, gitignored text files are required at build time (not included in this repo):

- `Shared/PodcastSources/podcast_token.txt` — bootstrap API token
- `Shared/API/webhook_base_url.txt` — base URL for the backend webhooks

## License

MIT — see [LICENSE](LICENSE). Original copyright (c) 2002-2025 Brent Simmons.
