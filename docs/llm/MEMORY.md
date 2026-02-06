# OpenHiker Project Memory

## Project Structure
- Dual-platform: iOS companion + standalone watchOS app
- `Shared/` compiled into both targets (models, storage)
- watchOS uses SpriteKit for map rendering (not SwiftUI)
- No third-party dependencies; Apple frameworks + SQLite3 only
- AGPL-3.0 license; all files need copyright header

## Key Patterns
- **Models**: `Codable + Sendable + Identifiable + Equatable` convention
- **SQLite pattern**: `TileStore`, `WaypointStore`, `RouteStore`, and `RoutingStore` all use `@unchecked Sendable` + `DispatchQueue(label:)` serial queue + `queue.sync {}` for thread safety
- **Singleton pattern**: `WatchConnectivityManager.shared`, `RegionStorage.shared`, `WatchConnectivityReceiver.shared`, `WaypointStore.shared`, `RouteStore.shared`
- **Environment injection**: Singletons injected via `@StateObject` in App entry point -> `.environmentObject()` -> `@EnvironmentObject` in views
- **WatchConnectivity**: `transferFile` for large data (MBTiles), `transferUserInfo` for small data (waypoints), `updateApplicationContext` for state
- **Platform guards**: iOS files use `#if os(iOS)`, watchOS files don't need guards (separate target)
- **MBTiles Y-flip**: TMS convention uses inverted Y: `tmsY = (2^z - 1) - y`
- **AGPL header**: All files start with the AGPL-3.0 copyright block
- `@AppStorage` for user preferences
- Thread safety: serial DispatchQueues for SQLite, HKHealthStore is thread-safe
- `sqlite3_bind_text` uses `unsafeBitCast(-1, to: sqlite3_destructor_type.self)` for SQLITE_TRANSIENT — in RouteStore, extracted as named `sqliteTransient` constant
- **Track compression**: `TrackCompression` uses 20 bytes/point binary format (Float32 lat/lon/alt + Float64 timestamp) + zlib; constants `bytesPerPoint`, `compressionBufferMargin`, `decompressionBufferMultiplier`
- **Walking/resting time**: Pure static function `LocationManager.computeWalkingAndRestingTime(from:)` + `classifyRestPeriod()` helper; thresholds in `HikeStatisticsConfig` (`restingSpeedThreshold`, `minRestDurationSec`)
- **GitHub API**: `GitHubRouteService` is a Swift Actor for thread safety; uses Git Data API (blobs/trees/commits/refs) for uploads
- **Token obfuscation**: XOR-based obfuscation for embedded GitHub bot token (placeholder — needs real token before deploy)
- **Location in SwiftUI**: Use `@StateObject` + `CLLocationManagerDelegate` class (not plain `CLLocationManager` property — views are recreated)

## Xcode Project (pbxproj)
- ID format: `2A...` for iOS file refs, `2B...` for watchOS, `1A...` for iOS build files, `1B...` for watchOS
- Shared files need build file entries in BOTH targets (different IDs, same file ref)
- Groups: `5A...` iOS, `5B...` watchOS, `5C...` Shared
- watchOS target: `6B0000010000000000000001`
- iOS target: `6A0000010000000000000001`

## Key Files
- `Shared/Models/`: Region.swift, TileCoordinate.swift, HikeStatistics.swift, Waypoint.swift, SavedRoute.swift, SharedRoute.swift, ActivityType.swift
- `Shared/Storage/`: TileStore.swift (+ WritableTileStore), WaypointStore.swift, RouteStore.swift, RoutingStore.swift
- `Shared/Services/`: RoutingEngine.swift (A* pathfinding), GitHubRouteService.swift (actor — GitHub API for community route sharing)
- `Shared/Utilities/`: TrackCompression.swift (binary pack + zlib for GPS tracks), RouteExporter.swift (SavedRoute ↔ SharedRoute ↔ GPX ↔ Markdown), PhotoCompressor.swift
- `OpenHiker iOS/Views/`: RouteUploadView.swift, CommunityBrowseView.swift, CommunityRouteDetailView.swift
- `route-repo-template/`: GitHub Actions workflows + repo setup for OpenHikerRoutes
- SpriteKit map: `MapRenderer.swift` manages `MapScene` (SKScene with tilesNode + overlaysNode)

## Phase Status
- Phase 1 (Hike Metrics + HealthKit): Completed and merged
- Phase 2 (Waypoints & Pins): Implemented on `claude/implement-phase2-waypoints-soKPD`
- Phase 3 (Save Routes & Review Past Hikes): Implemented on `claude/phase3-save-routes-review-oogwp`
- Phase 4 (Custom Offline Routing Engine): Implemented on `claude/implement-routing-engine-KCnec`
- Phase 5 (Community Route Sharing): Implemented on `claude/add-route-upload-feature-47R66`

### Phase 1 Details
- `HikeStatistics` shared model, `HikeStatsFormatter`, `CalorieEstimator`
- `HikeStatsOverlay` view with auto-hide
- `HealthKitManager` with workout session, HR/SpO2 queries, route builder
- HealthKit entitlements, Info.plist entries, framework linked
- Developer docs at `docs/developer/hike-metrics-healthkit.md`

