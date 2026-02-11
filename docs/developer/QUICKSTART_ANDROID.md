# Android Developer Quickstart

Welcome to the OpenHiker Android app! This guide will get you building, running, and contributing as quickly as possible.

## Prerequisites

| Requirement | Minimum Version |
|-------------|-----------------|
| Android Studio | Ladybug (2024.2) or newer |
| JDK | 17 (bundled with Android Studio) |
| Gradle | 8.13 (wrapper included) |
| Kotlin | 2.0.21 |
| Android SDK | compileSdk 35, minSdk 26 (Android 8.0) |

No API keys or proprietary SDKs are required. The project uses only open-source dependencies resolved from Maven Central, Google, and JitPack.

## Clone & Build

```bash
git clone https://github.com/hherb/OpenHiker.git
cd OpenHiker/OpenHikerAndroid
```

### Build from the command line

```bash
# Debug build
./gradlew :app:assembleDebug

# Release build
./gradlew :app:assembleRelease

# Run unit tests
./gradlew :app:testDebugUnitTest

# Run instrumentation tests (requires a connected device or emulator)
./gradlew :app:connectedDebugAndroidTest

# Run core module tests (pure Kotlin, no emulator needed)
./gradlew :core:test
```

### Open in Android Studio

1. Open Android Studio
2. Select **File > Open** and navigate to `OpenHiker/OpenHikerAndroid/`
3. Wait for Gradle sync to finish (first sync downloads ~500MB of dependencies)
4. Select a device or emulator and press **Run** (Shift+F10)

> **Tip:** Use an emulator with Google Play Services and a location set via **Extended controls > Location** to test GPS features without a physical device.

## Module Structure

The Android project is a two-module Gradle build:

```
OpenHikerAndroid/
├── core/                          ← Pure Kotlin library (no Android dependencies)
│   └── src/main/kotlin/com/openhiker/core/
│       ├── community/             ← GitHub route sharing models
│       ├── compression/           ← Track data compression (zlib, 20 bytes/point)
│       ├── elevation/             ← HGT elevation file parsing & interpolation
│       ├── formats/               ← MBTiles schema, GPX, routing DB definitions
│       ├── geo/                   ← Coordinate math, Haversine, Mercator projection
│       ├── model/                 ← Shared data classes (Region, Route, Waypoint, etc.)
│       ├── navigation/            ← Route-following logic & turn detection
│       ├── overpass/              ← Overpass API query builder for OSM trail data
│       ├── routing/               ← A* pathfinding, cost functions, graph interface
│       └── util/                  ← General utilities
│
├── app/                           ← Android application module
│   └── src/main/java/com/openhiker/android/
│       ├── MainActivity.kt        ← Single-activity entry point (Compose)
│       ├── OpenHikerApp.kt        ← Hilt Application class + MapLibre init
│       ├── data/
│       │   ├── db/                ← Database layer
│       │   │   ├── routes/        ← Room database for saved hikes
│       │   │   ├── routing/       ← Routing graph SQLite database
│       │   │   ├── tiles/         ← MBTiles read/write tile storage
│       │   │   └── waypoints/     ← Waypoint Room database
│       │   └── repository/        ← Repository pattern (data access abstraction)
│       ├── di/                    ← Hilt dependency injection modules
│       │   ├── DatabaseModule.kt
│       │   ├── DispatcherModule.kt
│       │   ├── LocationModule.kt
│       │   ├── NetworkModule.kt
│       │   └── RepositoryModule.kt
│       ├── service/
│       │   ├── community/         ← GitHub-based community route service
│       │   ├── download/          ← Tile download with rate limiting
│       │   ├── elevation/         ← Copernicus DEM elevation data
│       │   ├── export/            ← GPX and PDF exporters
│       │   ├── location/          ← GPS provider + foreground tracking service
│       │   ├── map/               ← Offline MapLibre style generation
│       │   ├── navigation/        ← Turn-by-turn navigation with audio cues
│       │   ├── osm/               ← OSM PBF/Overpass data downloader
│       │   ├── routing/           ← Routing graph builder
│       │   └── sync/              ← Cloud drive sync engine
│       └── ui/
│           ├── community/         ← Community route browsing & uploading
│           ├── components/        ← Reusable Compose components
│           ├── export/            ← Export bottom sheet
│           ├── hikes/             ← Hike history list & detail
│           ├── map/               ← Main map screen (MapLibre)
│           ├── navigation/        ← App navigation graph (NavHost)
│           ├── regions/           ← Region selection & download management
│           ├── routing/           ← Route planning & turn-by-turn navigation
│           ├── settings/          ← Settings screen
│           ├── theme/             ← Material 3 theme definition
│           └── waypoints/         ← Waypoint management
│
├── build.gradle.kts               ← Root build script (plugin declarations)
├── settings.gradle.kts            ← Module includes + repository config
└── gradle/
    └── libs.versions.toml         ← Version catalog (single source of truth for deps)
```

