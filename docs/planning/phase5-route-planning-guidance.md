# Phase 5: Route Planning & Active Guidance

**Estimated effort:** ~4 weeks
**Dependencies:** Phase 4 (routing engine)
**Platform focus:** iOS (planning), watchOS (guidance)

## Overview

Route planning UI on iPhone where users tap to set start/end/via-points and the routing engine computes the optimal path. Turn-by-turn guidance on the watch with route polyline, upcoming turn instructions, haptic feedback, and off-route detection.

---

## Feature 5.1: Route Planning on iPhone

**Size:** L (Large)

### What It Does

Interactive route planning on the iPhone map:
1. Tap to set start point (green pin)
2. Tap to set end point (red pin)
3. Optionally tap to add via-points (blue pins)
4. Routing engine computes optimal hiking or cycling path
5. Display route as polyline on MapKit with statistics
6. Drag pins to adjust (re-computes on drop)
7. Save planned route and transfer to watch for guidance

### UI Design

#### Route Planning View

```
┌──────────────────────────────┐
│  [Cancel]  Plan Route  [Save]│
├──────────────────────────────┤
│                              │
│     MapKit View              │
│     [Start 🟢]              │
│     ~~~trail polyline~~~     │
│     [Via 🔵]                │
│     ~~~trail polyline~~~     │
│     [End 🔴]                │
│                              │
├──────────────────────────────┤
│ Mode: [🥾 Hiking] [🚴 Cycling] │
├──────────────────────────────┤
│ Distance: 12.4 km           │
│ Est. Time: 4h 23m           │
│ Elevation: +823m / -756m    │
├──────────────────────────────┤
│ Directions:                  │
│ 1. Head north on Forest Rd   │
│ 2. In 1.2 km, turn left     │
│ 3. Follow Ridge Trail 3.4km │
│ ...                          │
└──────────────────────────────┘
```

### Interaction Model

1. **First tap** → place start pin (green), show "Tap to set destination"
2. **Second tap** → place end pin (red), auto-compute route
3. **Subsequent taps** → add via-points (blue), re-compute route
4. **Long-press on pin** → drag to reposition, re-compute on drop
5. **Tap on pin** → option to remove it
6. **Mode toggle** → switch hiking/cycling, re-compute

### Turn Instruction Generation

At each junction node along the computed route, generate a turn instruction:

```swift
struct TurnInstruction: Codable, Sendable {
    let coordinate: CLLocationCoordinate2D
    let direction: TurnDirection
    let distanceFromPrevious: Double    // meters
    let cumulativeDistance: Double       // meters from start
    let trailName: String?              // OSM trail name, if available
    let description: String             // "Turn left onto Blue Ridge Trail"
}

enum TurnDirection: String, Codable, Sendable {
    case start          // "Start heading north"
    case straight       // "Continue straight"
    case slightLeft     // "Bear left"
    case left           // "Turn left"
    case sharpLeft      // "Sharp left"
    case slightRight    // "Bear right"
    case right          // "Turn right"
    case sharpRight     // "Sharp right"
    case uTurn          // "U-turn"
    case arrive         // "Arrive at destination"
}
```

**Direction calculation:**
1. Compute bearing of incoming edge (last ~50m before junction)
2. Compute bearing of outgoing edge (first ~50m after junction)
3. Calculate bearing change: `delta = outBearing - inBearing` (normalized to -180..180)
4. Map to TurnDirection:
   - -15° to +15°: straight
   - +15° to +45°: slightRight
   - +45° to +135°: right
   - +135° to +180°: sharpRight / uTurn
   - Symmetric for left turns

**Description generation:**
```swift
func generateDescription(_ turn: TurnInstruction) -> String {
    let directionText: String
    switch turn.direction {
    case .start: directionText = "Head \(cardinalDirection(turn.bearing))"
    case .straight: directionText = "Continue straight"
    case .left: directionText = "Turn left"
    // ... etc
    }

    if let name = turn.trailName {
        return "\(directionText) onto \(name)"
    } else {
        return "\(directionText) heading \(cardinalDirection(turn.bearing))"
    }
}
```

### Planned Route Model

