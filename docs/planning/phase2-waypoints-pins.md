# Phase 2: Waypoints & Pins

**Estimated effort:** ~3 weeks
**Dependencies:** None (can run in parallel with Phase 1)
**Platform focus:** Shared model, then watchOS, then iOS

## Overview

Build the shared waypoint data model and storage layer, then add platform-specific UI for dropping pins. Watch gets a quick "mark this spot" with category presets and voice dictation. iPhone gets full pin creation with camera/photo library. Bidirectional sync via WatchConnectivity.

---

## Feature 2.1: Shared Waypoint Data Model & Storage

**Size:** M (Medium)

### Data Model

```swift
/// Categories for waypoint pins, each with an SF Symbol icon.
enum WaypointCategory: String, Codable, CaseIterable, Sendable {
    case trailMarker    // "signpost.right"
    case viewpoint      // "eye"
    case waterSource    // "drop.fill"
    case campsite       // "tent"
    case danger         // "exclamationmark.triangle"
    case food           // "fork.knife"
    case shelter        // "house"
    case parking        // "car"
    case custom         // "mappin"
}

/// A geotagged waypoint with optional photo and annotation.
struct Waypoint: Identifiable, Codable, Sendable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let timestamp: Date
    var label: String
    var category: WaypointCategory
    var note: String
    var hasPhoto: Bool
    var hikeId: UUID?              // links to a SavedRoute (Phase 3)
}
```

### Storage: `WaypointStore`

SQLite database following the `TileStore` pattern (see `Shared/Storage/TileStore.swift`):
- Serial dispatch queue for thread safety
- `@unchecked Sendable` with internal synchronization
- `open()` / `close()` lifecycle
- Direct SQLite3 API (no third-party ORM)

**Schema:**
```sql
CREATE TABLE waypoints (
    id TEXT PRIMARY KEY,              -- UUID as string
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    altitude REAL,
    timestamp TEXT NOT NULL,          -- ISO 8601
    label TEXT NOT NULL DEFAULT '',
    category TEXT NOT NULL DEFAULT 'custom',
    note TEXT NOT NULL DEFAULT '',
    has_photo INTEGER NOT NULL DEFAULT 0,
    hike_id TEXT,                     -- FK to saved route UUID
    photo_data BLOB,                 -- full-res JPEG (iOS only)
    photo_thumbnail BLOB             -- 100x100 JPEG (both platforms)
);

CREATE INDEX idx_waypoints_hike ON waypoints(hike_id);
CREATE INDEX idx_waypoints_location ON waypoints(latitude, longitude);
```

**Key methods:**
```swift
func open() throws
func close()
func insert(_ waypoint: Waypoint) throws
func insert(_ waypoint: Waypoint, photo: Data?, thumbnail: Data?) throws
func update(_ waypoint: Waypoint) throws
func delete(id: UUID) throws
func fetchAll() throws -> [Waypoint]
func fetchForHike(_ hikeId: UUID) throws -> [Waypoint]
func fetchNearby(latitude: Double, longitude: Double, radiusMeters: Double) throws -> [Waypoint]
func fetchThumbnail(id: UUID) throws -> Data?
func fetchPhoto(id: UUID) throws -> Data?
```

### Files to Create

- `Shared/Models/Waypoint.swift` — `Waypoint` struct, `WaypointCategory` enum
- `Shared/Storage/WaypointStore.swift` — SQLite CRUD

### Testing

- Unit test CRUD operations on WaypointStore
- Test spatial query (fetchNearby) with known coordinates
- Test that Waypoint encodes/decodes correctly via Codable

---

## Feature 2.2: Drop Pins on Watch

**Size:** M (Medium)

### What It Does

A "pin" button on the watch map. Tapping it opens a compact sheet where the user selects a category (via SF Symbol grid) and optionally dictates a label. The pin is saved at the current GPS location and rendered on the SpriteKit map.

### UI Flow

1. User taps pin button (📍 icon in bottom controls bar)
2. Sheet opens with:
   - Current coordinates displayed at top (read-only)
   - Category grid: 3×3 grid of SF Symbol buttons (one per `WaypointCategory`)
   - Label field: optional text via watchOS dictation (`TextField` with `.dictation`)
   - "Save" button
3. On save → create `Waypoint`, insert into `WaypointStore`, render marker on map
4. Dismiss sheet

### SpriteKit Waypoint Markers

Add waypoint rendering to `MapScene` (in `MapRenderer.swift`):
- Each waypoint = `SKSpriteNode` with the category's SF Symbol rendered as a `UIImage`
- Position calculated from lat/lon → pixel coordinates (same math as position marker)
- Markers update position on zoom/pan (like tiles do)
- Tap on marker → show label in a tooltip overlay (optional, Phase 2.2 enhancement)

### WatchConnectivity Sync

When a waypoint is saved on the watch, sync to iPhone:
- Use `WCSession.default.transferUserInfo(["waypoint": waypointJSON])` (queued, reliable delivery)
- On iPhone: `WatchTransferManager` receives `userInfo`, decodes `Waypoint`, inserts into local `WaypointStore`

