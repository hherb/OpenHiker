# Developer Quickstart

Welcome to OpenHiker! This guide will get you building, running, and contributing as quickly as possible.

## Prerequisites

| Requirement | Minimum Version |
|-------------|-----------------|
| macOS | Ventura 13.0+ |
| Xcode | 15.0+ |
| iOS deployment target | 17.0 |
| watchOS deployment target | 10.0 |
| macOS deployment target | 14.0 |

No third-party dependencies — the project uses only Apple frameworks and the system SQLite3 library, so there's nothing to install beyond Xcode.

## Clone & Build

```bash
git clone https://github.com/hherb/OpenHiker.git
cd OpenHiker
open OpenHiker.xcodeproj
```

### Build from the command line

```bash
# iOS (iPhone simulator)
xcodebuild -scheme "OpenHiker" -destination "platform=iOS Simulator,name=iPhone 15 Pro"

# watchOS (Apple Watch simulator)
xcodebuild -scheme "OpenHiker Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)"
```

### Run in Xcode

1. Open `OpenHiker.xcodeproj`
2. Select the **OpenHiker** scheme for the iOS app, **OpenHiker Watch App** for watchOS, or the macOS scheme for Mac
3. Choose a simulator (or "My Mac" for macOS) and press **Cmd+R**

> **Tip:** To test the full iOS ↔ Watch data flow, run both simulators side by side. The iOS simulator can transfer files to the paired Watch simulator via WatchConnectivity.

## Project Structure

```
OpenHiker/
├── Shared/                  ← Code compiled into ALL targets (iOS, watchOS, macOS)
│   ├── Models/              ← Data types (Region, Waypoint, SavedRoute, PlannedRoute, RoutingGraph, etc.)
│   ├── Storage/             ← SQLite stores (TileStore, WaypointStore, RouteStore, RoutingStore)
│   ├── Services/            ← Shared business logic (RoutingEngine, CloudSyncManager, GitHubRouteService, etc.)
│   └── Utilities/           ← Pure functions (TrackCompression, RouteExporter, PhotoCompressor)
│
├── OpenHiker iOS/           ← iPhone & iPad companion app
│   ├── App/                 ← Entry point (OpenHikerApp) + root ContentView (adaptive TabView / NavigationSplitView)
│   ├── Views/               ← SwiftUI views (region selector, route planning, hike review, community, export, waypoints)
│   └── Services/            ← TileDownloader (actor), WatchTransferManager, RegionStorage, OSMDataDownloader,
│                              PBFParser, ProtobufReader, RoutingGraphBuilder, ElevationDataManager, PDFExporter
│
├── OpenHiker watchOS/       ← Apple Watch standalone app
│   ├── App/                 ← Entry point (OpenHikerWatchApp) + WatchContentView (4-tab vertically-paged interface)
│   ├── Views/               ← MapView (SpriteKit), stats overlay, navigation overlay, waypoint/save sheets
│   └── Services/            ← MapRenderer, LocationManager, HealthKitManager, RouteGuidance
│
├── OpenHiker macOS/         ← Native macOS planning & review app
│   ├── App/                 ← Entry point (OpenHikerMacApp) + MacContentView (NavigationSplitView sidebar)
│   ├── Views/               ← Hikes, waypoints, planned routes, community, settings views
│   └── Services/            ← MacPDFExporter
│
└── docs/
    ├── developer/           ← Implementation guides (you are here)
    └── planning/            ← Feature specs and roadmap
```

### Targets and schemes

| Target | Scheme | What it does |
|--------|--------|-------------|
| **OpenHiker** | `OpenHiker` | iPhone/iPad app — downloads map tiles, manages regions, plans routes, reviews past hikes, community |
| **OpenHiker Watch App** | `OpenHiker Watch App` | Apple Watch app — offline map display, GPS tracking, live stats, turn-by-turn guidance |
| **OpenHiker macOS** | `OpenHiker macOS` | Mac app — hike review hub, waypoint browser, planned routes, community, iCloud sync |

Files in `Shared/` are compiled into all targets. Platform-specific code uses conditional imports:

```swift
#if canImport(UIKit)
    // iOS code (UIImage, etc.)
#elseif canImport(WatchKit)
    // watchOS code
#elseif canImport(AppKit)
    // macOS code
#endif
```

