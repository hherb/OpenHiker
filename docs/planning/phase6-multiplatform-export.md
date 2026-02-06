# Phase 6: Multi-Platform & Export (Revised)

**Estimated effort:** ~8-11 weeks
**Dependencies:** All Phases 1–5 (builds on all prior features)
**Platform focus:** macOS (native), iPadOS (adaptive layouts), iOS (export), iCloud (sync)

## Overview

Adapt the app for iPad with adaptive layouts, build a first-class native macOS app as a planning/review hub, add export of completed hikes as PDF reports and Markdown summary cards, and sync data between devices via iCloud.

**Key changes from original plan:**
- Mac Catalyst replaced with a **native macOS Xcode target** for full macOS UX
- Export section scoped to what's **actually missing** (PR #6 already added GPX/JSON/Markdown export for `SharedRoute`)
- **iCloud sync** added so macOS app receives data from iOS

---

## Implementation Order

| Sub-feature | Size | Estimate | Rationale |
|------------|------|----------|-----------|
| **6.3 Export** | M | ~2 weeks | Fewest deps, immediate value, `HikeSummaryExporter` reusable by macOS later |
| **6.2 iPad Adaptive** | M | ~1-2 weeks | Quick wins; NavigationSplitView patterns inform macOS structure |
| **6.4 iCloud Sync** | L | ~2-3 weeks | Must be in place before macOS app is useful |
| **6.1 Native macOS** | XL | ~3-4 weeks | Largest scope; benefits from 6.2 + 6.3 + 6.4 being done first |

---

## Feature 6.3: Export (PDF, Hike Summary, Share Sheet)

**Size:** M (Medium)
**Estimated effort:** ~2 weeks
**Dependencies:** Phase 3 (SavedRoute), Phase 2 (Waypoints)

### What Already Exists (from PR #6 / Phase 5)

| Capability | Status | Location |
|-----------|--------|----------|
| GPX 1.1 export | Done | `Shared/Utilities/RouteExporter.swift` — `toGPX()` on `SharedRoute` |
| JSON export | Done | `Shared/Utilities/RouteExporter.swift` — `toJSON()` |
| Markdown (GitHub README) | Done | `Shared/Utilities/RouteExporter.swift` — `toMarkdown()` for `SharedRoute` community display |
| Community upload | Done | `OpenHiker iOS/Views/RouteUploadView.swift` + `Shared/Services/GitHubRouteService.swift` |

### What's Missing

| Capability | Why |
|-----------|-----|
| **PDF export** | No PDF generation exists anywhere in the codebase |
| **Personal hike summary Markdown** | Existing `toMarkdown()` is for `SharedRoute` GitHub display. `SavedRoute` has heart rate, calories, walking/resting time that `SharedRoute` does not carry |
| **Map snapshot for export** | No `MKMapSnapshotter` usage in codebase |
| **Elevation chart as image** | `ElevationProfileView` exists as SwiftUI view but no image rendering |
| **Multi-format export dialog** | Only "Share to Community" button exists on `HikeDetailView` |
| **Share sheet integration** | No `ShareLink` / `UIActivityViewController` |

### Personal Hike Summary Markdown

The existing `RouteExporter.toMarkdown()` produces a GitHub README for `SharedRoute`. It does NOT include:
- Heart rate (avg, max) — `SavedRoute` has `averageHeartRate`, `maxHeartRate`
- Calories — `SavedRoute` has `estimatedCalories`
- Walking vs. resting time — `SavedRoute` has `walkingTime`, `restingTime`
- Average speed — computable from `totalDistance / walkingTime`
- Date and time range of hike

Example output:

```markdown
# Hike: Blue Ridge Trail

**Date:** 6 February 2026, 08:15 – 12:38
**Duration:** 4h 23m (Walking: 3h 48m, Resting: 35m)

## Statistics

| Metric | Value |
|--------|-------|
| Distance | 12.4 km |
| Elevation Gain | +823 m |
| Elevation Loss | -756 m |
| Avg Heart Rate | 142 bpm |
| Max Heart Rate | 178 bpm |
| Calories | ~1,234 kcal |
| Avg Speed | 3.3 km/h |

## Waypoints

1. **Trailhead** (47.4211°N, 10.9853°E) — Start point
2. **Summit Viewpoint** (47.4312°N, 10.9790°E) — "Amazing views of the valley"

## Comments

Great weather, clear skies. Trail was well-marked.

---
*Recorded with OpenHiker — https://github.com/hherb/OpenHiker*
```

