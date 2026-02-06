# OpenHiker Project Memory

## Project Structure
- Dual-platform: iOS companion + standalone watchOS app
- `Shared/` compiled into both targets (models, storage)
- watchOS uses SpriteKit for map rendering (not SwiftUI)
- No third-party dependencies; Apple frameworks + SQLite3 only
- AGPL-3.0 license; all files need copyright header

## Key Patterns
- **Models**: `Codable + Sendable + Identifiable` convention
- **SQLite pattern**: `TileStore` and `WaypointStore` both use `@unchecked Sendable` + `DispatchQueue(label:)` serial queue + `queue.sync {}` for thread safety
- **Singleton pattern**: `WatchConnectivityManager.shared`, `RegionStorage.shared`, `WatchConnectivityReceiver.shared`, `WaypointStore.shared`
- **Environment injection**: Singletons injected via `@StateObject` in App entry point -> `.environmentObject()` -> `@EnvironmentObject` in views
- **WatchConnectivity**: `transferFile` for large data (MBTiles), `transferUserInfo` for small data (waypoints), `updateApplicationContext` for state
- **Platform guards**: iOS files use `#if os(iOS)`, watchOS files don't need guards (separate target)
- **MBTiles Y-flip**: TMS convention uses inverted Y: `tmsY = (2^z - 1) - y`
- **AGPL header**: All files start with the AGPL-3.0 copyright block
- `@AppStorage` for user preferences
- Thread safety: serial DispatchQueues for SQLite, HKHealthStore is thread-safe
- `sqlite3_bind_text` uses `unsafeBitCast(-1, to: sqlite3_destructor_type.self)` for SQLITE_TRANSIENT

## Xcode Project (pbxproj)
- ID format: `2A...` for iOS file refs, `2B...` for watchOS, `1A...` for iOS build files, `1B...` for watchOS
- Shared files need build file entries in BOTH targets (different IDs, same file ref)
- Groups: `5A...` iOS, `5B...` watchOS, `5C...` Shared
- watchOS target: `6B0000010000000000000001`
- iOS target: `6A0000010000000000000001`

## Key Files
- `Shared/Models/`: Region.swift, TileCoordinate.swift, HikeStatistics.swift, Waypoint.swift
- `Shared/Storage/`: TileStore.swift (+ WritableTileStore), WaypointStore.swift
- SpriteKit map: `MapRenderer.swift` manages `MapScene` (SKScene with tilesNode + overlaysNode)

## Phase Status
- Phase 1 (Hike Metrics + HealthKit): Completed and merged
- Phase 2 (Waypoints & Pins): Implemented on `claude/implement-phase2-waypoints-soKPD`
- Phase 3+ (Route Import, Offline Search): Not started

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