## Architecture Overview

### Data Flow

```
┌──────────────────────┐                    ┌──────────────────────┐
│      iOS App         │   WatchConnectivity│     Watch App        │
│                      │   ────────────────►│                      │
│ RegionSelectorView   │   .mbtiles files   │ MapView (SpriteKit)  │
│   ↓                  │   planned routes   │   ↑                  │
│ TileDownloader       │   waypoints (JSON) │ MapRenderer          │
│   ↓                  │                    │   ↑                  │
│ WritableTileStore    │                    │ TileStore (read-only) │
│   ↓                  │                    │                      │
│ WatchTransferManager │◄───────────────────│ WatchConnectivity-   │
│                      │   waypoints back   │ Receiver             │
└──────────┬───────────┘                    └──────────────────────┘
           │
           │ iCloud (CloudKit)
           ▼
┌──────────────────────┐
│      Mac App         │
│                      │
│ MacHikesView         │
│ MacWaypointsView     │
│ MacPlannedRoutesView │
│ MacCommunityView     │
└──────────────────────┘
```

1. **iOS downloads tiles** → `TileDownloader` (Swift Actor) fetches from OpenTopoMap → writes to MBTiles via `WritableTileStore`
2. **iOS builds routing graphs** → `OSMDataDownloader` fetches PBF data → `RoutingGraphBuilder` builds graph → `RoutingStore` persists
3. **iOS plans routes** → `RoutingEngine` computes A* paths → `PlannedRouteStore` saves planned routes
4. **iOS transfers to watch** → `WatchTransferManager` sends `.mbtiles`, planned routes, and waypoints via `WCSession.transferFile()`
5. **Watch receives & stores** → `WatchConnectivityReceiver` saves to `Documents/regions/`
6. **Watch renders offline** → `MapRenderer` opens `TileStore` (read-only SQLite) → SpriteKit renders tiles with GPS overlay
7. **Watch provides guidance** → `RouteGuidance` delivers turn-by-turn instructions with `NavigationOverlay` and haptic feedback
8. **iCloud syncs across devices** → `CloudSyncManager` + `CloudKitStore` sync routes, waypoints, and regions to Mac and other devices

### iOS Tab Structure (iPhone)

The iPhone app uses a `TabView` with six tabs:

| Tab | View | Purpose |
|-----|------|---------|
| Regions | `RegionSelectorView` | Browse map, select & download regions |
| Downloaded | `RegionsListView` | Manage downloaded regions, transfer to watch |
| Hikes | `HikesListView` | Browse saved hike history |
| Routes | `PlannedRoutesListView` | Plan routes, manage planned routes |
| Community | `CommunityBrowseView` | Browse & download shared routes |
| Watch | `WatchSyncView` | Watch connectivity status & transfers |

On iPad, the app switches to a `NavigationSplitView` with a persistent sidebar (plus a dedicated Waypoints section).

### watchOS Tab Structure

The watch app uses a vertically-paged `TabView` with four tabs:

| Tab | View | Purpose |
|-----|------|---------|
| Map | `MapView` | SpriteKit offline map with GPS overlay |
| Routes | `WatchPlannedRoutesView` | Select a planned route to start navigation |
| Regions | `RegionsListView` | Available offline map regions |
| Settings | `SettingsView` | GPS mode, units, HealthKit, display prefs |

### macOS Sidebar Structure

The Mac app uses a `NavigationSplitView` with four sidebar sections:

| Section | View | Purpose |
|---------|------|---------|
| Hikes | `MacHikesView` | Hike history browser |
| Waypoints | `MacWaypointsView` | Waypoints table view |
| Planned Routes | `MacPlannedRoutesView` | Planned routes list |
| Community | `MacCommunityView` | Community route browser |

### Key Singletons

