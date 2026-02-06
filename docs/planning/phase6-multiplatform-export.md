# Phase 6: Multi-Platform & Export

**Estimated effort:** ~3 weeks
**Dependencies:** All Phases 1–5 (builds on all prior features)
**Platform focus:** macOS/iPadOS (layouts), iOS (export)

## Overview

Adapt the app for iPad and Mac with a planning/review hub that leverages larger screens. Add export of completed hikes as quick Markdown summary cards or detailed multi-page PDF reports.

---

## Feature 6.1: macOS & iPad Variants

**Size:** L (Large)

### What It Does

A full-featured planning and review hub on iPad and Mac, using adaptive SwiftUI layouts. Same codebase — the `Shared/` directory (models, storage, routing engine) already compiles cross-platform.

### Approach: Adaptive Layouts (Not Separate Targets)

The iOS target already has `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad). Rather than creating a separate macOS target, use **Mac Catalyst** (checkbox in Xcode) plus **adaptive SwiftUI layouts**.

This means:
- One codebase, one target (with Mac Catalyst enabled)
- `NavigationSplitView` on iPad/Mac, `TabView` on iPhone
- Wider map views, side panels for route planning, larger elevation charts

### Layout Strategy

#### iPhone (compact width)
```
TabView:
  Tab 1: Regions (map + download)
  Tab 2: Downloaded regions list
  Tab 3: Watch sync
  Tab 4: Hikes (review)
  Tab 5: Routes (planning)
```

#### iPad / Mac (regular width)
```
NavigationSplitView:
  Sidebar:
    📍 Regions
    📂 Downloaded
    ⌚ Watch
    🥾 Hikes
    🗺️ Routes
    📌 Waypoints

  Detail:
    (selected section content)
    - Maps use full available width
    - Route planning: map + controls side-by-side
    - Hike review: map + stats + elevation side-by-side
```

### Key Adaptations

#### Route Planning (iPad/Mac)
- Full-screen map takes ~70% of width
- Side panel (~30%) shows:
  - Start/end/via-point list (editable)
  - Mode toggle
  - Route statistics
  - Turn-by-turn directions (scrollable)
- Drag-and-drop GPX file import (NSItemProvider)
- Keyboard shortcuts: ⌘N for new route, ⌘S for save, Delete to remove selected pin

#### Hike Review (iPad/Mac)
- Map and elevation profile displayed side-by-side (not stacked)
- Statistics in a wide grid layout
- Photo gallery as a proper grid (not single-column list)
- Comment editing with full keyboard

#### Region Management (iPad/Mac)
- Larger map for region selection
- Download queue visible alongside map
- Multi-region selection for batch operations

### Implementation

Use `@Environment(\.horizontalSizeClass)` to switch layouts:

```swift
struct AdaptiveContentView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            // iPad / Mac: NavigationSplitView
            NavigationSplitView {
                SidebarView()
            } detail: {
                DetailView()
            }
        } else {
            // iPhone: TabView (existing layout)
            TabView {
                // ... existing tabs
            }
        }
    }
}
```

### Mac Catalyst Specifics

- Enable "Mac (Designed for iPad)" or full Mac Catalyst in Xcode target settings
- Add macOS-specific keyboard shortcuts via `.keyboardShortcut()`
- Window resizing: set minimum size to 800×600
- Menu bar: add File → Import GPX, File → Export, Edit → Preferences
- Toolbar: add common actions (New Route, Download Region, etc.)

### WatchConnectivity on Mac

Note: WatchConnectivity is **not available on macOS**. The Mac version:
- Cannot send regions to the watch directly
- Functions as a planning/review station only
- Shares data with iOS via iCloud (or manual file transfer)
- Consider adding iCloud sync for route/waypoint data (future enhancement)

### Files to Modify

#### `OpenHiker iOS/App/ContentView.swift`
- Refactor to `AdaptiveContentView` using `horizontalSizeClass`
- `NavigationSplitView` path for iPad/Mac
- `TabView` path for iPhone (existing code largely unchanged)

#### `OpenHiker iOS/Views/RegionSelectorView.swift`
- Adaptive map size
- Side panel for download config on iPad/Mac (instead of sheet)

#### `OpenHiker iOS/Views/HikeDetailView.swift`
- Horizontal layout for map + elevation on iPad/Mac
- Wider photo grid

#### `OpenHiker iOS/Views/RoutePlanningView.swift`
- Side panel for route controls on iPad/Mac

### Files to Create

#### `OpenHiker iOS/Views/SidebarView.swift`
- Navigation sidebar for iPad/Mac with section list
- SF Symbol icons, selection state

#### `OpenHiker iOS/Views/WaypointsListView.swift`
- Dedicated waypoints list view (accessible from sidebar on iPad/Mac)
- Map showing all waypoints, list with filters

### Xcode Project Changes

- Enable "Mac (Designed for iPad)" in target settings
- Or enable full Mac Catalyst support
- Test that all frameworks compile for macOS (MapKit, HealthKit — note HealthKit not available on Mac)
- Add `#if !os(macOS)` guards around HealthKit and WatchConnectivity code

### Testing

1. Build for iPad simulator → verify NavigationSplitView layout
2. Build for Mac Catalyst → verify window opens, menus work
3. Route planning on iPad → verify map + side panel layout
4. Hike review on iPad → verify horizontal map + elevation layout
5. Resize Mac window → verify adaptive layout responds
6. Verify WatchConnectivity sections are hidden on Mac
7. Test keyboard shortcuts on Mac (⌘N, ⌘S, Delete)

