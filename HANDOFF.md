# HANDOFF: Light/Dark Adaptive Feed Icons

## What We're Fixing

Feed icons in three places should show a **light variant** in light mode and a **dark variant** in dark mode:
1. Main feed list (sidebar cells)
2. Timeline nav bar (right bar button, circular icon)
3. Article nav bar (same)

Icons come from server-side JSON source files that provide both an `image_url` (dark) and `image_url_light` (light) field per feed.

---

## Current Infrastructure (Already Built)

| Component | File | What It Does |
|---|---|---|
| `LightFeedIconStore` | `Shared/Favicons/LightFeedIconStore.swift` | Persists `[feedURL → lightIconURL]` in UserDefaults |
| `SourceImageCache` | `Shared/Images/SourceImageCache.swift` | Downloads + caches source images; `adaptiveImage(darkURL:lightURL:)` builds a `UIImageAsset` |
| `IconImageCache.imageForFeed` | `Shared/IconImageCache.swift:154` | Creates `UIImageAsset` for podcast/youtube/news when both images are available |
| `IconImageCache.rssLibraryIcon` | `Shared/IconImageCache.swift:200` | Uses `SourceImageCache.adaptiveImage` for RSS library feeds |
| Source managers | `PodcastSourcesManager`, `YoutubeSourcesManager`, `RSSSourcesManager` | Populate `LightFeedIconStore` from light URLs after fetching |

---

## Root Causes of Failure

### 1. Nav bar icons are rasterized — kills `UIImageAsset` (PRIMARY BUG)

**File:** `iOS/MainTimeline/MainTimelineViewController.swift:154`
**Method:** `FeedNavigationChrome.makeTopBarFeedIcon`

```swift
let result = UIGraphicsImageRenderer(size: canvasSize).image { _ in
    UIBezierPath(ovalIn: ...).addClip()
    sourceImage.draw(in: ...)  // ← captures pixels at current trait, destroys UIImageAsset
}.withRenderingMode(.alwaysOriginal)
```

`UIGraphicsImageRenderer` renders `iconImage.image` to a static bitmap. Even if `iconImage.image` is backed by a `UIImageAsset` with both light/dark variants registered, the renderer asks for pixels at the **current** trait collection and produces a plain `UIImage`. The adaptive backing is gone.

**Fix:** Render **two bitmaps** — one with dark trait, one with light trait — then register both with a new `UIImageAsset` and return the dark-backed image. The `UIButton` in the nav bar (set via `setBackgroundImage`) does automatically resolve `UIImageAsset` variants because it inherits trait changes from the view hierarchy.

```swift
// In makeTopBarFeedIcon, instead of a single renderer:
let darkTraitEnv = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: .dark)])
let lightTraitEnv = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: .light)])
let darkBitmap = UIGraphicsImageRenderer(size: canvasSize, format: .init(for: darkTraitEnv)).image { ctx in
    ctx.cgContext.setFillColor(UIColor.black.cgColor) // or whatever bg
    UIBezierPath(ovalIn: ...).addClip()
    darkSourceImage.draw(in: ...)
}.withRenderingMode(.alwaysOriginal)
let lightBitmap = UIGraphicsImageRenderer(size: canvasSize, format: .init(for: lightTraitEnv)).image { ctx in
    UIBezierPath(ovalIn: ...).addClip()
    lightSourceImage.draw(in: ...)
}.withRenderingMode(.alwaysOriginal)
let asset = UIImageAsset()
asset.register(darkBitmap, with: UITraitCollection(userInterfaceStyle: .dark))
asset.register(lightBitmap, with: UITraitCollection(userInterfaceStyle: .light))
return darkBitmap  // .imageAsset is now set; UIButton/UIImageView will resolve automatically
```

BUT this requires the light image to be available **before** the nav icon is rendered. See Root Cause 4.

---

### 2. `topBarIconCache` is mode-blind

**File:** `iOS/MainTimeline/MainTimelineViewController.swift` (`FeedNavigationChrome`)

The icon cache keys on feed ID only. Once the dark bitmap is cached, switching to light mode returns the cached dark bitmap — the two-bitmap fix above would be undermined.

**Fix:** Key the cache on `"\(feedID):\(traitStyle)"` OR store the `UIImageAsset`-backed image itself (which auto-resolves), not two separate bitmaps. The cleanest approach is to cache the **adaptive image** (dark image backed by the asset) without splitting by style — then it self-resolves.

---

### 3. Nav bar `lastNavigationIconKey` blocks re-render on mode switch

**File:** `iOS/MainTimeline/MainTimelineViewController.swift:1193`

```swift
let iconKey = String(describing: iconSource?.sidebarItemID)
if iconKey == lastNavigationIconKey, navigationItem.rightBarButtonItem != nil {
    return  // ← skips update when switching modes with same feed selected
}
```

When the user switches dark↔light while a feed is open, this short-circuits the update and the nav bar keeps the old icon.

**Fix:** If the fix is "cache one adaptive image", this isn't needed anymore — the image auto-resolves. But if re-rendering is required, clear `lastNavigationIconKey = nil` from the trait-change handler that already exists in `MainTimelineViewController`.

---

### 4. Light image may not be downloaded when `imageForFeed` first runs

**File:** `Shared/IconImageCache.swift:176`

```swift
if let lightURL = LightFeedIconStore.shared.lightIconURL(for: feed.url),
   let lightImage = SourceImageCache.shared.image(for: lightURL) {
    // Only reaches here if light image is already in cache
```