### Why two modules?

| Module | Purpose | Dependencies |
|--------|---------|-------------|
| **`core`** | Platform-independent business logic: routing algorithm, coordinate math, data models, file formats | Kotlin stdlib + kotlinx.serialization only |
| **`app`** | Android UI, services, storage, DI | Everything (Compose, Hilt, Room, MapLibre, etc.) |

The `core` module is a pure Kotlin JVM library (JDK 21 toolchain) with zero Android dependencies. This means core logic is unit-testable without emulators and could theoretically be shared with other JVM platforms.

## Architecture Overview

### Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | Jetpack Compose + Material 3 |
| Navigation | Compose Navigation (single-activity) |
| DI | Hilt (Dagger) |
| Database | Room (routes, waypoints) + raw SQLite (tiles, routing graphs) |
| Network | OkHttp + Retrofit |
| Map SDK | MapLibre Android (BSD-2 license, no API key) |
| Async | Kotlin Coroutines + Flow |
| Serialization | kotlinx.serialization |
| Background work | WorkManager (Hilt-aware workers) |
| Charts | Vico (elevation profiles) |
| Images | Coil 3 |
| Preferences | DataStore |

### Data Flow

```
┌──────────────────────────────────────────────────────────┐
│                     Android App                          │
│                                                          │
│  ┌──────────────┐    ┌──────────────┐   ┌────────────┐  │
│  │  UI Layer    │    │  Service     │   │  Data      │  │
│  │  (Compose)   │───▶│  Layer       │──▶│  Layer     │  │
│  │              │    │              │   │            │  │
│  │ MapScreen    │    │ TileDownload │   │ TileStore  │  │
│  │ HikeList     │    │ LocationProv │   │ RouteDB    │  │
│  │ RoutePlanning│    │ RoutingGraph │   │ WaypointDB │  │
│  │ Community    │    │ Navigation   │   │ RoutingDB  │  │
│  └──────┬───────┘    └──────────────┘   └────────────┘  │
│         │                                                │
│         │    ViewModel (Hilt-injected)                    │
│         │    StateFlow / SharedFlow                       │
│         ▼                                                │
│  ┌──────────────┐                                        │
│  │ core module  │  ← Pure Kotlin: A* routing, geo math,  │
│  │              │    cost functions, data models          │
│  └──────────────┘                                        │
└──────────────────────────────────────────────────────────┘
```

1. **User selects a region** on the map → `TileDownloadService` fetches tiles from OpenTopoMap with rate limiting (50ms/request, 6 concurrent connections) → tiles stored in MBTiles via `WritableTileStore`
2. **Routing data is built** → `OSMDataDownloader` fetches trail data from Overpass API → `RoutingGraphBuilder` constructs a graph with Naismith's-rule edge costs → persisted in `RoutingStore`
3. **User plans a route** → `AStarRouter` (in `core`) computes the path → `PlannedRouteStore` saves it
4. **User starts hiking** → `HikeTrackingService` (foreground service) records GPS → track saved via `RouteRepository`
5. **Turn-by-turn navigation** → `NavigationService` follows the planned route, generating audio and haptic cues
6. **Community sharing** → routes uploaded/downloaded via GitHub API

