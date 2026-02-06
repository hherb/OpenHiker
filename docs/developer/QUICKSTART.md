# Developer Quickstart

Welcome to OpenHiker! This guide will get you building, running, and contributing as quickly as possible.

## Prerequisites

| Requirement | Minimum Version |
|-------------|-----------------|
| macOS | Ventura 13.0+ |
| Xcode | 15.0+ |
| iOS deployment target | 17.0 |
| watchOS deployment target | 10.0 |

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
2. Select the **OpenHiker** scheme for the iOS app, or **OpenHiker Watch App** for watchOS
3. Choose a simulator and press **Cmd+R**

> **Tip:** To test the full iOS ↔ Watch data flow, run both simulators side by side. The iOS simulator can transfer files to the paired Watch simulator via WatchConnectivity.

## Project Structure

```
OpenHiker/
├── Shared/                  ← Code compiled into BOTH targets
│   ├── Models/              ← Data types (Region, Waypoint, SavedRoute, etc.)
│   ├── Storage/             ← SQLite stores (TileStore, WaypointStore, RouteStore)
│   └── Utilities/           ← Pure functions (TrackCompression)
│
├── OpenHiker iOS/           ← iPhone companion app
│   ├── App/                 ← Entry point (OpenHikerApp) + root ContentView
│   ├── Views/               ← SwiftUI views (region selector, waypoints, hike review)
│   └── Services/            ← TileDownloader (actor), WatchTransferManager, RegionStorage
│
├── OpenHiker watchOS/       ← Apple Watch standalone app
│   ├── App/                 ← Entry point (OpenHikerWatchApp) + WatchContentView
│   ├── Views/               ← MapView (SpriteKit), stats overlay, waypoint/save sheets
│   └── Services/            ← MapRenderer, LocationManager, HealthKitManager
│
└── docs/
    ├── developer/           ← Implementation guides (you are here)
    └── planning/            ← Feature specs and roadmap
```

### Two targets, one Xcode project

| Target | Scheme | What it does |
|--------|--------|-------------|
| **OpenHiker** | `OpenHiker` | iPhone app — downloads map tiles, manages regions, reviews past hikes |
| **OpenHiker Watch App** | `OpenHiker Watch App` | Apple Watch app — offline map display, GPS tracking, live stats |

Files in `Shared/` are compiled into both targets. Platform-specific code uses conditional imports:

```swift
#if canImport(UIKit)
    // iOS code (UIImage, etc.)
#elseif canImport(WatchKit)
    // watchOS code
#endif
```

## Architecture Overview

### Data Flow

```
┌──────────────────────┐                    ┌──────────────────────┐
│      iOS App         │   WatchConnectivity│     Watch App        │
│                      │   ────────────────►│                      │
│ RegionSelectorView   │   .mbtiles files   │ MapView (SpriteKit)  │
│   ↓                  │   waypoints (JSON) │   ↑                  │
│ TileDownloader       │   routes (JSON)    │ MapRenderer          │
│   ↓                  │                    │   ↑                  │
│ WritableTileStore    │                    │ TileStore (read-only) │
│   ↓                  │                    │                      │
│ WatchTransferManager │◄───────────────────│ WatchConnectivity-   │
│                      │   waypoints back   │ Receiver             │
└──────────────────────┘                    └──────────────────────┘
```

1. **iOS downloads tiles** → `TileDownloader` (Swift Actor) fetches from OpenTopoMap → writes to MBTiles via `WritableTileStore`
2. **iOS transfers to watch** → `WatchTransferManager` sends `.mbtiles` file via `WCSession.transferFile()`
3. **Watch receives & stores** → `WatchConnectivityReceiver` saves to `Documents/regions/`
4. **Watch renders offline** → `MapRenderer` opens `TileStore` (read-only SQLite) → SpriteKit renders tiles with GPS overlay

### Key Singletons

