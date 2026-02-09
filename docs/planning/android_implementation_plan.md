# Android OpenHiker — Stepwise Implementation Plan

## Decisions Made

- **Map SDK:** MapLibre Native Android (osmdroid archived Nov 2024, no longer maintained)
- **Tile sources:** Same as iOS — OpenTopoMap, CyclOSM, OpenStreetMap Standard
- **Cloud sync:** File-based export/import to user-chosen cloud drive (Dropbox, iCloud Drive, Google Drive). Atomic file format for efficient syncing — no proprietary backend.
- **P2P sharing:** Deferred to a later phase.
- **Watch features:** Excluded from initial port.

## Technology Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| Language | Kotlin | Android-native, coroutines map to Swift actors |
| UI | Jetpack Compose | Declarative like SwiftUI, official MapLibre Compose support |
| Map SDK | MapLibre Native Android | Free (BSD-2), GPU-accelerated, native MBTiles via `mbtiles://`, active maintenance |
| Navigation | Compose Navigation | Standard Compose navigation |
| Database | Room | Type-safe SQLite, coroutine support, same schemas as iOS |
| HTTP | OkHttp + Retrofit | Connection pooling, interceptors, rate limiting |
| Concurrency | Kotlin Coroutines + Flow | Direct equivalent of Swift async/await + Combine |
| Location | FusedLocationProviderClient + fallback to LocationManager | Best accuracy with GMS, works without GMS too |
| DI | Hilt | Standard Android DI, integrates with ViewModel/Compose |
| Serialization | Kotlinx.serialization | Multiplatform, performant, Kotlin-native |
| Charts | Vico | Compose-native charting library |
| Image Loading | Coil | Kotlin-first, Compose integration |
| PDF | Android PdfDocument API | Built-in, no dependencies |
| Background | Foreground Service + WorkManager | GPS tracking requires foreground service on Android |
| Build | Gradle with Kotlin DSL (.kts) | Modern Android standard |
| Min SDK | API 26 (Android 8.0, ~97% device coverage) | Java 8 desugaring not needed, good baseline |

---

## Project Structure

