# Android Port Feasibility Assessment

## Executive Summary

Porting OpenHiker to Android is **highly feasible**. The app's architecture separates platform-specific UI and services from core algorithms and data formats that are platform-agnostic. The iOS app (minus watch features) comprises roughly 55 Swift files across iOS-specific views/services and shared logic. An Android port would require a **full UI rewrite** in Jetpack Compose and **platform service adaptation**, but the core algorithms (A\* routing, elevation interpolation, tile coordinate math, track compression) and all data formats (MBTiles, SQLite routing DB, GPX, JSON) transfer directly.

**Difficulty rating: Medium-High.** Not a trivial port, but no fundamental blockers exist. Every iOS capability has a well-established Android equivalent.

---

## Scope: What Gets Ported (iOS App Minus Watch)

The iOS app features targeted for Android:

| Feature | iOS Files Involved | Complexity |
|---------|-------------------|------------|
| Offline map tile download & display | TileDownloader, TileStore, WritableTileStore, RegionSelectorView, TrailMapView | High |
| Region management (save/rename/delete) | RegionStorage, RegionSelectorView | Low |
| A\* offline routing with elevation | RoutingEngine, RoutingGraphBuilder, RoutingStore | Medium |
| OSM trail data download & parsing | OSMDataDownloader, PBFParser | Medium |
| Elevation data (SRTM/ASTER) | ElevationDataManager | Medium |
| GPS tracking with statistics | iOSLocationManager | Medium |
| Turn-by-turn navigation with haptics | iOSRouteGuidance, iOSNavigationView | Medium |
| Route planning (start/end/via-points) | RoutePlanningView, RoutePlanningMapView | Medium |
| Hike history with elevation profiles | HikesListView, HikeDetailView, ElevationProfileView | Medium |
| Waypoint management with photos | WaypointsListView, WaypointDetailView, AddWaypointView | Low-Medium |
| PDF/GPX export | PDFExporter, RouteExporter | Medium |
| Community route browsing & sharing | CommunityBrowseView, CommunityRouteDetailView, RouteUploadView, GitHubRouteService | Low-Medium |
| Peer-to-peer region sharing | PeerTransferService, PeerSendView, PeerReceiveView | High |
| Cloud sync | CloudSyncManager, CloudKitStore | High |

**Excluded** (watch-specific):
- WatchConnectivityManager / WatchConnectivityReceiver
- WatchHealthRelay
- MapRenderer (SpriteKit-based watch rendering)
- All watchOS views

---

## Component-by-Component Analysis

### 1. Map Display & Tile Rendering

**iOS approach:** MapKit `MKMapView` with `MKTileOverlay` for custom tile servers (OpenTopoMap, CyclOSM), plus direct MBTiles reading via SQLite for offline tiles.

**Android equivalent:** Several strong options:
- **Mapbox Maps SDK** — First-class offline tile support, MBTiles integration, custom tile sources. Best match for the offline-first architecture.
- **Google Maps SDK** — Widely used but weaker offline support. Would require a custom tile provider layer.
- **osmdroid** — Open-source, native MBTiles support, no API key needed. Lighter weight but less polished.
- **MapLibre** — Open-source fork of Mapbox GL, good offline support.

**Recommendation:** Mapbox or MapLibre for closest feature parity with the iOS MKTileOverlay approach. osmdroid is a viable zero-cost alternative.

**Effort:** Medium. The tile coordinate math (including TMS Y-flipping) is identical — it's just wiring it into a different map SDK.

### 2. Tile Downloading (TileDownloader)

**iOS approach:** Swift Actor with rate-limited concurrent downloads (50ms throttle, 150 tiles/batch), URLSession with 6 connections/host, subdomain rotation, exponential backoff retry.

**Android equivalent:**
- **OkHttp** with a `Dispatcher` configured for connection limits
- **Kotlin Coroutines** with `Flow` for rate limiting (replaces Swift Actor isolation)
- `kotlinx.coroutines.delay()` for throttling
- Same tile URL patterns (platform-agnostic HTTP)

**Effort:** Low-Medium. The download logic is straightforward HTTP with rate limiting. Kotlin coroutines are a natural fit for Swift's actor model.

### 3. SQLite Storage (MBTiles, Routing, Routes, Waypoints)

**iOS approach:** Direct SQLite3 C API calls with serial DispatchQueues for thread safety. Four database types: MBTiles tiles, routing graphs, saved routes (with zlib-compressed tracks), and waypoints (with photo BLOBs).

