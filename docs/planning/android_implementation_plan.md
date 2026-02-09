# Android OpenHiker — Stepwise Implementation Plan

## Decisions Made

- **Map SDK:** MapLibre Native Android (osmdroid archived Nov 2024; Mapbox not free)
- **Tile sources:** Same as iOS — OpenTopoMap, CyclOSM, OpenStreetMap Standard (raster PNG)
- **Cloud sync:** File-based export/import to user-chosen cloud drive (Dropbox, Google Drive, OneDrive) via Storage Access Framework. Atomic per-entity files for efficient delta sync. No proprietary backend.
- **P2P sharing:** Deferred to a future phase.
- **Watch features:** Excluded from initial port.

### iOS-Only Features (Not Ported)

These features are Apple-platform-exclusive and have no Android equivalent:

- **Apple Maps Directions Integration** — `DirectionsRequestHandler` registers as a pedestrian routing app via `MKDirectionsApplicationSupportedModes`. Apple Maps can launch OpenHiker with an `MKDirectionsRequest` URL. No Android equivalent exists (Google Maps does not support third-party offline routing providers in the same way). Consider: Android intent filter for `geo:` URIs as a lighter alternative in a future phase.
- **WatchConnectivity** — iOS↔watchOS file transfer and messaging. Wear OS equivalent deferred.
- **HealthKit / WatchHealthRelay** — Heart rate, calories from Apple Watch. Wear OS Health Services equivalent deferred.
- **SpriteKit MapRenderer** — watchOS-specific tile rendering engine.
- **macOS app** — Entire macOS target (`OpenHiker macOS/`).

---

## Architecture: Cross-Platform Reusable Library

A core design principle for the Android port is to **maximise code that could be shared** between platforms. Even though we are writing Kotlin (not using Kotlin Multiplatform yet), we structure the codebase so that all platform-agnostic logic lives in a `core` library module with **zero Android framework dependencies**. This mirrors the iOS `Shared/` directory and makes future KMP adoption straightforward.

### Module Structure

```
OpenHikerAndroid/
├── core/                                    # Pure Kotlin library (no Android deps)
│   ├── src/main/kotlin/com/openhiker/core/
│   │   ├── geo/                             # Geographic pure functions
│   │   │   ├── TileCoordinate.kt            # Web Mercator ↔ lat/lon, TMS Y-flip
│   │   │   ├── BoundingBox.kt               # Bounding box math
│   │   │   ├── TileRange.kt                 # Tile enumeration for a bbox + zoom
│   │   │   ├── Haversine.kt                 # Distance, bearing calculations
│   │   │   └── MercatorProjection.kt        # Pixel ↔ coordinate transforms
│   │   ├── routing/                          # A* engine (pure algorithm)
│   │   │   ├── AStarRouter.kt               # A* pathfinding (takes graph interface)
│   │   │   ├── RoutingGraph.kt              # Interface: node/edge queries
│   │   │   ├── RoutingCostConfig.kt         # All cost constants (see appendix)
│   │   │   ├── CostFunction.kt             # Edge cost calculation (pure function)
│   │   │   ├── TurnDetector.kt              # Turn instruction generation
│   │   │   └── ComputedRoute.kt             # Result data class
│   │   ├── elevation/                        # Elevation data (pure math)
│   │   │   ├── HgtParser.kt                 # Parse HGT binary → grid
│   │   │   ├── BilinearInterpolator.kt      # Sub-cell elevation lookup
│   │   │   └── ElevationProfile.kt          # Profile from coordinate list
│   │   ├── compression/                      # Track data compression
│   │   │   └── TrackCompression.kt          # Encode/decode + zlib (see appendix)
│   │   ├── formats/                          # File format read/write
│   │   │   ├── GpxSerializer.kt             # GPX 1.1 XML generation
│   │   │   ├── MbTilesSchema.kt             # MBTiles SQL constants + TMS flip
│   │   │   ├── RoutingDbSchema.kt           # Routing DB SQL constants
│   │   │   └── SyncManifest.kt              # Cloud sync manifest format
│   │   ├── navigation/                       # Route-following logic
│   │   │   ├── RouteFollower.kt             # Position → instruction matching
│   │   │   ├── OffRouteDetector.kt          # Off-route with hysteresis
│   │   │   └── RouteGuidanceConfig.kt       # Thresholds (see appendix)
│   │   ├── overpass/                         # Overpass API query building
│   │   │   ├── OverpassQueryBuilder.kt      # Query string construction
│   │   │   └── OsmXmlParser.kt              # XML response → nodes/ways
│   │   ├── community/                        # GitHub API data types
│   │   │   ├── RouteIndex.kt                # Index model
│   │   │   ├── SharedRoute.kt               # Shared route model
│   │   │   └── RouteSlugifier.kt            # URL-safe name generation
│   │   └── model/                            # Shared data classes
│   │       ├── Region.kt
│   │       ├── RegionMetadata.kt
│   │       ├── PlannedRoute.kt
│   │       ├── SavedRoute.kt
│   │       ├── TurnInstruction.kt
│   │       ├── TurnDirection.kt
│   │       ├── Waypoint.kt
│   │       ├── WaypointCategory.kt
│   │       ├── HikeStatistics.kt
│   │       ├── ElevationPoint.kt
│   │       ├── RoutingMode.kt
│   │       └── TileServer.kt               # Server URLs + subdomain config
│   └── build.gradle.kts                     # Pure Kotlin, no Android plugin
│
├── app/                                     # Android application module
│   ├── src/main/
│   │   ├── java/com/openhiker/android/
│   │   │   ├── OpenHikerApp.kt              # Hilt application class
│   │   │   ├── MainActivity.kt              # Single-activity entry point
│   │   │   ├── di/                           # Hilt dependency injection
│   │   │   │   ├── DatabaseModule.kt
│   │   │   │   ├── NetworkModule.kt
│   │   │   │   └── LocationModule.kt
│   │   │   ├── data/
│   │   │   │   ├── db/
│   │   │   │   │   ├── tiles/
│   │   │   │   │   │   ├── TileStore.kt           # MBTiles reader (Android SQLite)
│   │   │   │   │   │   └── WritableTileStore.kt   # MBTiles writer
│   │   │   │   │   ├── routing/
│   │   │   │   │   │   ├── RoutingDatabase.kt     # Room DB
│   │   │   │   │   │   ├── RoutingDao.kt          # Implements core RoutingGraph
│   │   │   │   │   │   └── RoutingEntities.kt
│   │   │   │   │   ├── routes/
│   │   │   │   │   │   ├── RouteDatabase.kt
│   │   │   │   │   │   ├── RouteDao.kt
│   │   │   │   │   │   └── RouteEntities.kt
│   │   │   │   │   └── waypoints/
│   │   │   │   │       ├── WaypointDatabase.kt
│   │   │   │   │       ├── WaypointDao.kt
│   │   │   │   │       └── WaypointEntities.kt
│   │   │   │   └── repository/
│   │   │   │       ├── RegionRepository.kt
│   │   │   │       ├── RouteRepository.kt
│   │   │   │       ├── WaypointRepository.kt
│   │   │   │       └── PlannedRouteRepository.kt
│   │   │   ├── service/
│   │   │   │   ├── tile/
│   │   │   │   │   └── TileDownloadService.kt
│   │   │   │   ├── location/
│   │   │   │   │   ├── LocationForegroundService.kt   # Android foreground service
│   │   │   │   │   └── LocationProvider.kt            # Fused/fallback wrapper
│   │   │   │   ├── elevation/
│   │   │   │   │   └── ElevationDataManager.kt        # Download + cache HGT tiles
│   │   │   │   ├── osm/
│   │   │   │   │   ├── OSMDataDownloader.kt           # HTTP download
│   │   │   │   │   └── PBFParser.kt                   # PBF binary parse
│   │   │   │   ├── navigation/
│   │   │   │   │   └── NavigationService.kt           # Wraps core RouteFollower + haptics
│   │   │   │   ├── export/
│   │   │   │   │   └── PDFExporter.kt                 # Android PdfDocument API
│   │   │   │   ├── community/
│   │   │   │   │   └── GitHubRouteService.kt          # Retrofit + GitHub API
│   │   │   │   └── sync/
│   │   │   │       └── CloudDriveSync.kt              # SAF-based sync
│   │   │   └── ui/
│   │   │       ├── navigation/
│   │   │       │   └── AppNavigation.kt
│   │   │       ├── theme/
│   │   │       │   ├── Theme.kt
│   │   │       │   ├── Color.kt
│   │   │       │   └── Type.kt
│   │   │       ├── settings/
│   │   │       │   ├── SettingsScreen.kt
│   │   │       │   └── SettingsViewModel.kt
│   │   │       ├── regions/
│   │   │       │   ├── RegionSelectorScreen.kt
│   │   │       │   ├── RegionSelectorViewModel.kt
│   │   │       │   ├── RegionListScreen.kt
│   │   │       │   └── RegionListViewModel.kt
│   │   │       ├── map/
│   │   │       │   ├── MapScreen.kt
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
│   │   │       └── components/
│   │   │           ├── ElevationProfileChart.kt
│   │   │           ├── HikeStatsBar.kt
│   │   │           ├── TileSourceSelector.kt
│   │   │           └── PermissionHandler.kt
│   │   ├── res/
│   │   └── AndroidManifest.xml
│   └── build.gradle.kts
├── gradle/
├── build.gradle.kts
├── settings.gradle.kts
└── gradle.properties
```