---

## Feature 6.2: Export Routes as PDF & Markdown

**Size:** M (Medium)

### What It Does

Export completed hikes in two formats:
1. **Quick Summary Card (Markdown):** Key stats, waypoint list. Easy to share via messages/email.
2. **Detailed Report (PDF):** Multi-page document with map snapshot, elevation profile, photo gallery, statistics table, waypoint list, and comments.

### Markdown Export

```markdown
# Hike: Blue Ridge Trail

**Date:** 6 February 2026
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
3. **Water Source** (47.4280°N, 10.9850°E) — "Clear stream, good for filtering"
4. **Steep Section** ⚠️ (47.4250°N, 10.9820°E) — "Use caution, loose rocks"

## Comments

Great weather, clear skies. Trail was well-marked except for the section
after the summit where we had to navigate by GPS.

---
*Recorded with OpenHiker — https://github.com/openhiker*
```

### PDF Export

Multi-page PDF generated with `UIGraphicsPDFRenderer`:

**Page 1: Cover & Summary**
- Title, date, duration
- Map snapshot (MKMapSnapshotter with route polyline overlay)
- Summary statistics table

**Page 2: Elevation Profile**
- Full-width elevation chart (render Swift Charts to CGImage)
- Min/max/avg elevation annotations
- Distance markers on X axis

**Page 3+: Photo Gallery**
- 2-up or 3-up photo grid with captions
- Each photo shows: thumbnail, waypoint name, coordinate, note
- Skip if no photos

**Final Page: Waypoint Table & Comments**
- Table with columns: #, Name, Category, Coordinate, Note
- Comments section

### Map Snapshot

Use `MKMapSnapshotter` to generate a static map image with the route overlay:

```swift
func generateMapSnapshot(
    route: SavedRoute,
    waypoints: [Waypoint],
    size: CGSize
) async throws -> UIImage {
    let options = MKMapSnapshotter.Options()
    // Set region to fit the route bounding box with padding
    options.size = size
    options.mapType = .standard
    // Note: OpenTopoMap tiles can't be used in MKMapSnapshotter
    // Use standard Apple Maps for the export snapshot

    let snapshotter = MKMapSnapshotter(options: options)
    let snapshot = try await snapshotter.start()

    // Draw route polyline and waypoint markers on the snapshot image
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
        snapshot.image.draw(at: .zero)
        // Draw route polyline
        // Draw waypoint markers
        // Draw start/end pins
    }
}
```

### Elevation Chart Image

Render the Swift Charts elevation profile to a `UIImage` for embedding in PDF:

```swift
func renderElevationChart(
    trackPoints: [CLLocation],
    size: CGSize
) -> UIImage {
    let chartView = ElevationProfileView(trackPoints: trackPoints)
    let renderer = ImageRenderer(content: chartView.frame(width: size.width, height: size.height))
    renderer.scale = 2.0  // Retina
    return renderer.uiImage ?? UIImage()
}
```

### Share Sheet

After generating the export, present via `UIActivityViewController` (or `ShareLink` in SwiftUI):
- Markdown: share as `.md` file or plain text
- PDF: share as `.pdf` file
- GPX: share existing GPX export
- Option to share all three at once

### Files to Create

#### `Shared/Services/MarkdownExporter.swift`
- `func exportAsMarkdown(route: SavedRoute, waypoints: [Waypoint]) -> String`
- Pure string generation, no platform dependencies
- Locale-aware formatting (metric/imperial based on user preference)

#### `OpenHiker iOS/Services/PDFExporter.swift`
- `func exportAsPDF(route: SavedRoute, waypoints: [Waypoint], trackPoints: [CLLocation]) async throws -> Data`
- Uses `UIGraphicsPDFRenderer` for multi-page PDF
- Calls `MKMapSnapshotter` for map image
- Renders elevation chart via `ImageRenderer`

#### `OpenHiker iOS/Views/ExportSheet.swift`
- SwiftUI sheet with format selection:
  - Quick Summary (Markdown)
  - Detailed Report (PDF)
  - GPS Track (GPX)
  - All formats
- Progress indicator during generation
- Preview before sharing
- Share button → `UIActivityViewController`

### Files to Modify

#### `OpenHiker iOS/Views/HikeDetailView.swift`
- Add share/export button in toolbar or bottom bar
- Opens `ExportSheet`

### Formatting Considerations

- **Locale-aware units:** Use user's metric/imperial preference
- **Date formatting:** Use `DateFormatter` with user's locale (not hardcoded US format)
- **Coordinate format:** Degrees with 4 decimal places, N/S/E/W suffix
- **Number formatting:** Use `NumberFormatter` for locale-appropriate decimal separators

### Testing

1. Complete a hike with waypoints and photos
2. Open hike detail → tap export
3. Select Markdown → verify output format, correct stats, waypoint list
4. Select PDF → verify multi-page layout:
   - Page 1: map snapshot with route visible
   - Page 2: elevation profile readable
   - Page 3: photos with captions (if photos exist)
   - Final: waypoint table and comments
5. Share via Messages → verify file is receivable
6. Test with a hike that has no photos → verify PDF skips photo page
7. Test with different locales:
   - German: km, m, comma decimals
   - US English: mi, ft, period decimals
   - Australian English: km, m, period decimals
8. Test PDF file size stays reasonable (< 10 MB for a typical hike)