**Android equivalent:**
- **Room** (recommended) — Type-safe SQLite abstraction with coroutine support
- **Android SQLite API** — Direct equivalent of the C API approach
- Schema is identical — same tables, same columns, same queries

**Effort:** Low. The database schemas are platform-agnostic. Room would actually simplify the code compared to raw SQLite calls. MBTiles files created on iOS can be read directly on Android.

### 4. Offline A\* Routing (RoutingEngine)

**iOS approach:** A\* pathfinding over a SQLite graph database with elevation-aware cost functions, surface type multipliers, SAC scale penalties, and bidirectional edge support.

**Android equivalent:** The algorithm is pure computation with no platform dependencies:
- A\* algorithm → identical in Kotlin
- Priority queue → Java `PriorityQueue`
- Haversine distance → pure math
- Cost functions → pure math
- SQLite graph queries → Room or Android SQLite

**Effort:** Low. This is the most directly portable component. The algorithm, cost functions, and database schema transfer 1:1.

### 5. Routing Graph Construction (RoutingGraphBuilder, OSMDataDownloader, PBFParser)

**iOS approach:** Downloads OSM data via Overpass API, parses PBF format, identifies junctions, builds edge graph with elevation lookups, writes to SQLite.

**Android equivalent:**
- HTTP requests → OkHttp/Retrofit (same Overpass API endpoints)
- PBF parsing → **osm-pbf** Java library or manual port
- Graph construction → pure algorithm, direct port
- Elevation lookups → same HGT format, same bilinear interpolation

**Effort:** Medium. The PBF parser is the most involved piece. An existing Java OSM library could replace the custom parser.

### 6. Elevation Data (ElevationDataManager)

**iOS approach:** Downloads HGT tiles from S3/OpenTopography, gzip decompresses, reads 16-bit big-endian grid, bilinear interpolation for sub-cell accuracy.

**Android equivalent:**
- Same S3 URLs (platform-agnostic)
- `java.util.zip.GZIPInputStream` for decompression
- `java.nio.ByteBuffer` with `ByteOrder.BIG_ENDIAN` for HGT reading
- Bilinear interpolation is pure math

**Effort:** Low. Nearly line-for-line translation.

### 7. GPS & Location (iOSLocationManager)

**iOS approach:** `CLLocationManager` with configurable accuracy modes, heading updates, continuous tracking with distance/elevation accumulation.

**Android equivalent:**
- **FusedLocationProviderClient** (Google Play Services) — Best accuracy, battery optimization
- **Android LocationManager** — Works without Play Services
- `SensorManager` with `TYPE_ROTATION_VECTOR` for compass heading
- Location permission model differs (Android requires `ACCESS_FINE_LOCATION` runtime permission + background location rationale)

**Effort:** Medium. The concepts map directly, but Android's permission model is more complex (foreground service required for background tracking, `ACCESS_BACKGROUND_LOCATION` permission, notification requirement).

### 8. Turn-by-Turn Navigation (iOSRouteGuidance)

**iOS approach:** Compares current GPS position against route segments, calculates distance to next turn, fires haptic feedback at thresholds (100m approach, at turn, off-route warning).

**Android equivalent:**
- Route following logic → pure algorithm, direct port
- Haptics → `android.os.VibrationEffect` / `HapticFeedbackConstants`
- Foreground service with persistent notification for active navigation
- Text-to-speech via `android.speech.tts.TextToSpeech` (bonus feature)

**Effort:** Low-Medium. Algorithm is portable. Android requires a foreground service for reliable background GPS during navigation.

### 9. UI Layer (All Views)

**iOS approach:** 21 SwiftUI views with `@State`, `@Published`, `@EnvironmentObject`, `NavigationStack`, `TabView`, adaptive iPhone/iPad layouts.

**Android equivalent:**
- **Jetpack Compose** — Direct conceptual parallel to SwiftUI
- `remember`/`mutableStateOf` ↔ `@State`
- `ViewModel` + `StateFlow` ↔ `ObservableObject` + `@Published`
- `NavHost`/`NavController` ↔ `NavigationStack`
- `Scaffold` with `BottomNavigation` ↔ `TabView`
- `NavigationRail` for tablets ↔ `NavigationSplitView` for iPad

**Effort:** High. This is the largest single work item. Every view must be rewritten. However, the structure maps well — Compose and SwiftUI share the same declarative paradigm.

### 10. PDF Export (PDFExporter)

