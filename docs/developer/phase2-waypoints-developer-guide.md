# Waypoints & Pins — Developer Guide

This document covers the Phase 2 implementation: waypoint/pin creation on both Apple Watch and iPhone, SQLite-backed storage, bidirectional sync via WatchConnectivity, and map marker rendering. It is written so that a developer unfamiliar with the codebase can modify, expand, or debug this feature.

## Architecture Overview

```
Shared/
  Models/Waypoint.swift           -- WaypointCategory enum + Waypoint struct
  Storage/WaypointStore.swift     -- SQLite CRUD (singleton, serial-queue synchronized)

OpenHiker watchOS/
  Views/AddWaypointSheet.swift    -- Compact pin-drop UI (category grid + label)
  Views/MapView.swift             -- Pin button in bottom bar, waypoint markers
  Services/MapRenderer.swift      -- SpriteKit waypoint marker nodes on MapScene
  App/OpenHikerWatchApp.swift     -- WaypointStore init + WCSession waypoint handlers

OpenHiker iOS/
  Views/AddWaypointView.swift     -- Full form: map preview, category, label, note, photo
  Views/WaypointDetailView.swift  -- View/edit/delete waypoint + full photo viewer
  Views/RegionSelectorView.swift  -- Pin drop button, MapKit annotations, detail sheet
  Services/WatchTransferManager.swift  -- Waypoint sync to/from watch
  App/OpenHikerApp.swift          -- WaypointStore init on launch
```

All waypoint data flows through `WaypointStore.shared` (a singleton). The store is opened once on app launch from both `OpenHikerApp` and `OpenHikerWatchApp`.

---

## Files Reference

### New Files

| File | Target | Purpose |
|------|--------|---------|
| `Shared/Models/Waypoint.swift` | iOS + watchOS | `WaypointCategory` enum (9 categories with icon, color, display name) and `Waypoint` struct (Identifiable, Codable, Sendable, Equatable) |
| `Shared/Storage/WaypointStore.swift` | iOS + watchOS | SQLite-backed storage: insert, update, delete, fetchAll, fetchForHike, fetchNearby, fetchPhoto/Thumbnail |
| `OpenHiker watchOS/Views/AddWaypointSheet.swift` | watchOS | ScrollView with coordinates header, 3x3 category grid, label TextField, Save button |
| `OpenHiker iOS/Views/AddWaypointView.swift` | iOS | NavigationStack Form with map preview, horizontal category picker, label/note fields, camera/library photo picker |
| `OpenHiker iOS/Views/WaypointDetailView.swift` | iOS | Form with map, read-only/editable details, full-resolution photo viewer, delete with confirmation |

### Modified Files

| File | What Changed |
|------|-------------|
| `OpenHiker watchOS/Services/MapRenderer.swift` | Added `updateWaypointMarkers(waypoints:)` and `createWaypointMarkerNode(for:)` to `MapScene`; added `colorFromHex(_:)` helper |
| `OpenHiker watchOS/Views/MapView.swift` | Added pin button to bottom controls; added `showingAddWaypoint` sheet; added `waypoints` state; added `loadWaypoints()` and `refreshWaypointMarkers()` methods |
| `OpenHiker watchOS/App/OpenHikerWatchApp.swift` | Added `initializeWaypointStore()` on appear; added `syncWaypointToPhone(_:)` method; added `didReceiveUserInfo` handler for incoming waypoints |
| `OpenHiker iOS/Views/RegionSelectorView.swift` | Added waypoint state variables; added `ForEach` MapKit `Annotation` for waypoints; added pin drop button; added add/detail sheets; added `loadWaypoints()` and `dropPinAtCenter()` |
| `OpenHiker iOS/Services/WatchTransferManager.swift` | Added `sendWaypointToWatch(_:thumbnail:)` method; added `didReceiveUserInfo` handler for incoming waypoints from watch |
| `OpenHiker iOS/App/OpenHikerApp.swift` | Added `initializeWaypointStore()` on appear |

