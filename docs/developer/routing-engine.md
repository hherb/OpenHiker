# Phase 4: Routing Engine — Developer Guide

**Last updated:** 2026-02-06

This guide covers the offline A* routing engine added in Phase 4. It explains the architecture, data flow, file layout, cost model, and how to modify or debug each component.

---

## Architecture Overview

```
┌─────────────────────────── iOS (build pipeline) ──────────────────────────┐
│                                                                           │
│  OSMDataDownloader ──► PBFParser ──► RoutingGraphBuilder ──► .routing.db  │
│        │                                     ▲                            │
│        │ (Overpass API)        ElevationDataManager                       │
│        ▼                     (Copernicus / SRTM)                          │
│   trail XML/PBF                                                           │
│                                                                           │
│  WatchTransferManager ──► transfers .routing.db to watch                  │
└───────────────────────────────────────────────────────────────────────────┘

┌────────────────── Shared (iOS + watchOS) ──────────────────┐
│                                                             │
│  RoutingStore (read-only SQLite)                            │
│       ▲                                                     │
│       │                                                     │
│  RoutingEngine (A* pathfinding)                             │
│       │                                                     │
│       ▼                                                     │
│  ComputedRoute { nodes, edges, coordinates, stats }         │
└─────────────────────────────────────────────────────────────┘
```

## Files and Responsibilities

### Shared (both platforms)

| File | What it does |
|------|-------------|
| `Shared/Models/RoutingGraph.swift` | Data types: `RoutingNode`, `RoutingEdge`, `RoutingMode`, `ComputedRoute`, `RoutingCostConfig`, `RoutingError`, `EdgeGeometry`, plus the `haversineDistance()` helper. |
| `Shared/Storage/RoutingStore.swift` | Read-only SQLite access to `.routing.db`. Serial-queue pattern matching `TileStore`. Provides `getNode`, `getEdgesFrom`, `nearestNode`, `getNodesInBoundingBox`, metadata queries. |
| `Shared/Services/RoutingEngine.swift` | A* pathfinding with via-point support. Uses `RoutingStore` for graph queries and a `BinaryMinHeap` for the open set. |

### iOS only (build pipeline)

| File | What it does |
|------|-------------|
| `OpenHiker iOS/Services/ProtobufReader.swift` | Minimal protobuf wire-format decoder: varints, ZigZag, length-delimited fields. No external dependency. |
| `OpenHiker iOS/Services/PBFParser.swift` | Parses `.osm.pbf` files (DenseNodes + Ways), filtering for routable highway tags. |
| `OpenHiker iOS/Services/ElevationDataManager.swift` | Downloads and caches Copernicus DEM / SRTM elevation tiles (HGT format). Provides bilinear-interpolated elevation queries. |
| `OpenHiker iOS/Services/RoutingGraphBuilder.swift` | Orchestrates graph construction: junction detection → way splitting → elevation lookup → cost computation → SQLite output. |
| `OpenHiker iOS/Services/OSMDataDownloader.swift` | Downloads trail data from the Overpass API (XML) and parses it into `PBFParser.OSMNode`/`OSMWay` types. |

### Modified existing files

| File | Changes |
|------|---------|
| `Shared/Models/Region.swift` | Added `hasRoutingData` to `Region`, `RegionMetadata`, and `RegionSelectionRequest`. Added `routingDbFilename`. Added download status cases: `.downloadingTrailData`, `.downloadingElevation`, `.buildingRoutingGraph`. |
| `OpenHiker iOS/Services/WatchTransferManager.swift` | Added `transferRoutingDatabase(at:metadata:)`. Updated `sendAvailableRegions()` to include `hasRoutingData`. |
| `OpenHiker watchOS/App/OpenHikerWatchApp.swift` | Added `handleReceivedRoutingDB()` in `WatchConnectivityReceiver`. Updated app context parsing to include `hasRoutingData`. |

---

## SQLite Schema (`.routing.db`)

```sql
CREATE TABLE routing_nodes (
    id INTEGER PRIMARY KEY,          -- OSM node ID
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    elevation REAL                   -- metres ASL; NULL if unknown
);

CREATE TABLE routing_edges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_node INTEGER NOT NULL REFERENCES routing_nodes(id),
    to_node INTEGER NOT NULL REFERENCES routing_nodes(id),
    distance REAL NOT NULL,          -- metres (haversine)
    elevation_gain REAL DEFAULT 0,   -- metres (forward direction)
    elevation_loss REAL DEFAULT 0,   -- metres (forward direction)
    surface TEXT,                    -- OSM surface=* tag
    highway_type TEXT,               -- OSM highway=* tag
    sac_scale TEXT,                  -- SAC hiking difficulty
    trail_visibility TEXT,
    name TEXT,                       -- trail name
    osm_way_id INTEGER,             -- source OSM way ID
    cost REAL NOT NULL,             -- forward traversal cost
    reverse_cost REAL NOT NULL,     -- reverse traversal cost
    is_oneway INTEGER DEFAULT 0,
    geometry BLOB                   -- packed Float32 intermediate coords
);

CREATE TABLE routing_metadata (
    key TEXT PRIMARY KEY,
    value TEXT
);

CREATE INDEX idx_nodes_lat_lon ON routing_nodes(latitude, longitude);
CREATE INDEX idx_edges_from ON routing_edges(from_node);
CREATE INDEX idx_edges_to ON routing_edges(to_node);
```

