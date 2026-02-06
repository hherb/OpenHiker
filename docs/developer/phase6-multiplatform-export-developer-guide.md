# Phase 6: Multi-Platform & Export — Developer Guide

This document covers the implementation of Phase 6: iPad adaptive layouts, hike export (PDF/Markdown/GPX), iCloud sync, and native macOS app. Read this before modifying, expanding, or debugging any of these features.

---

## Feature Overview

Phase 6 adds four sub-features:

1. **6.3 Export** — PDF, Markdown, and GPX export of personal hikes via share sheet
2. **6.2 iPad Adaptive** — NavigationSplitView sidebar layout on iPad, TabView on iPhone
3. **6.4 iCloud Sync** — Bidirectional CloudKit sync for routes, waypoints, and planned routes
4. **6.1 macOS App** — Native macOS target with NavigationSplitView, menu commands, and macOS-specific PDF export

---

## Architecture Diagram

```
                    iCloud (CloudKit Private DB)
                         |          |
                    push/pull   push/pull
                         |          |
   iOS/iPadOS App -------+          +------- macOS App
   +------------------+                  +------------------+
   | ContentView      |                  | MacContentView   |
   |  iPhone: TabView |                  | NavigationSplit  |
   |  iPad: SplitView |                  |   3-column       |
   |                  |                  |                  |
   | HikeDetailView   |                  | MacHikeDetail    |
   |  Export button   |                  |  Export via       |
   |  -> ExportSheet  |                  |  NSSavePanel     |
   +------------------+                  +------------------+
          |                                      |
          v                                      v
   Shared Layer (both targets)
   +------------------------------------------------+
   | Models: SavedRoute, Waypoint, PlannedRoute     |
   |   (+modifiedAt, +cloudKitRecordID fields)      |
   | Storage: RouteStore, WaypointStore              |
   |   (+schema migration for sync columns)          |
   | Services: HikeSummaryExporter (Markdown+GPX)   |
   |           CloudSyncManager (Actor)              |
   |           CloudKitStore (Actor)                 |
   | Utilities: PhotoCompressor (#if AppKit/UIKit)   |
   +------------------------------------------------+
```

---

## File Map

### Shared (iOS + macOS targets)

| File | Purpose |
|------|---------|
| `Shared/Services/HikeSummaryExporter.swift` | Personal hike Markdown + GPX export from `SavedRoute` |
| `Shared/Services/CloudKitStore.swift` | Actor wrapping CKDatabase for typed CRUD operations |
| `Shared/Services/CloudSyncManager.swift` | Bidirectional sync coordinator between local SQLite and iCloud |

### Modified Shared Files

| File | Change |
|------|--------|
| `Shared/Models/SavedRoute.swift` | Added `modifiedAt: Date?`, `cloudKitRecordID: String?` |
| `Shared/Models/Waypoint.swift` | Added `modifiedAt: Date?`, `cloudKitRecordID: String?` |
| `Shared/Models/PlannedRoute.swift` | Added `modifiedAt: Date?`, `cloudKitRecordID: String?` |
| `Shared/Storage/RouteStore.swift` | Schema migration + updated INSERT/UPDATE/parse for new columns |
| `Shared/Storage/WaypointStore.swift` | Schema migration for `modified_at` and `cloudkit_record_id` |
| `Shared/Storage/TileStore.swift` | Added `#elseif canImport(AppKit)`, expanded `WritableTileStore` to macOS |
| `Shared/Utilities/PhotoCompressor.swift` | Added `#elseif canImport(AppKit)` block with NSImage methods |

### iOS-Only (new)

| File | Purpose |
|------|---------|
| `OpenHiker iOS/Services/PDFExporter.swift` | Multi-page PDF via `UIGraphicsPDFRenderer` + `MKMapSnapshotter` |
| `OpenHiker iOS/Views/ExportSheet.swift` | Format picker + preview + `UIActivityViewController` share sheet |
| `OpenHiker iOS/Views/SidebarView.swift` | iPad sidebar with `SidebarSection` enum |
| `OpenHiker iOS/Views/WaypointsListView.swift` | Grouped waypoints list (iPad sidebar section) |
| `OpenHiker iOS/OpenHiker iOS.entitlements` | iCloud + CloudKit entitlements |