### Core vs App Boundary

The split follows one rule: **if it can be unit-tested without an Android emulator, it belongs in `core/`.**

| `core/` (pure Kotlin) | `app/` (Android) |
|---|---|
| TileCoordinate math, TMS Y-flip | TileStore (Android SQLite API) |
| A\* algorithm, cost functions | RoutingDao (Room, implements RoutingGraph interface) |
| HGT parsing, bilinear interpolation | ElevationDataManager (HTTP download, file I/O) |
| Track compression encode/decode | LocationForegroundService (GPS hardware) |
| GPX XML generation | PDFExporter (Android Canvas/PdfDocument) |
| RouteFollower, OffRouteDetector | NavigationService (haptics, notifications) |
| Overpass query construction | OSMDataDownloader (OkHttp HTTP calls) |
| Sync manifest format | CloudDriveSync (SAF DocumentProvider) |
| All data models | All UI screens (Compose) |
| Route guidance config/thresholds | All ViewModels |
| RouteSlugifier, cost config | Hilt modules, FileProvider, permissions |

This means the `core/` module can later become a **Kotlin Multiplatform** (KMP) module shared with the iOS app, replacing the current Swift `Shared/` code entirely — both platforms would use identical routing, elevation, and coordinate logic from a single source.

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
| Preferences | Jetpack DataStore | Replaces iOS `@AppStorage` for settings persistence |
| Build | Gradle with Kotlin DSL (.kts) | Modern Android standard |
| Min SDK | API 26 (Android 8.0, ~97% device coverage) | Java 8 desugaring not needed, good baseline |

---

## Implementation Phases

### Phase 1: Foundation & Offline Maps

The goal is a working app that can download, store, and display map tiles offline.

#### Step 1.1 — Project Scaffolding

**What:** Create the Android project with two Gradle modules (`core` + `app`).

- Initialize Android project with `com.openhiker.android` package
- Create `core` module as pure Kotlin library (no `com.android.library` plugin — just `kotlin("jvm")`)
- Configure Gradle with all dependencies:
  - `core`: Kotlinx.serialization only
  - `app`: MapLibre, Room, Hilt, OkHttp, Retrofit, Compose, Vico, Coil, DataStore
- Set up Hilt application class and DI modules (`DatabaseModule`, `NetworkModule`, `LocationModule`)
- Create `MainActivity` with single-activity Compose architecture
- Set up `AppNavigation` with `NavHost` and placeholder screens for all tabs
- Configure Material 3 theme (colors, typography)
- Bottom navigation with tabs: Navigate, Regions, Hikes, Routes, Community
- Add Settings screen accessible from top bar (gear icon)
- Configure ProGuard/R8 rules
- `AndroidManifest.xml` permissions:
  - `INTERNET`, `ACCESS_NETWORK_STATE` (tile download)
  - `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` (GPS)
  - `ACCESS_BACKGROUND_LOCATION` (hike tracking — requested separately per Android guidelines)
  - `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION` (background GPS)
  - `VIBRATE` (haptic feedback)
  - `POST_NOTIFICATIONS` (foreground service notification, Android 13+)

**Depends on:** Nothing.
**Deliverable:** App compiles, launches, shows tabbed navigation with empty screens. `core` module compiles as standalone JAR.

#### Step 1.2 — Data Models & Room Databases

**What:** Port all data models to `core/` and set up Room databases in `app/`.

**In `core/` (pure Kotlin, no Android deps):**

- `geo/TileCoordinate.kt` — Web Mercator ↔ lat/lon conversions:
  - `fun toLatLon(): Pair<Double, Double>` — tile to lat/lon (top-left corner)
  - `fun tmsY(): Int` — TMS Y-flip: `(1 shl z) - 1 - y`
  - `companion object fun fromLatLon(lat, lon, zoom): TileCoordinate`
- `geo/BoundingBox.kt` — Geographic bounds (north, south, east, west)
- `geo/TileRange.kt` — Enumerate all tiles in a bbox for a zoom range
- `geo/Haversine.kt` — Distance and bearing between coordinates
- `model/Region.kt`, `RegionMetadata.kt` — Region data classes
- `model/PlannedRoute.kt`, `TurnInstruction.kt`, `TurnDirection.kt`, `ComputedRoute.kt`
- `model/SavedRoute.kt`, `HikeStatistics.kt`
- `model/Waypoint.kt`, `WaypointCategory.kt` (9 categories: viewpoint, water, shelter, summit, campsite, danger, info, parking, custom)
- `model/ElevationPoint.kt`, `RoutingMode.kt` (hiking, cycling)
- `model/TileServer.kt` — Server definitions with URLs and subdomain patterns (see Appendix A)
- `community/RouteIndex.kt`, `SharedRoute.kt`
- `formats/MbTilesSchema.kt` — SQL constants for MBTiles tables
- `formats/RoutingDbSchema.kt` — SQL constants for routing tables
- `compression/TrackCompression.kt` — Encode/decode GPS tracks (see Appendix B)

**In `app/` (Android):**

- Room database for routes (`saved_routes` table with zlib-compressed track BLOBs)
- Room database for waypoints (`waypoints` table with photo BLOBs)
- Room database for routing (`routing_nodes`, `routing_edges`, `routing_metadata`)
- `TileStore` — Read-only MBTiles access using Android `SQLiteDatabase` API (not Room — MBTiles has a pre-existing schema). Uses `MbTilesSchema` constants from `core/`.
- `WritableTileStore` — Extends TileStore with insert for downloads
- Repository classes with coroutine-based data access

**Depends on:** Step 1.1.
**Deliverable:** All core models compile as pure Kotlin. Room databases create tables. TileStore reads/writes MBTiles. Unit tests for TileCoordinate math and TrackCompression pass.

#### Step 1.3 — Map Display with MapLibre

**What:** Display an interactive map using MapLibre with online tile sources.