### Files to Create

#### `OpenHiker watchOS/Views/AddWaypointSheet.swift`
- Category picker grid
- Dictation text field for label
- Save button that creates Waypoint from current GPS + selected category

### Files to Modify

#### `OpenHiker watchOS/Views/MapView.swift`
- Add pin button to `bottomControls` (between center and region picker)
- Add `@State private var showingAddWaypoint = false`
- Add `.sheet(isPresented: $showingAddWaypoint)` for `AddWaypointSheet`
- On appear + on waypoint change: call `mapScene?.updateWaypointMarkers()`

#### `OpenHiker watchOS/Services/MapRenderer.swift`
- Add `func updateWaypointMarkers(waypoints: [Waypoint])` to `MapScene`
- Create/reposition `SKSpriteNode` markers for each waypoint
- Node naming convention: `"waypoint-\(id)"` for identification
- Remove markers that no longer exist, add new ones

#### `OpenHiker watchOS/App/OpenHikerWatchApp.swift`
- Initialize `WaypointStore.shared` and inject into environment
- In `WatchConnectivityReceiver`: add handler for incoming waypoint userInfo from iPhone
- Add outgoing waypoint sync: after saving a new waypoint, call `transferUserInfo`

### Testing

1. Start tracking on watch, tap pin button
2. Select a category, optionally dictate a label, save
3. Verify marker appears on map at current GPS location
4. Pan/zoom — marker should reposition correctly
5. Verify waypoint appears in iPhone's WaypointStore after sync

---

## Feature 2.3: Drop Pins on iPhone with Photos

**Size:** M (Medium)

### What It Does

Long-press on the MapKit map to drop a pin. Opens a full creation form with:
- Auto-filled coordinates from the tap location
- Category picker (segmented control or picker wheel)
- Label and note text fields
- Photo picker (camera or photo library)
- Save button

Also renders existing waypoints (including those synced from watch) as MapKit annotations.

### Photo Handling

- **Camera:** Use `UIImagePickerController` with `sourceType: .camera`
- **Photo library:** Use `PHPickerViewController` (modern, no deprecated APIs)
- **Storage:** Full-res JPEG in `WaypointStore.photo_data` on iOS, 100×100 thumbnail in `photo_thumbnail`
- **Thumbnail generation:** Scale image with `UIGraphicsImageRenderer`, compress as JPEG quality 0.7
- **Transfer to watch:** Only thumbnails are sent (watch has limited storage)

### MapKit Annotations

Render waypoints as `MKAnnotationView` instances:
- Custom view with the category's SF Symbol
- Callout on tap showing label, note, and thumbnail
- Tapping callout opens `WaypointDetailView`

### WatchConnectivity Sync

When iPhone receives waypoints from watch or creates new ones:
- Outgoing to watch: send waypoint JSON + thumbnail (no full photo) via `transferUserInfo`
- Incoming from watch: decode waypoint from `userInfo`, insert into local store

### Files to Create

#### `OpenHiker iOS/Views/AddWaypointView.swift`
- Form view with:
  - Map snippet showing the pin location (small `MKMapView` preview)
  - Category picker
  - Label text field
  - Note text area
  - Photo section: camera button + library button + thumbnail preview
  - Save / Cancel buttons

#### `OpenHiker iOS/Views/WaypointDetailView.swift`
- Read/edit view for existing waypoint
- Full photo display (tap to enlarge)
- Edit label, note, category
- Delete button with confirmation

### Files to Modify

#### `OpenHiker iOS/Views/RegionSelectorView.swift`
- Add `UILongPressGestureRecognizer` on the MapKit view (or SwiftUI `onLongPressGesture`)
- Convert tap coordinate to `CLLocationCoordinate2D` via `MKMapView.convert(_:toCoordinateFrom:)`
- Open `AddWaypointView` sheet with pre-filled coordinates
- Add `MKAnnotationView` rendering for existing waypoints from `WaypointStore`
- On annotation tap → navigate to `WaypointDetailView`

#### `OpenHiker iOS/Services/WatchTransferManager.swift`
- In `session(_:didReceiveUserInfo:)`: check for waypoint key, decode, insert into local store
- Add `sendWaypointToWatch(_ waypoint: Waypoint)` method that packages JSON + thumbnail

#### `OpenHiker iOS/App/OpenHikerApp.swift`
- Initialize `WaypointStore.shared` and inject into environment

### Privacy Permissions

Add to iOS `Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>OpenHiker uses the camera to take geotagged photos at waypoints along your hike.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>OpenHiker accesses your photo library to attach photos to waypoints along your hike.</string>
```

### Testing

1. Long-press on iPhone map → verify AddWaypointView opens with correct coordinates
2. Select category, enter label, take/select photo → save
3. Verify pin appears as MapKit annotation on the map
4. Tap annotation → verify detail view shows label, note, full photo
5. Verify thumbnail syncs to watch and appears on watch map
6. Drop pin on watch → verify it appears on iPhone map after sync
7. Delete waypoint on iPhone → verify it's removed from map