### iOS-Only (modified)

| File | Change |
|------|--------|
| `OpenHiker iOS/App/ContentView.swift` | Adaptive layout: `horizontalSizeClass` switches TabView/SplitView |
| `OpenHiker iOS/App/OpenHikerApp.swift` | Added `initializeCloudSync()` call |
| `OpenHiker iOS/Views/HikeDetailView.swift` | Export button via `Menu` with "Export Hike..." and "Share to Community" |

### macOS-Only (new)

| File | Purpose |
|------|---------|
| `OpenHiker macOS/App/OpenHikerMacApp.swift` | `@main` entry point, WindowGroup + Settings scene |
| `OpenHiker macOS/App/MacContentView.swift` | NavigationSplitView root, `MacSidebarSection` enum |
| `OpenHiker macOS/App/OpenHikerCommands.swift` | Menu bar commands (Cmd+Shift+S for sync) |
| `OpenHiker macOS/Views/MacHikesView.swift` | Hikes list with NavigationSplitView |
| `OpenHiker macOS/Views/MacHikeDetailView.swift` | Map + elevation + stats + export via `FileDocument` |
| `OpenHiker macOS/Views/MacWaypointsView.swift` | Table-style sortable waypoints list |
| `OpenHiker macOS/Views/MacPlannedRoutesView.swift` | Read-only planned routes (planning is iOS-only) |
| `OpenHiker macOS/Views/MacCommunityView.swift` | Community route browser |
| `OpenHiker macOS/Views/MacSettingsView.swift` | Settings with General + Sync tabs |
| `OpenHiker macOS/Services/MacPDFExporter.swift` | Core Graphics PDF + `ExportDocument` (FileDocument) |
| `OpenHiker macOS/OpenHiker macOS.entitlements` | iCloud, sandbox, network, file access |

---

## 6.3 Export — How It Works

### HikeSummaryExporter (Shared)

Location: `Shared/Services/HikeSummaryExporter.swift`

A pure static `enum` (no instances) with two methods:

```swift
enum HikeSummaryExporter {
    static func toMarkdown(route: SavedRoute, waypoints: [Waypoint], useMetric: Bool) -> String
    static func toGPX(route: SavedRoute, waypoints: [Waypoint]) -> Data
}
```

**Markdown** output includes personal stats not found in the community `RouteExporter.toMarkdown()`: heart rate, calories, walking/resting time, average speed, date/time range, and comments.

**GPX** delegates to existing `RouteExporter.toGPX()` by first converting `SavedRoute` to a `SharedRoute` (the community format). Waypoints are included as GPX waypoint elements.

**Distinction from RouteExporter:** `RouteExporter` operates on `SharedRoute` for GitHub community display. `HikeSummaryExporter` operates on `SavedRoute` + `[Waypoint]` for personal export with full health/timing data.

### PDFExporter (iOS)

Location: `OpenHiker iOS/Services/PDFExporter.swift`

Multi-page PDF using `UIGraphicsPDFRenderer` (A4 size, 595x842pt):

| Page | Content |
|------|---------|
| 1 | Cover: title, date, duration. Map snapshot via `MKMapSnapshotter` with route polyline overlay. Summary statistics grid. |
| 2 | Full-width elevation chart rendered via `ImageRenderer` from a SwiftUI `Chart`. Min/max/avg annotations. |
| 3+ | Photo gallery: 2-up grid with captions. Skipped if no waypoint photos. |
| Last | Waypoints table + comments section. |

Key async method:
```swift
static func exportAsPDF(route: SavedRoute, waypoints: [Waypoint], useMetric: Bool) async throws -> Data
```

The `async` is needed because `MKMapSnapshotter.start()` is async.