### Navigation Structure

The app uses a single `Activity` with Compose Navigation. Five top-level tabs are displayed as a bottom bar (phones) or navigation rail (tablets):

| Tab | Screen | Purpose |
|-----|--------|---------|
| Navigate | `MapScreen` | MapLibre map with GPS, offline tiles, route overlays |
| Regions | `RegionListScreen` | Manage downloaded regions, navigate to download selector |
| Hikes | `HikeListScreen` | Browse saved hike history |
| Routes | `RoutePlanningScreen` | Plan routes with A* pathfinding |
| Community | `CommunityBrowseScreen` | Browse and download shared routes |

Additional screens (settings, detail views, waypoints, turn-by-turn navigation) are pushed onto the navigation stack from the tab screens.

### Dependency Injection

Hilt modules in `di/` provide all injectable dependencies:

| Module | Provides |
|--------|----------|
| `DatabaseModule` | Room databases, tile stores, routing stores |
| `NetworkModule` | OkHttpClient, Retrofit instances |
| `RepositoryModule` | Repository implementations |
| `LocationModule` | FusedLocationProviderClient |
| `DispatcherModule` | Coroutine dispatchers (IO, Default, Main) |

ViewModels use `@HiltViewModel` and receive dependencies via constructor injection. Screens obtain ViewModels via `hiltViewModel()`.

### Storage Layout

All data is stored locally on-device under the app's internal storage:

```
/data/data/com.openhiker.android/
├── databases/
│   ├── routes.db              ← Saved hikes (Room)
│   └── waypoints.db           ← Waypoints (Room)
├── files/
│   ├── regions/
│   │   ├── <uuid>.mbtiles     ← Downloaded tile databases
│   │   └── <uuid>.routing.db  ← Routing graph databases
│   ├── regions_metadata.json  ← Region list
│   └── planned_routes/        ← Planned route JSON files
└── shared_prefs/              ← DataStore preferences
```

### Key Singletons and Stores

| Component | Type | Purpose |
|-----------|------|---------|
| `TileStore` | Raw SQLite | Read-only MBTiles access (TMS Y-flip) |
| `WritableTileStore` | Raw SQLite | MBTiles creation during download |
| `RoutingStore` / `WritableRoutingStore` | Raw SQLite | Routing graph persistence |
| `RouteDatabase` | Room | Saved hike CRUD |
| `WaypointDatabase` | Room | Waypoint CRUD |
| `UserPreferencesRepository` | DataStore | Settings persistence |

## Cross-Platform Compatibility

The Android app shares data formats with the iOS/watchOS/macOS apps for potential cross-device workflows:

| Format | Schema | Notes |
|--------|--------|-------|
| MBTiles (`.mbtiles`) | Standard MBTiles with TMS Y-flip | Byte-compatible with iOS `TileStore` |
| Routing DB (`.routing.db`) | Custom SQLite with nodes/edges tables | Same schema and cost constants |
| GPX (`.gpx`) | Standard GPX XML | Import/export interop |
| Track binary | 20 bytes/point, zlib compressed | Identical compression format |
| Region metadata (`.json`) | JSON | kotlinx.serialization ↔ Swift Codable |
| Elevation data (`.hgt.gz`) | SRTM HGT binary | Same Copernicus DEM source |

## Important Technical Gotchas

### MBTiles Y-coordinate flipping

MBTiles uses the TMS convention where Y is inverted compared to web slippy maps (XYZ):

```kotlin
val tmsY = (1 shl zoom) - 1 - slippyY   // (2^zoom - 1) - y
```

This conversion is handled inside `TileStore`. Be aware of which convention you're using when working with tile coordinates.

### MapLibre for map rendering

The map is rendered using **MapLibre Android SDK** (open-source fork of Mapbox GL). It supports:
- Online tile sources (OpenTopoMap, CyclOSM, OSM Standard)
- Offline MBTiles via `mbtiles://` URI scheme
- GeoJSON overlays for region boundaries and routes
- 50MB ambient tile cache configured at startup