| Singleton | Platform | Purpose |
|-----------|----------|---------|
| `WatchConnectivityManager.shared` | iOS | Sends files/messages to the watch |
| `WatchConnectivityReceiver.shared` | watchOS | Receives files/messages from iOS |
| `WaypointStore.shared` | Both | SQLite CRUD for waypoints |
| `RouteStore.shared` | Both | SQLite CRUD for saved hikes |
| `RegionStorage.shared` | iOS | Manages downloaded region metadata |

These are injected as `@StateObject` / `@EnvironmentObject` at the app entry point.

### Storage Layout

**iOS** (`Documents/`):
```
regions/
  <uuid>.mbtiles          ← Downloaded tile databases
regions_metadata.json      ← Region list (JSON)
waypoints.db               ← Waypoint SQLite database
routes.db                  ← Saved routes SQLite database
```

**watchOS** (`Documents/`):
```
regions/
  <uuid>.mbtiles          ← Transferred tile databases
regions_metadata.json      ← Region list (JSON)
waypoints.db               ← Waypoint SQLite database
routes.db                  ← Saved routes SQLite database
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

### WatchConnectivity delivery guarantees

| Method | Guarantee | Used for |
|--------|-----------|----------|
| `transferFile()` | Queued, survives app termination | MBTiles, route files |
| `transferUserInfo()` | Queued, reliable delivery | Waypoint sync |
| `updateApplicationContext()` | Latest-value-wins, no queue | Region list updates |
| `sendMessage()` | Immediate, requires reachable counterpart | On-demand requests |

## Required Capabilities & Permissions

### watchOS

The watch app declares these in `Info.plist` and the entitlements file:

- **Location** (always + when-in-use) — GPS tracking and map positioning
- **HealthKit** — Heart rate, SpO2, workout recording
- **Background modes** — `location` (background GPS), `workout-processing` (HealthKit sessions)

### iOS

- **Location** (when-in-use) — Map display and tile downloading context

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
10. **Cross-platform compatibility** — Code in `Shared/` must work on both iOS and watchOS

### Model conventions

All shared models conform to `Codable`, `Sendable`, and `Identifiable`. Use value types (`struct`) unless you have a strong reason for a class.

## Where to Start

### Fixing a bug

1. Identify whether it's an iOS or watchOS issue (or shared code)
2. Trace the data flow from the relevant view → service → store
3. Check the existing developer guides in `docs/developer/` for context on the feature area

### Adding a feature

1. Read the [roadmap](../planning/roadmap.md) — your feature may already be planned with a spec
2. Check the phase planning docs in `docs/planning/` for detailed requirements
3. Follow the existing patterns: models in `Shared/Models/`, stores in `Shared/Storage/`, views and services in the platform-specific directories

### Exploring the codebase

Start with these files to understand the core flow:

| File | Why |
|------|-----|
| `OpenHiker iOS/App/ContentView.swift` | iOS tab structure and navigation |
| `OpenHiker watchOS/App/WatchContentView.swift` | Watch tab structure |
| `OpenHiker watchOS/Views/MapView.swift` | How the offline map is displayed |
| `OpenHiker watchOS/Services/LocationManager.swift` | GPS tracking, track recording, live stats |
| `OpenHiker iOS/Services/TileDownloader.swift` | How tiles are fetched and stored |
| `Shared/Storage/TileStore.swift` | The SQLite pattern all stores follow |

## Further Reading

- [Feature Roadmap](../planning/roadmap.md) — What's done and what's next
- [Phase 1: Hike Metrics & HealthKit](hike-metrics-healthkit.md) — HealthKit integration details
- [Phase 2: Waypoints Developer Guide](phase2-waypoints-developer-guide.md) — Waypoint system architecture
- [Phase 3: Save Routes Developer Guide](phase3-save-routes-developer-guide.md) — Route persistence and hike review

## CI

GitHub Actions workflows run on push to `main` and on pull requests:

- **ios.yml** — Builds and tests the iOS target on `macos-latest`
- **codeql.yml** — CodeQL security analysis

## License

OpenHiker is licensed under **AGPL-3.0**. All contributions must be compatible with this license.