---

## Data Model

### WaypointCategory

An enum with 9 cases, each providing:

| Property | Type | Example |
|----------|------|---------|
| `rawValue` | `String` | `"trailMarker"` (persisted in SQLite) |
| `iconName` | `String` | `"signpost.right"` (SF Symbol) |
| `displayName` | `String` | `"Trail Marker"` (UI label) |
| `colorHex` | `String` | `"4A90D9"` (6-char hex, no `#`) |

**Adding a new category:** Add a case to the enum and implement all four computed properties. No schema migration needed — the category column is TEXT and unknown values fall back to `.custom`.

### Waypoint

A lightweight struct (no photo blobs inline):

```
id:         UUID        (primary key)
latitude:   Double      (WGS84 degrees)
longitude:  Double      (WGS84 degrees)
altitude:   Double?     (meters above sea level, nil if unavailable)
timestamp:  Date        (creation time)
label:      String      (short user label, can be empty)
category:   WaypointCategory
note:       String      (longer description, can be empty)
hasPhoto:   Bool        (whether photo_data BLOB is non-null)
hikeId:     UUID?       (optional link to a hike, for Phase 3)
```

**Serialization:**

- `Codable` for JSON persistence if needed
- `toDictionary() / fromDictionary(_:)` for WatchConnectivity transfer (uses primitive types compatible with `WCSession.transferUserInfo`)

---

## Storage (WaypointStore)

### SQLite Schema

```sql
CREATE TABLE IF NOT EXISTS waypoints (
    id              TEXT PRIMARY KEY,
    latitude        REAL NOT NULL,
    longitude       REAL NOT NULL,
    altitude        REAL,
    timestamp       TEXT NOT NULL,       -- ISO 8601 with fractional seconds
    label           TEXT NOT NULL DEFAULT '',
    category        TEXT NOT NULL DEFAULT 'custom',
    note            TEXT NOT NULL DEFAULT '',
    has_photo       INTEGER NOT NULL DEFAULT 0,
    hike_id         TEXT,
    photo_data      BLOB,               -- Full-resolution JPEG (iOS only, typically)
    photo_thumbnail BLOB                 -- 100x100 JPEG thumbnail (synced to both)
);

CREATE INDEX IF NOT EXISTS idx_waypoints_hike ON waypoints(hike_id);
CREATE INDEX IF NOT EXISTS idx_waypoints_location ON waypoints(latitude, longitude);
```

### Thread Safety

Follows the same pattern as `TileStore`:

- `final class WaypointStore: @unchecked Sendable`
- All operations run on `DispatchQueue(label: "com.openhiker.waypointstore", qos: .userInitiated)`
- `queue.sync { ... }` for all database access

### Database Location

Both platforms: `Documents/waypoints.db`

### Key Methods

| Method | Description |
|--------|-------------|
| `open()` | Opens/creates the database, runs schema migration |
| `close()` | Closes the SQLite connection (idempotent) |
| `insert(_:)` | Insert without photo |
| `insert(_:photo:thumbnail:)` | Insert with optional photo BLOBs |
| `update(_:)` | Update mutable fields (label, category, note, hasPhoto, hikeId) |
| `delete(id:)` | Delete by UUID |
| `fetchAll()` | All waypoints, newest first |
| `fetchForHike(_:)` | Waypoints linked to a hike, oldest first |
| `fetchNearby(latitude:longitude:radiusMeters:)` | Spatial query with bounding-box pre-filter + Haversine check |
| `fetchThumbnail(id:)` | 100x100 JPEG thumbnail BLOB |
| `fetchPhoto(id:)` | Full-resolution JPEG BLOB |

### Extending the Schema

To add a column:

1. Add the column to `createSchema()` in the `CREATE TABLE IF NOT EXISTS` statement
2. Add a `ALTER TABLE` migration in `createSchema()` that runs after table creation (wrap in try/catch since the column may already exist)
3. Update `parseWaypointRow(_:)` to read the new column
4. Update `insert` and `update` SQL to include the new column
5. Update `Waypoint` struct and `toDictionary()/fromDictionary(_:)`

