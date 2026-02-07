# Phase 6 Follow-Up: Missing macOS Functionality

**Status:** Implementation suggestions for features deferred from Phase 6
**Dependencies:** Phase 6 complete (6.1 macOS, 6.2 iPad, 6.3 Export, 6.4 iCloud Sync)
**Estimated effort:** ~3-4 weeks total

---

## Overview

The Phase 6 implementation delivered the core macOS app (NavigationSplitView, hike review, waypoints, community browse, export, settings, iCloud sync). Several planned features were deferred because they require additional infrastructure or depend on the macOS target being buildable first. This document covers what remains and how to implement each feature.

---

## 1. GPX Drag-and-Drop Import

**Effort:** ~3 days
**Planned in:** 6.1 (File: `OpenHiker macOS/Views/GPXImportHandler.swift`)

### What's Missing

The macOS app cannot import GPX files. The planning doc specified:
- `NSOpenPanel` with `.gpx` UTType filter for File -> Import GPX
- Drag-and-drop onto map views (`onDrop(of: [.fileURL])`)
- Parse GPX -> create `PlannedRoute` or display track on map

### Implementation Steps

1. **Register custom UTType** in the macOS target's Info.plist:
   ```xml
   <key>UTImportedTypeDeclarations</key>
   <array>
     <dict>
       <key>UTTypeIdentifier</key> <string>com.topografix.gpx</string>
       <key>UTTypeConformsTo</key> <array><string>public.xml</string></array>
       <key>UTTypeTagSpecification</key>
       <dict><key>public.filename-extension</key> <array><string>gpx</string></array></dict>
     </dict>
   </array>
   ```

2. **Create `OpenHiker macOS/Views/GPXImportHandler.swift`:**
   - Parse GPX XML using `XMLParser` (Foundation, no dependencies)
   - Extract `<trk>` -> track points, `<wpt>` -> waypoints, `<rte>` -> route points
   - Convert to `PlannedRoute` + `[Waypoint]` and insert into stores
   - Display import preview sheet with map + point count before committing

3. **Add File -> Import GPX menu command** in `OpenHikerCommands.swift`:
   ```swift
   Button("Import GPX...") {
       let panel = NSOpenPanel()
       panel.allowedContentTypes = [UTType(filenameExtension: "gpx")!]
       panel.allowsMultipleSelection = false
       if panel.runModal() == .OK, let url = panel.url {
           // Parse and import
       }
   }
   .keyboardShortcut("i", modifiers: .command)
   ```

4. **Add `.onDrop()` to map views** (`MacHikeDetailView`, `MacPlannedRoutesView`):
   ```swift
   .onDrop(of: [.fileURL], isTargeted: nil) { providers in
       // Extract URL, verify .gpx extension, parse, import
   }
   ```

### Testing
- Import a multi-track GPX file from popular hiking apps (Komoot, AllTrails)
- Drag GPX file onto sidebar or map area
- Verify waypoints and track points are correctly parsed
- Verify `PlannedRoute` appears in the Routes section after import

---

## 2. iCloud Documents for MBTiles Region Sync