```
OpenHikerAndroid/
├── app/
│   ├── src/main/
│   │   ├── java/com/openhiker/android/
│   │   │   ├── OpenHikerApp.kt              # Application class, Hilt entry point
│   │   │   ├── MainActivity.kt              # Single-activity architecture
│   │   │   ├── di/                           # Hilt modules
│   │   │   │   ├── DatabaseModule.kt
│   │   │   │   ├── NetworkModule.kt
│   │   │   │   └── LocationModule.kt
│   │   │   ├── data/
│   │   │   │   ├── db/                       # Room databases
│   │   │   │   │   ├── tiles/                # MBTiles read/write
│   │   │   │   │   │   ├── TileStore.kt
│   │   │   │   │   │   └── WritableTileStore.kt
│   │   │   │   │   ├── routing/              # Routing graph DB
│   │   │   │   │   │   ├── RoutingDatabase.kt
│   │   │   │   │   │   ├── RoutingDao.kt
│   │   │   │   │   │   └── RoutingEntities.kt
│   │   │   │   │   ├── routes/               # Saved hikes DB
│   │   │   │   │   │   ├── RouteDatabase.kt
│   │   │   │   │   │   ├── RouteDao.kt
│   │   │   │   │   │   └── RouteEntities.kt
│   │   │   │   │   └── waypoints/            # Waypoints DB
│   │   │   │   │       ├── WaypointDatabase.kt
│   │   │   │   │       ├── WaypointDao.kt
│   │   │   │   │       └── WaypointEntities.kt
│   │   │   │   ├── model/                    # Data classes
│   │   │   │   │   ├── Region.kt
│   │   │   │   │   ├── TileCoordinate.kt
│   │   │   │   │   ├── BoundingBox.kt
│   │   │   │   │   ├── PlannedRoute.kt
│   │   │   │   │   ├── SavedRoute.kt
│   │   │   │   │   ├── TurnInstruction.kt
│   │   │   │   │   ├── Waypoint.kt
│   │   │   │   │   ├── ElevationPoint.kt
│   │   │   │   │   └── HikeStatistics.kt
│   │   │   │   └── repository/               # Data access layer
│   │   │   │       ├── RegionRepository.kt
│   │   │   │       ├── RouteRepository.kt
│   │   │   │       ├── WaypointRepository.kt
│   │   │   │       └── PlannedRouteRepository.kt
│   │   │   ├── service/                      # Background & platform services
│   │   │   │   ├── tile/
│   │   │   │   │   └── TileDownloadService.kt
│   │   │   │   ├── location/
│   │   │   │   │   ├── LocationService.kt          # Foreground service
│   │   │   │   │   └── LocationManager.kt
│   │   │   │   ├── routing/
│   │   │   │   │   ├── RoutingEngine.kt
│   │   │   │   │   └── RoutingGraphBuilder.kt
│   │   │   │   ├── elevation/
│   │   │   │   │   └── ElevationDataManager.kt
│   │   │   │   ├── osm/
│   │   │   │   │   ├── OSMDataDownloader.kt
│   │   │   │   │   └── PBFParser.kt
│   │   │   │   ├── navigation/
│   │   │   │   │   └── RouteGuidance.kt
│   │   │   │   ├── export/
│   │   │   │   │   ├── PDFExporter.kt
│   │   │   │   │   └── GPXExporter.kt
│   │   │   │   ├── community/
│   │   │   │   │   └── GitHubRouteService.kt
│   │   │   │   └── sync/
│   │   │   │       └── CloudDriveSync.kt
│   │   │   └── ui/
│   │   │       ├── navigation/
│   │   │       │   └── AppNavigation.kt          # NavHost + routes
│   │   │       ├── theme/
│   │   │       │   ├── Theme.kt
│   │   │       │   ├── Color.kt
│   │   │       │   └── Type.kt
│   │   │       ├── regions/
│   │   │       │   ├── RegionSelectorScreen.kt
│   │   │       │   ├── RegionSelectorViewModel.kt
│   │   │       │   ├── RegionListScreen.kt
│   │   │       │   └── RegionListViewModel.kt
│   │   │       ├── map/
│   │   │       │   ├── MapScreen.kt                # MapLibre Compose map
│   │   │       │   └── MapViewModel.kt
│   │   │       ├── routing/
│   │   │       │   ├── RoutePlanningScreen.kt
│   │   │       │   ├── RoutePlanningViewModel.kt
│   │   │       │   ├── RouteDetailScreen.kt
│   │   │       │   └── RouteDetailViewModel.kt
│   │   │       ├── navigation_guidance/
│   │   │       │   ├── NavigationScreen.kt
│   │   │       │   └── NavigationViewModel.kt
│   │   │       ├── hikes/
│   │   │       │   ├── HikeListScreen.kt
│   │   │       │   ├── HikeListViewModel.kt
│   │   │       │   ├── HikeDetailScreen.kt
│   │   │       │   └── HikeDetailViewModel.kt
│   │   │       ├── waypoints/
│   │   │       │   ├── WaypointListScreen.kt
│   │   │       │   ├── WaypointDetailScreen.kt
│   │   │       │   ├── AddWaypointScreen.kt
│   │   │       │   └── WaypointViewModel.kt
│   │   │       ├── community/
│   │   │       │   ├── CommunityBrowseScreen.kt
│   │   │       │   ├── CommunityRouteDetailScreen.kt
│   │   │       │   ├── RouteUploadScreen.kt
│   │   │       │   └── CommunityViewModel.kt
│   │   │       ├── export/
│   │   │       │   └── ExportSheet.kt
│   │   │       └── components/                     # Reusable UI components
│   │   │           ├── ElevationProfileChart.kt
│   │   │           ├── HikeStatsBar.kt
│   │   │           ├── TileSourceSelector.kt
│   │   │           └── PermissionHandler.kt
│   │   ├── res/                                    # Android resources
│   │   └── AndroidManifest.xml
│   └── build.gradle.kts
├── gradle/
├── build.gradle.kts                                # Root build file
├── settings.gradle.kts
└── gradle.properties
```

---

## Implementation Phases

### Phase 1: Foundation & Offline Maps

The goal is to get a working app that can download, store, and display map tiles offline.

#### Step 1.1 — Project Scaffolding

**What:** Create the Android project with all dependencies configured.

- Initialize Android project with `com.openhiker.android` package
- Configure Gradle with all dependencies (MapLibre, Room, Hilt, OkHttp, Coroutines, Compose, Vico, Coil, Kotlinx.serialization)
- Set up Hilt application class and dependency injection modules
- Create `MainActivity` with single-activity Compose architecture
- Set up `AppNavigation` with `NavHost` and placeholder screens for all tabs
- Configure Material 3 theme (colors, typography)
- Set up bottom navigation with tabs: Navigate, Regions, Hikes, Routes, Community
- Configure ProGuard/R8 rules
- Set up `AndroidManifest.xml` with required permissions:
  - `INTERNET`, `ACCESS_NETWORK_STATE` (tile download)
  - `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` (GPS)
  - `ACCESS_BACKGROUND_LOCATION` (hike tracking)
  - `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION` (background GPS)
  - `VIBRATE` (haptic feedback)
  - `POST_NOTIFICATIONS` (foreground service notification, Android 13+)