- Integrate MapLibre Compose into `MapScreen`
- Create local style JSONs for each tile source (loaded from assets). Use `TileServer` config from `core/` for URLs. Example for OpenTopoMap:
  ```json
  {
    "version": 8,
    "sources": {
      "opentopomap": {
        "type": "raster",
        "tiles": [
          "https://a.tile.opentopomap.org/{z}/{x}/{y}.png",
          "https://b.tile.opentopomap.org/{z}/{x}/{y}.png",
          "https://c.tile.opentopomap.org/{z}/{x}/{y}.png"
        ],
        "tileSize": 256,
        "attribution": "© OpenStreetMap contributors, SRTM | © OpenTopoMap (CC-BY-SA)"
      }
    },
    "layers": [{"id": "opentopomap", "type": "raster", "source": "opentopomap"}]
  }
  ```
- CyclOSM style JSON (note the `/cyclosm/` path segment):
  ```json
  {
    "version": 8,
    "sources": {
      "cyclosm": {
        "type": "raster",
        "tiles": [
          "https://a.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
          "https://b.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
          "https://c.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png"
        ],
        "tileSize": 256,
        "attribution": "© OpenStreetMap contributors | CyclOSM"
      }
    },
    "layers": [{"id": "cyclosm", "type": "raster", "source": "cyclosm"}]
  }
  ```
- OSM Standard style JSON (single subdomain — no rotation):
  ```json
  {
    "version": 8,
    "sources": {
      "osm": {
        "type": "raster",
        "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
        "tileSize": 256,
        "attribution": "© OpenStreetMap contributors"
      }
    },
    "layers": [{"id": "osm", "type": "raster", "source": "osm"}]
  }
  ```
- Tile source switching via style JSON swap
- `LocationComponent` for GPS position display (COMPASS render mode for heading arrow)
- Camera position persistence via Jetpack DataStore (equivalent to iOS `@AppStorage("lastLatitude")`, `@AppStorage("lastLongitude")`, `@AppStorage("lastSpan")`)

**Depends on:** Step 1.1.
**Deliverable:** Working interactive map with online tiles, GPS overlay, and persisted camera position.

#### Step 1.4 — Tile Downloading

**What:** Port the tile download engine for offline map storage.

- `TileDownloadService` using Kotlin coroutines:
  - OkHttp client with `Dispatcher(maxRequests=6, maxRequestsPerHost=6)`
  - Rate limiting via `delay(50)` between requests (OSM tile usage policy compliance)
  - Subdomain distribution: deterministic hash `abs(tile.x + tile.y) % subdomains.size` (same as iOS — ensures same tile always maps to same subdomain for HTTP cache coherence)
  - Batch processing (150 tiles per batch)
  - Exponential backoff retry (4 attempts: 2s, 4s, 8s, 16s delays)
  - `User-Agent` header: `"OpenHiker-Android/1.0 (hiking app; https://github.com/hherb/OpenHiker)"`
  - Progress reporting via `StateFlow<DownloadProgress>` (tile count, percentage, current zoom level)
  - Cancellation support via coroutine `Job`
- Uses `core/geo/TileRange` to calculate tile coordinates from `BoundingBox` + zoom range
- Writes via `WritableTileStore` with transaction batching (commit every 100 tiles)

**Depends on:** Step 1.2 (TileStore/WritableTileStore).
**Deliverable:** Can download a region's tiles to an MBTiles file with progress reporting.

#### Step 1.5 — Region Selection UI

**What:** Build the region selection and download interface.

- `RegionSelectorScreen`:
  - Full-screen MapLibre map with tile source selector dropdown
  - Location search bar using Android `Geocoder` API (GMS fallback: Nominatim free endpoint)
  - Drag-to-select rectangle overlay for defining region bounds:
    - Touch-and-drag gesture creates a selection rectangle
    - Rectangle drawn with blue stroke (3dp) and semi-transparent blue fill (10% opacity)
    - Semi-transparent dark overlay (30% opacity) covers map outside selection during drag
    - On release: convert screen rectangle to geographic `BoundingBox` via MapLibre camera projection
    - Small selections (< 50dp width or height) snap to 60% of visible region centered on map center
  - Zoom level range selector (12–16, adjustable)
  - Tile count estimate display (calculated from `TileRange` in real-time)
  - Tile server selection (OpenTopoMap, CyclOSM, OSM Standard)
  - Download button with confirmation dialog showing estimated size
  - Download progress: progress bar + tile count + percentage + current zoom level
  - Cancel download button
- `RegionSelectorViewModel`: manages bounds, zoom range, server selection; triggers download
- Region metadata storage: JSON in `filesDir/regions_metadata.json`
- MBTiles storage: `filesDir/regions/<uuid>.mbtiles`
- Routing DB storage: `filesDir/regions/<uuid>.routing.db`

**Depends on:** Steps 1.3 (map display), 1.4 (tile download).
**Deliverable:** User can select a map region, download tiles, and see download progress.

#### Step 1.6 — Offline Map Display

**What:** Display downloaded regions offline using MBTiles.

- Generate local style JSON referencing MBTiles file via `mbtiles://` URI:
  ```json
  {
    "version": 8,
    "sources": {
      "offline": {
        "type": "raster",
        "url": "mbtiles://<absolute-path-to-mbtiles-file>",
        "tileSize": 256
      }
    },
    "layers": [{"id": "offline", "type": "raster", "source": "offline"}]
  }
  ```
  Note: MapLibre requires the MBTiles file to be on the filesystem (not in app assets). The `filesDir/regions/` path satisfies this.
- Switch between online browsing mode and offline region viewing mode
- Region boundary overlays on the map (GeoJSON polygon source + FillLayer with blue stroke, semi-transparent fill)
- Handle missing tiles gracefully (blank area outside downloaded bounds)
- Test in airplane mode: map renders from local MBTiles, zero network requests

**Depends on:** Steps 1.3, 1.5.
**Deliverable:** Downloaded regions display fully offline.

#### Step 1.7 — Region Management

**What:** List, rename, and delete downloaded regions.

- `RegionListScreen`:
  - List of downloaded regions with name, tile count, file size, zoom range, area (km²)
  - Swipe-to-delete with confirmation dialog
  - Tap to rename (dialog with text field)
  - Tap to view on map (navigate to MapScreen centered on region bbox)
  - Storage usage summary at top (total size of all regions)
- `RegionListViewModel`: loads from JSON metadata, manages rename/delete, recalculates stats
- Delete operation removes both `.mbtiles` and `.routing.db` files

**Depends on:** Steps 1.5, 1.6.
**Deliverable:** Full region CRUD. **End of Phase 1** — functional offline map viewer.

---

### Phase 2: Navigation & Routing

The goal is GPS tracking, offline A\* routing, and turn-by-turn navigation.

#### Step 2.1 — GPS Location Service

**What:** Continuous GPS tracking with a foreground service for background operation.

- `LocationForegroundService` (Android Foreground Service):
  - Persistent notification: "OpenHiker is tracking your hike" with distance/time stats
  - Notification actions: Pause/Resume, Stop
  - `FusedLocationProviderClient` with `LocationRequest`:
    - High accuracy: `PRIORITY_HIGH_ACCURACY`, interval 2s, minDisplacement 5m
    - Balanced: `PRIORITY_BALANCED_POWER_ACCURACY`, interval 5s, minDisplacement 10m
    - Low power: `PRIORITY_LOW_POWER`, interval 10s, minDisplacement 50m
  - Fallback to `android.location.LocationManager` if Google Play Services unavailable
  - Compass heading via `SensorManager` + `TYPE_ROTATION_VECTOR` sensor
  - `activityType`-equivalent: set `LocationRequest.setMaxWaitTime()` for batching in low-power mode