**Effort:** ~1 week
**Planned in:** 6.4 iCloud Sync (Strategy #2)

### What's Missing

Region `.mbtiles` files (5-100 MB each) do not sync between devices. Currently, each device must download tiles independently. The planning doc specified iCloud Drive file coordination.

### Implementation Steps

1. **Create `Shared/Services/RegionSyncManager.swift`** (actor):
   - Obtain the ubiquity container URL:
     ```swift
     let containerURL = FileManager.default.url(
         forUbiquityContainerIdentifier: "iCloud.com.openhiker.ios"
     )?.appendingPathComponent("Documents/regions")
     ```
   - Copy local `.mbtiles` files to the container after download completes
   - Use `NSFileCoordinator` for safe read/write of large files

2. **Create `Shared/Services/RegionMetadataQuery.swift`:**
   - Use `NSMetadataQuery` scoped to `NSMetadataQueryUbiquitousDocumentsScope`
   - Filter for `*.mbtiles` files
   - Detect new/updated/removed region files from other devices
   - Download on-demand: check `NSURLUbiquitousItemDownloadingStatusKey`
   - Trigger download: `FileManager.startDownloadingUbiquitousItem(at:)`

3. **Modify `OpenHiker iOS/Services/RegionStorage.swift`:**
   - After saving a downloaded region locally, also copy to iCloud container
   - When a new region appears via `NSMetadataQuery`, copy from iCloud to local storage
   - Deduplicate by region name + bounds to avoid double-downloads

4. **Handle large file transfers gracefully:**
   - Show download progress for regions syncing from iCloud
   - Allow cancellation of iCloud region downloads
   - Skip auto-downloading regions larger than a configurable threshold (default 50 MB)

### Considerations
- iCloud Drive storage is limited per user (5 GB free tier)
- Large `.mbtiles` files may take minutes to sync over cellular
- Need UI indicator showing sync status per region (local-only, uploading, downloading, synced)
- Consider offering opt-in per-region sync rather than syncing all regions automatically

### Testing
- Download region on iOS -> verify it appears in iCloud Drive container
- Open macOS app -> verify `NSMetadataQuery` discovers the file
- Trigger download on macOS -> verify `.mbtiles` is usable
- Delete on one device -> verify coordinated removal on other
- Test with poor network (throttle) -> verify partial downloads resume

---

## 3. NSUbiquitousKeyValueStore for Preference Sync

**Effort:** ~2 days
**Planned in:** 6.4 iCloud Sync (Strategy #3)

### What's Missing

User preferences (metric/imperial units, default author name, etc.) don't sync between devices. Each device stores preferences independently via `@AppStorage` / `UserDefaults`.

### Implementation Steps

1. **Create `Shared/Services/PreferenceSyncManager.swift`:**
   ```swift
   /// Bridges @AppStorage (UserDefaults) with NSUbiquitousKeyValueStore for
   /// cross-device preference synchronization.
   final class PreferenceSyncManager {
       static let shared = PreferenceSyncManager()

       private let kvStore = NSUbiquitousKeyValueStore.default
       private let syncedKeys = ["useMetricUnits", "defaultAuthorName",
                                  "defaultCountry", "defaultArea"]

       /// Call once on app launch to start observing changes.
       func startObserving() {
           NotificationCenter.default.addObserver(
               self,
               selector: #selector(kvStoreDidChange),
               name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
               object: kvStore
           )
           kvStore.synchronize()
       }
   }
   ```

2. **Modify preference writes** to dual-write:
   - When the user changes a preference in Settings, write to both `UserDefaults` and `NSUbiquitousKeyValueStore`
   - When a remote change arrives via notification, update `UserDefaults`

3. **Initialize in app entry points:**
   - `OpenHikerApp.swift` (iOS)
   - `OpenHikerMacApp.swift` (macOS)
   - Call `PreferenceSyncManager.shared.startObserving()` on launch

### Considerations
- `NSUbiquitousKeyValueStore` has a 1 MB total limit and 1024 key limit
- Only sync small settings (strings, bools, numbers) — never large data
- Handle the `NSUbiquitousKeyValueStoreServerChange` reason to avoid overwriting local changes with stale server data

---

## 4. macOS Route Planning View

**Effort:** ~1 week
**Planned in:** 6.1 (File: `OpenHiker macOS/Views/MacRoutePlanningView.swift`)

### What's Missing

The macOS app shows planned routes in a read-only list (`MacPlannedRoutesView`) but has no interactive route planning. The planning doc specified a full-width map with side panel controls.

### Implementation Steps

1. **Create `OpenHiker macOS/Views/MacRoutePlanningView.swift`:**
   - Map occupies ~70% width with the route overlay
   - Side panel (~30%) contains: start/end/via-point list, mode toggle (hiking/cycling), route statistics, turn-by-turn directions
   - Right-click context menu on map for "Set Start Here" / "Set End Here" / "Add Via Point"
   - Reuse `RoutingEngine` and `RoutingGraphBuilder` from Shared/iOS

2. **Modify `MacContentView.swift`:**
   - Change the `.routes` sidebar case from `MacPlannedRoutesView()` to a split view: planned routes list + `MacRoutePlanningView` for selected route

3. **Add route creation flow:**
   - "New Route" button (also accessible via Cmd+N menu command)
   - Create empty `PlannedRoute` -> open in `MacRoutePlanningView`
   - Save/cancel flow with unsaved-changes confirmation

### Dependencies
- Requires `RoutingEngine`, `RoutingGraphBuilder`, `OSMDataDownloader`, `PBFParser` in the macOS target's source build phase (already included in Phase 6)
- Requires OSM routing data downloaded for the region (same as iOS)

---

## 5. macOS Region Selector View

**Effort:** ~4 days
**Planned in:** 6.1 (File: `OpenHiker macOS/Views/MacRegionSelectorView.swift`)

### What's Missing

The macOS app has no region management. Users cannot download tile regions for offline use on macOS.

### Implementation Steps

1. **Create `OpenHiker macOS/Views/MacRegionSelectorView.swift`:**
   - Full-screen MapKit view with rectangle selection tool
   - Side panel showing: selected bounds, estimated tile count, estimated file size, zoom range picker
   - Download button + progress indicator
   - Reuse `TileDownloader` (actor) and `WritableTileStore` from Shared/iOS

2. **Create `OpenHiker macOS/Views/MacDownloadedRegionsView.swift`:**
   - List of downloaded `.mbtiles` regions with file sizes
   - Delete/rename actions via context menu
   - Map preview showing region bounds

3. **Add to sidebar:** Wire up `.regions` and `.downloaded` cases in `MacContentView`

### Considerations
- macOS has more storage and better network than watchOS — can support larger regions
- Consider allowing background downloads via `URLSession` background configuration
- Show Finder integration: "Show in Finder" context menu action for `.mbtiles` files

---

## 6. macOS Waypoint Creation View

**Effort:** ~2 days
**Planned in:** 6.1 (File: `OpenHiker macOS/Views/MacAddWaypointView.swift`)

### What's Missing

Users can view waypoints on macOS but cannot create new ones. The planning doc specified a form with `NSOpenPanel` for photo file picker.

### Implementation Steps

1. **Create `OpenHiker macOS/Views/MacAddWaypointView.swift`:**
   - Sheet/popover form: name, category picker, coordinates (manual entry or click-on-map), notes
   - Photo attachment via `NSOpenPanel` (no camera on Mac)
   - Drag-and-drop image support (`onDrop(of: [.image])`)
   - Reuse `WaypointStore` and `PhotoCompressor` (AppKit path)

2. **Add "New Waypoint" button** to `MacWaypointsView` toolbar

---

## 7. Multiple Window Support

**Effort:** ~2 days
**Planned in:** 6.1

### What's Missing

The macOS app uses a single `WindowGroup`. The planning doc mentioned opening different routes in separate windows.

### Implementation Steps

1. **Add a secondary `WindowGroup`** for route detail:
   ```swift
   WindowGroup("Hike Detail", for: UUID.self) { $routeId in
       if let routeId {
           MacHikeDetailView(routeId: routeId)
       }
   }
   ```

2. **Open new windows** via `@Environment(\.openWindow)`:
   ```swift
   Button("Open in New Window") {
       openWindow(value: route.id)
   }
   ```

3. **Add window state restoration** using `defaultSize(width:height:)` and `.windowResizability(.contentMinSize)`

---

## Priority Order

| # | Feature | Effort | Value | Priority |
|---|---------|--------|-------|----------|
| 1 | GPX Drag-and-Drop Import | 3 days | High — key macOS differentiator | P1 |
| 2 | macOS Region Selector | 4 days | High — enables offline use | P1 |
| 3 | macOS Route Planning | 1 week | High — core app purpose | P1 |
| 4 | iCloud Documents for MBTiles | 1 week | Medium — convenience | P2 |
| 5 | macOS Waypoint Creation | 2 days | Medium — completes CRUD | P2 |
| 6 | Preference Sync | 2 days | Low — minor convenience | P3 |
| 7 | Multiple Window Support | 2 days | Low — nice-to-have | P3 |