**Map snapshot:** Uses standard Apple Maps (not OpenTopoMap — `MKMapSnapshotter` cannot use custom tile sources). The route polyline is drawn onto the snapshot image using `UIGraphicsImageRenderer`.

**Elevation chart:** Uses `ImageRenderer` (iOS 16+) to render a SwiftUI `Chart` view to a `UIImage` for inclusion in the PDF.

### ExportSheet (iOS)

Location: `OpenHiker iOS/Views/ExportSheet.swift`

Components:
- `ExportFormat` enum: `.markdown`, `.pdf`, `.gpx` with display metadata
- `ExportSheet` view: format picker, Markdown preview, async export, share button
- `ShareSheetView`: `UIViewControllerRepresentable` wrapping `UIActivityViewController`

Data flow:
1. User taps "Export Hike..." in HikeDetailView toolbar Menu
2. ExportSheet presents with format picker
3. User selects format -> preview updates (Markdown only shows inline preview)
4. User taps "Share" -> export runs async -> temp file written -> share sheet opens

### MacPDFExporter (macOS)

Location: `OpenHiker macOS/Services/MacPDFExporter.swift`

Three components:
- `MacExportFormat` enum: same as iOS but with macOS file UTTypes
- `ExportDocument: FileDocument`: Wraps export data for macOS `NSSavePanel` via `.fileExporter()`
- `MacPDFExporter`: Core Graphics PDF generation using `CGContext`/`CTLine` (no UIKit)

### Extending Export

**Adding a new format:**
1. Add a case to `ExportFormat` (iOS) and `MacExportFormat` (macOS) with icon, subtitle, extension, MIME type
2. Add generation logic in `ExportSheet.generateExportData()` (iOS) or in the macOS export handler
3. For shared logic, add a method to `HikeSummaryExporter`

**Adding more PDF pages:**
1. In `PDFExporter.swift` (iOS), call `context.beginPage()` before drawing
2. Use `drawText()` / `drawRect()` helpers already in the file
3. For macOS, add equivalent `CGContext` drawing in `MacPDFExporter`

---

## 6.2 iPad Adaptive Layouts — How It Works

### Detection Mechanism

`ContentView.swift` uses `@Environment(\.horizontalSizeClass)`:
- `.compact` (iPhone, iPad slide-over) -> `iPhoneLayout` (TabView, unchanged from before)
- `.regular` (iPad full/split) -> `iPadLayout` (NavigationSplitView)

This preserves all existing iPhone behavior with zero regressions.

### SidebarView

Location: `OpenHiker iOS/Views/SidebarView.swift`

```swift
enum SidebarSection: String, CaseIterable, Identifiable {
    case regions, downloaded, hikes, routes, waypoints, community, watch
}
```

Each case has a `title`, `iconName`, and the enum conforms to `Identifiable` for SwiftUI `List` selection.

### iPad NavigationSplitView

The iPad layout uses a two-column `NavigationSplitView`:
- Sidebar: `SidebarView(selection:)` with bound `SidebarSection?`
- Detail: `switch sidebarSelection` dispatching to the appropriate view

Each detail view is wrapped in its own `NavigationStack` for independent navigation:
```swift
case .hikes:
    NavigationStack { HikesListView() }
```

### WaypointsListView

Location: `OpenHiker iOS/Views/WaypointsListView.swift`

A dedicated waypoints browser for the iPad sidebar's "Waypoints" section. Groups waypoints by `WaypointCategory` using `WaypointCategory.allCases`. Supports swipe-to-delete.

### Adding a New Sidebar Section

1. Add a case to `SidebarSection` enum in `SidebarView.swift`
2. Add title, icon, and section order in the enum's computed properties
3. Add a `case .newSection:` in `ContentView.iPadLayout`'s detail switch
4. Add a corresponding tab in `ContentView.iPhoneLayout` if also needed on iPhone

---

## 6.4 iCloud Sync — How It Works

### Overview

Manual CloudKit sync over the existing raw SQLite stores. The local SQLite database remains the source of truth; CloudKit is a mirror.