---

## WatchConnectivity Sync

### Protocol: `transferUserInfo`

Waypoints are synced using `WCSession.transferUserInfo(_:)` which provides reliable queued delivery even when the receiving app is not running.

### Sync Flow

```
Watch -> iPhone:
  1. User saves waypoint on watch (AddWaypointSheet)
  2. WaypointStore.shared.insert(waypoint)
  3. WatchConnectivityReceiver.syncWaypointToPhone(waypoint)
     -> session.transferUserInfo(waypoint.toDictionary() + ["type": "waypoint"])
  4. iPhone receives in WatchConnectivityManager.didReceiveUserInfo
     -> Waypoint.fromDictionary(userInfo)
     -> WaypointStore.shared.insert(waypoint)

iPhone -> Watch:
  1. User saves waypoint on iPhone (AddWaypointView)
  2. WaypointStore.shared.insert(waypoint, photo:, thumbnail:)
  3. WatchConnectivityManager.sendWaypointToWatch(waypoint, thumbnail:)
     -> session.transferUserInfo(waypoint.toDictionary() + ["type": "waypoint", "thumbnailData": ...])
  4. Watch receives in WatchConnectivityReceiver.didReceiveUserInfo
     -> Waypoint.fromDictionary(userInfo)
     -> WaypointStore.shared.insert(waypoint, photo: nil, thumbnail: thumbnailData)
```

### Key Design Decision: `transferUserInfo` vs `transferFile`

- `transferUserInfo` is used instead of `transferFile` because waypoints are small (< 1KB without photo)
- Only the 100x100 thumbnail (< 10KB JPEG) is included in the transfer — full photos are too large for watch storage
- The `"type": "waypoint"` key in the dictionary routes the payload to the waypoint handler

### Adding New Sync Types

To sync a new entity type via the same channel:

1. Add a `toDictionary() / fromDictionary(_:)` pair to your model
2. In the sending side, add `["type": "yourType"]` to the dictionary
3. In `didReceiveUserInfo`, add a new `case` check for `type == "yourType"`

---

## Watch Map Rendering (SpriteKit)

### Waypoint Markers on MapScene

`MapScene.updateWaypointMarkers(waypoints:)` is called from `MapView` whenever:

- The view appears (initial load)
- Zoom level changes (Digital Crown)
- Map recenters on user position
- A waypoint is added or removed
- A region is loaded

Each marker is an `SKNode` with:

```
SKNode (container, z=75)
  +-- SKShapeNode (stem: triangle, 6pt tall)
  +-- SKShapeNode (circle: 10pt radius, white border)
  +-- SKSpriteNode (icon: SF Symbol rendered as UIImage texture, 13x13pt)
```

Marker names follow the pattern `"waypoint-<UUID>"` for identification.

### Position Calculation

Markers are positioned using the same Web Mercator projection as tiles:

```swift
let n = Double(1 << zoom)
let posX = (longitude + 180.0) / 360.0 * n
let posY = (1.0 - asinh(tan(latitude * .pi / 180.0)) / .pi) / 2.0 * n
let screenX = viewWidth / 2 + CGFloat(posX - centerX) * tileSize
let screenY = viewHeight / 2 - CGFloat(posY - centerY) * tileSize
```

### Z-Order

The z-positions in MapScene are layered:

| z-position | Content |
|------------|---------|
| 0 | Tile sprites |
| 50 | Track trail polyline |
| **75** | **Waypoint markers** |
| 99 | Heading cone |
| 100 | Position marker (blue dot) |
| 200 | Compass |

---

## iOS Map Integration (MapKit)

### Waypoint Annotations

In `RegionSelectorView`, waypoints are rendered as MapKit `Annotation` views inside the `Map` content builder:

```swift
ForEach(waypoints) { waypoint in
    Annotation(label, coordinate: waypoint.coordinate) {
        Button { /* show detail */ } label: {
            Image(systemName: waypoint.category.iconName)
                .frame(width: 28, height: 28)
                .background(Color.orange)
                .clipShape(Circle())
        }
    }
}
```

Tapping an annotation opens `WaypointDetailView` as a sheet.

### Pin Drop Flow

1. User taps the pin button (mappin.and.ellipse icon) in the right-side control stack
2. `dropPinAtCenter()` reads the current map camera center
3. `AddWaypointView` is presented as a sheet with the pre-filled coordinates
4. On save, the waypoint is appended to the local `waypoints` array and appears on the map

---

## Photo Handling (iOS Only)

### Capture and Storage

Photos can come from two sources:

- **Camera** via `CameraView` (wraps `UIImagePickerController`)
- **Photo Library** via `PhotosPicker` (SwiftUI native)

Both are processed through `processPhoto(_: UIImage)`:

1. Full-resolution JPEG at 0.8 quality -> `photoData`
2. 100x100 thumbnail via `UIGraphicsImageRenderer` at 0.7 quality -> `thumbnailData`
3. Both stored in `WaypointStore` BLOB columns via `insert(_:photo:thumbnail:)`

### Thumbnail Generation

```swift
let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
let thumbnail = renderer.image { ctx in
    // Aspect-fill scaling centered in the square
    image.draw(in: scaledRect)
}
thumbnailData = thumbnail.jpegData(compressionQuality: 0.7)
```

The thumbnail is small enough (< 10KB) to include in `transferUserInfo` to the watch. Full photos are not synced to the watch due to storage constraints.

---

## Debugging Tips

### SQLite Inspection

On the simulator, the waypoints database is at:

```
~/Library/Developer/CoreSimulator/Devices/<UUID>/data/Containers/Data/Application/<UUID>/Documents/waypoints.db
```

Open with any SQLite client:

```bash
sqlite3 path/to/waypoints.db
.schema
SELECT id, label, category, datetime(timestamp) FROM waypoints;
```

### WatchConnectivity Debugging

- Watch-to-phone transfers log: `"Queued waypoint sync to iPhone: <UUID>"`
- Phone-to-watch transfers log: `"Queued waypoint sync to watch: <UUID>"`
- Reception logs: `"Received and saved waypoint from watch/iPhone: <UUID>"`
- Failures log the error via `print()`

To test sync without hardware:

1. Run both simulators simultaneously in Xcode
2. Waypoints created on one side should appear on the other after a short delay
3. Check the Console for the log messages above

### Map Marker Issues

If markers don't appear on the watch map:

1. Confirm `loadWaypoints()` is called (check console for errors)
2. Confirm `mapScene` is not nil when `refreshWaypointMarkers()` runs
3. Check that markers aren't off-screen (zoom out or check coordinates)
4. Verify the `overlaysNode` z-position hierarchy in `MapScene`

### Photo Issues

If photos don't display in `WaypointDetailView`:

1. Check `waypoint.hasPhoto` is `true`
2. Try `fetchThumbnail` as fallback if `fetchPhoto` returns nil
3. Verify BLOB data was written: `SELECT length(photo_data) FROM waypoints WHERE id = '...'`

---

## Future Extension Points

| Feature | Where to Modify |
|---------|----------------|
| Add new category | `WaypointCategory` enum — add case + all computed properties |
| Bulk import/export | Add GPX waypoint parsing to `WaypointStore` or a new `WaypointImporter` |
| Link waypoints to hike | Set `hikeId` on the `Waypoint`, use `fetchForHike(_:)` to retrieve |
| Distance-to-waypoint | Use `CLLocation.distance(from:)` with `locationManager.currentLocation` |
| Waypoint list view | Create a new tab/view that calls `WaypointStore.shared.fetchAll()` |
| Cloud sync | Replace `WaypointStore` with CloudKit or add a sync adapter layer |
