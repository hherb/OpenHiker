# Phase 3: Save Routes & Review Past Hikes — Developer Guide

This document covers the architecture, data flow, and extension points for the Phase 3 "Save Routes & Review Past Hikes" feature. Read this before modifying, expanding, or debugging any of the route-saving or hike-review code.

---

## Feature Overview

Phase 3 adds the ability to:

1. **Watch**: Save a completed hike (track data + statistics) to a local SQLite database
2. **Watch -> Phone**: Transfer saved routes to the iPhone via WatchConnectivity
3. **iPhone**: Browse, search, and review past hikes with map overlay, elevation profile, and statistics

---

## Architecture Diagram

```
Watch (save)                            iPhone (review)
+------------------+                    +-------------------+
| MapView          |                    | HikesListView     |
|  toggleTracking()|                    |  searchable list   |
|        |         |                    |        |          |
|        v         |                    |        v          |
| SaveHikeSheet    |   transferFile()   | HikeDetailView    |
|  compress track  | -----------------> |  map + polyline   |
|  insert route    |   JSON-encoded     |  stats grid       |
|        |         |   SavedRoute       |  elevation chart  |
|        v         |                    |  comment editor   |
| RouteStore (SQLite)                   | RouteStore (SQLite)|
+------------------+                    +-------------------+
         |                                       |
         v                                       v
  Documents/routes.db                   Documents/routes.db
```

---

## File Map

### Shared (both targets)

| File | Purpose |
|------|---------|
| `Shared/Models/SavedRoute.swift` | Data model struct with all hike metadata + compressed track BLOB |
| `Shared/Storage/RouteStore.swift` | SQLite CRUD following the `WaypointStore` singleton pattern |
| `Shared/Utilities/TrackCompression.swift` | Binary pack + zlib compress/decompress for GPS tracks |

### watchOS

| File | Purpose |
|------|---------|
| `OpenHiker watchOS/Views/SaveHikeSheet.swift` | Modal sheet to name/comment/save/discard a completed hike |
| `OpenHiker watchOS/Views/MapView.swift` | Modified: presents `SaveHikeSheet` on tracking stop |
| `OpenHiker watchOS/App/OpenHikerWatchApp.swift` | Modified: initializes `RouteStore`, adds `transferRouteToPhone()` |
| `OpenHiker watchOS/Services/LocationManager.swift` | Modified: adds `walkingAndRestingTime` computed property |

### iOS

| File | Purpose |
|------|---------|
| `OpenHiker iOS/Views/HikesListView.swift` | Searchable list of all saved hikes with swipe-to-delete |
| `OpenHiker iOS/Views/HikeDetailView.swift` | Full detail view with map, stats, waypoints, comment editor |
| `OpenHiker iOS/Views/ElevationProfileView.swift` | Swift Charts area/line chart for elevation profile |
| `OpenHiker iOS/App/ContentView.swift` | Modified: adds "Hikes" tab (index 2) |
| `OpenHiker iOS/Services/WatchTransferManager.swift` | Modified: handles `didReceive file` for `"savedRoute"` type |
| `OpenHiker iOS/App/OpenHikerApp.swift` | Modified: initializes `RouteStore` on launch |

---

## Data Model: `SavedRoute`

```swift
struct SavedRoute: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String           // editable
    let startLatitude: Double
    let startLongitude: Double
    let endLatitude: Double
    let endLongitude: Double
    let startTime: Date
    let endTime: Date
    let totalDistance: Double   // meters
    let elevationGain: Double  // meters
    let elevationLoss: Double  // meters (positive value)
    let walkingTime: TimeInterval
    let restingTime: TimeInterval
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let estimatedCalories: Double?
    var comment: String        // editable
    let regionId: UUID?
    let trackData: Data        // compressed binary (see TrackCompression)
}
```

**Mutable fields**: Only `name` and `comment` are editable after creation. All other fields are immutable.

**Computed properties**: `duration`, `formattedDate`, `formattedStartTime`.

---

## Track Compression Format

`TrackCompression` converts `[CLLocation]` to/from zlib-compressed binary data.