### PDF Export

Multi-page PDF generated with `UIGraphicsPDFRenderer`:

**Page 1: Cover & Summary**
- Title, date, duration
- Map snapshot (MKMapSnapshotter with route polyline overlay)
- Summary statistics table

**Page 2: Elevation Profile**
- Full-width elevation chart (render `ElevationProfileView` to image via `ImageRenderer`)
- Min/max/avg elevation annotations
- Distance markers on X axis

**Page 3+: Photo Gallery**
- 2-up photo grid with captions
- Each photo shows: thumbnail, waypoint name, coordinate, note
- Skip if no photos

**Final Page: Waypoint Table & Comments**
- Table with columns: #, Name, Category, Coordinate, Note
- Comments section

### Map Snapshot

Use `MKMapSnapshotter` to generate a static map image with route overlay:

```swift
func generateMapSnapshot(
    route: SavedRoute,
    waypoints: [Waypoint],
    size: CGSize
) async throws -> UIImage {
    let options = MKMapSnapshotter.Options()
    options.size = size
    options.mapType = .standard
    // Note: OpenTopoMap tiles can't be used in MKMapSnapshotter
    // Use standard Apple Maps for the export snapshot

    let snapshotter = MKMapSnapshotter(options: options)
    let snapshot = try await snapshotter.start()

    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
        snapshot.image.draw(at: .zero)
        // Draw route polyline
        // Draw waypoint markers
        // Draw start/end pins
    }
}
```

### Files to Create

#### `Shared/Services/HikeSummaryExporter.swift`
Operates on `SavedRoute` + `[Waypoint]` directly (distinct from `RouteExporter` which works with `SharedRoute`):
- `toMarkdown(route:waypoints:useMetric:) -> String` — personal hike card with HR, calories, walking/resting split, avg speed
- `toGPX(route:waypoints:) -> Data` — convenience: converts `SavedRoute` → `SharedRoute` → GPX internally

Reuses `HikeStatsFormatter` for locale-aware formatting. Goes in `Shared/` so macOS can use it too.

#### `OpenHiker iOS/Services/PDFExporter.swift`
iOS-specific (`UIGraphicsPDFRenderer`, `MKMapSnapshotter`, `ImageRenderer`):
- `exportAsPDF(route:waypoints:useMetric:) async throws -> Data`
- Internal helpers: `generateMapSnapshot(...)`, `renderElevationChart(...)`

#### `OpenHiker iOS/Views/ExportSheet.swift`
SwiftUI sheet with:
- Format picker: Quick Summary (Markdown), Detailed Report (PDF), GPS Track (GPX), All Formats
- Progress indicator during generation
- Preview section
- Share button using `ShareLink` (iOS 16+)

### Files to Modify

#### `OpenHiker iOS/Views/HikeDetailView.swift`
Add an Export toolbar button alongside the existing "Share to Community" button. Use a `Menu` with two items: "Share to Community" (existing `RouteUploadView`) and "Export" (new `ExportSheet`).

### Formatting Considerations

- **Locale-aware units:** Use `@AppStorage("useMetricUnits")` preference
- **Date formatting:** `DateFormatter` with user's locale (not hardcoded US format)
- **Coordinate format:** Degrees with 4 decimal places, N/S/E/W suffix
- **Number formatting:** `NumberFormatter` for locale-appropriate decimal separators

### Testing

1. Markdown export includes HR, calories, walking/resting split, avg speed
2. PDF multi-page layout: map snapshot with polyline, elevation chart, photos (present/absent), waypoint table
3. Share sheet delivers files via Messages, Mail, AirDrop
4. Edge cases: no photos → skip photo pages; no waypoints; no HR data
5. Locale testing: metric (km/m, comma decimals) vs imperial (mi/ft, period decimals)
6. PDF size stays < 10 MB for typical hike with 5-10 photos

---

## Feature 6.2: iPad Adaptive Layouts

**Size:** M (Medium)
**Estimated effort:** ~1-2 weeks
**Dependencies:** Phases 1-5 complete

### What It Does

