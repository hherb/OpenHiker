# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OpenHiker is a dual-platform iOS/watchOS app for offline hiking navigation on Apple Watch using free OpenTopoMap tiles. The iOS companion app downloads map regions and transfers them to the watch via WatchConnectivity. The watch app renders maps offline using SpriteKit with GPS tracking.

**License:** AGPL-3.0

## Build Commands

Build iOS app:
```bash
xcodebuild -scheme "OpenHiker" -destination "platform=iOS Simulator,name=iPhone 15 Pro"
```

Build watchOS app:
```bash
xcodebuild -scheme "OpenHiker Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)"
```

The project has two Xcode targets (`OpenHiker` and `OpenHiker Watch App`) with corresponding schemes. There are no third-party dependencies — only Apple frameworks and the system SQLite3 library.

## Architecture

### Platform Split

- **`Shared/`** — Code compiled into both targets
  - `Models/` — `Region`, `TileCoordinate`, `RegionMetadata` data types
  - `Storage/` — `TileStore` (read-only) and `WritableTileStore` for MBTiles SQLite access
- **`OpenHiker iOS/`** — iPhone companion app
  - `App/` — `OpenHikerApp` entry point, `ContentView` (TabView with 3 tabs)
  - `Views/` — `RegionSelectorView` (MapKit-based region selection)
  - `Services/` — `TileDownloader` (actor), `RegionStorage`, `WatchTransferManager`
- **`OpenHiker watchOS/`** — Apple Watch standalone app
  - `App/` — `OpenHikerWatchApp` entry point, `WatchContentView` (TabView with 3 tabs)
  - `Views/` — `MapView` (SpriteKit-based map display)
  - `Services/` — `MapRenderer` (SpriteKit tile rendering), `LocationManager` (GPS/heading)

### Key Data Flow

1. iOS: User selects region → `TileDownloader` (actor) fetches tiles from OpenTopoMap → writes to MBTiles via `WritableTileStore`
2. iOS: `WatchTransferManager` sends `.mbtiles` file to watch via `WCSession.transferFile()`
3. Watch: `WatchConnectivityReceiver` receives file → saves to `Documents/regions/` → persists `RegionMetadata` as JSON
4. Watch: `MapRenderer` opens `TileStore` (read-only SQLite) → `MapScene` (SpriteKit) renders tiles with GPS overlay

### Important Technical Details

- **MBTiles uses TMS Y-coordinate flipping** — the Y coordinate is inverted (`(2^zoom - 1) - y`) compared to web mercator (slippy map) convention. This conversion is in `TileStore`.
- **`TileDownloader` is a Swift Actor** for thread-safe concurrent downloads with rate limiting (100ms per tile to respect OSM tile usage policy).
- **SpriteKit is used for watch map rendering** instead of SwiftUI — it handles dynamic tile positioning and zoom more efficiently on watchOS.
- **Cross-platform conditional imports** — `TileStore.swift` uses `#if canImport(UIKit)` / `#elseif canImport(WatchKit)` for platform-specific image types.
- **Singletons for connectivity** — `WatchConnectivityManager.shared` (iOS) and `WatchConnectivityReceiver.shared` (watchOS) are injected as `@EnvironmentObject`.
- **State persistence** — Region metadata as JSON files in Documents, tile data as MBTiles (SQLite), user preferences via `@AppStorage`.

## Development Rules (from docs/llm/general_golden_rules.md)

1. Clean separation of concerns in modules
2. Prefer reusable pure functions over complex classes
3. All functions/classes/methods need doc strings (junior-dev friendly)
4. No magic numbers — use settings/configurations
5. All public functions need unit tests
6. Never truncate data unless explicitly approved
7. Network calls need retry with exponential backoff
8. All errors must be handled, logged, and reported to the user
9. Research unfamiliar library APIs before use
10. Keep cross-platform compatibility in mind

# External API and library documentation
Always use Context7 MCP when I need library/API documentation, code generation, setup or configuration steps without me having to explicitly ask.