| Singleton | Platform | Purpose |
|-----------|----------|---------|
| `WatchConnectivityManager.shared` | iOS | Sends files/messages to the watch |
| `WatchConnectivityReceiver.shared` | watchOS | Receives files/messages from iOS |
| `WaypointStore.shared` | All | SQLite CRUD for waypoints |
| `RouteStore.shared` | All | SQLite CRUD for saved hikes |
| `RoutingStore.shared` | All | SQLite CRUD for routing graphs |
| `PlannedRouteStore.shared` | All | SQLite CRUD for planned routes |
| `RegionStorage.shared` | iOS | Manages downloaded region metadata |
| `CloudSyncManager.shared` | iOS, macOS | iCloud sync coordination |

These are injected as `@StateObject` / `@EnvironmentObject` at the app entry point.

### Storage Layout

**iOS** (`Documents/`):
```
regions/
  <uuid>.mbtiles          ← Downloaded tile databases
  <uuid>.routing.db       ← Routing graph databases
regions_metadata.json      ← Region list (JSON)
waypoints.db               ← Waypoint SQLite database
routes.db                  ← Saved routes SQLite database
planned_routes/            ← Planned route JSON files
```

**watchOS** (`Documents/`):
```
regions/
  <uuid>.mbtiles          ← Transferred tile databases
regions_metadata.json      ← Region list (JSON)
waypoints.db               ← Waypoint SQLite database
routes.db                  ← Saved routes SQLite database
planned_routes/            ← Planned route JSON files
```

### SQLite Pattern

All stores follow the same pattern established in `TileStore.swift`:

- Serial `DispatchQueue` for thread safety
- Direct SQLite3 C API (no ORM)
- `@unchecked Sendable` conformance
- Explicit `open()` / `close()` lifecycle
- Errors surfaced as typed enums, never silently swallowed

## Important Technical Gotchas

### MBTiles Y-coordinate flipping

MBTiles uses the TMS convention where Y is inverted compared to web mercator (slippy map / XYZ):

```swift
let tmsY = (1 << zoom) - 1 - slippyY   // (2^zoom - 1) - y
```

This conversion lives in `TileStore`. If you're working with tile coordinates, be aware of which convention you're using.

### SpriteKit for watch map rendering

The watch map is rendered with **SpriteKit** (`MapScene`), not SwiftUI. This is intentional — SpriteKit handles dynamic tile positioning and zoom far more efficiently on watchOS. The bridge between SwiftUI and SpriteKit is in `MapView.swift` (via `SpriteView`).

### TileDownloader is a Swift Actor

`TileDownloader` uses Swift's `actor` isolation for thread-safe concurrent downloads. It rate-limits requests to **100ms per tile** to respect the [OSM tile usage policy](https://operations.osmfoundation.org/policies/tiles/). Don't bypass this.

### OSM PBF parsing pipeline

The routing data pipeline works as follows:
1. `OSMDataDownloader` fetches regional `.osm.pbf` extracts from Geofabrik
2. `ProtobufReader` provides low-level Protocol Buffer decoding
3. `PBFParser` extracts trail/path ways and nodes from the PBF data
4. `RoutingGraphBuilder` constructs the routing graph with edge weights based on Naismith's rule
5. `ElevationDataManager` provides Copernicus DEM elevation data for cost calculations
6. `RoutingStore` persists the graph as a compact SQLite database

### Routing engine

`RoutingEngine` implements A* pathfinding with a hiking/cycling cost function:
- Surface type penalties (paved vs. gravel vs. trail)
- Slope-based cost using Naismith's rule
- Activity type support (`ActivityType`: hiking vs. cycling)
- Turn instruction generation (`TurnInstruction`)

### WatchConnectivity delivery guarantees

| Method | Guarantee | Used for |
|--------|-----------|----------|
| `transferFile()` | Queued, survives app termination | MBTiles, routing databases, planned routes |
| `transferUserInfo()` | Queued, reliable delivery | Waypoint sync |
| `updateApplicationContext()` | Latest-value-wins, no queue | Region list updates |
| `sendMessage()` | Immediate, requires reachable counterpart | On-demand requests |

### iCloud sync

`CloudSyncManager` coordinates sync between devices using `CloudKitStore` for CloudKit operations. Routes, waypoints, and region metadata sync across iOS and macOS devices. The Mac app shows sync status in its sidebar.

## Required Capabilities & Permissions

### watchOS

The watch app declares these in `Info.plist` and the entitlements file:

- **Location** (always + when-in-use) — GPS tracking and map positioning
- **HealthKit** — Heart rate, SpO2, workout recording
- **Background modes** — `location` (background GPS), `workout-processing` (HealthKit sessions)

### iOS

- **Location** (when-in-use) — Map display and tile downloading context
- **iCloud** — CloudKit container for cross-device sync

### macOS

- **iCloud** — CloudKit container for cross-device sync

## Coding Conventions

These are enforced across the project (see [general_golden_rules.md](../llm/general_golden_rules.md)):

1. **Separation of concerns** — Models, Storage, Services, and Views are distinct layers
2. **Pure functions over complex classes** — Extract logic into testable free functions where possible
3. **Doc strings on everything** — Write them so a junior developer can understand the purpose and flow
4. **No magic numbers** — Use named constants or configuration values
5. **Unit tests for public APIs** — (Note: test coverage is still being built out)
6. **Never truncate data** — Don't silently drop records or shorten collections
7. **Retry with exponential backoff** — All network calls must handle transient failures
8. **Handle all errors** — Log them and surface to the user; no silent `catch {}`
9. **Research before using unfamiliar APIs** — Don't guess; read the docs first
10. **Cross-platform compatibility** — Code in `Shared/` must work on iOS, watchOS, and macOS

### Model conventions

All shared models conform to `Codable`, `Sendable`, and `Identifiable`. Use value types (`struct`) unless you have a strong reason for a class.

## Where to Start

### Fixing a bug

1. Identify whether it's an iOS, watchOS, macOS, or shared code issue
2. Trace the data flow from the relevant view → service → store
3. Check the existing developer guides in `docs/developer/` for context on the feature area

### Adding a feature

1. Read the [roadmap](../planning/roadmap.md) — your feature may already be planned with a spec
2. Check the phase planning docs in `docs/planning/` for detailed requirements
3. Follow the existing patterns: models in `Shared/Models/`, stores in `Shared/Storage/`, services in `Shared/Services/`, views in the platform-specific directories

### Exploring the codebase

Start with these files to understand the core flow:

| File | Why |
|------|-----|
| `OpenHiker iOS/App/ContentView.swift` | iOS adaptive layout (iPhone tabs / iPad sidebar) |
| `OpenHiker watchOS/App/WatchContentView.swift` | Watch 4-tab structure |
| `OpenHiker macOS/App/MacContentView.swift` | Mac sidebar structure |
| `OpenHiker watchOS/Views/MapView.swift` | How the offline map is displayed |
| `OpenHiker watchOS/Services/LocationManager.swift` | GPS tracking, track recording, live stats |
| `OpenHiker watchOS/Services/RouteGuidance.swift` | Turn-by-turn navigation engine |
| `OpenHiker iOS/Services/TileDownloader.swift` | How tiles are fetched and stored |
| `OpenHiker iOS/Views/RoutePlanningView.swift` | Route planning UI with A* |
| `Shared/Services/RoutingEngine.swift` | The A* pathfinding implementation |
| `Shared/Storage/TileStore.swift` | The SQLite pattern all stores follow |

## Further Reading

- [Feature Roadmap](../planning/roadmap.md) — What's done and what's next
- [Phase 1: Hike Metrics & HealthKit](hike-metrics-healthkit.md) — HealthKit integration details
- [Phase 2: Waypoints Developer Guide](phase2-waypoints-developer-guide.md) — Waypoint system architecture
- [Phase 3: Save Routes Developer Guide](phase3-save-routes-developer-guide.md) — Route persistence and hike review
- [Phase 5: Route Planning & Guidance](phase5-route-planning-guidance.md) — Route planning and turn-by-turn guidance
- [Phase 6: Multi-Platform & Export](phase6-multiplatform-export-developer-guide.md) — macOS, iPad, PDF/Markdown export
- [Routing Engine](routing-engine.md) — A* routing engine internals

## CI

GitHub Actions workflows run on push to `main` and on pull requests:

- **ios.yml** — Builds and tests the iOS target on `macos-latest`
- **swift.yml** — Swift build and test workflow
- **codeql.yml** — CodeQL security analysis

## License

OpenHiker is licensed under **AGPL-3.0**. All contributions must be compatible with this license.