```swift
/// A route computed by the routing engine, ready for navigation.
struct PlannedRoute: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    let mode: RoutingMode                        // hiking or cycling
    let startCoordinate: CLLocationCoordinate2D
    let endCoordinate: CLLocationCoordinate2D
    let viaPoints: [CLLocationCoordinate2D]
    let coordinates: [CLLocationCoordinate2D]    // full path polyline
    let turnInstructions: [TurnInstruction]
    let totalDistance: Double                     // meters
    let estimatedDuration: TimeInterval          // seconds
    let elevationGain: Double                    // meters
    let elevationLoss: Double                    // meters
    let createdAt: Date
    let regionId: UUID?
}
```

### Files to Create

#### `OpenHiker iOS/Views/RoutePlanningView.swift`
- MapKit view with interactive pin placement
- Mode toggle (hiking/cycling)
- Route polyline overlay
- Statistics summary
- Directions list
- Save button → store to RouteStore, option to transfer to watch

#### `OpenHiker iOS/Views/RouteDetailView.swift`
- Read-only view of a saved planned route
- Map with polyline, elevation profile, turn list
- "Send to Watch" button
- "Start Navigation" (opens on watch)

#### `Shared/Models/PlannedRoute.swift`
- PlannedRoute struct

#### `Shared/Models/TurnInstruction.swift`
- TurnInstruction struct, TurnDirection enum
- Direction calculation helpers

### Files to Modify

#### `OpenHiker iOS/App/ContentView.swift`
- Add "Routes" tab (5th tab) or integrate into existing "Regions" tab as a mode
- Tab icon: `"arrow.triangle.turn.up.right.diamond"`

#### `Shared/Services/RoutingEngine.swift`
- Add `generateTurnInstructions(route: ComputedRoute) -> [TurnInstruction]`
- Add bearing calculation helpers

#### `OpenHiker iOS/Services/WatchTransferManager.swift`
- Add `sendPlannedRouteToWatch(_ route: PlannedRoute)` method
- Package as JSON + coordinate data via `transferFile`

### Testing

1. Open Route Planning, tap two points on the map
2. Verify route is computed and displayed as polyline
3. Verify statistics (distance, time, elevation) are reasonable
4. Verify turn instructions are generated at junctions
5. Switch between hiking/cycling → verify route changes
6. Drag a pin → verify route re-computes
7. Add via-point → verify route passes through it
8. Save route → verify it appears in Routes list
9. Transfer to watch → verify watch receives it

---

## Feature 5.2: Active Route Guidance on Watch

**Size:** L (Large)

### What It Does

Turn-by-turn navigation on the watch during a hike or bike ride:
- Route polyline displayed on the SpriteKit map (purple, distinct from orange track trail)
- Current instruction overlay: arrow icon + distance + description
- Haptic feedback at each turn point
- Off-route detection with warning and optional re-routing
- Progress indicator showing % of route completed

### Navigation Overlay

```
┌─────────────────────┐
│ ↰ In 200m           │  Direction arrow + distance
│ Turn left onto       │  Instruction text
│ Forest Trail         │  Trail name
├─────────────────────┤
│ ████░░░░░░ 34%      │  Progress bar
│ 4.2 km remaining    │  Remaining distance
└─────────────────────┘
```

Overlay sits at the top of the map, uses `.ultraThinMaterial` background.

### Route Guidance Engine

```swift
// OpenHiker watchOS/Services/RouteGuidance.swift

/// Tracks the user's position along a planned route and provides navigation guidance.
///
/// Monitors GPS location updates, determines which turn instruction is upcoming,
/// calculates distance to the next turn, detects off-route conditions, and
/// triggers haptic feedback at turn points.
final class RouteGuidance: ObservableObject {
    @Published var currentInstruction: TurnInstruction?
    @Published var distanceToNextTurn: Double?       // meters
    @Published var progress: Double = 0              // 0.0–1.0
    @Published var remainingDistance: Double = 0     // meters
    @Published var isOffRoute: Bool = false
    @Published var isNavigating: Bool = false

    /// Start navigating along the given route.
    func start(route: PlannedRoute)

    /// Stop navigation.
    func stop()

    /// Update with a new GPS location.
    func updateLocation(_ location: CLLocation)

    // Internal:
    // - Find nearest point on route polyline to current position
    // - Calculate distance along route from that point
    // - Determine which turn instruction is next
    // - Check if distance to route > 50m → off-route warning
    // - When within 30m of a turn point → trigger haptic + advance to next
}
```