### Model Changes

All synced models (`SavedRoute`, `Waypoint`, `PlannedRoute`) gained two optional fields:

```swift
var modifiedAt: Date?       // Set on create/update, used for conflict resolution
var cloudKitRecordID: String?  // CKRecord.ID.recordName, set after first sync
```

Both fields default to `nil` for backwards compatibility. Existing code that creates these models without specifying sync fields continues to work unchanged.

### Schema Migration

`RouteStore` and `WaypointStore` use idempotent `ALTER TABLE ADD COLUMN`:

```swift
private func migrateSchema(db: OpaquePointer?) {
    let migrations = [
        "ALTER TABLE saved_routes ADD COLUMN modified_at TEXT",
        "ALTER TABLE saved_routes ADD COLUMN cloudkit_record_id TEXT"
    ]
    for sql in migrations {
        sqlite3_exec(db, sql, nil, nil, nil)  // Silently fails if column exists
    }
}
```

This is called after `createSchema()` in the store's `open()` method. The `ALTER TABLE` approach avoids needing a version table — columns are only added if missing.

### CloudKitStore

Location: `Shared/Services/CloudKitStore.swift`

An `actor` wrapping `CKDatabase` for typed operations:

- Container: `iCloud.com.openhiker.ios` (private database)
- Record types: `"SavedRoute"`, `"Waypoint"`, `"PlannedRoute"`
- Each model's UUID becomes the `CKRecord.ID.recordName`
- Methods: `save(route:)`, `fetchAllRoutes()`, `deleteRoute(recordID:)`, etc.
- `setupSubscriptions()`: Creates `CKQuerySubscription` for push notifications

### CloudSyncManager

Location: `Shared/Services/CloudSyncManager.swift`

An `actor` coordinating bidirectional sync:

```
syncOnLaunch()
  -> checkiCloudAvailability()
  -> setupSubscriptions()
  -> performSync()
       -> pushRoutes() / pushWaypoints()
       -> pullRoutes() / pullWaypoints()
```

**Conflict resolution:** Last-writer-wins using `modifiedAt`. During `pullRoutes()`, if a local route and cloud route share the same UUID, the one with the newer `modifiedAt` wins.

**Retry:** `retryWithBackoff()` generic helper. 4 attempts, 2-second base delay, exponential backoff (2s, 4s, 8s, 16s).

**Notifications:** Posts `Notification.Name.cloudSyncCompleted` when sync finishes, allowing views to refresh.

### Entitlements

iOS: `OpenHiker iOS/OpenHiker iOS.entitlements`
macOS: `OpenHiker macOS/OpenHiker macOS.entitlements`

Both require:
- `com.apple.developer.icloud-services` = `["CloudKit"]`
- `com.apple.developer.icloud-container-identifiers` = `["iCloud.com.openhiker.ios"]`

### Extending Sync

**Syncing a new model type:**
1. Add `modifiedAt: Date?` and `cloudKitRecordID: String?` to the model
2. Add `save(newModel:)` and `fetchAllNewModels()` to `CloudKitStore`
3. Add `pushNewModels()` and `pullNewModels()` to `CloudSyncManager.performSync()`
4. Add schema migration if the model uses SQLite

**Changing conflict resolution:**
The `pullRoutes()` method in `CloudSyncManager` has the comparison logic:
```swift
if let localModified = existingLocal.modifiedAt,
   let cloudModified = cloudRoute.modifiedAt,
   localModified >= cloudModified {
    continue  // Local is newer, skip cloud version
}
```
Replace this block with your preferred strategy (e.g., merge fields, prompt user).

---

## 6.1 macOS App — How It Works

### Target Configuration

- **Target name:** "OpenHiker macOS"
- **Bundle ID:** `com.openhiker.macos`
- **Deployment target:** macOS 14.0 (Sonoma)
- **Linked frameworks:** SQLite3, MapKit, CloudKit
- **NOT linked:** HealthKit, WatchConnectivity (unavailable on macOS)

