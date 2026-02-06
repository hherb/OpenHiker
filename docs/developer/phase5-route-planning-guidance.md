# Phase 5: Route Planning & Active Guidance — Developer Guide

**Last updated:** 2026-02-06

This guide covers the route planning (iOS) and turn-by-turn navigation (watchOS) features added in Phase 5. It explains the architecture, data flow, file layout, key algorithms, and how to modify or debug each component.

---

## Architecture Overview

```
┌────────────────────────── iOS (route planning) ────────────────────────────┐
│                                                                             │
│  RoutePlanningView (MapKit)                                                 │
│       │ tap to place start/end/via pins                                     │
│       ▼                                                                     │
│  RoutingEngine.findRoute() ──► ComputedRoute                               │
│       │                                                                     │
│       ▼                                                                     │
│  TurnInstructionGenerator.generate() ──► [TurnInstruction]                 │
│       │                                                                     │
│       ▼                                                                     │
│  PlannedRoute.from(computedRoute:) ──► PlannedRouteStore (JSON files)      │
│       │                                                                     │
│       ▼                                                                     │
│  WatchTransferManager.sendPlannedRouteToWatch() ──► WCSession.transferFile │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────── watchOS (active guidance) ─────────────────┐
│                                                             │
│  WatchConnectivityReceiver                                  │
│       │ receives planned route JSON                         │
│       ▼                                                     │
│  PlannedRouteStore (JSON files)                             │
│       │                                                     │
│       ▼                                                     │
│  WatchPlannedRoutesView                                     │
│       │ user taps route to navigate                         │
│       ▼                                                     │
│  RouteGuidance.start(route:)                                │
│       │ feeds from LocationManager                          │
│       │                                                     │
│       ├──► NavigationOverlay (SwiftUI on map)               │
│       ├──► MapScene.updateRouteLine() (SpriteKit polyline)  │
│       └──► WKHapticType haptics at turns and off-route      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Files and Responsibilities

### New Files

#### Shared (both platforms)

| File | What it does |
|------|-------------|
| `Shared/Models/TurnInstruction.swift` | `TurnDirection` enum (start, straight, left, right, sharp, u-turn, arrive), `TurnInstruction` struct, `BearingCalculator` (bearing math, cardinal directions), `TurnInstructionConfig` (angle thresholds), `TurnInstructionGenerator` (generates instructions from a `ComputedRoute`). |
| `Shared/Models/PlannedRoute.swift` | `PlannedRoute` model (coordinates + instructions + stats), `PlannedRouteStore` (JSON file persistence), `.plannedRouteSyncReceived` notification. |

#### iOS only

| File | What it does |
|------|-------------|
| `OpenHiker iOS/Views/RoutePlanningView.swift` | Interactive MapKit view for placing start/end/via pins, computing routes, and saving planned routes. Includes `RouteAnnotation` and `StatItem` helper types. |
| `OpenHiker iOS/Views/RouteDetailView.swift` | Read-only detail view of a saved planned route with map, stats, directions list, and "Send to Watch" button. |

#### watchOS only

| File | What it does |
|------|-------------|
| `OpenHiker watchOS/Services/RouteGuidance.swift` | Main navigation engine. Tracks position along polyline, advances turn instructions, detects off-route, triggers haptics. `RouteGuidanceConfig` holds all thresholds. |
| `OpenHiker watchOS/Views/NavigationOverlay.swift` | SwiftUI overlay on the map showing current instruction, distance to next turn, progress bar, and off-route warning. |

### Modified Files

| File | Changes |
|------|---------|
| `OpenHiker iOS/App/ContentView.swift` | Added `PlannedRoutesListView` tab (tag 3), shifted Community and Watch tabs to 4 and 5. |
| `OpenHiker iOS/App/OpenHikerApp.swift` | Added `initializePlannedRouteStore()` call on app launch. |
| `OpenHiker iOS/Services/RegionStorage.swift` | Added `routingDbURL(for:)` method. |
| `OpenHiker iOS/Services/WatchTransferManager.swift` | Added `sendPlannedRouteToWatch(fileURL:route:)` method. |
| `OpenHiker watchOS/App/OpenHikerWatchApp.swift` | Added `RouteGuidance` as `@StateObject`, injected as environment object. Added `initializePlannedRouteStore()`. Added `"plannedRoute"` case to file reception switch. Added `handleReceivedPlannedRoute()`. |
| `OpenHiker watchOS/App/WatchContentView.swift` | Added `WatchPlannedRoutesView` tab (tag 1), shifted Regions and Settings to tags 2 and 3. Added `RouteGuidance` environment object. |
| `OpenHiker watchOS/Services/MapRenderer.swift` | Added `routeNode` property to `MapScene`. Added `updateRouteLine(coordinates:)` and `clearRouteLine()` methods for purple route polyline (z=40). |
| `OpenHiker watchOS/Views/MapView.swift` | Added `RouteGuidance` environment object. Added `NavigationOverlay`. Added `refreshRouteLine()`. Feeds GPS updates to `routeGuidance.updateLocation()`. |

---

## Data Flow: End to End

### 1. Route Creation (iOS)

1. User opens "Routes" tab → `PlannedRoutesListView` → taps "+"
2. If multiple regions have routing data, a picker appears
3. `RoutePlanningView` opens with a MapKit map
4. User taps map: first tap = start (green pin), second = end (red pin)
5. On second tap, `RoutingEngine.findRoute(from:to:via:mode:)` runs on a background task
6. `TurnInstructionGenerator.generate(from:)` produces turn instructions
7. Result displayed as purple polyline + stats + directions list
8. User taps "Save" → `PlannedRoute.from(computedRoute:name:mode:regionId:)` → `PlannedRouteStore.shared.save()`
9. Optionally, "Send to Watch" → `WatchTransferManager.sendPlannedRouteToWatch()`

### 2. Route Transfer (iOS → watchOS)

1. `WCSession.transferFile()` sends the JSON file with metadata `{"type": "plannedRoute", "routeId": ..., "name": ...}`
2. Watch receives file in `WatchConnectivityReceiver.session(_:didReceive:)`
3. Decoded as `PlannedRoute`, saved via `PlannedRouteStore.shared.save()`
4. `.plannedRouteSyncReceived` notification posted

### 3. Active Navigation (watchOS)

1. User opens "Routes" tab → `WatchPlannedRoutesView`
2. Taps a route → `RouteGuidance.start(route:)` called, tab switches to Map
3. `MapScene.updateRouteLine()` renders purple polyline (z=40, below track trail)
4. `NavigationOverlay` appears at top and bottom of map
5. On each GPS update: `RouteGuidance.updateLocation()`:
   - Projects position onto polyline via `closestPointOnRoute()`
   - Updates progress, remaining distance, distance to next turn
   - Advances instruction when user passes a turn point (< 30m)
   - Detects off-route (> 50m from polyline)
   - Triggers haptics at 100m (approaching) and 30m (at turn)

---

## Key Algorithms

### Turn Instruction Generation

The `TurnInstructionGenerator` iterates over consecutive edge pairs in the `ComputedRoute`:

1. For each junction (node shared between edge[i] and edge[i+1]):
   - Compute **incoming bearing**: direction of the last segment of edge[i] arriving at the junction
   - Compute **outgoing bearing**: direction of the first segment of edge[i+1] leaving the junction
   - **delta** = outgoing - incoming, normalized to -180..+180
   - Map delta to `TurnDirection` using the thresholds in `TurnInstructionConfig`

Thresholds (degrees):
| Range | Direction |
|-------|-----------|
| 0-15 | `.straight` (filtered out) |
| 15-45 | `.slightLeft` / `.slightRight` |
| 45-135 | `.left` / `.right` |
| 135-170 | `.sharpLeft` / `.sharpRight` |
| 170-180 | `.uTurn` |

Instructions within 50m of each other are merged to avoid rapid-fire guidance.

### Position-on-Route Projection

`RouteGuidance.closestPointOnRoute()` finds the nearest point on the polyline:

1. For each segment, project the user's position onto the line segment (clamped to segment bounds)
2. Compute haversine distance from user to projected point
3. Track the minimum-distance projection
4. Return: closest point, segment index, and distance along the route

Uses a simplified planar projection for the per-segment math (adequate at hiking distances).

### Off-Route Detection

- **Trigger**: Distance from polyline > 50m → `isOffRoute = true`, `.failure` haptic
- **Clear**: Distance < 30m → `isOffRoute = false`
- Hysteresis (different trigger/clear thresholds) prevents rapid toggling near the boundary

---

## Configuration Constants

### `TurnInstructionConfig` (Shared/Models/TurnInstruction.swift)

| Constant | Default | Purpose |
|----------|---------|---------|
| `straightThresholdDegrees` | 15.0 | Max bearing change still classified as "straight" |
| `slightTurnThresholdDegrees` | 45.0 | Max for "slight turn" |
| `normalTurnThresholdDegrees` | 135.0 | Max for "turn" |
| `uTurnThresholdDegrees` | 170.0 | Max before "u-turn" |
| `minimumInstructionSpacingMetres` | 50.0 | Min distance between consecutive instructions |

### `RouteGuidanceConfig` (OpenHiker watchOS/Services/RouteGuidance.swift)

| Constant | Default | Purpose |
|----------|---------|---------|
| `offRouteThresholdMetres` | 50.0 | Distance to trigger off-route warning |
| `offRouteClearThresholdMetres` | 30.0 | Distance to clear off-route warning |
| `approachingTurnDistanceMetres` | 100.0 | Distance for "approaching" haptic |
| `atTurnDistanceMetres` | 30.0 | Distance for "at turn" haptic / instruction advance |
| `arrivedDistanceMetres` | 30.0 | Distance to trigger arrival notification |

---

## Persistence: PlannedRouteStore

Unlike `RouteStore` (SQLite), `PlannedRouteStore` uses simple JSON files:

```
Documents/
  planned_routes/
    <uuid>.json    ← One file per planned route (JSON-encoded PlannedRoute)