- `LocationProvider` (app-level wrapper):
  - Exposes `StateFlow<Location?>`, `StateFlow<Float?>` (heading degrees)
  - Incremental distance calculation via `core/geo/Haversine`
  - Elevation gain/loss accumulation with noise filter (ignore changes < 3m)
  - Track point recording to in-memory list
  - Distance filter: ignore updates < 5m apart (prevent GPS jitter)
- Runtime permission handling (three-stage request per Android guidelines):
  1. `ACCESS_FINE_LOCATION` — request on first GPS use
  2. `ACCESS_BACKGROUND_LOCATION` — request separately when starting a hike recording (with rationale dialog)
  3. `POST_NOTIFICATIONS` — request on Android 13+ for foreground service notification

**Depends on:** Step 1.1.
**Deliverable:** GPS tracking in foreground and background. Location dot on map follows user.

#### Step 2.2 — Elevation Data Manager

**What:** Port SRTM/ASTER elevation data system.

- **In `core/elevation/`** (pure Kotlin):
  - `HgtParser.kt`: Parse HGT binary format
    - Grid: 3601 × 3601 samples per 1° × 1° cell
    - Sample: 16-bit signed big-endian integer (meters above sea level)
    - Void value: -32768 (no data)
    - File size: exactly 25,934,402 bytes uncompressed (3601 × 3601 × 2)
  - `BilinearInterpolator.kt`: Sub-cell elevation lookup
    - Input: latitude, longitude, HGT grid
    - Compute fractional row/col within grid
    - Interpolate between 4 surrounding samples
    - Handle void values (skip, return nearest non-void)
  - `ElevationProfile.kt`: Generate profile from coordinate list using interpolator

- **In `app/service/elevation/`** (Android):
  - `ElevationDataManager.kt`:
    - Downloads HGT tiles from Tilezen/Mapzen Skadi:
      - URL: `https://elevation-tiles-prod.s3.amazonaws.com/skadi/{N|S}{lat}/{N|S}{lat}{E|W}{lon}.hgt.gz`
      - Example: `https://elevation-tiles-prod.s3.amazonaws.com/skadi/N47/N47E011.hgt.gz`
    - Fallback: OpenTopography SRTM GL1 (60°N–56°S coverage)
    - Gzip decompression via `java.util.zip.GZIPInputStream`
    - In-memory LRU cache of parsed grids (`android.util.LruCache`, max 4 tiles ~100MB)
    - Exponential backoff retry (4 attempts: 2s, 4s, 8s, 16s)
    - Storage: `filesDir/elevation/{N|S}{lat}{E|W}{lon}.hgt.gz`

**Depends on:** Step 1.1 (network layer).
**Deliverable:** Elevation queries for any lat/lon. Core interpolation unit-tested.

#### Step 2.3 — OSM Data Download & PBF Parsing

**What:** Port the Overpass API download and OSM data parsing pipeline.

- **In `core/overpass/`** (pure Kotlin):
  - `OverpassQueryBuilder.kt` — Constructs Overpass QL queries:
    ```
    [out:xml][timeout:300];
    way["highway"~"^(path|footway|track|cycleway|bridleway|steps|pedestrian|
    residential|unclassified|tertiary|secondary|primary|trunk|living_street|
    service)$"]({south},{west},{north},{east});
    (._;>;);
    out body;
    ```
    - Timeout: 300 seconds (sent in query, not just HTTP timeout)
    - Bounding box: `(south,west,north,east)` format
    - Recurse-down `(._;>;)` fetches referenced nodes even if outside bbox
    - Returns URL-encoded POST body: `data=<encoded_query>`
  - `OsmXmlParser.kt` — Streaming XML parser for Overpass response → nodes + ways

- **In `app/service/osm/`** (Android):
  - `OSMDataDownloader.kt`:
    - Primary endpoint: `https://overpass-api.de/api/interpreter`
    - Fallback endpoint: `https://overpass.kumi.systems/api/interpreter`
    - POST with `Content-Type: application/x-www-form-urlencoded`
    - Region size limit: 100 × 100 km (10,000 km²) — reject larger regions with user error
    - OkHttp `callTimeout(330.seconds)` (300s query + 30s buffer)
    - Retry strategy:
      - Try primary, then fallback, up to 4 total attempts
      - Delay: `2^(attempt+1)` seconds between retries
      - HTTP 429 (rate limited): longer delay `2^(attempt+2)` seconds
      - HTTP 504 (gateway timeout): skip to fallback endpoint immediately (do not retry same)
      - Only retry on 5xx and transient network errors, not on 4xx client errors
    - Cache downloaded XML in `filesDir/osm/`
  - `PBFParser.kt`:
    - Option A: Use `crosby.binary` (osm-pbf) Java library from Maven Central
    - Option B: Port the Swift PBF parser if library doesn't handle our filtering needs
    - Filter to routable highway values (see `RoutingCostConfig` in Appendix C)
    - Extract: node IDs + lat/lon, way IDs + node reference lists + tags

**Depends on:** Step 1.1 (network layer).
**Deliverable:** Can download and parse OSM trail data for a region. Query builder unit-tested.

#### Step 2.4 — Routing Graph Builder

**What:** Port the graph construction pipeline.

- **In `core/routing/`** (pure algorithm):
  - `RoutingCostConfig.kt` — All cost constants (see Appendix C for full table)
  - `CostFunction.kt`:
    - `fun edgeCost(distance, elevGain, elevLoss, surface, highway, sacScale, mode): Double`
    - Naismith's rule for climb: `distance + (elevGain * climbPenalty)`
    - Tobler's function for descent penalty by grade
    - Surface type multiplier lookup
    - SAC scale multiplier lookup
    - Highway type adjustments (e.g., `steps` × 1.5 for hiking)
    - Returns `Double.MAX_VALUE` for impassable edges

- **In `app/` (Android)**:
  - `RoutingGraphBuilder` (coroutine-based):
    1. Take parsed OSM nodes + ways as input
    2. Identify junction nodes (nodes referenced by ≥2 ways)
    3. Split ways at junctions into edges
    4. Query elevation for all nodes via `ElevationDataManager`
    5. Compute forward and reverse edge costs via `core/CostFunction`
    6. Write to Room database: `routing_nodes`, `routing_edges`, `routing_metadata`
    7. Progress reporting via `StateFlow` (node count, edge count, percentage)

**Depends on:** Steps 2.2 (elevation), 2.3 (OSM data).
**Deliverable:** Routing graph database built from OSM + elevation data. Cost function unit-tested.

#### Step 2.5 — A\* Routing Engine

**What:** Port A\* pathfinding to `core/` as a pure algorithm.

- **In `core/routing/`:**
  - `RoutingGraph.kt` — Interface (implemented by Room DAO in `app/`):
    ```kotlin
    interface RoutingGraph {
        fun getNode(id: Long): RoutingNode?
        fun getEdgesFrom(nodeId: Long): List<RoutingEdge>
        fun findNearestNode(lat: Double, lon: Double): RoutingNode?
    }
    ```
  - `AStarRouter.kt`:
    - Takes `RoutingGraph` interface (no Room/Android dependency)
    - `java.util.PriorityQueue` for open set
    - Haversine heuristic (admissible, consistent — never overestimates)
    - Via-point support: sequential A\* between waypoints, concatenate results
    - Returns `ComputedRoute`:
      - Ordered coordinate list (polyline)
      - Turn-by-turn `TurnInstruction` list
      - Total distance, elevation gain/loss, estimated walking/cycling time
      - Elevation profile (`List<ElevationPoint>`)
  - `TurnDetector.kt`:
    - Generates `TurnInstruction` list from edge sequence
    - Detects turn direction by bearing change between consecutive edges
    - Includes street/trail name from OSM `name` tag

- **In `app/`:**
  - `RoutingDao` implements `RoutingGraph` interface
  - `RoutingEngine` wrapper: opens database, calls `AStarRouter`, returns result