The iOS target already has `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad). The current `ContentView` uses a 6-tab `TabView` optimized for iPhone. This sub-feature adds a `NavigationSplitView` layout for iPad's larger screen.

### Layout Strategy

#### iPhone (compact width)
```
TabView:
  Tab 1: Regions (map + download)
  Tab 2: Downloaded regions list
  Tab 3: Hikes (review)
  Tab 4: Routes (planning)
  Tab 5: Community (browse)
  Tab 6: Watch sync
```

#### iPad (regular width)
```
NavigationSplitView:
  Sidebar (220pt):         Detail:
    📍 Regions             Full-width content for selected section
    📂 Downloaded          - Maps use full available width
    🥾 Hikes              - Route planning: map + controls side-by-side
    🗺️ Routes             - Hike review: map + stats + elevation side-by-side
    🌐 Community
    📌 Waypoints
    ⌚ Watch
```

### Key Adaptations

#### Route Planning (iPad)
- Full-screen map takes ~70% of width
- Side panel (~30%) shows start/end/via-point list, mode toggle, route statistics, turn-by-turn directions (scrollable)

#### Hike Review (iPad)
- Map and elevation profile displayed side-by-side (not stacked)
- Statistics in a wide grid layout
- Photo gallery as a proper grid (not single-column list)

#### Region Management (iPad)
- Larger map for region selection
- Download configuration as side panel (instead of sheet)

### Implementation

Use `@Environment(\.horizontalSizeClass)` to switch layouts:

```swift
struct ContentView: View {
    @EnvironmentObject var watchConnectivity: WatchConnectivityManager
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                SidebarView()
            } detail: {
                DetailView()
            }
        } else {
            TabView {
                // ... existing tabs
            }
        }
    }
}
```

### Files to Create

#### `OpenHiker iOS/Views/SidebarView.swift`
Navigation sidebar with SF Symbol icons, selection state, badge counts.

#### `OpenHiker iOS/Views/WaypointsListView.swift`
Dedicated waypoints list view accessible from sidebar. Map showing all waypoints + filterable list.

### Files to Modify

#### `OpenHiker iOS/App/ContentView.swift`
- Refactor to use `horizontalSizeClass`
- `NavigationSplitView` path for iPad
- `TabView` path for iPhone (existing code largely unchanged)

#### `OpenHiker iOS/Views/HikeDetailView.swift`
On iPad: horizontal layout — map (60%) + elevation + stats panel (40%).

#### `OpenHiker iOS/Views/RoutePlanningView.swift`
On iPad: map (70%) + side panel (30%) with route controls.

#### `OpenHiker iOS/Views/RegionSelectorView.swift`
On iPad: larger map, side panel for download configuration.

### Testing

1. Build for iPhone simulator → verify TabView layout still works
2. Build for iPad simulator → verify NavigationSplitView layout
3. Split View multitasking → verify layout adapts when size class changes
4. Route planning on iPad → verify map + side panel layout
5. Hike review on iPad → verify horizontal map + elevation layout
6. No regressions in iPhone behavior

---

## Feature 6.4: iCloud Sync

**Size:** L (Large)
**Estimated effort:** ~2-3 weeks
**Dependencies:** Phases 1-5, needed before 6.1 (macOS) to be useful

### What It Does

Syncs routes, waypoints, planned routes, and region metadata between iOS and macOS via iCloud. Uses a combination of CloudKit (structured data), iCloud Documents (large files), and NSUbiquitousKeyValueStore (preferences).

### Sync Strategy

#### 1. CloudKit (for structured data: routes, waypoints, planned routes)

The existing `RouteStore`, `WaypointStore`, and `PlannedRouteStore` use raw SQLite3. Rather than migrating to Core Data + `NSPersistentCloudKitContainer` (which would require rewriting the storage layer), use **manual CloudKit sync**:

- Keep raw SQLite stores as the local source of truth
- Add a `CloudSyncManager` (Actor) that watches for local changes and syncs to CloudKit
- Subscribe to remote changes and apply them locally
- Use model `id: UUID` as `CKRecord.ID` for deduplication
- Conflict resolution: last-write-wins based on `modifiedAt` timestamp

#### 2. iCloud Documents (for region .mbtiles files)

MBTiles files are large (5-100 MB). Use iCloud Drive file coordination:
- `FileManager.default.url(forUbiquityContainerIdentifier:)` for iCloud container
- Store region files in the iCloud container's `Documents/regions/`
- `NSMetadataQuery` to discover files synced from other devices
- `NSFileCoordinator` for safe read/write

#### 3. NSUbiquitousKeyValueStore (for preferences)

Small settings (metric/imperial units, default author name, etc.) sync trivially.

### Architecture

#### `Shared/Services/CloudSyncManager.swift` (new, Actor)

Core sync coordinator:
- `syncRoutes()` — push/pull `SavedRoute` records to/from CloudKit private database
- `syncWaypoints()` — push/pull `Waypoint` records
- `syncPlannedRoutes()` — push/pull `PlannedRoute` records
- `observeRemoteChanges()` — CKSubscription for real-time push notifications
- Conflict resolution: last-write-wins based on `modifiedAt` timestamp

#### `Shared/Services/CloudKitStore.swift` (new)

Low-level CloudKit wrapper:
- `save(record:)`, `fetch(recordType:predicate:)`, `delete(recordID:)`
- Retry with exponential backoff (reuse pattern from `GitHubRouteService`)
- Batch operations for initial sync
- CKSubscription setup for change notifications

### Model Changes

All synced models need two new fields for iCloud coordination:
- `modifiedAt: Date` — for conflict resolution (last-write-wins)
- `cloudKitRecordID: String?` — for mapping to CKRecord

Models already have `id: UUID` which serves as the primary key and deduplication key.

### Entitlements

- iCloud capability with CloudKit
- iCloud Documents container: `iCloud.com.openhiker`
- CloudKit container: `iCloud.com.openhiker`

### Files to Create

| File | Purpose |
|------|---------|
| `Shared/Services/CloudSyncManager.swift` | Sync coordinator (Actor) |
| `Shared/Services/CloudKitStore.swift` | CloudKit CRUD wrapper |

### Files to Modify

| File | Change |
|------|--------|
| `Shared/Models/SavedRoute.swift` | Add `modifiedAt: Date`, `cloudKitRecordID: String?` fields |
| `Shared/Models/Waypoint.swift` | Add `modifiedAt: Date`, `cloudKitRecordID: String?` fields |
| `Shared/Models/PlannedRoute.swift` | Add `modifiedAt: Date`, `cloudKitRecordID: String?` fields |
| `Shared/Storage/RouteStore.swift` | Schema migration to add `modified_at` column |
| `Shared/Storage/WaypointStore.swift` | Schema migration to add `modified_at` column |
| `OpenHiker iOS/App/OpenHikerApp.swift` | Initialize `CloudSyncManager` on launch |
| iOS entitlements file | Add iCloud + CloudKit capability |

### Testing

1. Create a route on iOS → appears on second iOS device (or macOS once 6.1 is built)
2. Create a waypoint on one device → syncs to other
3. Edit route comment on both devices → last-write-wins resolves correctly
4. Delete a route on one device → deleted on other
5. Large MBTiles region file syncs via iCloud Documents
6. Offline editing → changes queue and sync when connectivity returns
7. Initial sync: existing data uploads on first iCloud enable
8. Preferences sync via NSUbiquitousKeyValueStore

---

## Feature 6.1: Native macOS App

**Size:** XL (Extra Large)
**Estimated effort:** ~3-4 weeks
**Dependencies:** Phases 1-5, 6.3 (Export), 6.4 (iCloud Sync)

### What It Does

A first-class native macOS SwiftUI application as a **separate Xcode target** ("OpenHiker macOS") — NOT Mac Catalyst. Serves as a full-featured planning and review hub with native macOS idioms. Cannot sync with Apple Watch directly (WatchConnectivity unavailable on macOS), but receives data from iOS via iCloud sync (6.4).

### macOS App Role

1. **Route planning** — full-screen map, drag-and-drop GPX import, side panel controls
2. **Hike review** — saved hikes with maps, elevation profiles, statistics, photos
3. **Community** — browse/download/upload community routes
4. **Region management** — download and manage offline tile regions
5. **Export** — PDF, Markdown, GPX (using `HikeSummaryExporter` from 6.3 + macOS-specific PDF renderer)
6. **iCloud sync** — automatically receives routes/waypoints/regions from iOS via 6.4

### macOS-Native Features

These are features that Mac Catalyst cannot deliver well — the reason for building a native target:

- **NavigationSplitView** with proper three-column layout (sidebar + content + detail)
- **Menu bar commands** — File → Import GPX, File → Export, File → New Route, Edit → Settings
- **Keyboard shortcuts** — ⌘N (new route), ⌘E (export), ⌘I (import GPX), ⌘, (settings), Delete (remove selected)
- **NSSavePanel / NSOpenPanel** for native file import/export dialogs
- **Drag-and-drop** for GPX files onto the map (`onDrop(of: [.fileURL])` with UTType)
- **Multiple window support** (open different routes in separate windows via `WindowGroup`)
- **Window state restoration** with minimum size 900×600 and `defaultSize`
- **Proper macOS Settings window** (SwiftUI `Settings` scene with tabbed layout)
- **Right-click context menus** on routes, waypoints, regions
- **Table-style list views** with sortable columns for hike browsing
- **Toolbar customization** with standard macOS toolbar items

### Layout Strategy

```
NavigationSplitView (three-column):
  Sidebar (220pt):         Content:              Detail:
    📍 Regions             Region list/map        Selected region info
    📂 Downloaded          Downloaded list        Region detail
    🥾 Hikes              Hikes table            HikeDetailView
    🗺️ Routes             Planned routes list    RouteDetailView
    🌐 Community          Browse list            CommunityRouteDetailView
    📌 Waypoints          Waypoints list         WaypointDetailView