### Phase 2 Details
- `Waypoint` model + `WaypointCategory` enum (9 categories with SF Symbols)
- `WaypointStore` SQLite CRUD (photos as BLOBs, 100x100 thumbnails)
- watchOS: `AddWaypointSheet`, SpriteKit markers in `MapScene`, pin button in `MapView`
- iOS: `AddWaypointView` (camera + photo library), `WaypointDetailView` (edit/delete)
- iOS: MapKit `Annotation` markers in `RegionSelectorView`
- Bidirectional sync via `transferUserInfo` (thumbnails only to watch)
- Developer docs at `docs/developer/phase2-waypoints-developer-guide.md`

### Phase 3 Details
- `SavedRoute` model (18 fields including compressed track BLOB)
- `RouteStore` SQLite CRUD (singleton, same pattern as WaypointStore)
- `TrackCompression` binary pack + zlib: 20 bytes/point → ~15x smaller than GPX
- watchOS: `SaveHikeSheet` modal (save/discard after tracking stop)
- watchOS: `MapView` modified to present SaveHikeSheet when tracking stops
- iOS: `HikesListView` (searchable, swipe-to-delete), `HikeDetailView` (map + polyline + stats + elevation + comments)
- iOS: `ElevationProfileView` with Swift Charts (AreaMark + LineMark, subsampled to 200 points)
- WatchConnectivity: JSON-encoded SavedRoute via `transferFile` with `["type": "savedRoute"]` metadata
- Walking/resting classification: speed-based state machine (< 0.3 m/s threshold, 60s min rest)
- Developer docs at `docs/developer/phase3-save-routes-developer-guide.md`

### Phase 4 Details (Routing Engine)
- **A* pathfinding** with via-point support: segmented routing (start→via1→via2→end)
- **Shared files**: `RoutingGraph.swift` (models + cost config), `RoutingStore.swift` (SQLite read-only), `RoutingEngine.swift` (A* + BinaryMinHeap)
- **iOS-only files**: `ProtobufReader.swift` (wire format decoder), `PBFParser.swift` (OSM PBF), `ElevationDataManager.swift` (Tilezen skadi tiles), `RoutingGraphBuilder.swift` (graph construction pipeline), `OSMDataDownloader.swift` (Overpass API)
- **Cost model**: Naismith's rule (`hikingClimbPenaltyPerMetre = 7.92`) + surface/SAC-scale multipliers, all in `RoutingCostConfig` enum
- **Edge geometry**: Float32 packed lat/lon pairs in BLOB (`EdgeGeometry.pack/unpack`)
- **Elevation data**: Tilezen skadi tiles (gzip-compressed HGT on AWS S3), bilinear interpolation, memory-limited tile cache
- **SQLite schema**: `routing_nodes(id, latitude, longitude, elevation)`, `routing_edges(16 columns)`, `routing_metadata(key, value)` with indexes on `from_node`, `to_node`, `lat/lon`
- **Graph builder pipeline**: identifyJunctions → splitWaysAtJunctions → lookupElevations → computeEdgeCosts → writeToSQLite
- **WatchConnectivity**: `.routing.db` transferred alongside `.mbtiles`, `hasRoutingData` field in `Region`/`RegionMetadata`
- **Patterns**: Actor (PBFParser, ElevationDataManager, RoutingGraphBuilder, OSMDataDownloader), Serial DispatchQueue (RoutingStore)
- Developer docs at `docs/developer/routing-engine.md`

### Phase 5 Details (Community Route Sharing)
- Community route sharing via GitHub repo `hherb/OpenHikerRoutes` with PR-based moderation
- `SharedRoute` model: canonical JSON format with `route.json` + `route.gpx` + `README.md` + `photos/`
- `ActivityType` enum: hiking, cycling, running, skiTouring, other (with SF Symbol icons)
- `RouteExporter`: bidirectional SavedRoute ↔ SharedRoute + GPX 1.1 + Markdown export
- `GitHubRouteService` (actor): upload via Git Data API (blob → tree → commit → ref → PR), browse via raw `index.json`
- `PhotoCompressor`: downsample to 640x400 JPEG at 70% quality (~30-80 KB each)
- `index.json` at repo root: master index rebuilt by GitHub Actions on merge to main
- Browse: `CommunityBrowseView` with activity type and proximity filtering (Haversine distance)
- Upload: `RouteUploadView` sheet from HikeDetailView toolbar
- Download: `CommunityRouteDetailView` with MapKit polyline preview and offline save
- `SimpleLocationProvider`: `@StateObject` + `CLLocationManagerDelegate` for location in CommunityBrowseView
- Bot token: XOR-obfuscated, embedded in binary (placeholder — needs real token before deploy)
- iOS `ContentView` now has 5 tabs: Regions, Downloaded, Hikes, Community, Watch

## Dev Rules (from docs/llm/general_golden_rules.md)
1. Clean separation of concerns
2. Prefer reusable pure functions
3. Doc strings for everything (junior-friendly)
4. No magic numbers (use config constants)
5. Unit tests for public functions
6. Never truncate data
7. Network calls need retry + exponential backoff
8. All errors must be handled, logged, reported
9. Research unfamiliar APIs first
10. Keep cross-platform compatibility in mind
