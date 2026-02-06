# Phase 4: Custom Offline Routing Engine

**Estimated effort:** ~5 weeks
**Dependencies:** None (can be developed in parallel with Phases 1–3)
**Platform focus:** iOS (data pipeline), Shared (routing engine + storage)

## Overview

Build a fully offline A\* routing engine in pure Swift for hiking and cycling trails. The pipeline downloads OSM trail data and elevation data for a geographic region, constructs a routing graph stored in SQLite, and provides pathfinding with terrain-aware cost functions.

This is the most complex feature in the roadmap. It is decomposed into these sub-tasks:

1. PBF Parser — Read OpenStreetMap binary data in pure Swift
2. Elevation Data Manager — Download and query Copernicus DEM / SRTM elevation tiles
3. Routing Graph Builder — Extract trails, compute costs, build SQLite graph
4. Routing Engine — A\* pathfinding with hiking/cycling cost functions
5. Integration — Hook into the existing region download pipeline

---

## Data Sources (Global Coverage)

### OSM Trail Data

**Source:** Geofabrik regional extracts — https://download.geofabrik.de/
- Every continent and country available as `.osm.pbf` files
- Updated daily, free to use, ODbL license (AGPL-3.0 compatible)
- Data covers the entire world — not US-centric

**Alternative for small areas:** Overpass API (https://overpass-api.de/api/interpreter)
- Can query specific bounding boxes with tag filters
- Useful for testing and small regions
- Rate-limited, not suitable for large extracts

### Elevation Data

**Primary: Copernicus DEM GLO-30**
- Source: ESA Copernicus programme, distributed via AWS Open Data
- Coverage: **90°N to 90°S** — true global, including:
  - All of Scandinavia (Norway, Sweden, Finland above 60°N)
  - Iceland, Svalbard
  - Australia, New Zealand
  - All of Europe, Asia, Africa, Americas
- Resolution: 30 meters (~1 arc-second)
- Format: GeoTIFF tiles, organized by 1°×1° cells
- License: CC-BY-4.0 (compatible with AGPL-3.0)
- Download URL pattern: `s3://copernicus-dem-30m/Copernicus_DSM_COG_10_{N|S}{lat}_00_{E|W}{lon}_DEM/`

**Fallback: SRTM 1-arc-second**
- Source: NASA/USGS
- Coverage: **60°N to 56°S** — misses northern Scandinavia
- Resolution: 30 meters (1 arc-second)
- Format: `.hgt` files (raw 16-bit signed integers, 3601×3601 grid per 1°×1° tile)
- License: Public domain
- Download: https://e4ftl01.cr.usgs.gov/MEASURES/SRTMGL1.003/

**Strategy:** Use Copernicus as primary (global). Fall back to SRTM only if Copernicus is unavailable for a specific tile. Both are free and AGPL-compatible.

---

## Sub-task 4.1: PBF Parser

### OSM PBF Format Overview

The `.osm.pbf` (Protobuf Binary Format) is a compressed binary format for OpenStreetMap data. Structure:

```
File = [BlobHeader + Blob]*
  BlobHeader = { type: "OSMHeader" | "OSMData", datasize }
  Blob = { raw | zlib_data | lzma_data }
    → HeaderBlock (for type "OSMHeader")
    → PrimitiveBlock (for type "OSMData")
      → StringTable (shared string pool)
      → PrimitiveGroup[]
        → Node[] | DenseNodes | Way[] | Relation[]
```

We only need **Nodes** (coordinates) and **Ways** (trail segments) — Relations can be ignored for routing.

### Implementation Approach

Write a minimal PBF decoder in pure Swift. The protobuf wire format is simple:
- Varint encoding for integers
- Length-delimited fields for strings and nested messages
- ZigZag encoding for signed integers
- Zlib decompression for blob payloads (use Apple's `Compression` framework)

**We do NOT need a full protobuf library.** The PBF schema is fixed and small — we decode only the specific message types we need.

### Key Classes

```swift
// OpenHiker iOS/Services/PBFParser.swift

/// Parses OpenStreetMap PBF (Protobuf Binary Format) files to extract trail data.
///
/// Only extracts nodes and ways relevant to hiking/cycling routing.
/// Ignores relations, metadata, and non-trail features.
actor PBFParser {
    /// A parsed OSM node with coordinates and tags.
    struct OSMNode {
        let id: Int64
        let latitude: Double    // degrees
        let longitude: Double   // degrees
        let tags: [String: String]
    }

    /// A parsed OSM way with ordered node references and tags.
    struct OSMWay {
        let id: Int64
        let nodeRefs: [Int64]   // ordered list of node IDs
        let tags: [String: String]
    }

    /// Parse a PBF file at the given path, extracting hiking/cycling trails.
    ///
    /// - Parameters:
    ///   - fileURL: URL to the .osm.pbf file
    ///   - boundingBox: Geographic filter — only include data within this box
    ///   - progress: Callback with (bytesProcessed, totalBytes) for UI progress
    /// - Returns: Tuple of (nodes, ways) relevant to routing
    func parse(
        fileURL: URL,
        boundingBox: BoundingBox,
        progress: @escaping (Int64, Int64) -> Void
    ) async throws -> (nodes: [Int64: OSMNode], ways: [OSMWay])
}
```

### Trail Tag Filtering

Only extract ways matching hiking/cycling trail tags:

```swift
/// Tags that indicate a way is usable for hiking or cycling routing.
static let routingHighwayValues: Set<String> = [
    "path", "footway", "track", "cycleway", "bridleway", "steps",
    "pedestrian", "residential", "unclassified", "tertiary",
    "secondary", "primary", "trunk", "living_street", "service"
]

/// Check if a way's tags indicate it's a routable trail/path.
static func isRoutableWay(_ tags: [String: String]) -> Bool {
    guard let highway = tags["highway"] else { return false }
    // Exclude motorways, motorway_links
    guard routingHighwayValues.contains(highway) else { return false }
    // Exclude access=private, access=no
    if let access = tags["access"], access == "private" || access == "no" { return false }
    // Exclude foot=no for hiking (unless it's a cycleway)
    if let foot = tags["foot"], foot == "no", tags["highway"] != "cycleway" { return false }
    return true
}
```

### Protobuf Wire Format Decoder

```swift
// Internal helper for reading protobuf wire format
struct ProtobufReader {
    private var data: Data
    private var offset: Int

    mutating func readVarint() -> UInt64
    mutating func readSignedVarint() -> Int64    // ZigZag decoded
    mutating func readFixed32() -> UInt32
    mutating func readFixed64() -> UInt64
    mutating func readLengthDelimited() -> Data
    mutating func readFieldTag() -> (fieldNumber: Int, wireType: Int)
    var isAtEnd: Bool
}
```

### Testing

- Parse a small PBF extract (download a city-sized extract from Geofabrik, e.g., Liechtenstein at 2.4 MB)
- Verify node coordinates are correct (spot-check against known landmarks)
- Verify way node references form valid sequences
- Verify tag filtering only includes hiking/cycling trails

---

## Sub-task 4.2: Elevation Data Manager

### HGT File Format (SRTM)

Simple binary format:
- 3601 × 3601 grid of 16-bit signed big-endian integers
- Each cell = elevation in meters
- -32768 = void (no data)
- Filename encodes SW corner: `N47E011.hgt` = tile covering 47°N–48°N, 11°E–12°E

### GeoTIFF Format (Copernicus)

More complex but standard:
- TIFF file with geographic metadata tags
- Use Apple's `ImageIO` framework to read TIFF
- Or parse the raw TIFF structure (simpler than it sounds for COG format)
- Alternatively, convert to HGT-equivalent format during download preprocessing

### Implementation

```swift
// OpenHiker iOS/Services/ElevationDataManager.swift

/// Downloads and queries elevation data from Copernicus DEM or SRTM.
///
/// Manages a cache of elevation tiles in the app's Documents directory.
/// Each tile covers 1°×1° and is ~25 MB (SRTM HGT) or similar (Copernicus).
actor ElevationDataManager {
    /// Look up elevation for a single coordinate.
    ///
    /// Loads the relevant tile from cache (or downloads it first).
    /// Uses bilinear interpolation between the 4 nearest grid points.
    func elevation(at coordinate: CLLocationCoordinate2D) async throws -> Double?

    /// Look up elevations for multiple coordinates efficiently.
    ///
    /// Groups coordinates by tile, loads each tile once, queries all points.
    func elevations(for coordinates: [CLLocationCoordinate2D]) async throws -> [Double?]

    /// Download elevation tile(s) covering the given bounding box.
    func downloadTiles(for boundingBox: BoundingBox, progress: @escaping (Int, Int) -> Void) async throws

    /// Clear cached elevation tiles to free storage.
    func clearCache() throws
}
```

### Bilinear Interpolation

For a query point (lat, lon), find the 4 surrounding grid points and interpolate:

```
Given: grid spacing = 1/3600 degrees (for 1-arc-second data)
Row = floor((tileNorthLat - lat) * 3600)
Col = floor((lon - tileWestLon) * 3600)
Interpolate between: (row,col), (row+1,col), (row,col+1), (row+1,col+1)
```

### Tile Naming & Download

**SRTM:** `https://e4ftl01.cr.usgs.gov/MEASURES/SRTMGL1.003/2000.02.11/{N|S}{lat}{E|W}{lon}.SRTMGL1.hgt.zip`
- Filename: `N47E011.hgt` (latitude zero-padded to 2 digits, longitude to 3)
- Requires NASA Earthdata login (free registration)

**Copernicus:** Available via AWS S3 (no auth required):
- `s3://copernicus-dem-30m/Copernicus_DSM_COG_10_{N|S}{lat:02d}_00_{E|W}{lon:03d}_DEM/`
- Each folder contains a GeoTIFF `.tif` file

**Strategy for the app:**
1. First check if Copernicus tile is available (preferred, global coverage, no auth)
2. Fall back to SRTM if Copernicus fails
3. Cache downloaded tiles in `Documents/elevation/` directory
4. Skip tiles over oceans (return nil for water areas)

### Testing

- Download a single HGT tile (e.g., the Alps: N47E011)
- Query a known peak (e.g., Zugspitze 47.4211°N, 10.9853°E, expected ~2962m)
- Verify interpolated elevation is within 30m of known value
- Test void handling (ocean, missing data)

---

## Sub-task 4.3: Routing Graph Builder

### Graph Construction Algorithm

1. **Parse OSM data:** Extract all trail ways and their node coordinates (Sub-task 4.1)
2. **Identify junctions:** Nodes that appear in 2+ ways are junction points
3. **Split ways at junctions:** Each segment between junctions becomes a routing edge
4. **Look up elevations:** Query elevation data for all junction nodes (Sub-task 4.2)
5. **Compute edge costs:** Distance + elevation penalties + surface/difficulty penalties
6. **Write to SQLite:** Insert nodes and edges into the routing database

### SQLite Schema

```sql
-- Junction nodes (intersections and endpoints of trail segments)
CREATE TABLE routing_nodes (
    id INTEGER PRIMARY KEY,          -- OSM node ID
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    elevation REAL                   -- meters ASL, from Copernicus/SRTM
);

-- Trail segments between junction nodes
CREATE TABLE routing_edges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_node INTEGER NOT NULL REFERENCES routing_nodes(id),
    to_node INTEGER NOT NULL REFERENCES routing_nodes(id),
    distance REAL NOT NULL,          -- meters (haversine)
    elevation_gain REAL DEFAULT 0,   -- meters (from → to direction)
    elevation_loss REAL DEFAULT 0,   -- meters (from → to direction)
    surface TEXT,                    -- paved, gravel, dirt, etc.
    highway_type TEXT,               -- path, footway, track, etc.
    sac_scale TEXT,                  -- hiking difficulty grade
    trail_visibility TEXT,           -- excellent, good, intermediate, etc.
    name TEXT,                       -- trail name from OSM
    osm_way_id INTEGER,             -- source way for attribution
    cost REAL NOT NULL,              -- precomputed forward A* cost
    reverse_cost REAL NOT NULL,      -- precomputed reverse A* cost
    is_oneway INTEGER DEFAULT 0,    -- 1 if one-way (rare for trails)
    geometry BLOB                   -- packed float32 intermediate coords
);

-- Indexes for routing queries
CREATE INDEX idx_nodes_lat_lon ON routing_nodes(latitude, longitude);
CREATE INDEX idx_edges_from ON routing_edges(from_node);
CREATE INDEX idx_edges_to ON routing_edges(to_node);

-- Metadata
CREATE TABLE routing_metadata (
    key TEXT PRIMARY KEY,
    value TEXT
);
-- Keys: version, created_at, bounding_box, node_count, edge_count,
--        osm_data_date, elevation_source
```

### Edge Geometry Storage

Non-junction intermediate nodes along a trail are stored as compressed geometry in the edge's `geometry` BLOB. This allows rendering the trail path without storing every intermediate node as a routing node.

**Format:** Packed float32 array: `[lat0, lon0, lat1, lon1, ...]`
- 8 bytes per intermediate point
- Only stored if there are intermediate nodes between junctions

### Cost Function

#### Hiking Mode (Naismith's Rule Extended)

```
forward_cost = distance × surface_multiplier × sac_multiplier
             + elevation_gain × 7.92    // Naismith: +1 hr per 600m gain
             + descent_cost(elevation_loss, avg_grade)
```

**Surface multipliers:**

| Surface Tag | Multiplier | Rationale |
|-------------|-----------|-----------|
| `paved`, `asphalt`, `concrete` | 1.0× | Easy, fast surface |
| `compacted`, `fine_gravel` | 1.1× | Well-maintained trail |
| `gravel` | 1.2× | Loose surface |
| `ground`, `dirt` | 1.3× | Natural surface |
| `grass` | 1.4× | Uneven, slippery when wet |
| `sand` | 1.8× | Energy-intensive |
| `rock`, `pebblestone` | 1.5× | Slow, careful footing |
| (unknown/missing) | 1.3× | Conservative default |

**SAC hiking scale multipliers:**

| SAC Grade | Multiplier | Description |
|-----------|-----------|-------------|
| `hiking` (T1) | 1.0× | Marked trail, no special equipment |
| `mountain_hiking` (T2) | 1.2× | Steeper, some scrambling |
| `demanding_mountain_hiking` (T3) | 1.5× | Exposed, hands needed |
| `alpine_hiking` (T4) | 2.0× | Alpine terrain, some via ferrata |
| `demanding_alpine_hiking` (T5) | 3.0× | Serious alpine, ropes needed |
| `difficult_alpine_hiking` (T6) | 5.0× | Expert only |

**Descent cost (based on Tobler's hiking function):**

| Average Grade | Descent Multiplier | Reasoning |
|--------------|-------------------|-----------|
| < 10% (gentle) | 0.5× of equivalent ascent | Easy downhill |
| 10–20% (moderate) | 0.8× | Starting to brake |
| 20–30% (steep) | 1.0× | As slow as flat |
| > 30% (very steep) | 1.5× | Dangerous, very slow |

#### Cycling Mode

Same structure with modified multipliers:
- Surface penalties are harsher (sand/grass = 3.0×, gravel = 1.5×)
- Elevation gain penalty increased (cycling harder uphill than walking)
- `steps` / `stairs`: cost = infinity (impassable by bike)
- `highway=footway` with `bicycle=no`: impassable

### Implementation

```swift
// OpenHiker iOS/Services/RoutingGraphBuilder.swift

/// Builds a routing graph SQLite database from parsed OSM data and elevation data.
actor RoutingGraphBuilder {
    /// Build a routing graph for the given region.
    ///
    /// - Parameters:
    ///   - ways: Parsed OSM ways (trails)
    ///   - nodes: Parsed OSM nodes (coordinates)
    ///   - elevationManager: For looking up node elevations
    ///   - outputPath: File path for the output .routing.db file
    ///   - progress: Callback with (step description, fraction 0.0–1.0)
    func buildGraph(
        ways: [PBFParser.OSMWay],
        nodes: [Int64: PBFParser.OSMNode],
        elevationManager: ElevationDataManager,
        outputPath: String,
        progress: @escaping (String, Double) -> Void
    ) async throws

    // Internal steps:
    // 1. identifyJunctions(ways:) -> Set<Int64>
    // 2. splitWaysAtJunctions(ways:, junctions:) -> [Edge]
    // 3. lookupElevations(nodes:, elevationManager:) async throws
    // 4. computeEdgeCosts(edges:) -> [Edge with costs]
    // 5. writeToSQLite(nodes:, edges:, outputPath:) throws
}
```

### Data Size Estimates

Based on typical OSM trail density:

| Region Size | Trail Nodes | Routing Nodes (Junctions) | Edges | SQLite Size |
|------------|-------------|--------------------------|-------|-------------|
| 10×10 km (city) | 5k–20k | 500–2k | 400–1.5k | 0.5–2 MB |
| 50×50 km (valley) | 50k–200k | 5k–20k | 4k–15k | 5–20 MB |
| 100×100 km (region) | 200k–800k | 20k–80k | 15k–60k | 20–80 MB |

These sizes are comparable to the MBTiles tile data, making the routing database a reasonable addition to the region download.

### Testing

- Build a graph from the Liechtenstein PBF extract
- Verify node count and edge count are reasonable
- Verify elevation values are populated for mountain nodes
- Verify cost asymmetry (uphill edge cost > downhill reverse cost)
- Verify junction detection (nodes shared by 2+ ways)

---

## Sub-task 4.4: Routing Engine (A\*)

### A\* Algorithm

```swift
// Shared/Services/RoutingEngine.swift

/// Offline routing engine using A* pathfinding on a precomputed trail graph.
///
/// Works on both iOS and watchOS by reading from a RoutingStore (SQLite).
final class RoutingEngine {
    private let store: RoutingStore

    /// Find the optimal hiking or cycling route between two points.
    ///
    /// - Parameters:
    ///   - from: Start coordinate (snapped to nearest routing node)
    ///   - to: End coordinate (snapped to nearest routing node)
    ///   - via: Optional intermediate waypoints
    ///   - mode: Routing mode (.hiking or .cycling)
    /// - Returns: A computed route with path, instructions, and statistics
    func findRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        via: [CLLocationCoordinate2D] = [],
        mode: RoutingMode
    ) throws -> ComputedRoute

    /// Find the nearest routing node to a coordinate.
    ///
    /// Uses the spatial index for efficient lookup.
    func nearestNode(to coordinate: CLLocationCoordinate2D) throws -> RoutingNode?
}

enum RoutingMode {
    case hiking
    case cycling
}

/// Result of a routing computation.
struct ComputedRoute {
    let nodes: [RoutingNode]              // ordered junction nodes
    let edges: [RoutingEdge]              // edges between nodes
    let totalDistance: Double              // meters
    let totalCost: Double                 // abstract cost units
    let estimatedDuration: TimeInterval   // seconds (from cost function)
    let elevationGain: Double             // meters
    let elevationLoss: Double             // meters
    let coordinates: [CLLocationCoordinate2D]  // full path including intermediate points
}
```

### A\* Heuristic

Use haversine distance as the admissible heuristic (always ≤ actual cost):

```swift
func heuristic(from: RoutingNode, to: RoutingNode) -> Double {
    let distance = haversineDistance(
        lat1: from.latitude, lon1: from.longitude,
        lat2: to.latitude, lon2: to.longitude
    )
    // Admissible: minimum possible cost is the straight-line distance
    // (no surface penalty, no elevation, flat terrain)
    return distance
}
```

### Nearest Node Lookup

For snapping start/end coordinates to the routing graph:

```swift
/// Find nodes within a radius, ordered by distance.
/// Uses SQLite index on (latitude, longitude) with bounding box pre-filter.
func nearestNode(to coordinate: CLLocationCoordinate2D, maxRadiusMeters: Double = 500) throws -> RoutingNode? {
    // 1. Compute bounding box for the search radius
    // 2. Query: SELECT * FROM routing_nodes WHERE latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?
    // 3. Sort results by haversine distance
    // 4. Return closest
}
```

### Routing Store (Read-Only SQLite)

```swift
// Shared/Storage/RoutingStore.swift

/// Read-only SQLite access to a precomputed routing graph.
///
/// Follows the TileStore pattern: serial queue, @unchecked Sendable, open/close lifecycle.
final class RoutingStore: @unchecked Sendable {
    func open() throws
    func close()
    func getNode(_ id: Int64) throws -> RoutingNode?
    func getEdgesFrom(_ nodeId: Int64) throws -> [RoutingEdge]
    func getEdgesTo(_ nodeId: Int64) throws -> [RoutingEdge]
    func getNodesInBoundingBox(_ bbox: BoundingBox) throws -> [RoutingNode]
    func getMetadata() throws -> [String: String]
}
```

### Performance Considerations

- **Priority queue:** Use a min-heap for the A\* open set (Swift doesn't have a built-in heap — implement a simple binary heap or use `CFBinaryHeap`)
- **Visited set:** `Set<Int64>` of visited node IDs
- **Edge loading:** Load edges on-demand per node (not all at once) to save memory on watchOS
- **Typical performance:** 50×50 km region with 10k nodes should route in < 1 second on Apple Watch
- **Via-point routing:** Route in segments (start → via1 → via2 → end), concatenate results

### Testing

- Route between two known points in a test region
- Verify path follows actual trails (not straight lines)
- Verify cost asymmetry: A→B uphill should cost more than B→A downhill
- Benchmark: 10k-node graph should route in < 1 second
- Test "no route found" case (disconnected graph segments)
- Test via-point routing: verify path passes through all via-points in order

---

## Sub-task 4.5: Integration with Region Download Pipeline

### Modified Download Flow

The existing `TileDownloader` (actor at `OpenHiker iOS/Services/TileDownloader.swift`) downloads map tiles for a region. Extend this to also build a routing graph:

```
1. User selects region          (existing)
2. Download map tiles           (existing TileDownloader)
3. Download OSM PBF extract     (NEW: OSMDataDownloader)
4. Download elevation tiles     (NEW: ElevationDataManager)
5. Parse PBF, filter trails     (NEW: PBFParser)
6. Build routing graph          (NEW: RoutingGraphBuilder)
7. Save as <uuid>.routing.db    (NEW)
8. Transfer .mbtiles + .routing.db to watch  (extend WatchTransferManager)
```

### OSM Data Download

For downloading OSM data for a specific bounding box, use the Overpass API for targeted extracts:

```
POST https://overpass-api.de/api/interpreter
data=[out:xml][bbox:{south},{west},{north},{east}];
     way["highway"~"path|footway|track|cycleway|bridleway|steps|pedestrian|
         residential|unclassified|tertiary|secondary|primary"];
     (._;>;);
     out body;
```

Or download the full regional PBF from Geofabrik and filter locally:
- Pros: No API rate limits, works offline after download
- Cons: Larger download (country-level PBF files can be hundreds of MB)

**Recommended approach:** Use Overpass API for regions < 100×100 km (quick, filtered). Fall back to Geofabrik PBF for larger regions.

### Files to Create

- `OpenHiker iOS/Services/OSMDataDownloader.swift` — Actor for downloading OSM trail data
- `OpenHiker iOS/Services/PBFParser.swift` — Pure Swift PBF decoder
- `OpenHiker iOS/Services/RoutingGraphBuilder.swift` — Graph construction
- `OpenHiker iOS/Services/ElevationDataManager.swift` — Copernicus/SRTM tile management
- `Shared/Storage/RoutingStore.swift` — Read-only routing graph access
- `Shared/Models/RoutingGraph.swift` — `RoutingNode`, `RoutingEdge`, `RoutingMode`, `ComputedRoute`
- `Shared/Services/RoutingEngine.swift` — A\* pathfinding

### Files to Modify

- `OpenHiker iOS/Services/TileDownloader.swift` — Add optional routing data build step
- `OpenHiker iOS/Services/WatchTransferManager.swift` — Transfer `.routing.db` alongside `.mbtiles`
- `OpenHiker watchOS/App/OpenHikerWatchApp.swift` — Receive and store `.routing.db` files
- `Shared/Models/Region.swift` — Add `hasRoutingData: Bool` to `Region` and `RegionMetadata`
- `OpenHiker iOS/App/ContentView.swift` — Add routing data toggle to download config

### Progress Reporting

Extend `RegionDownloadProgress.Status` to include routing-specific stages:
```swift
case downloadingTrailData    // "Downloading trail data..."
case downloadingElevation    // "Downloading elevation data..."
case buildingRoutingGraph    // "Building routing graph..."
```

### Testing End-to-End

1. Select a small region on iPhone (e.g., 10×10 km around a known hiking area)
2. Download tiles + routing data
3. Verify `.routing.db` file is created alongside `.mbtiles`
4. Open routing database — verify node and edge counts are reasonable
5. Run a route query between two points in the region
6. Transfer both files to watch — verify watch can open `.routing.db`
7. Test with regions from different continents:
   - European Alps (dense trail network, high elevation)
   - New Zealand Southern Alps (sparser trails)
   - Australian Blue Mountains (moderate density)
   - Scandinavian mountains above 60°N (test Copernicus coverage)