```

### Xcode Project Changes

**New target:** "OpenHiker macOS"
- Product type: `com.apple.product-type.application`
- Platform: macOS 14.0+ (Sonoma — for MapKit SwiftUI, Charts, NavigationSplitView)
- Bundle identifier: `com.openhiker.macos`
- Linked frameworks: `SQLite3.tbd`, MapKit, Charts, UniformTypeIdentifiers, CloudKit
- **NOT linked:** HealthKit, WatchConnectivity

**Source file membership for macOS target:**

All `Shared/` files (19 files, after platform guard updates):
- `Shared/Models/` — all 10 model files
- `Shared/Storage/` — all 4 store files
- `Shared/Services/` — `RoutingEngine.swift`, `GitHubRouteService.swift`, `CloudSyncManager.swift` (from 6.4), `CloudKitStore.swift` (from 6.4)
- `Shared/Utilities/` — `TrackCompression.swift`, `RouteExporter.swift`, `PhotoCompressor.swift`
- `Shared/Services/HikeSummaryExporter.swift` (from 6.3)

Reused iOS services (pure Swift/networking — add to macOS target as-is):
- `OpenHiker iOS/Services/TileDownloader.swift`
- `OpenHiker iOS/Services/RegionStorage.swift`
- `OpenHiker iOS/Services/RoutingGraphBuilder.swift`
- `OpenHiker iOS/Services/PBFParser.swift`
- `OpenHiker iOS/Services/ProtobufReader.swift`
- `OpenHiker iOS/Services/ElevationDataManager.swift`
- `OpenHiker iOS/Services/OSMDataDownloader.swift`

### Shared Code Platform Guards

#### `Shared/Storage/TileStore.swift`

Current (lines 20-24):
```swift
#if canImport(UIKit)
import UIKit
#elseif canImport(WatchKit)
import WatchKit
#endif
```

Change to:
```swift
#if canImport(UIKit)
import UIKit
#elseif canImport(WatchKit)
import WatchKit
#elseif canImport(AppKit)
import AppKit
#endif
```

Current (line 310): `#if os(iOS)` gating `WritableTileStore`.
Change to: `#if os(iOS) || os(macOS)` — `WritableTileStore` has no UIKit dependencies, only SQLite3/Foundation.