### Source File Membership

The macOS target compiles:
1. All `Shared/` files (models, storage, services, utilities)
2. All `OpenHiker macOS/` files
3. Select iOS services that are pure Swift/Foundation (TileDownloader, RegionStorage, PBFParser, etc.)

It does NOT compile:
- `OpenHiker iOS/Views/*` (UIKit-dependent views)
- `OpenHiker iOS/Services/PDFExporter.swift` (uses UIGraphicsPDFRenderer)
- WatchConnectivity-related files

### Platform Guards in Shared Code

**TileStore.swift:** The import block uses three-way conditional:
```swift
#if canImport(UIKit)
import UIKit
#elseif canImport(WatchKit)
import WatchKit
#elseif canImport(AppKit)
import AppKit
#endif
```

`WritableTileStore` is gated with `#if os(iOS) || os(macOS)` (it uses only SQLite3 + Foundation, no UIKit).

**PhotoCompressor.swift:** Full `#elseif canImport(AppKit)` block with:
- `compress(_ image: NSImage) -> Data?` — TIFF → `NSBitmapImageRep` → JPEG
- `compressData(_ data: Data) -> Data?` — `NSImage(data:)` → compress
- `downsample(_ image: NSImage, ...)` — `NSImage.lockFocus()` + draw

### macOS App Structure

```
OpenHiker macOS/
  App/
    OpenHikerMacApp.swift      -- @main, WindowGroup + Settings + Commands
    MacContentView.swift       -- NavigationSplitView, MacSidebarSection enum
    OpenHikerCommands.swift    -- Menu commands (Sync: Cmd+Shift+S)
  Views/
    MacHikesView.swift         -- List + detail split for hikes
    MacHikeDetailView.swift    -- Map, elevation chart, stats, export
    MacWaypointsView.swift     -- Native Table with sortable columns
    MacPlannedRoutesView.swift -- Read-only list (planning is iOS-only)
    MacCommunityView.swift     -- Community browser with search
    MacSettingsView.swift      -- Tabbed Settings (General + Sync)
  Services/
    MacPDFExporter.swift       -- CGContext PDF, ExportDocument, MacExportFormat
  OpenHiker macOS.entitlements -- iCloud, sandbox, network
```

### macOS Export via FileDocument

macOS uses `FileDocument` protocol + `.fileExporter()` modifier for NSSavePanel integration:

```swift
struct ExportDocument: FileDocument {
    let data: Data
    let contentType: UTType

    func fileWrapper(configuration:) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
```

The hike detail view presents export via:
```swift
.fileExporter(isPresented: $showExport, document: exportDocument, ...)
```

### WatchConnectivity on macOS

WatchConnectivity is not available on macOS. The macOS app:
- Has no Watch tab in the sidebar
- Receives data from iOS via iCloud sync only
- Cannot directly transfer regions to Apple Watch
- Watch-related files are excluded from the macOS target

### Adding a New macOS View

1. Create `OpenHiker macOS/Views/MacNewView.swift`
2. Add a case to `MacSidebarSection` in `MacContentView.swift`
3. Add the detail view switch case in `MacContentView`
4. Add the file reference to `project.pbxproj` (see "Xcode Project" section below)

---

## Xcode Project Configuration

### ID Convention in project.pbxproj

| Prefix | Meaning |
|--------|---------|
| `1A` | iOS PBXBuildFile entries |
| `1B` | watchOS PBXBuildFile entries |
| `1C` | macOS PBXBuildFile entries |
| `2A` | Shared/iOS PBXFileReference entries |
| `2B` | watchOS-only PBXFileReference entries |
| `2C` | macOS-only PBXFileReference entries |
| `3A/3B/3C` | Product references (iOS/watchOS/macOS apps) |
| `5A` | iOS PBXGroup entries |
| `5B` | watchOS PBXGroup entries |
| `5C` | Shared PBXGroup entries |
| `5D` | macOS PBXGroup entries |
| `6A/6B/6C` | PBXNativeTarget (iOS/watchOS/macOS) |
| `7A/7B/7C` | XCConfigurationList |
| `9A/9B/9C` | XCBuildConfiguration |