`SourceImageCache.image(for:)` starts a download and returns `nil` if not cached yet. So on first run, `lightImage` is nil, the asset is never created, and `feedIconImageCache[feedID]` is set to the plain dark `iconImage`. Later, `sourceImageDidBecomeAvailable` fires → `invalidateFeedCaches` → `feedIconDidBecomeAvailable` → cells reconfigure. On the second call to `imageForFeed`, `lightImage` should now be available and the asset IS created. **This path should eventually work for cells.**

The issue is timing: the cell may show the dark icon briefly, and then switch — which is acceptable. But for nav bars, step 2 and 3 above prevent any switch.

---

### 5. `addDiscoverSource` drops the light URL

**File:** `iOS/MainFeed/MainFeedCollectionViewController.swift:514`

```swift
addFeedDirectly(urlString: urlString, category: source.category,
    sourceName: source.name, sourceAuthor: source.author,
    sourceImageURL: source.imageURL)
    // ← sourceImageURLLight is NOT passed
```

When a user adds a feed from the source picker, the light image URL from `source.imageURLLight` is silently dropped. The light icon is never stored in `LightFeedIconStore` for that feed session.

**Fix:** Add a `sourceImageURLLight` parameter to `addFeedDirectly` and store it in `LightFeedIconStore` immediately (mirroring what source managers do on load).

---

## Exact Next Steps

### Step 1 — Fix `addDiscoverSource` light URL (quick, unblocks testing)

In `MainFeedCollectionViewController`:

1. Add `sourceImageURLLight: String? = nil` parameter to `addFeedDirectly`.
2. At the top of `addFeedDirectly`, after setting `feed.iconURL`, also call:
   ```swift
   if let lightURL = sourceImageURLLight {
       LightFeedIconStore.shared.setLightIconURL(lightURL, for: feed.url)
   }
   ```
3. At the `addDiscoverSource` callsite (line 514), pass `sourceImageURLLight: source.imageURLLight`.

### Step 2 — Fix nav bar icon rendering in `FeedNavigationChrome.makeTopBarFeedIcon`

The goal: produce a single `UIImage` backed by a `UIImageAsset` containing both dark and light circle-clipped bitmaps.

1. In `imageForFeed` / `rssLibraryIcon`, the `iconImage` that reaches `makeTopBarFeedBarButton` already contains just the dark image. We need to also pass the light image.
   - Option A: Change `makeTopBarFeedBarButton(iconImage:...)` to also accept `lightIconImage: IconImage?`.
   - Option B: Attach the light image to `IconImage` struct (add `lightImage: UIImage?` field).
   - Option B is cleaner. Add `lightImage: UIImage?` to `IconImage`.

2. Populate `iconImage.lightImage` in `IconImageCache.imageForFeed`:
   ```swift
   if let lightURL = LightFeedIconStore.shared.lightIconURL(for: feed.url),
      let lightImg = SourceImageCache.shared.image(for: lightURL) {
       // Attach to iconImage for use during nav bar rendering
       return IconImage(iconImage.image, lightImage: lightImg, ...)
   }
   ```

3. In `makeTopBarFeedIcon`, if `iconImage.lightImage` is non-nil:
   - Render the dark circle using `UIGraphicsImageRenderer` with dark trait → `darkBitmap`
   - Render the light circle using light source image → `lightBitmap`
   - Create `UIImageAsset`, register both
   - Return `darkBitmap` (asset-backed, auto-resolves in `UIButton`/`UIImageView`)
   - Cache the asset-backed image by feed ID (no style suffix needed)

4. Remove the `lastNavigationIconKey` short-circuit check, or include a trait-style suffix in the key so mode switches trigger a re-render. (With a proper adaptive image, the `UIButton` auto-resolves without re-rendering — but the bar button item itself must be set at least once with the adaptive image.)

### Step 3 — Verify cells work (should be free once the image pipeline is right)

After Step 1 and 2, manually test:
- In light mode: add a podcast from the picker → main feed list cell should show the light icon
- Switch to dark mode → same cell should switch to dark icon automatically (UIImageView resolves UIImageAsset)
- Nav bar in MainTimelineViewController → should also switch
- Nav bar in ArticleViewController → same

If cells don't switch, the issue is that `UIImageView.image` was set with a non-asset image. Add a debug assertion: `assert(iconImage.image.imageAsset != nil)` inside `configureIcon` after the fix.

---

## Files To Modify

| File | Change |
|---|---|
| `Shared/IconImageCache.swift` | Build adaptive `IconImage` with `lightImage` populated from `LightFeedIconStore` + `SourceImageCache` |
| `iOS/MainTimeline/MainTimelineViewController.swift` | Fix `makeTopBarFeedIcon` to render dark+light bitmaps and return asset-backed image; fix cache key |
| `iOS/MainFeed/MainFeedCollectionViewController.swift` | Pass `sourceImageURLLight` through `addDiscoverSource` → `addFeedDirectly` → `LightFeedIconStore` |
| `iOS/Article/ArticleViewController.swift` | Same nav bar fix as MainTimeline (they share `FeedNavigationChrome`) |

---

## What Is Already Working (Do Not Redo)

- `LightFeedIconStore` — persists correctly, populated by source managers on load
- `SourceImageCache.adaptiveImage` — correctly builds `UIImageAsset` for RSS feeds
- `SourceImageCache.prefetchImages` — pre-warms light image downloads
- `IconImageCache.sourceImageDidBecomeAvailable` — invalidates caches and posts `feedIconDidBecomeAvailable` when light images finish downloading
- Source manager light URL population (Podcast, YouTube, RSS, News managers)
- Section header icons toggle in Appearance settings
- Add menu `preferredElementSize = .large`