### Edge geometry format

Intermediate coordinates (non-junction nodes along a trail) are stored as a packed `Float32` array in the `geometry` BLOB: `[lat0, lon0, lat1, lon1, ...]`. Use `EdgeGeometry.pack()` and `EdgeGeometry.unpack()` to convert.

---

## Cost Model

### Hiking mode (Naismith + Tobler)

```
forward_cost = distance × surface_mul × sac_mul
             + elevation_gain × 7.92
             + elevation_loss × 7.92 × descent_mul(grade)
```

**Surface multipliers** (from `RoutingCostConfig.hikingSurfaceMultipliers`):

| Surface | Multiplier |
|---------|-----------|
| paved/asphalt/concrete | 1.0 |
| compacted/fine_gravel | 1.1 |
| gravel | 1.2 |
| ground/dirt/earth | 1.3 |
| grass | 1.4 |
| rock/pebblestone | 1.5 |
| sand | 1.8 |
| mud | 2.0 |
| (unknown) | 1.3 |

**SAC scale multipliers** (from `RoutingCostConfig.sacScaleMultipliers`):

| SAC Grade | Multiplier |
|-----------|-----------|
| hiking (T1) | 1.0 |
| mountain_hiking (T2) | 1.2 |
| demanding_mountain_hiking (T3) | 1.5 |
| alpine_hiking (T4) | 2.0 |
| demanding_alpine_hiking (T5) | 3.0 |
| difficult_alpine_hiking (T6) | 5.0 |

**Descent multipliers** (from `RoutingCostConfig.descentMultiplier(gradePercent:)`):

| Grade | Multiplier | Rationale |
|-------|-----------|-----------|
| < 10% | 0.5 | Gentle, faster than flat |
| 10–20% | 0.8 | Starting to brake |
| 20–30% | 1.0 | As slow as flat |
| > 30% | 1.5 | Dangerous, very slow |

### Cycling mode

Uses the same formula with harsher surface penalties (`RoutingCostConfig.cyclingSurfaceMultipliers`) and a steeper climb penalty (12.0 per metre vs 7.92). Steps are impassable (`cost = infinity`).

### Tuning the cost model

All multipliers live in `RoutingCostConfig` (file: `Shared/Models/RoutingGraph.swift`). To change how the engine prioritises trails:

1. Edit the relevant dictionary or constant in `RoutingCostConfig`.
2. **Rebuild** the `.routing.db` files — costs are precomputed at build time. The engine reads `cost` and `reverse_cost` from SQLite at query time.
3. If you need *runtime* cost adjustments (e.g. user prefers paved paths), you would need to modify `RoutingEngine.astar()` to apply a runtime multiplier on top of the stored cost. The current design precomputes costs for performance.

---

## Via-Point Routing (Waypoints)

The engine supports **ordered via-points** between start and end:

```swift
let route = try engine.findRoute(
    from: startCoord,
    to: endCoord,
    via: [waypointA, waypointB],  // user-added intermediate stops
    mode: .hiking
)
```

Internally, `findRoute()`:
1. Prepends `from` and appends `to` to the `via` list → `[from, A, B, to]`
2. Snaps each coordinate to the nearest routing node
3. Runs A* for each consecutive pair: `from→A`, `A→B`, `B→to`
4. Concatenates the sub-routes, deduplicating junction nodes at segment boundaries
5. Returns a single `ComputedRoute` with aggregated statistics

The `ComputedRoute.viaPoints` field stores the original via coordinates so the UI can display and allow editing of waypoints. When the user moves a via-point, simply call `findRoute()` again with the updated array.

---

## Data Flow: Region Download Pipeline

```
1. User selects region on iPhone          (existing)
2. Download map tiles                      (existing TileDownloader)
3. Download OSM trail data                 (OSMDataDownloader → Overpass API)
4. Download elevation tiles                (ElevationDataManager → Copernicus/SRTM)
5. Parse trails, filter by highway tags    (PBFParser or Overpass XML parsing)
6. Build routing graph                     (RoutingGraphBuilder)
     a. Identify junctions (nodes in ≥2 ways)
     b. Split ways at junctions → edges
     c. Look up elevations for junction nodes
     d. Compute edge costs (forward + reverse)
     e. Write to SQLite
7. Save as <uuid>.routing.db               (alongside <uuid>.mbtiles)
8. Transfer both files to watch            (WatchTransferManager)
```

Steps 3–7 only run when `RegionSelectionRequest.includeRoutingData == true` (default: true).