### Binary record format (per point, 20 bytes)

| Offset | Type | Field |
|--------|------|-------|
| 0 | Float32 | latitude |
| 4 | Float32 | longitude |
| 8 | Float32 | altitude |
| 12 | Float64 | timestamp (timeIntervalSinceReferenceDate) |

### Compression pipeline

```
[CLLocation] → pack 20-byte records → zlib compress → Data (stored as BLOB)
Data (BLOB) → zlib decompress → unpack 20-byte records → [CLLocation]
```

### Size estimates

| Track points | Raw binary | Compressed | GPX XML equivalent |
|-------------|-----------|------------|-------------------|
| 100 | 2 KB | ~1 KB | ~15 KB |
| 1,000 | 20 KB | ~8-10 KB | ~150 KB |
| 10,000 | 200 KB | ~80-100 KB | ~1.5 MB |

### Extension point

To add fields (e.g., speed, horizontal accuracy), increase `bytesPerPoint` and append new fields after the timestamp. **You must also handle backward compatibility** by checking `rawData.count / oldBytesPerPoint` vs. `rawData.count / newBytesPerPoint` to detect the format version.

---

## RouteStore (SQLite)

Follows the same pattern as `WaypointStore`:

- **Singleton**: `RouteStore.shared`
- **Thread safety**: Serial `DispatchQueue` + `@unchecked Sendable`
- **Database path**: `Documents/routes.db`
- **Date format**: ISO 8601 with fractional seconds

### Schema

```sql
CREATE TABLE saved_routes (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    start_latitude REAL NOT NULL,
    start_longitude REAL NOT NULL,
    end_latitude REAL NOT NULL,
    end_longitude REAL NOT NULL,
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    total_distance REAL NOT NULL,
    elevation_gain REAL NOT NULL,
    elevation_loss REAL NOT NULL,
    walking_time REAL NOT NULL,
    resting_time REAL NOT NULL,
    avg_heart_rate REAL,
    max_heart_rate REAL,
    estimated_calories REAL,
    comment TEXT NOT NULL DEFAULT '',
    region_id TEXT,
    track_data BLOB NOT NULL
);

CREATE INDEX idx_routes_time ON saved_routes(start_time);
```

### CRUD operations

| Method | SQL | Notes |
|--------|-----|-------|
| `insert(_ route:)` | INSERT OR REPLACE | Full route including track BLOB |
| `update(_ route:)` | UPDATE name, comment | Only mutable fields |
| `delete(id:)` | DELETE | By UUID |
| `fetchAll()` | SELECT * ORDER BY start_time DESC | Returns newest first |
| `fetch(id:)` | SELECT * WHERE id = ? | Single route |
| `count()` | SELECT COUNT(*) | Total count |

### Adding a new column

1. Add the field to `SavedRoute`
2. Add the column to `createSchema()` with a `DEFAULT` value for backward compatibility
3. Update `insert()` to bind the new column
4. Update `parseRouteRow()` to read it (use a new column index)
5. If needed, add an `ALTER TABLE` migration — run it inside `createSchema()` after the `CREATE TABLE IF NOT EXISTS`

---

## Walking / Resting Time Calculation

Added to `LocationManager` as a computed property `walkingAndRestingTime`:

- Iterates consecutive track point pairs
- Calculates speed = distance / time
- Speed below `HikeStatisticsConfig.restingSpeedThreshold` (0.3 m/s) = potentially resting
- Must be below threshold for `walkingAndRestingMinRestDuration` (60 seconds) to count as rest
- Short pauses (< 60s) are counted as walking to avoid false positives

---

## WatchConnectivity Route Transfer

### Watch → iPhone flow

1. `SaveHikeSheet` encodes `SavedRoute` as JSON via `JSONEncoder` (with `.iso8601` date strategy)
2. Writes to a temp file (`<uuid>.hikedata`)
3. Calls `WatchConnectivityReceiver.transferRouteToPhone(fileURL:routeId:)`
4. Sends via `WCSession.transferFile()` with metadata: `["type": "savedRoute", "routeId": "<uuid>"]`
5. iPhone's `WatchConnectivityManager.session(_:didReceive:)` routes by `type`
6. `handleReceivedRoute()` decodes JSON and inserts into `RouteStore.shared`