### Tile download rate limiting

`TileDownloadService` respects OpenStreetMap tile usage policy with:
- **50ms minimum delay** between requests
- **6 concurrent connections** max
- **Exponential backoff** retry (4 attempts: 2s, 4s, 8s, 16s delays)
- **150 tiles per batch** transaction for SQLite writes

### Foreground service for hike recording

GPS tracking during hikes uses `HikeTrackingService`, a foreground service with a persistent notification. This ensures location updates continue when the app is backgrounded. The service is declared in `AndroidManifest.xml` with `foregroundServiceType="location"`.

### Hilt + WorkManager integration

The default WorkManager initializer is **disabled** in the manifest. Instead, `OpenHikerApp` implements `Configuration.Provider` with a `HiltWorkerFactory`, enabling `@HiltWorker`-annotated workers to receive injected dependencies.

### Room schema exports

Room database schemas are exported to `app/schemas/` for migration verification. If you change a Room `@Entity` or `@Database` version, you must write a migration and the schema file will be auto-updated.

## Running Tests

```bash
# Unit tests (no emulator required)
./gradlew :core:test                    # Core module tests
./gradlew :app:testDebugUnitTest        # App unit tests

# Instrumentation tests (requires emulator or device)
./gradlew :app:connectedDebugAndroidTest

# All tests
./gradlew test connectedDebugAndroidTest
```

### Existing test coverage

| Test file | What it covers |
|-----------|---------------|
| `RegionSelectorUiStateTest` | Region selector UI state logic |
| `RegionDisplayItemTest` | Region display formatting |
| `RegionListViewModelTest` | Region list ViewModel behavior |
| `UserPreferencesRepositoryTest` | DataStore preferences read/write |
| `SettingsViewModelTest` | Settings ViewModel logic |
| `SettingsScreenTest` (instrumentation) | Settings screen Compose UI |

Test infrastructure includes `FakeRegionDataSource` for repository testing and `HiltTestRunner` for instrumentation tests.

### Writing new tests

- **Unit tests** go in `app/src/test/` — use JUnit 4, kotlinx.coroutines-test, and Hilt testing
- **Instrumentation tests** go in `app/src/androidTest/` — use Compose UI testing with `HiltTestRunner`
- **Core tests** go in `core/src/test/` — pure JUnit 4 (no Android dependencies)

## Build Variants

| Variant | App ID | Minification | Notes |
|---------|--------|-------------|-------|
| **debug** | `com.openhiker.android.debug` | Off | Installs alongside release builds |
| **release** | `com.openhiker.android` | R8/ProGuard enabled + resource shrinking | Requires signing config |

## Coding Conventions

These apply across the entire OpenHiker project (see `docs/llm/general_golden_rules.md`):

1. **Separation of concerns** — `data/`, `service/`, `ui/` are distinct layers; ViewModels mediate between them
2. **Pure functions over complex classes** — Business logic goes in `core/` as testable free functions
3. **Doc strings on everything** — Write them so a junior developer can understand the purpose and flow
4. **No magic numbers** — Use named constants or `companion object` values
5. **Unit tests for public APIs** — Cover new public functions with tests
6. **Never truncate data** — Don't silently drop records or shorten collections
7. **Retry with exponential backoff** — All network calls must handle transient failures
8. **Handle all errors** — Log them and surface to the user; no empty `catch {}` blocks
9. **Research before using unfamiliar APIs** — Read the docs first
10. **Cross-platform compatibility** — Data formats in `core/` must stay compatible with iOS/watchOS/macOS

### Android-specific conventions

- **Compose-first UI** — All screens are `@Composable` functions, no XML layouts
- **Hilt for DI** — Use `@HiltViewModel`, `@Inject`, and Hilt modules; avoid manual singleton patterns
- **StateFlow for state** — ViewModels expose `StateFlow<UiState>` collected by Compose screens
- **Room for structured data** — Use Room DAOs for SQLite tables with typed entities
- **Raw SQLite for MBTiles/routing** — These use direct `SQLiteDatabase` for compatibility with the cross-platform schema
- **kotlinx.serialization** — Prefer over Gson/Moshi for JSON; annotate data classes with `@Serializable`

