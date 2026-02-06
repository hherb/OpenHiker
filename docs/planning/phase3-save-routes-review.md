# Phase 3: Save Routes & Review Past Hikes

**Estimated effort:** ~3 weeks
**Dependencies:** Phase 1.2 (HealthKit for stats), Phase 2.1 (Waypoint model for linking)
**Platform focus:** Shared model, then watchOS save, then iOS review

## Overview

Persist completed hikes with comprehensive statistics: track, distance, elevation gain/loss, walking/resting time, heart rate, calories, linked waypoints, and photos. Review past hikes on iPhone with MapKit track overlay, elevation profile chart, and statistics dashboard.

---

## Feature 3.1: Saved Route Data Model & Storage

**Size:** M (Medium)

### Data Model

```swift
/// A completed hike with full track data and statistics.
struct SavedRoute: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    let startLatitude: Double
    let startLongitude: Double
    let endLatitude: Double
    let endLongitude: Double
    let startTime: Date
    let endTime: Date
    let totalDistance: Double           // meters
    let elevationGain: Double           // meters
    let elevationLoss: Double           // meters
    let walkingTime: TimeInterval       // seconds
    let restingTime: TimeInterval       // seconds
    let averageHeartRate: Double?       // bpm
    let maxHeartRate: Double?           // bpm
    let estimatedCalories: Double?      // kcal
    var comment: String
    let regionId: UUID?                 // which map region was used
    let trackData: Data                 // compressed binary track
}
```

### Track Compression

Store track points as packed binary instead of GPX text to save space:

**Format:** Sequential records of `(Float32 latitude, Float32 longitude, Float32 altitude, Float64 timestamp)`
- 20 bytes per point vs ~150 bytes per GPX text point
- 1000-point hike: 20 KB compressed vs 150 KB text
- Use `zlib` compression (available in Apple's `Compression` framework) for further 50-60% reduction

```swift
// Shared/Utilities/TrackCompression.swift
struct TrackCompression {
    /// Encode CLLocation array to compact binary Data
    static func encode(_ locations: [CLLocation]) -> Data

    /// Decode binary Data back to CLLocation array
    static func decode(_ data: Data) -> [CLLocation]
}
```

### SQLite Schema

```sql
CREATE TABLE saved_routes (
    id TEXT PRIMARY KEY,                -- UUID
    name TEXT NOT NULL,
    start_latitude REAL NOT NULL,
    start_longitude REAL NOT NULL,
    end_latitude REAL NOT NULL,
    end_longitude REAL NOT NULL,
    start_time TEXT NOT NULL,           -- ISO 8601
    end_time TEXT NOT NULL,
    total_distance REAL NOT NULL,       -- meters
    elevation_gain REAL NOT NULL,       -- meters
    elevation_loss REAL NOT NULL,       -- meters
    walking_time REAL NOT NULL,         -- seconds
    resting_time REAL NOT NULL,         -- seconds
    avg_heart_rate REAL,                -- bpm, nullable
    max_heart_rate REAL,                -- bpm, nullable
    estimated_calories REAL,            -- kcal, nullable
    comment TEXT NOT NULL DEFAULT '',
    region_id TEXT,                     -- UUID of associated region
    track_data BLOB NOT NULL            -- compressed binary track
);

CREATE INDEX idx_routes_time ON saved_routes(start_time);
```

### LocationManager Extensions

Add to `OpenHiker watchOS/Services/LocationManager.swift`:

**Elevation loss** (complement to existing `elevationGain` at line 277):
```swift
var elevationLoss: Double {
    guard trackPoints.count > 1 else { return 0 }
    var loss: Double = 0
    for i in 1..<trackPoints.count {
        let diff = trackPoints[i].altitude - trackPoints[i - 1].altitude
        if diff < 0 { loss += abs(diff) }
    }
    return loss
}
```

**Walking vs resting time detection:**
- Speed threshold: 0.3 m/s (configurable via constant)
- Minimum rest duration: 60 seconds
- Algorithm: iterate through track points, compute speed between consecutive points. Consecutive points below threshold for > 60s = resting period. Sum up walking and resting intervals.

```swift
/// Minimum speed (m/s) to be considered "walking". Below this for restThresholdSeconds = "resting".
static let walkingSpeedThreshold: Double = 0.3

/// Minimum duration (seconds) below walking speed to count as a rest stop.
static let restThresholdSeconds: TimeInterval = 60

var walkingAndRestingTime: (walking: TimeInterval, resting: TimeInterval) {
    // ... implementation
}
```

### Files to Create

- `Shared/Models/SavedRoute.swift` — SavedRoute struct
- `Shared/Storage/RouteStore.swift` — SQLite CRUD (pattern from TileStore)
- `Shared/Utilities/TrackCompression.swift` — Binary encode/decode for CLLocation arrays

### Files to Modify

- `OpenHiker watchOS/Services/LocationManager.swift` — add `elevationLoss`, `walkingAndRestingTime`

### Testing

- Unit test TrackCompression round-trip (encode → decode, verify coordinates match)
- Unit test RouteStore CRUD
- Unit test elevationLoss calculation with known data
- Unit test walking/resting detection with synthetic track data

---

## Feature 3.2: Save Completed Hike on Watch

**Size:** M (Medium)

### What It Does

When the user stops tracking, present a "Save Hike" sheet that shows statistics and lets them name the hike and add a comment. Saves to local `RouteStore` and transfers to iPhone.

### UI Flow

1. User taps stop button → tracking stops
2. "Save Hike" sheet appears automatically with:
   - Auto-generated name: "Hike — 6 Feb 2026" (localized date format)
   - Editable name field (text input or dictation)
   - Statistics summary:
     - Distance: 8.4 km
     - Elevation: +523m / -489m
     - Duration: 3h 12m (walking: 2h 48m, resting: 24m)
     - Avg HR: 138 bpm (if HealthKit authorized)
     - Calories: ~890 kcal (if available)
   - Optional comment (dictation)
   - "Save" and "Discard" buttons
3. On save:
   - Compress track data via `TrackCompression.encode()`
   - Create `SavedRoute` with all stats
   - Insert into `RouteStore`
   - Also export GPX file (existing `exportTrackAsGPX()`)
   - Transfer route to iPhone via `WCSession.transferFile()`
4. On discard: clear track points, dismiss

### Transfer to iPhone

Package for `transferFile`:
- File: JSON-encoded `SavedRoute` (without `trackData`) + compressed track as separate file
- Or: single `.hikedata` file containing both metadata JSON + compressed track binary
- Metadata dict in `transferFile` userInfo: `["type": "savedRoute", "routeId": id.uuidString]`

### Files to Create

#### `OpenHiker watchOS/Views/SaveHikeSheet.swift`
- Summary stats display
- Name text field (with dictation)
- Comment text field (optional, with dictation)
- Save / Discard buttons

### Files to Modify

#### `OpenHiker watchOS/Views/MapView.swift`
- In `toggleTracking()`: when stopping, set `showingSaveHike = true`
- Add `@State private var showingSaveHike = false`
- Add `.sheet(isPresented: $showingSaveHike)` for SaveHikeSheet

#### `OpenHiker watchOS/App/OpenHikerWatchApp.swift`
- Initialize `RouteStore.shared`
- Add route transfer in WatchConnectivity: package and send via `transferFile`

### Testing

1. Record a track on the watch (walk around simulator with GPX file)
2. Stop tracking → verify SaveHikeSheet appears
3. Edit name, add comment → save
4. Verify route appears in local RouteStore
5. Verify route transfers to iPhone
6. Tap "Discard" → verify track points are cleared, no route saved

---

## Feature 3.3: Review Past Hikes on iPhone

**Size:** L (Large)

### What It Does

New "Hikes" tab on iOS showing all saved routes. Each hike has a rich detail view with:
- MapKit view with track polyline overlay
- Elevation profile chart (Swift Charts)
- Statistics grid
- Linked waypoints as annotations
- Photos from waypoints
- Editable comment

### iOS Tab Addition

Add 4th tab to `ContentView.swift` (currently has 3 tabs at line ~50):
```swift
TabView {
    // ... existing 3 tabs ...
    HikesListView()
        .tabItem {
            Image(systemName: "figure.hiking")
            Text("Hikes")
        }
}
```

### List View

- Sort by date (newest first)
- Each row shows: name, date, distance, duration, elevation gain
- Swipe to delete with confirmation
- Search bar to filter by name

### Detail View Layout

```
┌──────────────────────────┐
│     Map with Track       │  MapKit + MKPolyline overlay
│     [Start → End pins]   │  Green start, red end
│     [Waypoint pins]      │  Category-colored annotations
├──────────────────────────┤
│   Elevation Profile      │  Swift Charts area chart
│   ▲                      │  X: distance, Y: elevation
│   ──────────────────     │  Gradient fill (green→red)
├──────────────────────────┤
│ Distance │ Elevation     │  Statistics grid
│  8.4 km  │ +523m -489m  │
│ Duration │ Heart Rate    │
│  3h 12m  │ 138 avg bpm  │
│ Walking  │ Calories      │
│  2h 48m  │ ~890 kcal    │
├──────────────────────────┤
│ Waypoints (3)            │  List of linked waypoints
│  📍 Summit Viewpoint     │  With thumbnail + category icon
│  💧 Water Source          │
│  ⚠️ Steep Section         │
├──────────────────────────┤
│ Comment:                 │  Editable text field
│ "Great weather, ..."     │
├──────────────────────────┤
│ [Share] [Export]         │  Action buttons (Phase 6)
└──────────────────────────┘
```

### Elevation Profile

Use **Swift Charts** (`import Charts`) — Apple framework, no third-party dependency:

```swift
// OpenHiker iOS/Views/ElevationProfileView.swift
Chart {
    ForEach(elevationData, id: \.distance) { point in
        AreaMark(
            x: .value("Distance", point.distance / 1000),  // km
            y: .value("Elevation", point.elevation)          // meters
        )
        .foregroundStyle(
            .linearGradient(
                colors: [.green.opacity(0.3), .red.opacity(0.3)],
                startPoint: .bottom, endPoint: .top
            )
        )
    }
    LineMark(...)  // outline
}
.chartXAxisLabel("Distance (km)")
.chartYAxisLabel("Elevation (m)")
```

The elevation data is extracted from the decoded track points (decompress via `TrackCompression.decode()`).

### Receiving Routes from Watch

In `WatchTransferManager`:
- Handle incoming `transferFile` with `type: savedRoute`
- Decode `SavedRoute`, insert into local `RouteStore`
- Also receive and store associated waypoints

### Files to Create

#### `OpenHiker iOS/Views/HikesListView.swift`
- List of saved routes, sorted by date
- Search bar, swipe to delete
- Navigation to HikeDetailView

#### `OpenHiker iOS/Views/HikeDetailView.swift`
- ScrollView with map, elevation profile, stats grid, waypoints, comment
- Map: `MKMapView` with `MKPolyline` overlay from decoded track
- Waypoints: `MKPointAnnotation` instances from linked waypoints

#### `OpenHiker iOS/Views/ElevationProfileView.swift`
- Swift Charts `AreaMark` + `LineMark`
- Data from decoded track points: (cumulative distance, elevation) pairs

### Files to Modify

#### `OpenHiker iOS/App/ContentView.swift`
- Add 4th "Hikes" tab with `HikesListView()`

#### `OpenHiker iOS/Services/WatchTransferManager.swift`
- Handle incoming route transfers from watch
- Decode and persist to local RouteStore

#### `OpenHiker iOS/App/OpenHikerApp.swift`
- Initialize `RouteStore.shared` and inject into environment

### Testing

1. Transfer a saved route from watch to iPhone
2. Open Hikes tab → verify route appears in list with correct name, date, stats
3. Tap route → verify detail view shows:
   - Map with track polyline (correct geographic position)
   - Elevation profile chart with correct shape
   - Statistics grid with correct numbers
   - Linked waypoints as map annotations
4. Edit comment → verify it persists
5. Swipe to delete → verify route is removed
6. Search by name → verify filtering works