#### `Shared/Utilities/PhotoCompressor.swift`

Current: all image methods inside `#if canImport(UIKit)` using `UIImage` + `UIGraphicsImageRenderer`.

Add `#elseif canImport(AppKit)` block with:
- `compress(_ image: NSImage) -> Data?` using `NSBitmapImageRep` + JPEG encoding
- `compressData(_ data: Data) -> Data?` using `NSImage(data:)`
- `downsample(_ image: NSImage, ...)` using `NSImage.lockFocus()` / Core Graphics

### WatchConnectivity on Mac

WatchConnectivity is **not available on macOS**. The macOS app:
- Cannot send regions to the watch directly
- Receives synced data from iOS via iCloud (6.4)
- Functions as a planning/review/export station
- Watch-related UI sections (Watch Sync tab) are hidden on macOS

No platform guards needed in shared code — `WatchConnectivityManager` and `WatchTransferManager` are only in iOS-specific files that are not added to the macOS target.

### Files to Create

#### App Layer

| File | Purpose |
|------|---------|
| `OpenHiker macOS/App/OpenHikerMacApp.swift` | `@main` entry point. Initialize stores + CloudSync. `WindowGroup` + `Settings` scene + `.commands { MacCommands() }`. Window minimum size 900×600. |
| `OpenHiker macOS/App/MacContentView.swift` | `NavigationSplitView` root with three-column layout. Sidebar selection drives content and detail panes. |
| `OpenHiker macOS/App/MacCommands.swift` | Custom `Commands` struct: File → Import GPX (`NSOpenPanel`), File → Export (`NSSavePanel`), File → New Route. Keyboard shortcuts: ⌘N, ⌘E, ⌘I, ⌘,, Delete. |