**Depends on:** Step 2.4 (routing graph).
**Deliverable:** Offline hiking/cycling route computation. A\* algorithm unit-tested with mock graph.

#### Step 2.6 — Route Planning UI

**What:** Build route planning interface.

- `RoutePlanningScreen`:
  - Region picker (select which downloaded region to plan in)
  - Full-screen MapLibre map showing selected region's offline tiles
  - Tap to set start point (green marker)
  - Tap to set end point (red marker)
  - Long-press to add via-points (blue markers, draggable, removable)
  - "Compute Route" button → calls `RoutingEngine` on IO dispatcher
  - Loading indicator during computation
  - Route preview as polyline overlay (GeoJSON LineLayer, orange, 4dp width)
  - Stats display: distance, elevation gain/loss, estimated time
  - "Save Route" → name entry dialog → persist to `PlannedRouteRepository` as JSON
- `RoutePlanningViewModel`: manages start/end/via-point state, routing computation, save

**Depends on:** Steps 1.6 (offline map), 2.5 (routing engine).
**Deliverable:** Users can plan routes on offline maps with turn-by-turn instructions.

#### Step 2.7 — Turn-by-Turn Navigation

**What:** Live navigation guidance with haptic feedback.

- **In `core/navigation/`** (pure logic):
  - `RouteGuidanceConfig.kt` — Configurable thresholds (see Appendix D)
  - `RouteFollower.kt`:
    - Input: current lat/lon, route coordinate list, instruction list
    - Output: `NavigationState` data class:
      - `currentInstruction: TurnInstruction?`
      - `distanceToNextTurn: Double` (meters)
      - `progress: Float` (0.0–1.0)
      - `remainingDistance: Double` (meters)
      - `isApproachingTurn: Boolean` (within 100m)
      - `isAtTurn: Boolean` (within 30m)
      - `hasArrived: Boolean` (within 30m of destination)
    - Pure function: `fun update(lat, lon, cumulativeDistance): NavigationState`
    - Uses cumulative distance (not raw GPS) for accurate turn detection
  - `OffRouteDetector.kt`:
    - Hysteresis: off-route at 50m, clears at 30m (prevents flapping)
    - Pure function: `fun check(lat, lon, routeSegments): OffRouteState`

- **In `app/`** (Android):
  - `NavigationService`:
    - Subscribes to `LocationProvider` updates
    - Feeds locations into `core/RouteFollower` and `core/OffRouteDetector`
    - Haptic feedback via `android.os.Vibrator`/`VibratorManager`:
      - Approaching turn (100m): `VibrationEffect.createOneShot(100, 128)` — short, medium
      - At turn (30m): `VibrationEffect.createOneShot(200, 255)` — medium, strong
      - Off-route: `VibrationEffect.createWaveform([0, 300, 100, 100, 100, 300], -1)` — long-short-long
      - Arrived: `VibrationEffect.createWaveform([0, 100, 50, 100, 50, 100], -1)` — triple pulse
    - Exposes `StateFlow<NavigationState>` for UI
  - `NavigationScreen`:
    - Map with live GPS tracking (camera follows user heading)
    - Current instruction card: turn arrow icon + street name + distance
    - Distance to next turn (large text)
    - Progress bar
    - Real-time stats overlay (distance hiked, time, elevation)
    - Off-route warning banner (red, with "recalculate" option — future)
    - "Stop Navigation" button with confirmation

**Depends on:** Steps 2.1 (GPS), 2.5 (routing), 2.6 (route planning).
**Deliverable:** Full turn-by-turn hiking navigation with haptics. **End of Phase 2.** Core navigation logic unit-tested.

---

### Phase 3: History, Waypoints & Export

The goal is hike recording/review, waypoint management, and data export.

#### Step 3.1 — Hike Recording

**What:** Record GPS tracks during hikes with statistics.

> **Note:** The following GPS hike-recording features were deferred from Phase 2
> to Phase 3 to keep Phase 2 focused on routing and turn-by-turn navigation.
> Phase 2 delivered the basic `LocationProvider` (GPS + compass) and a minimal
> `HikeTrackingService` foreground service that keeps GPS alive. Phase 3 extends
> these to support full hike recording.

**Deferred from Phase 2 (GPS features to add):**
- Track point recording to in-memory list in `LocationProvider`
- Elevation gain/loss accumulation with noise filter (ignore changes < 3m)
- `FusedLocationProviderClient` integration with priority modes:
  - High accuracy: `PRIORITY_HIGH_ACCURACY`, interval 2s, minDisplacement 5m
  - Balanced: `PRIORITY_BALANCED_POWER_ACCURACY`, interval 5s, minDisplacement 10m
  - Low power: `PRIORITY_LOW_POWER`, interval 10s, minDisplacement 50m
- Pause/resume hike recording in `HikeTrackingService`
- Notification actions: Pause/Resume, Stop (with distance/time stats in notification)
- Runtime permission handling for `ACCESS_BACKGROUND_LOCATION` (separate request with rationale dialog)

**Hike recording features:**
- Extend `HikeTrackingService` to record track points during active hike
- `HikeStatistics` accumulation (uses `core/geo/Haversine`):
  - Total distance (Haversine sum of consecutive points)
  - Elevation gain/loss (with noise filter: ignore changes < 3m)
  - Walking time vs resting time (speed threshold: 0.3 m/s)
  - Average/max speed
  - Start/end timestamps
- Track compression via `core/compression/TrackCompression` (see Appendix B):
  - Binary encoding → zlib compression → store as BLOB in Room
  - Uses `java.util.zip.Deflater`/`Inflater`
  - Cross-platform compatible: same format as iOS (byte-for-byte identical output)
- Save to `RouteRepository` on hike completion
- Auto-save draft every 5 minutes to `filesDir/hike_draft.bin` (crash recovery)

**Depends on:** Step 2.1 (GPS service — basic LocationProvider and HikeTrackingService from Phase 2).
**Deliverable:** Hikes recorded with statistics and compressed tracks.

#### Step 3.2 — Hike History UI

**What:** Hike list and detail screens.

- `HikeListScreen`:
  - Scrollable list of saved hikes
  - Each card: name, date, distance, elevation gain, duration, small map thumbnail (optional)
  - Sort by: date (default), distance, elevation, duration
  - Swipe-to-delete with confirmation
  - Search by name
- `HikeDetailScreen`:
  - Map with recorded track polyline (GeoJSON LineLayer, orange)
  - Full statistics table (distance, elevation gain/loss, walking/resting time, avg/max speed)
  - Elevation profile chart (Vico line chart)
  - Waypoints pinned on map (from associated waypoints)
  - Rename / delete options
  - Export button → ExportSheet

**Depends on:** Steps 3.1, 1.6 (offline map for track display).
**Deliverable:** Past hikes viewable with track visualization and statistics.

#### Step 3.3 — Elevation Profile Chart

**What:** Reusable interactive elevation profile.

- `ElevationProfileChart` (Compose component, uses Vico):
  - X-axis: distance (km), Y-axis: elevation (m)
  - Touch/drag: crosshair marker shows elevation + distance at point
  - During navigation: animated current-position indicator
  - Gradient fill under line (green→brown by elevation)
  - Min/max elevation labels
  - Data source: `List<ElevationPoint>` from `core/`
- Used in: `HikeDetailScreen`, `RouteDetailScreen`, `NavigationScreen`

**Depends on:** Step 1.1 (Vico dependency).
**Deliverable:** Reusable elevation chart component.

#### Step 3.4 — Waypoint Management

**What:** Create, view, edit, and delete waypoints with photos.