**Depends on:** Nothing.
**Deliverable:** App compiles, launches, and shows tabbed navigation with empty screens.

#### Step 1.2 — Data Models & Room Databases

**What:** Port all data models from Swift to Kotlin and set up Room databases.

- Port `TileCoordinate` with web Mercator ↔ lat/lon conversions and TMS Y-flipping
- Port `BoundingBox`, `Region`, `RegionMetadata`
- Port `PlannedRoute`, `TurnInstruction`, `TurnDirection`, `ComputedRoute`
- Port `SavedRoute`, `HikeStatistics`, `TrackCompression` (zlib via `java.util.zip`)
- Port `Waypoint`, `WaypointCategory`
- Port `SharedRoute`, `RouteIndex`, community models
- Create Room database for routes (`saved_routes` table with zlib-compressed track BLOBs)
- Create Room database for waypoints (`waypoints` table with photo BLOBs)
- Create Room database for routing (`routing_nodes`, `routing_edges`, `routing_metadata` tables)
- Implement `TileStore` — read-only MBTiles access using Android SQLite API (not Room, since MBTiles is a pre-existing schema we don't own). Handle TMS Y-coordinate flipping.
- Implement `WritableTileStore` — extends TileStore with tile insertion for downloads
- Create repository classes with coroutine-based data access

**Depends on:** Step 1.1.
**Deliverable:** All data models compile, Room databases create tables, TileStore can read/write MBTiles files in tests.

#### Step 1.3 — Map Display with MapLibre

**What:** Display an interactive map using MapLibre with online tile sources.

- Integrate MapLibre Compose into `MapScreen`
- Create a local style JSON that references OpenTopoMap as a raster tile source:
  ```json
  {
    "version": 8,
    "sources": {
      "opentopomap": {
        "type": "raster",
        "tiles": ["https://a.tile.opentopomap.org/{z}/{x}/{y}.png"],
        "tileSize": 256,
        "attribution": "© OpenStreetMap contributors, SRTM | © OpenTopoMap (CC-BY-SA)"
      }
    },
    "layers": [{"id": "opentopomap", "type": "raster", "source": "opentopomap"}]
  }
  ```
- Implement tile source switching (OpenTopoMap, CyclOSM, OSM Standard) via style JSON swaps
- Add `LocationComponent` for GPS position display (COMPASS render mode for heading)
- Implement camera position persistence via DataStore (equivalent to iOS `@AppStorage`)
- Test: Map renders, pans, zooms smoothly. Tile source switches. GPS dot shows current location.

**Depends on:** Step 1.1.
**Deliverable:** Working interactive map with online tiles and GPS overlay.

#### Step 1.4 — Tile Downloading

**What:** Port the tile download engine for offline map storage.

- Implement `TileDownloadService` using Kotlin coroutines:
  - OkHttp client with `Dispatcher(maxRequests=6, maxRequestsPerHost=6)`
  - Rate limiting via `delay(50)` between requests (OSM tile usage policy)
  - Subdomain rotation for OpenTopoMap/CyclOSM (a/b/c subdomains)
  - Batch processing (150 tiles per batch)
  - Exponential backoff retry (4 attempts: 1s, 2s, 4s, 8s)
  - Proper `User-Agent` header: `"OpenHiker-Android/1.0 (hiking app; https://github.com/hherb/OpenHiker)"`
  - Progress reporting via `StateFlow<DownloadProgress>`
- Wire into `WritableTileStore` for tile persistence
- Calculate tile ranges from `BoundingBox` + zoom level range (port `TileRange` logic)

**Depends on:** Step 1.2 (TileStore/WritableTileStore).
**Deliverable:** Can programmatically download a region's tiles to an MBTiles file.

#### Step 1.5 — Region Selection UI

**What:** Build the region selection and download interface.

- `RegionSelectorScreen`:
  - Full-screen MapLibre map with tile source selector
  - Location search bar using Android Geocoder API (or Nominatim for GMS-free devices)
  - Drag-to-select rectangle overlay for defining region bounds
  - Zoom level range selector (12–16)
  - Tile count estimate display
  - Download button with confirmation
  - Download progress indicator (progress bar + tile count + percentage)
- `RegionSelectorViewModel`:
  - Manages selected bounds, zoom range, tile server
  - Triggers download via `TileDownloadService`
  - Exposes download state via `StateFlow`
- Region metadata storage: JSON file in app internal storage (`filesDir/regions_metadata.json`)
- MBTiles file storage: `filesDir/regions/<uuid>.mbtiles`

**Depends on:** Steps 1.3 (map display), 1.4 (tile download).
**Deliverable:** User can select a map region, download tiles, and see download progress.

#### Step 1.6 — Offline Map Display

**What:** Display downloaded regions offline using MBTiles.

- Generate local style JSON referencing MBTiles file via `mbtiles://` URI:
  ```json
  {
    "sources": {
      "offline": {
        "type": "raster",
        "url": "mbtiles:///data/data/com.openhiker.android/files/regions/<uuid>.mbtiles",
        "tileSize": 256
      }
    }
  }
  ```
- Switch between online browsing mode and offline region viewing mode
- Show region boundary overlays on the map (GeoJSON polygon source + FillLayer)
- Handle missing tiles gracefully (show placeholder or nothing outside downloaded region)
- Test in airplane mode: map renders from local MBTiles, no network requests.

**Depends on:** Steps 1.3, 1.5.
**Deliverable:** Downloaded regions display fully offline. Airplane mode works.

#### Step 1.7 — Region Management

**What:** List, rename, and delete downloaded regions.

- `RegionListScreen`:
  - List of downloaded regions with name, tile count, file size, zoom range, bounding box
  - Swipe-to-delete with confirmation dialog
  - Tap to rename (inline text field)
  - Tap to view on map (navigate to map centered on region)
  - Pull-to-refresh to recalculate file sizes
- `RegionListViewModel`:
  - Loads regions from JSON metadata
  - Manages rename/delete operations
  - Recalculates storage statistics

**Depends on:** Steps 1.5, 1.6.
**Deliverable:** Full region CRUD. End of Phase 1 — the app is a functional offline map viewer.

---

### Phase 2: Navigation & Routing

The goal is to add GPS tracking, offline routing, and turn-by-turn navigation.

#### Step 2.1 — GPS Location Service

**What:** Implement continuous GPS tracking with a foreground service for background operation.

- `LocationService` (Android Foreground Service):
  - Persistent notification showing "OpenHiker is tracking your hike"
  - `FusedLocationProviderClient` with `LocationRequest`:
    - High accuracy: `PRIORITY_HIGH_ACCURACY`, 5m displacement
    - Balanced: `PRIORITY_BALANCED_POWER_ACCURACY`, 10m displacement
    - Low power: `PRIORITY_LOW_POWER`, 50m displacement
  - Falls back to `android.location.LocationManager` if GMS unavailable
  - Compass heading via `SensorManager` + `TYPE_ROTATION_VECTOR`
  - Lifecycle-aware: starts/stops with hike recording
- `LocationManager` (app-level, not the Android system class):
  - Exposes `StateFlow<Location?>`, `StateFlow<Float?>` (heading)
  - Incremental distance calculation (Haversine between consecutive points)
  - Elevation gain/loss accumulation with noise filtering
  - Track point recording to in-memory list
- Runtime permission handling:
  - `ACCESS_FINE_LOCATION` (required)
  - `ACCESS_BACKGROUND_LOCATION` (requested separately per Android policy)
  - `POST_NOTIFICATIONS` (Android 13+, for foreground service notification)
  - Permission rationale dialogs explaining why each permission is needed

**Depends on:** Step 1.1.
**Deliverable:** GPS tracking works in foreground and background. Location dot on map follows user.

#### Step 2.2 — Elevation Data Manager

**What:** Port the SRTM/ASTER elevation data system.

- `ElevationDataManager`:
  - Downloads HGT tiles from Tilezen/Mapzen Skadi (same S3 URLs as iOS)
  - Fallback to OpenTopography SRTM GL1
  - Gzip decompression via `java.util.zip.GZIPInputStream`
  - HGT parsing: `java.nio.ByteBuffer` with `ByteOrder.BIG_ENDIAN`, 3601×3601 grid
  - Bilinear interpolation for sub-cell accuracy (port Swift math directly)
  - In-memory LRU cache of loaded tiles (`LruCache`)
  - Exponential backoff retry (4 attempts)
  - Storage: `filesDir/elevation/{N|S}{lat}{E|W}{lon}.hgt.gz`

**Depends on:** Step 1.1 (network layer).
**Deliverable:** Can query elevation for any lat/lon coordinate.

#### Step 2.3 — OSM Data Download & PBF Parsing

**What:** Port the Overpass API download and OSM data parsing pipeline.

- `OSMDataDownloader`:
  - Overpass API queries for hiking/cycling trails (same query filters as iOS)
  - Primary endpoint: `overpass-api.de`, fallback: `overpass.kumi.systems`
  - Region size limit: 100x100 km (10,000 km²)
  - 5-minute timeout via OkHttp `callTimeout()`
  - Exponential backoff retry
  - Cache downloaded data in `filesDir/osm/`
- `PBFParser`:
  - Option A: Use existing Java library `crosby.binary` (osm-pbf) from Maven Central
  - Option B: Port the Swift PBF parser (if the library doesn't fit)
  - Filter to routable ways (highway tags matching iOS filter set)
  - Extract nodes, ways with references

**Depends on:** Step 1.1 (network layer).
**Deliverable:** Can download and parse OSM trail data for a region.

#### Step 2.4 — Routing Graph Builder

**What:** Port the graph construction pipeline that creates the offline routing database.

- `RoutingGraphBuilder` (coroutine-based):
  1. Take parsed OSM nodes + ways as input
  2. Identify junction nodes (nodes shared by ≥2 ways)
  3. Split ways at junctions into edges
  4. Query elevation for all nodes via `ElevationDataManager`
  5. Compute edge costs (distance + elevation gain penalty + surface multiplier + SAC scale)
  6. Write to Room database: `routing_nodes`, `routing_edges`, `routing_metadata`
  - Surface type cost multipliers (same values as iOS):
    - Paved: 1.0, Gravel: 1.1, Dirt: 1.2, etc.
  - SAC scale penalties (same values as iOS)
  - Progress reporting via `StateFlow`

**Depends on:** Steps 2.2 (elevation), 2.3 (OSM data).
**Deliverable:** Can build a routing graph database from downloaded OSM + elevation data.

#### Step 2.5 — A\* Routing Engine

**What:** Port the A\* pathfinding algorithm.

- `RoutingEngine`:
  - A\* search over the Room routing database
  - `java.util.PriorityQueue` for open set
  - Haversine heuristic (admissible, consistent)
  - Elevation-aware cost calculation (same cost function as iOS)
  - Via-point support (sequential A\* between waypoints)
  - Returns `ComputedRoute` with:
    - Ordered list of coordinates (polyline)
    - Turn-by-turn `TurnInstruction` list
    - Total distance, elevation gain/loss, estimated time
    - Elevation profile (`List<ElevationPoint>`)

**Depends on:** Step 2.4 (routing graph).
**Deliverable:** Can compute offline hiking routes with turn instructions.

#### Step 2.6 — Route Planning UI

**What:** Build the route planning interface.

- `RoutePlanningScreen`:
  - Full-screen MapLibre map showing selected region's offline tiles
  - Tap to set start point (green marker)
  - Tap to set end point (red marker)
  - Long-press to add via-points (blue markers, draggable)
  - "Compute Route" button → calls `RoutingEngine`
  - Route preview as polyline overlay on map (GeoJSON LineLayer)
  - Stats display: distance, elevation gain/loss, estimated time
  - "Save Route" button → name entry → persist to `PlannedRouteRepository`
- `RoutePlanningViewModel`:
  - Manages start/end/via-point state
  - Triggers routing computation
  - Handles save operation

**Depends on:** Steps 1.6 (offline map), 2.5 (routing engine).
**Deliverable:** User can plan routes on offline map with A\* routing.

#### Step 2.7 — Turn-by-Turn Navigation

**What:** Implement live navigation guidance with haptic feedback.

- `RouteGuidance`:
  - Consumes location updates from `LocationManager`
  - Matches current position to nearest route segment
  - Calculates distance to next turn instruction
  - Detects off-route condition (configurable threshold, default 50m)
  - Exposes via `StateFlow`:
    - `currentInstruction: TurnInstruction?`
    - `distanceToNextTurn: Double`
    - `progress: Float` (0.0–1.0)
    - `remainingDistance: Double`
    - `isOffRoute: Boolean`
  - Haptic feedback via `android.os.Vibrator`:
    - Approaching turn (100m): short buzz
    - At turn: medium buzz
    - Off-route: warning pattern (long-short-long)
    - Route complete: success pattern
- `NavigationScreen`:
  - Map with live GPS tracking (camera follows user)
  - Current instruction card with turn arrow icon + street name
  - Distance to next turn
  - Progress bar
  - Stats overlay (distance, time, elevation)
  - Off-route warning banner
  - Stop navigation button

**Depends on:** Steps 2.1 (GPS), 2.5 (routing), 2.6 (route planning).
**Deliverable:** Full turn-by-turn hiking navigation. End of Phase 2.

---

### Phase 3: History, Waypoints & Export

The goal is to add hike recording/review, waypoint management, and data export.

#### Step 3.1 — Hike Recording

**What:** Record GPS tracks during a hike with statistics.

- Extend `LocationService` to record track points during active hike
- `HikeStatistics` accumulation:
  - Total distance (Haversine sum)
  - Elevation gain/loss (with noise filter: ignore changes < 3m)
  - Walking time vs resting time (speed threshold: 0.3 m/s)
  - Average/max speed
  - Start/end timestamps
- Track compression: zlib compress the coordinate array before saving to Room
  - Use `java.util.zip.Deflater`/`Inflater` (same algorithm as iOS)
  - Encoding: sequential lat, lon, elevation, timestamp per point as packed binary
- Save to `RouteRepository` on hike completion
- Auto-save draft every 5 minutes (crash recovery)

**Depends on:** Step 2.1 (GPS service).
**Deliverable:** Hikes are recorded with full statistics and compressed GPS tracks.

#### Step 3.2 — Hike History UI

**What:** Build the hike list and detail screens.

- `HikeListScreen`:
  - Scrollable list of saved hikes
  - Each card shows: name, date, distance, elevation gain, duration
  - Sort by date/distance/elevation
  - Swipe-to-delete with confirmation
  - Search/filter
- `HikeDetailScreen`:
  - Map with recorded track polyline (GeoJSON LineLayer)
  - Full statistics table
  - Elevation profile chart (Vico line chart)
  - Rename/delete options
  - Export button (→ ExportSheet)

**Depends on:** Steps 3.1, 1.6 (offline map for track display).
**Deliverable:** Users can review all past hikes with track visualization and statistics.

#### Step 3.3 — Elevation Profile Chart

**What:** Interactive elevation profile visualization.

- `ElevationProfileChart` (reusable Compose component):
  - Vico line chart: X-axis = distance (km), Y-axis = elevation (m)
  - Touch/drag to show elevation at point (crosshair marker)
  - During navigation: current position indicator on chart
  - Gradient fill under the line
  - Min/max elevation labels
- Used in: `HikeDetailScreen`, `RouteDetailScreen`, `NavigationScreen`

**Depends on:** Step 1.1 (Vico dependency).
**Deliverable:** Reusable elevation chart component.

#### Step 3.4 — Waypoint Management

**What:** Create, view, edit, and delete waypoints with photos.

- `AddWaypointScreen`:
  - Photo selection via `ActivityResultContracts.PickVisualMedia`
  - Also offer camera capture via `ActivityResultContracts.TakePicture`
  - Category picker (9 categories: viewpoint, water, shelter, summit, campsite, danger, info, parking, custom)
  - Notes text field
  - Auto-fills current GPS coordinates
  - Generates 100x100 thumbnail from selected photo
  - Saves to `WaypointRepository` (Room, with photo + thumbnail as BLOBs)
- `WaypointListScreen`:
  - All waypoints across all hikes
  - Filter by category chips
  - Thumbnail + name + category + distance from current location
  - Tap → detail view
- `WaypointDetailScreen`:
  - Full-resolution photo display
  - Name, category, coordinates, notes
  - Associated hike reference
  - Map snippet showing waypoint location
  - Edit/delete options

**Depends on:** Step 1.2 (Room database).
**Deliverable:** Full waypoint CRUD with photo support.

#### Step 3.5 — Route Detail & Management

**What:** View and manage planned routes.

- `RouteDetailScreen`:
  - Map with route polyline
  - Turn-by-turn instruction list (scrollable)
  - Elevation profile chart
  - Statistics (distance, elevation gain/loss, estimated time)
  - "Start Navigation" button → launches NavigationScreen
  - Rename / delete
  - Export button (→ ExportSheet)
  - Waypoints along route

**Depends on:** Steps 2.6 (route planning), 3.3 (elevation chart).
**Deliverable:** Full route detail view matching iOS parity.

#### Step 3.6 — PDF & GPX Export

**What:** Export hikes and routes to PDF reports and GPX files.

- `GPXExporter`:
  - Standard GPX 1.1 XML format
  - Includes track points with elevation and timestamps
  - Metadata (name, description)
  - Share via Android `Intent.ACTION_SEND` or save to Downloads via MediaStore
- `PDFExporter`:
  - `android.graphics.pdf.PdfDocument` for multi-page composition
  - Page 1: Map snapshot (MapLibre snapshot API) + title + date + stats table
  - Page 2: Elevation profile (render Vico chart to Bitmap, draw on PDF Canvas)
  - Page 3: Photos grid (if waypoint photos exist)
  - Page 4: Waypoint table
  - US Letter size (612x792 points)
  - Share via `FileProvider` + `Intent.ACTION_SEND`
- `ExportSheet`:
  - Bottom sheet with format selection (PDF / GPX)
  - Triggers appropriate exporter

**Depends on:** Steps 3.2 (hike data), 3.3 (chart), 3.5 (route data).
**Deliverable:** Hikes and routes exportable as PDF reports and GPX files. End of Phase 3.

---

### Phase 4: Community & Cloud Sync

The goal is to add community route sharing and cross-device sync.

#### Step 4.1 — Community Route Browsing

**What:** Browse and download community-shared routes from GitHub.

- `GitHubRouteService`:
  - Same GitHub API endpoints as iOS (`hherb/OpenHikerRoutes` repo)
  - Retrofit interface for REST calls
  - Fetch `index.json` for route catalog
  - Fetch individual `route.json` for details
  - Download route and save to `PlannedRouteRepository`
  - Token obfuscation via ProGuard string encryption or NDK
- `CommunityBrowseScreen`:
  - Scrollable list of community routes
  - Search/filter by name, distance, difficulty
  - Each card: name, author, distance, elevation, difficulty badge
  - Tap → detail view
- `CommunityRouteDetailScreen`:
  - Author info, description
  - Map preview with route polyline
  - Statistics
  - Download button → saves locally

**Depends on:** Step 1.1 (network layer).
**Deliverable:** Users can browse and download community routes.

#### Step 4.2 — Route Upload to Community

**What:** Allow users to share their routes with the community via GitHub PR.

- `RouteUploadScreen`:
  - Select a saved route to share
  - Compose metadata (description, difficulty, tips)
  - Select photos to attach
  - Preview before submitting
  - Submit → `GitHubRouteService` creates PR via GitHub API
  - Status feedback (submitting, submitted, error)

**Depends on:** Steps 4.1, 3.5 (route detail).
**Deliverable:** Users can upload routes to the community repository.

#### Step 4.3 — Cloud Drive Sync (Export/Import)

**What:** Implement file-based sync via user-chosen cloud drive.

**Architecture:**
Rather than a proprietary cloud backend, OpenHiker saves data in an atomic, self-contained format to a sync-enabled folder. The user's chosen cloud service (Dropbox, Google Drive, iCloud Drive) handles the actual sync transport.

- **Sync format:** A single `.openhiker` directory (or `.zip` bundle) containing:
  ```
  OpenHiker-Sync/
  ├── manifest.json           # Sync metadata: last modified timestamps, version
  ├── routes/
  │   ├── <uuid>.json         # Each saved route as individual JSON file
  │   └── ...
  ├── planned_routes/
  │   ├── <uuid>.json         # Each planned route as individual JSON file
  │   └── ...
  ├── waypoints/
  │   ├── <uuid>.json         # Waypoint metadata (coordinates, category, notes)
  │   ├── <uuid>.jpg          # Waypoint photo (full resolution)
  │   └── ...
  └── track_data/
      ├── <uuid>.bin          # Compressed GPS track data (zlib binary)
      └── ...
  ```

- **Sync strategy — per-file atomic updates:**
  - Each entity (route, waypoint, planned route) is a separate file
  - Files include a `modifiedAt` timestamp in their JSON
  - On export: only write files newer than last export timestamp
  - On import: only read files newer than local version (compare `modifiedAt`)
  - Deletions tracked via `manifest.json` tombstone list (deleted UUIDs + deletion timestamp)
  - This makes cloud drive sync efficient — Dropbox/GDrive/iCloud only transfer changed files

- **Android integration via Storage Access Framework (SAF):**
  - User picks a sync folder via `Intent.ACTION_OPEN_DOCUMENT_TREE`
  - App gets persistent URI permission to read/write in that folder
  - Works with any cloud drive that exposes a SAF `DocumentProvider`:
    - Google Drive ✓
    - Dropbox ✓ (via Dropbox Android app)
    - OneDrive ✓
    - iCloud Drive — not available on Android (iOS can use Files app integration instead)
  - Sync trigger: manual "Sync Now" button + optional WorkManager periodic sync

- `CloudDriveSync`:
  - `exportChanges(syncFolderUri: Uri)` — writes new/modified entities to sync folder
  - `importChanges(syncFolderUri: Uri)` — reads newer entities from sync folder
  - Conflict resolution: last-writer-wins (by `modifiedAt` timestamp)
  - Progress reporting via `StateFlow`

- UI:
  - Settings screen: "Choose Sync Folder" button → SAF folder picker
  - "Sync Now" button in main UI (e.g., toolbar action)
  - Sync status indicator (last sync time, pending changes count)
  - Optional: background sync every 15 minutes via WorkManager (with battery optimization awareness)

**Cross-platform iOS compatibility:**
The same `.openhiker` sync format can be adopted on iOS, replacing CloudKit. iOS users would choose a folder in the Files app (iCloud Drive, Dropbox, Google Drive are all accessible). This gives true cross-platform sync for free — an Android user and an iOS user sharing a Dropbox folder would automatically sync their routes and waypoints.

**Depends on:** Steps 1.2 (data models), 3.1 (saved routes), 3.4 (waypoints).
**Deliverable:** Cross-device sync via user-chosen cloud drive. End of Phase 4.

---

### Phase 5: Polish & Release Prep

#### Step 5.1 — Tablet & Foldable Layout

- `NavigationRail` for tablets (landscape) instead of bottom nav
- Adaptive layouts using `WindowSizeClass`
- Two-pane layouts for list/detail screens on large screens
- Test on common foldable form factors

#### Step 5.2 — Accessibility

- Content descriptions on all interactive elements
- TalkBack compatibility testing
- Sufficient color contrast (WCAG 2.1 AA)
- Font scaling support

#### Step 5.3 — Testing

- Unit tests for all pure logic (coordinate math, A\*, elevation interpolation, cost functions, track compression)
- Integration tests for Room databases (in-memory test DB)
- UI tests for critical flows (download region, plan route, start navigation)
- Snapshot tests for key screens

#### Step 5.4 — Performance & Battery

- Profile tile download battery impact
- Optimize foreground service GPS polling interval when user is stationary
- Memory profiling for large MBTiles files and elevation tile cache
- Startup time optimization (lazy initialization of heavy services)

#### Step 5.5 — Play Store Prep

- App icon & feature graphic
- Store listing (description, screenshots for phone + tablet)
- Privacy policy (location data, no telemetry)
- `ACCESS_BACKGROUND_LOCATION` declaration form (active hike tracking justification)
- Target SDK 34+ (Play Store requirement)
- App bundle signing

---

## Critical Path

The longest dependency chain determines the minimum implementation timeline:

```
1.1 Scaffolding
 ├─→ 1.2 Data Models ─→ 1.4 Tile Download ─→ 1.5 Region Selector ─→ 1.6 Offline Display ─→ 1.7 Region Mgmt
 ├─→ 1.3 Map Display ──────────────────────→ 1.5 ─→ 1.6
 │
 ├─→ 2.1 GPS Service ─→ 2.7 Navigation ─→ 3.1 Hike Recording ─→ 3.2 Hike History
 ├─→ 2.2 Elevation ──→ 2.4 Graph Builder ─→ 2.5 Routing Engine ─→ 2.6 Route Planning ─→ 2.7
 └─→ 2.3 OSM Download ─→ 2.4
```

**Critical path:** 1.1 → 1.2 → 1.4 → 1.5 → 1.6 → 2.5 → 2.6 → 2.7

Steps that can be developed in parallel:
- 1.3 (map display) ∥ 1.2 (data models) — no dependencies on each other
- 2.1 (GPS) ∥ 2.2 (elevation) ∥ 2.3 (OSM download) — independent services
- 3.3 (elevation chart) ∥ 3.4 (waypoints) — independent features
- 4.1 (community) can start anytime after 1.1 — only needs network layer

---

## Data Format Portability

All data formats are shared between iOS and Android:

| Format | Portable? | Notes |
|--------|-----------|-------|
| MBTiles (.mbtiles) | Yes | Same SQLite schema, same TMS Y-flip |
| Routing DB (.routing.db) | Yes | Same SQLite schema |
| GPX (.gpx) | Yes | Standard XML format |
| Planned routes (.json) | Yes | Same JSON structure |
| Region metadata (.json) | Yes | Same JSON structure |
| HGT elevation (.hgt.gz) | Yes | Same binary format |
| Track data (zlib binary) | Yes | Same compression, same encoding |
| Waypoint photos (BLOB) | Yes | Standard JPEG/PNG |
| Sync format (.openhiker) | Yes | Designed for cross-platform from the start |

An MBTiles file downloaded on iOS and transferred (via cloud drive) to Android will render identically — no conversion needed.