#### Views

| File | Purpose |
|------|---------|
| `OpenHiker macOS/Views/MacSidebarView.swift` | Navigation sidebar with sections (SF Symbol icons, selection state, badge counts for hike/route counts) |
| `OpenHiker macOS/Views/MacRegionSelectorView.swift` | Region selection with MapKit. Larger map area. Drag-and-drop GPX import onto map. Download config as side panel. |
| `OpenHiker macOS/Views/MacHikeDetailView.swift` | Horizontal layout: map (60%) + stats panel (40%). Elevation profile below map. Wide stats grid. Photo grid. Export button in toolbar. |
| `OpenHiker macOS/Views/MacRoutePlanningView.swift` | Full-width map (~70%) + side panel (~30%) with start/end/via list, mode toggle, stats, directions. Right-click context menu for adding waypoints. |
| `OpenHiker macOS/Views/MacHikesListView.swift` | Table-style layout with sortable columns (name, date, distance, elevation). Search bar. Context menu: Delete, Export, Share to Community. Multi-selection. |
| `OpenHiker macOS/Views/MacAddWaypointView.swift` | No camera — uses `NSOpenPanel` for photo file picker. Form layout in sheet or popover. Drag-and-drop image support. |
| `OpenHiker macOS/Views/MacSettingsView.swift` | macOS Settings window (SwiftUI `Settings` scene). Tabs: General (units, author name), Community (country, area), Map (default zoom). |
| `OpenHiker macOS/Views/MacCommunityBrowseView.swift` | Community browse adapted for macOS. Three-column: filter sidebar + route list + detail preview. |
| `OpenHiker macOS/Views/GPXImportHandler.swift` | GPX file import: `NSOpenPanel` with `.gpx` filter, parse → `PlannedRoute` or display on map. UTType registration for drag-and-drop. |

#### Services

| File | Purpose |
|------|---------|
| `OpenHiker macOS/Services/MacPDFExporter.swift` | macOS PDF generation using `CGContext`/`NSGraphicsContext`. Same page structure as iOS `PDFExporter`. `MKMapSnapshotter` works on macOS. |

### Testing

1. **Build:** `xcodebuild -scheme "OpenHiker macOS" -destination "platform=macOS"` succeeds
2. **Shared code:** All 19+ shared files compile for macOS without errors
3. **NavigationSplitView:** Sidebar selection → content → detail navigation works
4. **Menu bar:** File → Import GPX opens `NSOpenPanel`, File → Export opens `NSSavePanel`
5. **Keyboard shortcuts:** ⌘N, ⌘E, ⌘I, Delete, ⌘, all trigger correct actions
6. **Window management:** Resize respects 900×600 minimum, state persists across launches
7. **Region download:** `TileDownloader` + `WritableTileStore` create MBTiles on macOS
8. **MapKit rendering:** Works in region selector, hike detail, route planning views
9. **SQLite stores:** WaypointStore, RouteStore, RoutingStore CRUD works correctly
10. **Community browse:** `GitHubRouteService` fetches index, routes load
11. **PhotoCompressor:** NSImage path compresses correctly
12. **Drag-and-drop:** GPX files droppable onto map
13. **iCloud sync:** Route created on iOS appears on macOS
14. **Export:** PDF via `MacPDFExporter`, Markdown via `HikeSummaryExporter`