- `AddWaypointScreen`:
  - Photo source selection: gallery (`ActivityResultContracts.PickVisualMedia`) or camera (`ActivityResultContracts.TakePicture`)
  - Category picker: chip group with 9 categories (viewpoint, water, shelter, summit, campsite, danger, info, parking, custom)
  - Name text field
  - Notes text field (multiline)
  - Auto-fill current GPS coordinates (editable)
  - Preview: photo thumbnail + coordinates on mini-map
  - Save: generates 100×100 thumbnail via `Bitmap.createScaledBitmap()`, stores full photo + thumbnail as BLOBs in Room
- `WaypointListScreen`:
  - All waypoints across all hikes
  - Filter by category (chip row, multi-select)
  - Each row: thumbnail, name, category icon, distance from current location
  - Tap → WaypointDetailScreen
- `WaypointDetailScreen`:
  - Full-resolution photo (zoomable via Coil)
  - Name, category, coordinates (with copy button), notes
  - Associated hike link (tap to navigate to HikeDetailScreen)
  - Mini-map with waypoint pin
  - Edit / delete options

**Depends on:** Step 1.2 (Room database).
**Deliverable:** Full waypoint CRUD with photo support.

#### Step 3.5 — Route Detail & Management

**What:** View and manage planned routes.

- `RouteDetailScreen`:
  - Map with route polyline (GeoJSON LineLayer)
  - Turn-by-turn instruction list (scrollable, each row: icon + text + distance)
  - Elevation profile chart
  - Statistics: distance, elevation gain/loss, estimated time, surface breakdown
  - "Start Navigation" → launches NavigationScreen with this route
  - Rename / delete
  - Export button → ExportSheet
  - Via-points and waypoints along route shown on map

**Depends on:** Steps 2.6 (route planning), 3.3 (elevation chart).
**Deliverable:** Full route detail view.

#### Step 3.6 — PDF & GPX Export

**What:** Export hikes and routes to PDF and GPX.

- **In `core/formats/`** (pure Kotlin):
  - `GpxSerializer.kt`:
    - Standard GPX 1.1 XML output
    - Track points with lat, lon, elevation, timestamp
    - Metadata: name, description, creator="OpenHiker"
    - Pure function: `fun serialize(route: SavedRoute): String`
    - Also supports `PlannedRoute` export

- **In `app/`** (Android):
  - `GPXExporter.kt`:
    - Calls `core/GpxSerializer`, writes to file
    - Share via `Intent.ACTION_SEND` with `FileProvider` URI
    - Save to Downloads via `MediaStore.Downloads`
  - `PDFExporter.kt`:
    - `android.graphics.pdf.PdfDocument` for multi-page composition
    - Page 1: Map snapshot (MapLibre snapshot API) + title + date + stats table
    - Page 2: Elevation profile (render Vico chart to `Bitmap` via `AndroidView`, draw on PDF `Canvas`)
    - Page 3: Photos grid (2-up layout, if waypoint photos exist)
    - Page 4: Waypoint table
    - US Letter size (612 × 792 points)
    - Share via `FileProvider` + `Intent.ACTION_SEND`
  - `ExportSheet`: bottom sheet with format selection (PDF / GPX), triggers appropriate exporter

**Depends on:** Steps 3.2 (hike data), 3.3 (chart), 3.5 (route data).
**Deliverable:** Hikes and routes exportable as PDF reports and GPX files. **End of Phase 3.**

---

### Phase 4: Community & Cloud Sync

The goal is community route sharing and cross-device sync.

#### Step 4.1 — Community Route Browsing

**What:** Browse and download community routes from GitHub.

- **In `core/community/`** (pure Kotlin):
  - `RouteSlugifier.kt`: URL-safe name generation (lowercase, replace spaces with hyphens, strip special chars)
  - Data models: `RouteIndex`, `SharedRoute`, `SharedWaypoint`, `RoutePhoto`

- **In `app/`** (Android):
  - `GitHubRouteService` (Retrofit):
    - Repository: `hherb/OpenHikerRoutes`
    - Default branch: `main`
    - API base: `https://api.github.com`
    - Raw content: `https://raw.githubusercontent.com/hherb/OpenHikerRoutes/main`
    - Fetch `index.json` → parse to `RouteIndex`
    - Fetch `routes/{country}/{slug}/route.json` → parse to `SharedRoute`
    - Index cache: 300-second TTL, force-refresh available
    - Token obfuscation: XOR with 0xA5 key (same as iOS — speed bump only, real security is PR-based approval gate)
    - Obfuscation alternatives for Android: ProGuard string encryption, or NDK native function
  - `CommunityBrowseScreen`:
    - Scrollable list of community routes
    - Search/filter by name, distance, difficulty
    - Each card: name, author, distance, elevation, difficulty badge
    - Pull-to-refresh (force index reload)
  - `CommunityRouteDetailScreen`:
    - Author info, description
    - Map preview with route polyline
    - Statistics, photos
    - "Download" button → saves to `PlannedRouteRepository`

**Depends on:** Step 1.1 (network layer).
**Deliverable:** Users can browse and download community routes.

#### Step 4.2 — Route Upload to Community

**What:** Upload routes to community repository via GitHub PR.

- `GitHubRouteService` upload flow (same Git API sequence as iOS):
  1. `GET /repos/{owner}/{repo}/git/ref/heads/main` → get default branch SHA
  2. `GET /repos/{owner}/{repo}/git/commits/{sha}` → get tree SHA (note: tree SHA ≠ commit SHA)
  3. `POST /repos/{owner}/{repo}/git/refs` → create branch `route/{slug}-{uuid8}`
  4. For each file: `POST /repos/{owner}/{repo}/git/blobs` → create blob (base64-encoded)
  5. `POST /repos/{owner}/{repo}/git/trees` → create tree with `base_tree`
  6. `POST /repos/{owner}/{repo}/git/commits` → create commit
  7. `PATCH /repos/{owner}/{repo}/git/refs/heads/{branch}` → update ref (`force: true`)
  8. `POST /repos/{owner}/{repo}/pulls` → create PR (title, body, head=branch, base=main)
  - Retry: 4 attempts with exponential backoff (2s, 4s, 8s, 16s), only on 5xx, not on 4xx
  - File structure created:
    ```
    routes/{country}/{slug}/
      route.json
      route.gpx
      README.md
      photos/{filename}.jpg
    ```
- `RouteUploadScreen`:
  - Select saved route to share
  - Edit metadata: description, difficulty rating, tips
  - Select photos to attach
  - Preview before submit
  - Submit progress indicator → success/error feedback

**Depends on:** Steps 4.1, 3.5 (route detail).
**Deliverable:** Users can upload routes to community repository.

#### Step 4.3 — Cloud Drive Sync (Export/Import)

**What:** File-based sync via user-chosen cloud drive.

**Architecture:**
OpenHiker saves data in an atomic, self-contained format to a sync-enabled folder. The user's chosen cloud service handles the actual transport. No proprietary backend.

- **Sync directory format:**
  ```
  OpenHiker/
  ├── manifest.json           # Version, last sync timestamps, tombstone list
  ├── routes/
  │   ├── {uuid}.json         # Saved route metadata + statistics
  │   └── ...
  ├── planned_routes/
  │   ├── {uuid}.json         # Planned route with instructions
  │   └── ...
  ├── waypoints/
  │   ├── {uuid}.json         # Waypoint metadata (coordinates, category, notes)
  │   ├── {uuid}.jpg          # Full-resolution photo
  │   └── ...
  └── track_data/
      ├── {uuid}.bin          # Compressed GPS track (zlib binary, same as DB BLOB)
      └── ...
  ```

- **In `core/formats/`** (pure Kotlin):
  - `SyncManifest.kt`:
    - `data class SyncManifest`: version, `lastSyncTimestamp`, `tombstones: List<Tombstone>`
    - `data class Tombstone`: uuid, deletedAt timestamp
    - Serialization via Kotlinx.serialization
  - JSON format for all entities includes `modifiedAt: Long` (epoch millis)