**iOS approach:** `UIGraphicsPDFRenderer` for multi-page composition, `MKMapSnapshotter` for static map images, `ImageRenderer` for chart rendering.

**Android equivalent:**
- `android.graphics.pdf.PdfDocument` — Built-in PDF creation API
- Map snapshot → Mapbox/Google Maps snapshot API
- Chart rendering → render Compose chart to `Bitmap`, draw onto PDF `Canvas`
- Same page layout logic, different drawing API

**Effort:** Medium. PDF APIs differ in ergonomics but offer equivalent capabilities.

### 11. Cloud Sync (CloudSyncManager → Firebase)

**iOS approach:** CloudKit with CKRecord types for SavedRoute, Waypoint, PlannedRoute. Last-writer-wins conflict resolution. Push notifications for remote changes.

**Android equivalent:**
- **Firebase Cloud Firestore** — Most natural replacement
  - Document-based (similar to CKRecord)
  - Real-time listeners (better than CloudKit push)
  - Offline persistence built-in
  - Conflict resolution via transactions
- **Alternative:** Custom backend with REST API if cross-platform sync between iOS and Android users is desired

**Cross-platform consideration:** If iOS users should sync with Android users, both platforms need to share a backend. CloudKit is Apple-only. Options:
1. Migrate iOS to Firebase too (breaking change for existing users)
2. Build a sync bridge service
3. Accept separate sync ecosystems per platform

**Effort:** High. Not because Firebase is hard, but because the sync strategy, conflict resolution, and migration path need careful design.

### 12. Peer-to-Peer Transfer (PeerTransferService)

**iOS approach:** MultipeerConnectivity with MCSession for device discovery and file transfer. Sequential resource protocol (manifest → mbtiles → routing → routes → waypoints → done).

**Android equivalent:**
- **Nearby Connections API** (Google Play Services) — Closest match
  - Supports P2P discovery and file transfer
  - Works over Bluetooth, BLE, WiFi Direct
  - No internet required
- **WiFi Direct** — Lower-level alternative
- **Android Beam / NFC** — For initial handshake only

**Cross-platform P2P:** MultipeerConnectivity (iOS) and Nearby Connections (Android) are not interoperable. For iOS↔Android sharing:
- Custom TCP/UDP over local WiFi
- Bluetooth GATT service
- QR code + local HTTP server

**Effort:** High. The protocol logic is portable but the transport layer requires a complete rewrite. Cross-platform P2P would be an additional significant effort.

### 13. Community Routes (GitHub API)

**iOS approach:** REST calls to GitHub API for route index, details, and pull request creation. Obfuscated bot token for authentication.

**Android equivalent:**
- **Retrofit** + **OkHttp** — Same REST endpoints
- Same JSON response parsing (Kotlinx.serialization or Gson)
- Same GitHub API, same authentication approach
- Token obfuscation options: ProGuard/R8, NDK native code, Android Keystore

**Effort:** Low. This is pure REST with JSON — the most platform-agnostic component.

### 14. Photo Handling

**iOS approach:** PhotosUI `PHPickerViewController` for selection, thumbnail generation, BLOB storage in SQLite.

**Android equivalent:**
- `ActivityResultContracts.PickVisualMedia` (Photo Picker, Android 13+)
- `Intent.ACTION_PICK` (older devices)
- `android.graphics.Bitmap` for thumbnail generation
- Same BLOB storage approach in SQLite/Room

**Effort:** Low.

---

## Technology Stack Recommendation

| Layer | Recommended Technology |
|-------|----------------------|
| Language | Kotlin |
| UI Framework | Jetpack Compose |
| Navigation | Compose Navigation |
| Map SDK | MapLibre or Mapbox |
| HTTP Client | OkHttp + Retrofit |
| Database | Room (SQLite) |
| Concurrency | Kotlin Coroutines + Flow |
| Location | FusedLocationProviderClient |
| DI | Hilt |
| Serialization | Kotlinx.serialization |
| Image Loading | Coil |
| Charts | Vico or MPAndroidChart |
| PDF | Android PdfDocument API |
| Cloud Sync | Firebase Firestore |
| P2P | Nearby Connections API |
| Background Work | WorkManager |
| Build System | Gradle with KTS |
| Min SDK | API 26 (Android 8.0) |

---

## Effort Estimation

### By Component (relative sizing)