---

## Full File Summary

### Modified (shared — affects all targets)

| File | Change |
|------|--------|
| `Shared/Storage/TileStore.swift` | Add `#elseif canImport(AppKit)` import; expand `WritableTileStore` to `os(iOS) \|\| os(macOS)` |
| `Shared/Utilities/PhotoCompressor.swift` | Add `#elseif canImport(AppKit)` block with NSImage equivalents |
| `Shared/Models/SavedRoute.swift` | Add `modifiedAt: Date`, `cloudKitRecordID: String?` for iCloud sync |
| `Shared/Models/Waypoint.swift` | Add `modifiedAt: Date`, `cloudKitRecordID: String?` for iCloud sync |
| `Shared/Models/PlannedRoute.swift` | Add `modifiedAt: Date`, `cloudKitRecordID: String?` for iCloud sync |
| `Shared/Storage/RouteStore.swift` | Schema migration for `modified_at` column |
| `Shared/Storage/WaypointStore.swift` | Schema migration for `modified_at` column |

### New (shared)

| File | Purpose |
|------|---------|
| `Shared/Services/HikeSummaryExporter.swift` | Personal hike Markdown + GPX from `SavedRoute` (6.3) |
| `Shared/Services/CloudSyncManager.swift` | iCloud sync coordinator, Actor (6.4) |
| `Shared/Services/CloudKitStore.swift` | CloudKit CRUD wrapper (6.4) |

### New/Modified (iOS)

| File | Purpose |
|------|---------|
| `OpenHiker iOS/Services/PDFExporter.swift` | NEW — multi-page PDF generation (6.3) |
| `OpenHiker iOS/Views/ExportSheet.swift` | NEW — multi-format export dialog (6.3) |
| `OpenHiker iOS/Views/SidebarView.swift` | NEW — iPad navigation sidebar (6.2) |
| `OpenHiker iOS/Views/WaypointsListView.swift` | NEW — dedicated waypoints list (6.2) |
| `OpenHiker iOS/App/ContentView.swift` | MODIFY — adaptive TabView/NavigationSplitView (6.2) |
| `OpenHiker iOS/App/OpenHikerApp.swift` | MODIFY — initialize CloudSyncManager (6.4) |
| `OpenHiker iOS/Views/HikeDetailView.swift` | MODIFY — export button + iPad adaptive layout (6.2, 6.3) |
| `OpenHiker iOS/Views/RoutePlanningView.swift` | MODIFY — iPad side panel layout (6.2) |
| `OpenHiker iOS/Views/RegionSelectorView.swift` | MODIFY — iPad side panel (6.2) |
| iOS entitlements file | MODIFY — add iCloud + CloudKit (6.4) |

### New (macOS — ~14 files)

| File | Purpose |
|------|---------|
| `OpenHiker macOS/App/OpenHikerMacApp.swift` | App entry point (6.1) |
| `OpenHiker macOS/App/MacContentView.swift` | NavigationSplitView root (6.1) |
| `OpenHiker macOS/App/MacCommands.swift` | Menu bar commands (6.1) |
| `OpenHiker macOS/Views/MacSidebarView.swift` | Sidebar (6.1) |
| `OpenHiker macOS/Views/MacRegionSelectorView.swift` | Region selection + drag-and-drop (6.1) |
| `OpenHiker macOS/Views/MacHikeDetailView.swift` | Hike review (6.1) |
| `OpenHiker macOS/Views/MacRoutePlanningView.swift` | Route planning (6.1) |
| `OpenHiker macOS/Views/MacHikesListView.swift` | Table-style hike list (6.1) |
| `OpenHiker macOS/Views/MacAddWaypointView.swift` | Waypoint creation, file picker (6.1) |
| `OpenHiker macOS/Views/MacSettingsView.swift` | Settings window (6.1) |
| `OpenHiker macOS/Views/MacCommunityBrowseView.swift` | Community browse (6.1) |
| `OpenHiker macOS/Views/GPXImportHandler.swift` | GPX import (6.1) |
| `OpenHiker macOS/Services/MacPDFExporter.swift` | macOS PDF generation (6.1) |