### Metadata dictionary format

```swift
["type": "savedRoute", "routeId": "550E8400-E29B-41D4-A716-446655440000"]
```

### Debugging transfer issues

- Watch: check console for `"Queued route transfer to iPhone:"` log
- iPhone: check console for `"Received and saved route from watch:"` log
- If transfers fail: verify `WCSession.activationState == .activated` on both sides
- Large routes (10k+ points): transfer may fail if the JSON file exceeds watchOS limits (~50 MB)

---

## iOS Hike Review Views

### HikesListView

- Loads from `RouteStore.shared.fetchAll()` on `.onAppear`
- Searchable by route name (case-insensitive)
- Swipe-to-delete with confirmation dialog
- Each row shows: name, date/time, distance, duration, elevation gain

### HikeDetailView

- **Map section**: `Map` with `MapPolyline` for the track, green start flag, red end flag
- **Elevation profile**: `ElevationProfileView` using Swift Charts (`AreaMark` + `LineMark`)
- **Statistics grid**: 2-column `LazyVGrid` with stat cards
- **Waypoints section**: Shows waypoints linked via `hikeId`
- **Comment section**: Tap-to-edit with `TextEditor`, saves via `RouteStore.shared.update()`
- Track data decoded via `TrackCompression.decode()` on `.onAppear`

### ElevationProfileView

- Subsamples to max 200 points for chart performance
- X axis: distance in km (metric) or miles (imperial)
- Y axis: elevation in meters (metric) or feet (imperial)
- Uses `AreaMark` with green-to-red gradient fill + `LineMark` orange outline

---

## Extension Points

### Adding GPX export from iOS

The track data is already stored. To add GPX export:

1. Decode the track: `let locations = TrackCompression.decode(route.trackData)`
2. Reuse `LocationManager.exportTrackAsGPX()` logic (it's a pure function on `[CLLocation]`)
3. Add a share button in `HikeDetailView` toolbar

### Adding route display on the watch map

Load a saved route's track from `RouteStore.shared.fetch(id:)`, decode with `TrackCompression.decode()`, and pass the coordinates to `MapScene.updateTrackTrail()`.

### Adding statistics charts (pace over time, heart rate zones)

Extract data from `TrackCompression.decode()` — each CLLocation has a timestamp, so you can compute pace per segment. Heart rate data would require storing per-point HR in the track format (extend `bytesPerPoint`).

### Adding photos to hike reviews

Store photo UUIDs in a junction table (`hike_photos`) referencing `saved_routes.id`. The pattern already exists in `WaypointStore` for waypoint photos.

---

## Common Debugging Scenarios

### Route not appearing on iPhone after save

1. Check watch console for `"Queued route transfer to iPhone"` log
2. Check if `WCSession.activationState == .activated` on iPhone
3. Verify `RouteStore.shared` is opened on iPhone (`initializeRouteStore()` in `OpenHikerApp`)
4. Check `didReceive file` is called — add a breakpoint in `handleReceivedRoute()`

### Empty elevation profile

1. Check that `TrackCompression.decode()` returns points with valid altitude
2. GPS altitude can be negative (below sea level) or 0 — this is normal
3. If all altitudes are 0, the GPS may not have had a vertical fix

### Walking/resting time seems wrong

1. The 60-second minimum rest threshold filters out brief stops
2. Very slow walking (< 0.3 m/s = ~1 km/h) is counted as resting
3. Adjust `LocationManager.walkingAndRestingMinRestDuration` or `HikeStatisticsConfig.restingSpeedThreshold`

### Database migration after schema change

`RouteStore` uses `CREATE TABLE IF NOT EXISTS` — it won't update existing tables. For schema changes:

1. Add `ALTER TABLE` statements after `CREATE TABLE` in `createSchema()`
2. Wrap in a do/catch — the `ALTER` will fail silently if the column already exists
3. Never delete columns (SQLite doesn't support `DROP COLUMN` before 3.35.0)