```

Rationale: Planned routes are few, small (~50-200 KB each), and fully self-contained. JSON simplifies WatchConnectivity transfer (the file is already in transfer-ready format).

The store maintains an in-memory `@Published var routes: [PlannedRoute]` cache, sorted by creation date (newest first). Call `loadAll()` on app launch.

---

## Haptic Feedback Patterns

| Event | Haptic | Direction |
|-------|--------|-----------|
| Approaching turn (100m) | `.click` | Both |
| At left turn (30m) | `.directionDown` | Wrist-down feel |
| At right turn (30m) | `.directionUp` | Wrist-up feel |
| U-turn (30m) | `.failure` | Alert |
| Off-route | `.failure` | Alert |
| Arrived | `.success` | Celebration |

---

## Debugging Tips

### Route computation fails

1. Check that `region.hasRoutingData` is `true` and the `.routing.db` file exists at `RegionStorage.shared.routingDbURL(for:)`
2. Verify `RoutingStore.open()` succeeds — use breakpoint in `RoutePlanningView.computeRoute()`
3. Common errors: `RoutingError.noNearbyNode` means the tap point is too far from any trail

### Turn instructions look wrong

1. Add logging in `TurnInstructionGenerator.generate()` to print incoming/outgoing bearings and delta
2. Check `EdgeGeometry.unpack()` returns non-empty coordinates for edges with intermediate geometry
3. Adjust `TurnInstructionConfig` thresholds if turns are being classified incorrectly

### Navigation overlay not showing

1. Confirm `RouteGuidance` is injected as `@EnvironmentObject` in `OpenHikerWatchApp`
2. Verify `routeGuidance.isNavigating` is `true` — check `start(route:)` was called
3. Check `NavigationOverlay` is present in `MapView`'s ZStack

### Route polyline not rendering

1. Verify `mapScene?.updateRouteLine(coordinates:)` is being called in `refreshRouteLine()`
2. Check the route has >= 2 coordinates
3. Confirm `routeNode` z-position (40) is above tiles (0) but below track trail (50)

### Planned route not received on watch

1. Check `WCSession.activationState == .activated` on both sides
2. Verify the iOS transfer uses `type: "plannedRoute"` in metadata
3. Check `handleReceivedPlannedRoute()` in `WatchConnectivityReceiver` for decode errors
4. Verify the JSON decoder uses `.iso8601` date strategy (must match the encoder)

---

## Extending This System

### Adding a new turn direction

1. Add a case to `TurnDirection` in `TurnInstruction.swift`
2. Add the corresponding SF Symbol in `sfSymbolName`
3. Add the verb in `verb`
4. Update `BearingCalculator.turnDirection(fromBearingDelta:)` with new angle range
5. Update `RouteGuidance.playDirectionHaptic()` with the haptic pattern

### Adding route re-routing

When the user goes off-route, you could:
1. Detect the off-route condition (already done in `RouteGuidance`)
2. Open the `RoutingStore` for the region
3. Call `RoutingEngine.findRoute()` from the current position to the original destination
4. Replace `activeRoute` with the new `PlannedRoute` and call `start(route:)`
5. This requires the routing database to be available on the watch

### Elevation Profile (implemented)

`PlannedRoute` stores an optional `elevationProfile: [ElevationPoint]?` array generated at route
creation time from the `RoutingNode.elevation` (SRTM/Copernicus) data in `ComputedRoute`. The
`RouteDetailView` renders this using the existing `ElevationProfileView` Swift Charts component.

- `ElevationPoint` struct: `(distance: Double, elevation: Double)` — Codable, in metres
- `PlannedRoute.buildElevationProfile(from:)` walks the `ComputedRoute.nodes` accumulating per-edge distances
- Backward-compatible: existing JSON files without this field decode with `elevationProfile: nil`
- If `nil` or fewer than 2 points, the chart section is hidden

### Pin Repositioning (implemented)

`RoutePlanningView` supports long-press-to-reposition:

1. Long-press (0.5s) on any pin → enters reposition mode (pin highlights with yellow ring + scale)
2. Instruction text changes to "Tap the map to reposition [pin name]" (orange)
3. Next map tap moves the pin to the new coordinate and re-computes the route
4. Tapping any pin or pressing "Cancel" exits reposition mode without changes

### Supporting GPX import as planned routes

1. Parse the GPX file into `[CLLocationCoordinate2D]`
2. Create a `PlannedRoute` directly from the coordinates (no routing engine needed)
3. Skip turn instruction generation or generate instructions using bearing changes between consecutive GPX segments