- **Sync strategy — per-file atomic updates:**
  - Each entity is a separate file → cloud drive only syncs changed files
  - Export: only write files with `modifiedAt > lastExportTimestamp`
  - Import: only read files with `modifiedAt > localVersion.modifiedAt`
  - Deletions: tombstone list in `manifest.json` (UUID + deletion timestamp)
  - Tombstones expire after 30 days (prevent unbounded growth)
  - Conflict resolution: last-writer-wins by `modifiedAt` timestamp

- **Android integration via Storage Access Framework (SAF):**
  - User picks sync folder via `Intent.ACTION_OPEN_DOCUMENT_TREE`
  - App persists URI permission via `contentResolver.takePersistableUriPermission()`
  - Works with any `DocumentProvider`:
    - Google Drive (via Google Drive app)
    - Dropbox (via Dropbox app)
    - OneDrive (via OneDrive app)
    - Local storage / SD card
    - Note: iCloud Drive is not available on Android; iOS users sync via iOS Files app
  - `CloudDriveSync`:
    - `suspend fun exportChanges(syncFolderUri: Uri)` — write new/modified entities
    - `suspend fun importChanges(syncFolderUri: Uri)` — read newer entities
    - Progress: `StateFlow<SyncProgress>` (exporting/importing, entity count, errors)

- **UI:**
  - `SettingsScreen`: "Cloud Sync" section
    - "Choose Sync Folder" → SAF folder picker
    - Display current sync folder name
    - "Sync Now" button
    - Last sync timestamp display
    - Pending changes count
    - Toggle: auto-sync every 15 minutes (via WorkManager)
  - Sync button also accessible from main toolbar

- **Cross-platform iOS compatibility:**
  The sync format is platform-agnostic. An iOS implementation (replacing CloudKit) can read/write the same directory structure via the iOS Files app, which supports iCloud Drive, Dropbox, and Google Drive. This enables true cross-platform sync: an Android user and an iOS user sharing a Dropbox folder would automatically sync routes and waypoints.

**Depends on:** Steps 1.2 (data models), 3.1 (saved routes), 3.4 (waypoints).
**Deliverable:** Cross-device sync via user-chosen cloud drive. **End of Phase 4.**

---

### Phase 5: Settings, Polish & Release

#### Step 5.1 — Settings Screen

**What:** User preferences and app configuration.

- `SettingsScreen` sections:
  - **Map:** Default tile source (OpenTopoMap / CyclOSM / OSM Standard)
  - **GPS:** Accuracy mode (High / Balanced / Low Power)
  - **Navigation:** Unit system (metric / imperial), haptic feedback on/off
  - **Downloads:** Default zoom range, concurrent download limit
  - **Cloud Sync:** Sync folder, auto-sync toggle, sync interval
  - **Storage:** Total storage used, clear elevation cache, clear OSM cache
  - **About:** Version, licenses, OpenTopoMap/OSM attribution links, GitHub link
- Persistence via Jetpack DataStore (key-value, equivalent to iOS `@AppStorage`)

**Depends on:** Step 1.1.

#### Step 5.2 — Tablet & Foldable Layout

- `NavigationRail` for large screens (instead of bottom nav)
- Adaptive layouts using `WindowSizeClass` (Compose Material 3)
- Two-pane list/detail for: regions, hikes, routes, waypoints, community
- Test on: Pixel Tablet, Samsung Galaxy Fold, standard landscape

#### Step 5.3 — Accessibility

- `contentDescription` on all interactive elements
- TalkBack compatibility testing for all screens
- Sufficient color contrast (WCAG 2.1 AA minimum)
- Font scaling support (up to 200%)
- Haptic alternatives: optional audio cues for navigation turns

#### Step 5.4 — Testing

- **Unit tests** (in `core/` — fast, no emulator):
  - `TileCoordinate`: lat/lon ↔ tile conversions, TMS Y-flip
  - `Haversine`: distance, bearing
  - `TileRange`: tile enumeration from bbox + zoom
  - `AStarRouter`: pathfinding with mock `RoutingGraph`
  - `CostFunction`: edge costs for various surface/SAC/elevation combos
  - `TurnDetector`: turn instruction generation
  - `BilinearInterpolator`: elevation interpolation
  - `TrackCompression`: encode/decode roundtrip, cross-platform compatibility
  - `GpxSerializer`: valid GPX output
  - `OverpassQueryBuilder`: correct query strings
  - `RouteFollower`: position → instruction matching
  - `OffRouteDetector`: hysteresis behavior
  - `SyncManifest`: serialization/deserialization, tombstone expiry
- **Integration tests** (in `app/` — emulator/device):
  - Room databases: CRUD, migration
  - TileStore: MBTiles read/write
  - MapLibre: offline rendering from MBTiles
- **UI tests** (Compose testing):
  - RegionSelector: drag-to-select → correct bbox
  - RoutePlanning: set start/end → compute → display route
  - Navigation: mock location → instruction updates
- **Cross-platform data tests:**
  - Read an MBTiles file generated by iOS → verify tiles render
  - Decode a track blob compressed by iOS → verify coordinates match
  - Parse a sync JSON exported by iOS → verify all fields

#### Step 5.5 — Performance & Battery

- Profile tile download battery impact (Systrace)
- Optimize GPS polling: increase interval when user is stationary (speed < 0.1 m/s)
- Memory profiling: large MBTiles files, elevation tile LRU cache sizing
- Startup optimization: lazy initialization of heavy services (elevation, routing)
- MapLibre: tile cache size configuration, reduce overdraw

#### Step 5.6 — Play Store Prep

- App icon & adaptive icon (foreground + background layers)
- Feature graphic (1024 × 500)
- Store listing: description, 8+ screenshots (phone + tablet)
- Privacy policy (location data usage, no telemetry, no ads, AGPL-3.0)
- `ACCESS_BACKGROUND_LOCATION` declaration form: justify as "active hike GPS tracking for safety"
- Target SDK 35+ (2025 Play Store requirement)
- App bundle signing (`.aab`)
- Content rating questionnaire
- AGPL-3.0 compliance: link to source code in app and store listing

---

## Critical Path

```
1.1 Scaffolding
 ├─→ 1.2 Data Models ─→ 1.4 Tile Download ─→ 1.5 Region Selector ─→ 1.6 Offline Display ─→ 1.7 Region Mgmt
 ├─→ 1.3 Map Display ──────────────────────→ 1.5 ─→ 1.6
 │
 ├─→ 2.1 GPS Service ──────────────────────────────→ 2.7 Navigation ─→ 3.1 Hike Recording ─→ 3.2 Hike History
 ├─→ 2.2 Elevation ──→ 2.4 Graph Builder ─→ 2.5 Routing ─→ 2.6 Route Planning ─→ 2.7
 └─→ 2.3 OSM Download ─→ 2.4
```

**Critical path:** 1.1 → 1.2 → 1.4 → 1.5 → 1.6 → 2.6 → 2.7

**Parallel opportunities:**
- 1.2 (data models) ∥ 1.3 (map display) — no shared dependency
- 2.1 (GPS) ∥ 2.2 (elevation) ∥ 2.3 (OSM download) — independent services
- 3.3 (chart) ∥ 3.4 (waypoints) — independent features
- 4.1 (community browse) can start anytime after 1.1
- 5.1 (settings) can start anytime after 1.1

---

## Data Format Cross-Platform Compatibility

All data formats are shared between iOS and Android with byte-level compatibility:

| Format | Portable? | Notes |
|--------|-----------|-------|
| MBTiles (.mbtiles) | Yes | Same SQLite schema, same TMS Y-flip formula |
| Routing DB (.routing.db) | Yes | Same SQLite schema, same cost constants |
| GPX (.gpx) | Yes | Standard XML, same schema |
| Planned routes (.json) | Yes | Same JSON structure, Kotlinx.serialization ↔ Swift Codable |
| Region metadata (.json) | Yes | Same JSON structure |
| HGT elevation (.hgt.gz) | Yes | Same binary format, same S3 URLs |
| Track data (zlib binary) | Yes | Same binary layout, same compression (see Appendix B) |
| Waypoint photos (BLOB) | Yes | Standard JPEG/PNG |
| Sync directory | Yes | Platform-agnostic file structure |
| Community routes (GitHub) | Yes | Same API, same JSON, same repository |

An MBTiles file downloaded on iOS can be transferred (via cloud drive sync) to Android and rendered identically. A track recorded on Android and synced will display correctly on iOS. No conversion is needed for any format.

---

## Appendix A: Tile Server Configuration

Exact URLs and subdomain patterns (must match iOS implementation):

| Server | URL Pattern | Subdomains | Notes |
|--------|------------|------------|-------|
| OpenTopoMap | `https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png` | `a`, `b`, `c` | Topographic contours |
| CyclOSM | `https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png` | `a`, `b`, `c` | Note `/cyclosm/` path segment |
| OSM Standard | `https://tile.openstreetmap.org/{z}/{x}/{y}.png` | (none) | Single host, no rotation |

**Subdomain distribution formula:** `subdomains[abs(tile.x + tile.y) % subdomains.size]`

This deterministic hash ensures the same tile always maps to the same subdomain across both platforms, improving HTTP cache coherence.

---

## Appendix B: Track Compression Binary Format

Must match iOS `TrackCompression.swift` byte-for-byte for cross-platform compatibility.

**Per-point record: 20 bytes**

| Offset | Type | Size | Content |
|--------|------|------|---------|
| 0 | Float32 (LE) | 4 bytes | Latitude |
| 4 | Float32 (LE) | 4 bytes | Longitude |
| 8 | Float32 (LE) | 4 bytes | Altitude (meters) |
| 12 | Float64 (LE) | 8 bytes | Timestamp (seconds since reference date) |

- **Byte order:** Little-endian (native on both ARM platforms)
- **Note:** Float64 at offset 12 is not 8-byte aligned — use `ByteBuffer` without alignment assumptions
- **Compression:** zlib (DEFLATE) via `java.util.zip.Deflater` / `java.util.zip.Inflater`
- **Compression buffer:** input size + 64 bytes overhead margin
- **Decompression buffer:** 10× compressed size (safe upper bound)
- **Empty data:** return empty byte array, do not compress
- **Backwards compatibility:** if decompression fails, try reading as uncompressed (legacy format)

**Kotlin implementation sketch:**
```kotlin
object TrackCompression {
    private const val BYTES_PER_POINT = 20

    fun compress(points: List<TrackPoint>): ByteArray {
        if (points.isEmpty()) return ByteArray(0)
        val buffer = ByteBuffer.allocate(points.size * BYTES_PER_POINT)
            .order(ByteOrder.LITTLE_ENDIAN)
        for (p in points) {
            buffer.putFloat(p.latitude.toFloat())
            buffer.putFloat(p.longitude.toFloat())
            buffer.putFloat(p.altitude.toFloat())
            buffer.putDouble(p.timestamp)
        }
        val input = buffer.array()
        val deflater = Deflater()
        deflater.setInput(input)
        deflater.finish()
        val output = ByteArray(input.size + 64)
        val size = deflater.deflate(output)
        deflater.end()
        return output.copyOf(size)
    }

    fun decompress(data: ByteArray): List<TrackPoint> {
        if (data.isEmpty()) return emptyList()
        val inflater = Inflater()
        inflater.setInput(data)
        val output = ByteArray(data.size * 10)
        val size = try {
            inflater.inflate(output)
        } catch (e: DataFormatException) {
            // Fallback: try as uncompressed (legacy)
            return parseUncompressed(data)
        } finally {
            inflater.end()
        }
        return parseUncompressed(output.copyOf(size))
    }

    private fun parseUncompressed(data: ByteArray): List<TrackPoint> {
        val buffer = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
        val points = mutableListOf<TrackPoint>()
        while (buffer.remaining() >= BYTES_PER_POINT) {
            points.add(TrackPoint(
                latitude = buffer.float.toDouble(),
                longitude = buffer.float.toDouble(),
                altitude = buffer.float.toDouble(),
                timestamp = buffer.double
            ))
        }
        return points
    }
}
```

---

## Appendix C: Routing Cost Configuration

All constants must match iOS `RoutingCostConfig` for identical route computation.

**Base speeds (Naismith's Rule):**

| Parameter | Hiking | Cycling |
|-----------|--------|---------|
| Base speed (m/s) | 1.33 (~4.8 km/h) | 4.17 (~15 km/h) |
| Climb penalty per metre | 7.92 | 12.0 |

**Descent penalty (Tobler's Hiking Function):**

| Grade | Penalty multiplier |
|-------|-------------------|
| < 5% | 0.0 (no penalty) |
| 5–15% | 0.3 (slight braking) |
| 15–25% | 0.8 (significant braking) |
| ≥ 25% | 1.5 (very steep, slower than climbing) |

**Surface type multipliers:**

| Surface | Hiking | Cycling |
|---------|--------|---------|
| asphalt, concrete (paved) | 1.0 | 1.0 |
| compacted | 1.1 | 1.2 |
| fine_gravel | 1.1 | 1.3 |
| gravel | 1.2 | 1.5 |
| ground, dirt, earth | 1.3 | 2.0 |
| grass | 1.4 | 3.0 |
| sand | 1.8 | 3.0 |
| rock | 1.5 | 2.5 |
| pebblestone | 1.5 | 2.0 |
| mud | 2.0 | 4.0 |
| wood | 1.1 | 1.2 |
| unknown (default) | 1.3 | 1.5 |

**SAC scale multipliers (hiking only):**

| SAC Scale | Multiplier |
|-----------|-----------|
| hiking | 1.0 |
| mountain_hiking | 1.2 |
| demanding_mountain_hiking | 1.5 |
| alpine_hiking | 2.0 |
| demanding_alpine_hiking | 3.0 |
| difficult_alpine_hiking | 5.0 |
| missing/untagged | 1.0 |

**Highway type adjustments:**

| Highway | Hiking multiplier |
|---------|------------------|
| steps | 1.5 |
| all others | 1.0 |

**Impassable edge:** cost = `Double.MAX_VALUE` (prevents A\* selection)

**Routable highway values** (used in Overpass query filter):
`path`, `footway`, `track`, `cycleway`, `bridleway`, `steps`, `pedestrian`, `residential`, `unclassified`, `tertiary`, `secondary`, `primary`, `trunk`, `living_street`, `service`

---

## Appendix D: Route Guidance Thresholds

Must match iOS `RouteGuidanceConfig` for consistent navigation behavior.

| Threshold | Value | Description |
|-----------|-------|-------------|
| `offRouteThresholdMeters` | 50.0 | Distance to trigger off-route warning |
| `offRouteClearThresholdMeters` | 30.0 | Distance to clear off-route (hysteresis) |
| `approachingTurnDistanceMeters` | 100.0 | Distance to fire "approaching turn" haptic |
| `atTurnDistanceMeters` | 30.0 | Distance to fire "at turn" haptic and advance instruction |
| `arrivedDistanceMeters` | 30.0 | Distance from final destination to trigger "arrived" |

The hysteresis between `offRouteThresholdMeters` (50m) and `offRouteClearThresholdMeters` (30m) prevents rapid on/off flapping when the user walks near the route boundary.