When adding a new file, increment from the highest existing ID in the relevant prefix series.

### Adding a New File Checklist

For any new `.swift` file, you must add entries in **four** sections of `project.pbxproj`:

1. **PBXBuildFile** — one entry per target that compiles the file
   - Shared files: `1A` (iOS) + `1B` (watchOS) + `1C` (macOS) entries, all referencing the same `2A` file ref
   - iOS-only: one `1A` entry
   - macOS-only: one `1C` entry
2. **PBXFileReference** — one entry per file (use `2A` for shared/iOS, `2C` for macOS-only)
3. **PBXGroup** — add file ref to the appropriate group (Views, Services, etc.)
4. **PBXSourcesBuildPhase** — add build file ID to each target's sources list

Forgetting any section causes "Cannot find type in scope" build errors.

---

## Testing

### Export (6.3)

1. Markdown includes heart rate, calories, walking/resting split, avg speed
2. PDF generates multi-page: map snapshot, elevation chart, photos (or skip if none), waypoints
3. GPX contains track points and waypoints with correct coordinates
4. Share sheet delivers via Messages, Mail, AirDrop
5. Edge cases: no photos -> skip pages; no waypoints; no heart rate data -> show "N/A"
6. PDF size stays under 10 MB for typical hike with 5-10 photos

### iPad (6.2)

1. iPhone simulator -> TabView layout unchanged (no regressions)
2. iPad simulator -> NavigationSplitView with sidebar
3. Split View multitasking -> layout adapts when size class changes
4. All six sections accessible from sidebar
5. WaypointsListView groups by category, swipe-to-delete works

### iCloud Sync (6.4)

1. Create route on iOS -> appears on second device after sync
2. Edit route -> `modifiedAt` updates, change syncs
3. Conflict: edit on both devices -> last-writer-wins resolves
4. Delete on one device -> deleted on other
5. Offline edits queue and sync when connectivity returns
6. Schema migration runs cleanly on existing databases

### macOS (6.1)

1. macOS target builds without errors
2. All shared files compile with AppKit conditional imports
3. NavigationSplitView sidebar selection works
4. Hike detail shows map, elevation chart, stats, waypoints table
5. Export via NSSavePanel (PDF, Markdown, GPX)
6. Settings window with General and Sync tabs
7. iCloud sync receives data from iOS
8. No Watch tab in macOS sidebar

---

## Common Issues & Debugging

### "Cannot find type in scope" on macOS build

Missing file in `project.pbxproj`. Check that the file has:
- A `1C` PBXBuildFile entry
- The same `2A`/`2C` file reference
- An entry in the macOS PBXSourcesBuildPhase

### Schema migration doesn't add columns

`ALTER TABLE ADD COLUMN` silently fails if the column already exists (by design). If you need to verify, check with:
```sql
PRAGMA table_info(saved_routes);
```

### CloudKit sync not working

1. Check iCloud is signed in: `FileManager.default.ubiquityIdentityToken != nil`
2. Verify entitlements have `CloudKit` service and correct container ID
3. Check CloudKit Dashboard at https://icloud.developer.apple.com for record types
4. Enable CloudKit logging: `UserDefaults.standard.set(true, forKey: "com.apple.cloudkit.verbose-logs")`

### PhotoCompressor crash on macOS

Ensure the calling code uses the correct image type:
- iOS: `UIImage` in `#if canImport(UIKit)` block
- macOS: `NSImage` in `#if canImport(AppKit)` block

The `compressData(_ data: Data)` method is the safest cross-platform entry point — it accepts raw image bytes on both platforms.

### PDF export hangs

`MKMapSnapshotter.start()` is async and requires a network connection for Apple Maps tiles. In airplane mode, the snapshot will time out. The `PDFExporter` wraps this in a `Task` with error handling — check the console for timeout errors.