### Position-on-Route Calculation

To determine where the user is along the route:

1. Find the closest point on the route polyline to the user's GPS position
2. Calculate the distance along the route from the start to that closest point
3. Use this to determine progress % and which turn is upcoming

```swift
/// Find the closest point on a polyline to a given coordinate.
///
/// Returns: (closestPoint, segmentIndex, distanceAlongRoute)
func closestPointOnRoute(
    from coordinate: CLLocationCoordinate2D,
    route: [CLLocationCoordinate2D]
) -> (point: CLLocationCoordinate2D, segment: Int, distanceAlong: Double)
```

### Off-Route Detection

- **Threshold:** 50 meters from the nearest point on the route
- **Warning:** Display "Off Route" banner, play `WKInterfaceDevice.current().play(.failure)` haptic
- **Re-route option:** If routing database is available on watch, compute new route from current position to next via-point or destination
- **Auto-dismiss:** Warning clears when user returns within 30m of route

### Haptic Feedback

Use watchOS haptics at key moments:
- **Approaching turn (100m):** `.click` — gentle reminder
- **At turn point (30m):** `.directionUp` / `.directionDown` — confirm direction
- **Off-route:** `.failure` — alert
- **Arrived at destination:** `.success` — celebration

### SpriteKit Route Polyline

Render the planned route on the map alongside the track trail:

```swift
// In MapScene (MapRenderer.swift):
// Route polyline = purple, 4pt width (distinct from orange 3pt track trail)
// Same rendering approach as track trail but different color
func updateRouteLine(coordinates: [CLLocationCoordinate2D]) {
    // Convert coordinates to screen positions
    // Create/update SKShapeNode with the path
    // Color: .systemPurple, lineWidth: 4
}
```

### Receiving Planned Routes

The watch receives planned routes from iPhone via WatchConnectivity:
- `WatchConnectivityReceiver` handles incoming `transferFile` with `type: plannedRoute`
- Decode `PlannedRoute` from JSON, store in local `RouteStore`
- Add to navigation-ready routes list

### Files to Create

#### `OpenHiker watchOS/Views/NavigationOverlay.swift`
- SwiftUI overlay showing:
  - Direction arrow (SF Symbol rotated to match bearing)
  - Distance to next turn
  - Instruction text
  - Progress bar
  - "Off Route" warning when applicable
- Only visible when `routeGuidance.isNavigating`

#### `OpenHiker watchOS/Services/RouteGuidance.swift`
- Position tracking along route
- Turn instruction management
- Off-route detection
- Haptic feedback triggers

### Files to Modify

#### `OpenHiker watchOS/Views/MapView.swift`
- Add `NavigationOverlay()` to ZStack
- Add route polyline rendering via `mapScene?.updateRouteLine()`
- Add "Start Navigation" option when a planned route is loaded
- Bottom controls: add navigation start/stop button when route available

#### `OpenHiker watchOS/Services/MapRenderer.swift`
- Add `updateRouteLine(coordinates:)` to `MapScene`
- Purple 4pt `SKShapeNode` polyline (same technique as track trail)

#### `OpenHiker watchOS/App/OpenHikerWatchApp.swift`
- Handle incoming planned routes from WatchConnectivity
- Initialize `RouteGuidance` and inject into environment

#### `OpenHiker watchOS/App/WatchContentView.swift`
- Add planned routes to a "Routes" section in the Regions tab, or a new tab

### Testing

1. Plan a route on iPhone → transfer to watch
2. Start navigation on watch → verify route polyline appears (purple)
3. Verify first instruction shows in overlay
4. Simulate walking along route (GPX file in simulator)
5. Verify instructions advance as user reaches turn points
6. Verify haptic feedback at turns
7. Verify progress bar updates
8. Simulate going off-route → verify "Off Route" warning + haptic
9. Return to route → verify warning clears
10. Reach destination → verify "Arrived" notification
11. Stop navigation → verify overlay disappears, polyline remains visible