| Component | Effort | Notes |
|-----------|--------|-------|
| UI Layer (21 screens) | 35% | Complete rewrite in Compose |
| Map display + tile overlay | 12% | Map SDK integration, offline tiles |
| Platform services (GPS, permissions, storage) | 15% | Android-specific APIs |
| Cloud sync (CloudKit → Firebase) | 10% | New backend, migration design |
| P2P transfer | 8% | Nearby Connections API |
| Tile downloading | 5% | HTTP + coroutines |
| Routing engine + graph builder | 5% | Algorithm port + Room DB |
| Elevation data | 3% | Nearly direct translation |
| PDF/GPX export | 3% | Different PDF API |
| Community/GitHub integration | 2% | Same REST API |
| Photo handling | 2% | Standard Android APIs |

### Rough Sizing

For a developer experienced in both iOS and Android:

- **Core logic port** (routing, elevation, tile math, compression): ~15% of total effort. These are pure algorithms that translate almost line-for-line from Swift to Kotlin.
- **Data layer** (SQLite schemas, JSON models, file storage): ~10%. Room makes this arguably easier than the iOS raw SQLite approach.
- **Platform services** (GPS, permissions, background tasks, haptics): ~15%. Conceptually identical but API surfaces differ.
- **UI rewrite** (Compose screens, navigation, state management): ~35%. Largest single item. SwiftUI → Compose is conceptual mapping, not mechanical translation.
- **Infrastructure** (project setup, build system, CI, dependency management): ~10%.
- **Cloud/sync/P2P** (Firebase, Nearby Connections): ~15%. Most design-intensive area.

---

## Risk Assessment

### Low Risk
- **Data format compatibility** — MBTiles, SQLite routing DB, GPX, JSON all work identically on Android
- **Network APIs** — Same HTTP endpoints, same tile servers, same Overpass API
- **Core algorithms** — A\*, Haversine, bilinear interpolation, coordinate transforms are pure math
- **Kotlin/Compose maturity** — Well-established ecosystem with strong tooling

### Medium Risk
- **Offline map SDK choice** — Needs evaluation/prototyping to confirm MBTiles tile overlay performance
- **Background GPS tracking** — Android restrictions on background location (requires foreground service, user-visible notification, Play Store review scrutiny)
- **OSM tile usage policy** — Same rate limiting rules apply; need proper User-Agent header
- **Tablet/foldable layouts** — Android device fragmentation requires more layout testing than iOS iPad support

### High Risk
- **Cloud sync cross-platform** — If iOS and Android users need shared sync, CloudKit must be replaced on both platforms. This is a significant architectural decision.
- **Play Store location permission review** — Google has strict policies for `ACCESS_BACKGROUND_LOCATION`. The app must justify background access (active hike tracking). Rejection risk if not properly documented.
- **P2P cross-platform** — If iOS↔Android sharing is desired, neither MultipeerConnectivity nor Nearby Connections works cross-platform. Would need a custom protocol.

---

## Recommended Approach

### Phase 1: Core Offline Maps
1. Project setup (Gradle, Hilt, Room, Compose)
2. MBTiles reader (port TileStore)
3. Map display with offline tile overlay (MapLibre/Mapbox)
4. Region selector with tile download (port TileDownloader)
5. Region management (save/rename/delete)

### Phase 2: Navigation
6. GPS tracking with statistics (FusedLocationProvider + foreground service)
7. Port routing engine (A\* + Room database)
8. OSM data download and graph construction
9. Elevation data manager
10. Route planning UI
11. Turn-by-turn navigation with haptics

### Phase 3: History & Export
12. Hike recording and history
13. Elevation profile charts
14. Waypoint management with photos
15. PDF and GPX export

### Phase 4: Social & Sync
16. Community route browsing (GitHub API)
17. Firebase cloud sync
18. Nearby Connections P2P transfer

---

## Conclusion

The port is **feasible and well-scoped**. The iOS app's clean architecture — with shared pure-logic code separated from platform services — means the hardest parts (routing algorithms, tile coordinate math, elevation queries, data formats) are directly portable. The bulk of the work is UI rewriting (Compose) and platform service adaptation (GPS, storage, permissions), both of which have mature Android equivalents.

The two decisions with the largest architectural impact are:
1. **Map SDK choice** (MapLibre vs. Mapbox vs. osmdroid) — affects offline tile handling throughout the app
2. **Cloud sync strategy** — whether to keep CloudKit for iOS and Firebase for Android (separate ecosystems) or unify on a shared backend

Neither is a blocker, but both should be decided early as they ripple through the codebase.