---

## How to Debug

### Inspect a routing database

```bash
sqlite3 /path/to/region.routing.db
.schema
SELECT COUNT(*) FROM routing_nodes;
SELECT COUNT(*) FROM routing_edges;
SELECT * FROM routing_metadata;
-- Sample edges
SELECT id, from_node, to_node, distance, cost, reverse_cost, highway_type, surface
FROM routing_edges LIMIT 20;
```

### Verify cost asymmetry

Uphill edges should have higher forward cost than their reverse (downhill) cost:

```sql
SELECT id, from_node, to_node, elevation_gain, elevation_loss, cost, reverse_cost
FROM routing_edges
WHERE elevation_gain > 50
ORDER BY elevation_gain DESC
LIMIT 10;
```

### Check junction detection

Junctions should be nodes that appear in multiple edges:

```sql
SELECT from_node, COUNT(*) as edge_count
FROM routing_edges
GROUP BY from_node
HAVING edge_count > 1
ORDER BY edge_count DESC
LIMIT 20;
```

### Test the A* engine in code

```swift
let store = RoutingStore(path: dbPath)
try store.open()
defer { store.close() }

let engine = RoutingEngine(store: store)

// Find a route
let route = try engine.findRoute(
    from: CLLocationCoordinate2D(latitude: 47.42, longitude: 10.99),
    to: CLLocationCoordinate2D(latitude: 47.38, longitude: 10.94),
    mode: .hiking
)

print("Nodes: \(route.nodes.count)")
print("Distance: \(route.totalDistance) m")
print("ETA: \(route.estimatedDuration / 60) min")
print("Gain: \(route.elevationGain) m, Loss: \(route.elevationLoss) m")
print("Coordinates: \(route.coordinates.count) points")
```

### Common issues

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `noNearbyNode` error | User tapped far from any trail | Increase `RoutingCostConfig.nearestNodeSearchRadiusMetres` |
| `noRouteFound` error | Start and end are on disconnected trail networks | Check the region has connected trails; consider adding road connections |
| Routing database is empty | Overpass query returned no data | Verify the bounding box is correct; check Overpass API is reachable |
| Route takes an unexpected path | Cost model favours the wrong trail type | Inspect edge costs in SQLite; tune multipliers in `RoutingCostConfig` |
| Large database size | Dense urban area with many roads | Filter out major roads if only hiking is needed; reduce `routableHighwayValues` |

---

## How to Extend

### Add a new routing mode

1. Add a case to `RoutingMode` in `RoutingGraph.swift`
2. Add surface/penalty multiplier dictionaries to `RoutingCostConfig`
3. Update `RoutingGraphBuilder.computeDirectionalCost()` to use the new multipliers when building (or make cost mode-aware at query time)
4. Update `RoutingEngine.isEdgePassable()` for mode-specific edge filtering

### Add runtime cost preferences

To let users prefer e.g. "paved trails only":

1. Add a `RoutingPreferences` struct (surface weight, avoid steep, etc.)
2. Pass it into `RoutingEngine.findRoute()`
3. In `astar()`, multiply the stored `edge.cost` by a runtime adjustment factor before adding to `gScore`

### Render route on the watch map

The `ComputedRoute.coordinates` array contains the full path including intermediate geometry points. Pass this to `MapScene.updateRouteOverlay()` (to be added in Phase 5) the same way `updateTrackTrail()` currently renders GPS tracks.

### Add turn-by-turn directions

Each edge has a `name` (trail name) and `highwayType`. At each junction node where the trail name changes or the path turns significantly:

1. Compute the bearing change between consecutive edges
2. Generate a turn instruction ("Turn left onto Alpine Trail")
3. Store as an array of `RouteInstruction` objects in `ComputedRoute`

This is planned for Phase 5.

---

## Key Design Decisions

1. **Costs precomputed at build time** — The `.routing.db` stores both `cost` and `reverse_cost` per edge. A* reads these directly without recomputing. This makes route queries very fast (especially on watchOS) at the expense of needing to rebuild the database if cost parameters change.

2. **Bidirectional edges via query** — Rather than storing two rows per trail segment, we store one edge and let `RoutingStore.getEdgesFrom()` query both `from_node` and `to_node` columns. The A* engine checks `isOneway` and uses `reverseCost` when traversing in the reverse direction.

3. **Edge geometry as packed Float32** — Using Float32 instead of Float64 halves storage. At hiking scales the sub-metre precision loss is irrelevant. The `EdgeGeometry` helper handles packing/unpacking.

4. **Overpass API over Geofabrik PBF** — For typical hiking regions (< 100×100 km) the Overpass API is more convenient: it returns only the filtered data we need, no need for a multi-hundred-MB country extract. The PBF parser is still available for offline/large-region builds.

5. **Haversine as A* heuristic** — Straight-line haversine distance is always ≤ actual trail distance, making it admissible. It's fast to compute and works well globally.