## Where to Start

### Fixing a bug

1. Identify the screen where the bug occurs
2. Find the corresponding `*Screen.kt` in `ui/` and trace to its `*ViewModel.kt`
3. Follow the data flow: ViewModel → Repository → Database/Service
4. Check if the issue is in `core/` (algorithm/model) or `app/` (Android-specific)

### Adding a feature

1. Read the [roadmap](../planning/roadmap.md) and [Android implementation plan](../planning/android_implementation_plan.md)
2. Follow existing patterns:
   - **Models** → `core/src/main/kotlin/.../model/`
   - **Algorithm/logic** → `core/src/main/kotlin/.../` (appropriate package)
   - **Database** → `app/.../data/db/`
   - **Repository** → `app/.../data/repository/`
   - **Service** → `app/.../service/`
   - **UI** → `app/.../ui/` (Screen + ViewModel)
   - **DI binding** → `app/.../di/` (add `@Provides` or `@Binds` to the appropriate module)
3. Register new Hilt modules or Room DAOs in the DI layer
4. Add unit tests for new public APIs

### Exploring the codebase

Start with these files to understand the core flow:

| File | Why |
|------|-----|
| `app/.../MainActivity.kt` | Single-activity entry point |
| `app/.../OpenHikerApp.kt` | Application class, MapLibre init, Hilt + WorkManager setup |
| `app/.../ui/navigation/AppNavigation.kt` | Full navigation graph (all routes and screens) |
| `app/.../ui/map/MapScreen.kt` | Main map display (MapLibre, offline tiles, GPS overlay) |
| `app/.../service/download/TileDownloadService.kt` | How tiles are fetched and stored |
| `app/.../service/location/LocationProvider.kt` | GPS tracking with compass and distance filtering |
| `app/.../service/location/HikeTrackingService.kt` | Foreground service for background GPS |
| `app/.../data/db/tiles/TileStore.kt` | Read-only MBTiles access (TMS Y-flip) |
| `app/.../ui/routing/RoutePlanningScreen.kt` | Route planning UI |
| `app/.../service/navigation/NavigationService.kt` | Turn-by-turn navigation with audio cues |
| `core/.../routing/AStarRouter.kt` | A* pathfinding algorithm |
| `core/.../geo/GeoUtils.kt` | Haversine distance, bearing, coordinate math |
| `core/.../model/` | All shared data classes |

## Permissions

The app declares these permissions in `AndroidManifest.xml`:

| Permission | When used |
|-----------|-----------|
| `INTERNET` | Downloading map tiles and OSM trail data |
| `ACCESS_NETWORK_STATE` | Checking connectivity before downloads |
| `ACCESS_FINE_LOCATION` | GPS tracking on the map |
| `ACCESS_COARSE_LOCATION` | Fallback location |
| `ACCESS_BACKGROUND_LOCATION` | GPS during active hike recording (foreground service) |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION` | Persistent hike tracking notification |
| `VIBRATE` | Haptic feedback for navigation cues |
| `POST_NOTIFICATIONS` | Hike tracking notification (Android 13+) |

No analytics, advertising, or data-collection permissions are used. Location data never leaves the device.

## Further Reading

- [iOS/watchOS/macOS Quickstart](QUICKSTART.md) — Apple platform development guide
- [Android Implementation Plan](../planning/android_implementation_plan.md) — Detailed 5-phase implementation plan
- [Feature Roadmap](../planning/roadmap.md) — What's done and what's next
- [Routing Engine](routing-engine.md) — A* routing engine internals (shared algorithm)
- [Peer-to-Peer Sharing](peer-to-peer-sharing.md) — MultipeerConnectivity region & route transfer (iOS/macOS)
- [General Golden Rules](../llm/general_golden_rules.md) — Full coding conventions

## License

OpenHiker is licensed under **AGPL-3.0**. All contributions must be compatible with this license.
