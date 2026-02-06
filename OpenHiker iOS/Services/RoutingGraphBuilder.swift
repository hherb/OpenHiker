// Copyright (C) 2024-2026 Dr Horst Herb
//
// This file is part of OpenHiker.
//
// OpenHiker is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// OpenHiker is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with OpenHiker. If not, see <https://www.gnu.org/licenses/>.

import Foundation
import SQLite3
import CoreLocation

/// SQLite transient destructor type — tells SQLite to make its own copy of bound data.
/// Using this instead of `nil` (SQLITE_STATIC) ensures pointer safety when the Swift
/// value's lifetime may end before `sqlite3_step` is called.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Builds a routing graph SQLite database from parsed OSM data and elevation data.
///
/// ## Graph construction algorithm
/// 1. **Identify junctions**: Nodes that appear in ≥ 2 ways are junction points.
/// 2. **Split ways at junctions**: Each segment between junctions becomes a
///    routing edge. Intermediate nodes become packed geometry on the edge.
/// 3. **Look up elevations**: Query ``ElevationDataManager`` for all junction
///    node elevations.
/// 4. **Compute edge costs**: Distance + elevation penalties + surface/SAC
///    multipliers, for both forward and reverse traversal.
/// 5. **Write to SQLite**: Insert nodes and edges into the `.routing.db` file.
///
/// ## Data size estimates
/// | Region Size | Routing Nodes | Edges | SQLite Size |
/// |------------|---------------|-------|-------------|
/// | 10×10 km   | 500–2 k       | 400–1.5 k | 0.5–2 MB |
/// | 50×50 km   | 5 k–20 k      | 4 k–15 k  | 5–20 MB  |
/// | 100×100 km | 20 k–80 k     | 15 k–60 k | 20–80 MB |
actor RoutingGraphBuilder {

    /// Errors that can occur during graph construction.
    enum BuildError: Error, LocalizedError {
        case noTrailsFound
        case databaseCreationFailed(String)
        case inconsistentData(String)

        var errorDescription: String? {
            switch self {
            case .noTrailsFound:
                return "No hiking or cycling trails found in the downloaded OSM data."
            case .databaseCreationFailed(let msg):
                return "Failed to create routing database: \(msg)"
            case .inconsistentData(let msg):
                return "Inconsistent data during graph build: \(msg)"
            }
        }
    }

    /// A raw edge before being written to the database.
    private struct RawEdge {
        let fromNodeId: Int64
        let toNodeId: Int64
        let intermediateCoords: [CLLocationCoordinate2D]
        let distance: Double
        let tags: [String: String]
        let osmWayId: Int64
    }

    // MARK: - Public API

    /// Build a routing graph for a region.
    ///
    /// - Parameters:
    ///   - ways: Parsed OSM ways (filtered to routable trails).
    ///   - nodes: Parsed OSM nodes keyed by ID.
    ///   - elevationManager: For looking up junction node elevations.
    ///   - outputPath: File path for the output `.routing.db` file.
    ///   - boundingBox: The region's geographic bounding box (for metadata).
    ///   - progress: Callback with `(stepDescription, fractionComplete 0.0–1.0)`.
    func buildGraph(
        ways: [PBFParser.OSMWay],
        nodes: [Int64: PBFParser.OSMNode],
        elevationManager: ElevationDataManager,
        outputPath: String,
        boundingBox: BoundingBox,
        progress: @escaping (String, Double) -> Void
    ) async throws {

        guard !ways.isEmpty else { throw BuildError.noTrailsFound }

        // Step 1: Identify junctions
        progress("Identifying trail junctions...", 0.05)
        let junctions = identifyJunctions(ways: ways)

        // Step 2: Split ways at junctions into edges
        progress("Splitting trails into segments...", 0.15)
        let rawEdges = splitWaysAtJunctions(ways: ways, nodes: nodes, junctions: junctions)

        // Collect all junction node IDs
        var junctionNodeIds = Set<Int64>()
        for edge in rawEdges {
            junctionNodeIds.insert(edge.fromNodeId)
            junctionNodeIds.insert(edge.toNodeId)
        }

        // Step 3: Look up elevations for all junction nodes
        progress("Looking up elevations...", 0.30)
        let junctionCoords: [(id: Int64, coord: CLLocationCoordinate2D)] = junctionNodeIds.compactMap { id in
            guard let node = nodes[id] else { return nil }
            return (id: id, coord: CLLocationCoordinate2D(latitude: node.latitude, longitude: node.longitude))
        }

        let elevationValues = try await elevationManager.elevations(
            for: junctionCoords.map { $0.coord }
        )

        var nodeElevations: [Int64: Double] = [:]
        for (i, entry) in junctionCoords.enumerated() {
            nodeElevations[entry.id] = elevationValues[i]
        }

        // Step 4: Compute edge costs
        progress("Computing edge costs...", 0.55)
        let costEdges = computeEdgeCosts(
            rawEdges: rawEdges,
            nodes: nodes,
            nodeElevations: nodeElevations
        )

        // Step 5: Write to SQLite
        progress("Writing routing database...", 0.70)
        try writeToSQLite(
            junctionNodeIds: junctionNodeIds,
            nodes: nodes,
            nodeElevations: nodeElevations,
            edges: costEdges,
            outputPath: outputPath,
            boundingBox: boundingBox
        )

        let nodeCountResult = junctionNodeIds.count
        let edgeCountResult = costEdges.count
        progress("Routing graph complete: \(nodeCountResult) nodes, \(edgeCountResult) edges", 1.0)
    }

    // MARK: - Step 1: Identify Junctions

    /// Find all OSM node IDs that appear in two or more ways.
    ///
    /// These are intersections (or dead-ends) where the routing graph needs
    /// a node. All other nodes along a way become intermediate geometry.
    ///
    /// - Parameter ways: The parsed routable ways.
    /// - Returns: A set of junction node IDs.
    private func identifyJunctions(ways: [PBFParser.OSMWay]) -> Set<Int64> {
        var nodeCounts: [Int64: Int] = [:]

        for way in ways {
            // Start and end nodes are always junctions
            if let first = way.nodeRefs.first {
                nodeCounts[first, default: 0] += 2  // Force-promote start nodes
            }
            if let last = way.nodeRefs.last {
                nodeCounts[last, default: 0] += 2  // Force-promote end nodes
            }
            // Count interior nodes
            for nodeRef in way.nodeRefs.dropFirst().dropLast() {
                nodeCounts[nodeRef, default: 0] += 1
            }
        }

        // Junctions are nodes that appear in 2+ ways OR are start/end of a way
        return Set(nodeCounts.filter { $0.value >= 2 }.map { $0.key })
    }

    // MARK: - Step 2: Split Ways at Junctions

    /// Split each way at junction nodes to create routing edges.
    ///
    /// For a way with node refs [A, B, C, D, E] where B and D are junctions,
    /// this creates edges: A→B (with no intermediates), B→D (with C as
    /// intermediate geometry), D→E (with no intermediates).
    ///
    /// - Parameters:
    ///   - ways: The parsed ways to split.
    ///   - nodes: All parsed nodes (for coordinate lookup).
    ///   - junctions: The set of junction node IDs.
    /// - Returns: An array of raw edges ready for cost computation.
    private func splitWaysAtJunctions(
        ways: [PBFParser.OSMWay],
        nodes: [Int64: PBFParser.OSMNode],
        junctions: Set<Int64>
    ) -> [RawEdge] {

        var edges: [RawEdge] = []

        for way in ways {
            let refs = way.nodeRefs
            guard refs.count >= 2 else { continue }

            var segmentStartId = refs[0]
            var intermediateCoords: [CLLocationCoordinate2D] = []
            var segmentDistance: Double = 0
            var prevCoord: CLLocationCoordinate2D?

            if let startNode = nodes[segmentStartId] {
                prevCoord = CLLocationCoordinate2D(
                    latitude: startNode.latitude, longitude: startNode.longitude
                )
            }

            for i in 1..<refs.count {
                let nodeId = refs[i]
                guard let node = nodes[nodeId] else { continue }
                let coord = CLLocationCoordinate2D(latitude: node.latitude, longitude: node.longitude)

                // Accumulate distance
                if let prev = prevCoord {
                    segmentDistance += haversineDistance(
                        lat1: prev.latitude, lon1: prev.longitude,
                        lat2: coord.latitude, lon2: coord.longitude
                    )
                }
                prevCoord = coord

                if junctions.contains(nodeId) || i == refs.count - 1 {
                    // End of segment — create an edge
                    edges.append(RawEdge(
                        fromNodeId: segmentStartId,
                        toNodeId: nodeId,
                        intermediateCoords: intermediateCoords,
                        distance: segmentDistance,
                        tags: way.tags,
                        osmWayId: way.id
                    ))

                    // Reset for next segment
                    segmentStartId = nodeId
                    intermediateCoords = []
                    segmentDistance = 0
                } else {
                    // Interior node — becomes intermediate geometry
                    intermediateCoords.append(coord)
                }
            }
        }

        return edges
    }

    // MARK: - Step 3: Compute Edge Costs

    /// Represents an edge with pre-computed costs, ready for SQLite insertion.
    private struct CostEdge {
        let fromNodeId: Int64
        let toNodeId: Int64
        let distance: Double
        let elevationGain: Double
        let elevationLoss: Double
        let surface: String?
        let highwayType: String?
        let sacScale: String?
        let trailVisibility: String?
        let name: String?
        let osmWayId: Int64
        let forwardCost: Double
        let reverseCost: Double
        let isOneway: Bool
        let geometry: Data?
    }

    /// Compute forward and reverse traversal costs for each edge.
    ///
    /// Uses Naismith's rule extended with surface and SAC-scale multipliers.
    ///
    /// - Parameters:
    ///   - rawEdges: The split way segments.
    ///   - nodes: All parsed nodes (for coordinate lookup).
    ///   - nodeElevations: Elevation values keyed by node ID.
    /// - Returns: Edges with populated cost fields.
    private func computeEdgeCosts(
        rawEdges: [RawEdge],
        nodes: [Int64: PBFParser.OSMNode],
        nodeElevations: [Int64: Double]
    ) -> [CostEdge] {

        return rawEdges.map { raw in
            let fromElev = nodeElevations[raw.fromNodeId]
            let toElev = nodeElevations[raw.toNodeId]

            // Elevation gain/loss in forward direction
            var elevGain: Double = 0
            var elevLoss: Double = 0
            if let fromE = fromElev, let toE = toElev {
                let diff = toE - fromE
                if diff > 0 {
                    elevGain = diff
                } else {
                    elevLoss = abs(diff)
                }
            }

            let surface = raw.tags["surface"]
            let highwayType = raw.tags["highway"]
            let sacScale = raw.tags["sac_scale"]
            let trailVisibility = raw.tags["trail_visibility"]
            let name = raw.tags["name"]

            // One-way detection
            let oneway = raw.tags["oneway"]
            let isOneway = (oneway == "yes" || oneway == "1" || oneway == "true")

            // Surface multiplier (hiking mode)
            let surfaceMultiplier: Double
            if let s = surface, let m = RoutingCostConfig.hikingSurfaceMultipliers[s] {
                surfaceMultiplier = m
            } else {
                surfaceMultiplier = RoutingCostConfig.defaultHikingSurfaceMultiplier
            }

            // SAC scale multiplier
            let sacMultiplier: Double
            if let s = sacScale, let m = RoutingCostConfig.sacScaleMultipliers[s] {
                sacMultiplier = m
            } else {
                sacMultiplier = RoutingCostConfig.defaultSacMultiplier
            }

            // Forward cost (from → to)
            let forwardCost = computeDirectionalCost(
                distance: raw.distance,
                elevationGain: elevGain,
                elevationLoss: elevLoss,
                surfaceMultiplier: surfaceMultiplier,
                sacMultiplier: sacMultiplier,
                highwayType: highwayType
            )

            // Reverse cost (to → from): gain and loss are swapped
            let reverseCost: Double
            if isOneway {
                reverseCost = RoutingCostConfig.impassableCost
            } else {
                reverseCost = computeDirectionalCost(
                    distance: raw.distance,
                    elevationGain: elevLoss,   // Swapped
                    elevationLoss: elevGain,   // Swapped
                    surfaceMultiplier: surfaceMultiplier,
                    sacMultiplier: sacMultiplier,
                    highwayType: highwayType
                )
            }

            let geometry = EdgeGeometry.pack(raw.intermediateCoords)

            return CostEdge(
                fromNodeId: raw.fromNodeId,
                toNodeId: raw.toNodeId,
                distance: raw.distance,
                elevationGain: elevGain,
                elevationLoss: elevLoss,
                surface: surface,
                highwayType: highwayType,
                sacScale: sacScale,
                trailVisibility: trailVisibility,
                name: name,
                osmWayId: raw.osmWayId,
                forwardCost: forwardCost,
                reverseCost: reverseCost,
                isOneway: isOneway,
                geometry: geometry
            )
        }
    }

    /// Compute the traversal cost for one direction of an edge.
    ///
    /// ```
    /// cost = distance × surfaceMultiplier × sacMultiplier
    ///      + elevationGain × climbPenalty
    ///      + descentCost(elevationLoss, grade)
    /// ```
    ///
    /// - Parameters:
    ///   - distance: Horizontal distance in metres.
    ///   - elevationGain: Uphill metres in this direction.
    ///   - elevationLoss: Downhill metres in this direction.
    ///   - surfaceMultiplier: Surface penalty (1.0 = paved).
    ///   - sacMultiplier: SAC hiking scale penalty (1.0 = easy trail).
    ///   - highwayType: OSM highway type for special-case handling.
    /// - Returns: The abstract cost value.
    private func computeDirectionalCost(
        distance: Double,
        elevationGain: Double,
        elevationLoss: Double,
        surfaceMultiplier: Double,
        sacMultiplier: Double,
        highwayType: String?
    ) -> Double {
        // Steps get an extra penalty for hiking (steep, slow)
        let stepsPenalty: Double = (highwayType == "steps") ? 1.5 : 1.0

        var cost = distance * surfaceMultiplier * sacMultiplier * stepsPenalty

        // Ascent cost (Naismith's rule)
        cost += elevationGain * RoutingCostConfig.hikingClimbPenaltyPerMetre

        // Descent cost (Tobler's function)
        if elevationLoss > 0 && distance > 0 {
            let gradePercent = (elevationLoss / distance) * 100.0
            let descentMultiplier = RoutingCostConfig.descentMultiplier(gradePercent: gradePercent)
            cost += elevationLoss * RoutingCostConfig.hikingClimbPenaltyPerMetre * descentMultiplier
        }

        return cost
    }

    // MARK: - Step 4: Write to SQLite

    /// Write the complete routing graph to a SQLite database.
    ///
    /// Creates the schema, inserts all nodes and edges, creates indexes,
    /// and writes metadata. The entire write is wrapped in a transaction
    /// for performance.
    private func writeToSQLite(
        junctionNodeIds: Set<Int64>,
        nodes: [Int64: PBFParser.OSMNode],
        nodeElevations: [Int64: Double],
        edges: [CostEdge],
        outputPath: String,
        boundingBox: BoundingBox
    ) throws {
        // Create parent directory
        let parentDir = (outputPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        // Remove existing file
        if FileManager.default.fileExists(atPath: outputPath) {
            try FileManager.default.removeItem(atPath: outputPath)
        }

        var db: OpaquePointer?
        let result = sqlite3_open_v2(
            outputPath, &db,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard result == SQLITE_OK, let db = db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(db)
            throw BuildError.databaseCreationFailed(msg)
        }

        defer { sqlite3_close(db) }

        // Create schema
        try executeSQL(db: db, sql: """
            CREATE TABLE routing_nodes (
                id INTEGER PRIMARY KEY,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                elevation REAL
            )
            """)

        try executeSQL(db: db, sql: """
            CREATE TABLE routing_edges (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                from_node INTEGER NOT NULL REFERENCES routing_nodes(id),
                to_node INTEGER NOT NULL REFERENCES routing_nodes(id),
                distance REAL NOT NULL,
                elevation_gain REAL DEFAULT 0,
                elevation_loss REAL DEFAULT 0,
                surface TEXT,
                highway_type TEXT,
                sac_scale TEXT,
                trail_visibility TEXT,
                name TEXT,
                osm_way_id INTEGER,
                cost REAL NOT NULL,
                reverse_cost REAL NOT NULL,
                is_oneway INTEGER DEFAULT 0,
                geometry BLOB
            )
            """)

        try executeSQL(db: db, sql: """
            CREATE TABLE routing_metadata (
                key TEXT PRIMARY KEY,
                value TEXT
            )
            """)

        // Begin transaction for bulk insert
        try executeSQL(db: db, sql: "BEGIN TRANSACTION")

        // Insert nodes
        let insertNodeSQL = "INSERT OR IGNORE INTO routing_nodes (id, latitude, longitude, elevation) VALUES (?, ?, ?, ?)"
        var nodeStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertNodeSQL, -1, &nodeStmt, nil) == SQLITE_OK else {
            throw BuildError.databaseCreationFailed(String(cString: sqlite3_errmsg(db)))
        }

        for nodeId in junctionNodeIds {
            guard let node = nodes[nodeId] else { continue }

            sqlite3_reset(nodeStmt)
            sqlite3_bind_int64(nodeStmt, 1, nodeId)
            sqlite3_bind_double(nodeStmt, 2, node.latitude)
            sqlite3_bind_double(nodeStmt, 3, node.longitude)

            if let elev = nodeElevations[nodeId] {
                sqlite3_bind_double(nodeStmt, 4, elev)
            } else {
                sqlite3_bind_null(nodeStmt, 4)
            }

            guard sqlite3_step(nodeStmt) == SQLITE_DONE else {
                sqlite3_finalize(nodeStmt)
                throw BuildError.databaseCreationFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
        sqlite3_finalize(nodeStmt)

        // Insert edges
        let insertEdgeSQL = """
            INSERT INTO routing_edges
            (from_node, to_node, distance, elevation_gain, elevation_loss,
             surface, highway_type, sac_scale, trail_visibility, name,
             osm_way_id, cost, reverse_cost, is_oneway, geometry)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        var edgeStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertEdgeSQL, -1, &edgeStmt, nil) == SQLITE_OK else {
            throw BuildError.databaseCreationFailed(String(cString: sqlite3_errmsg(db)))
        }

        for edge in edges {
            sqlite3_reset(edgeStmt)
            sqlite3_bind_int64(edgeStmt, 1, edge.fromNodeId)
            sqlite3_bind_int64(edgeStmt, 2, edge.toNodeId)
            sqlite3_bind_double(edgeStmt, 3, edge.distance)
            sqlite3_bind_double(edgeStmt, 4, edge.elevationGain)
            sqlite3_bind_double(edgeStmt, 5, edge.elevationLoss)

            bindTextOrNull(edgeStmt, 6, edge.surface)
            bindTextOrNull(edgeStmt, 7, edge.highwayType)
            bindTextOrNull(edgeStmt, 8, edge.sacScale)
            bindTextOrNull(edgeStmt, 9, edge.trailVisibility)
            bindTextOrNull(edgeStmt, 10, edge.name)

            sqlite3_bind_int64(edgeStmt, 11, edge.osmWayId)
            sqlite3_bind_double(edgeStmt, 12, edge.forwardCost)
            sqlite3_bind_double(edgeStmt, 13, edge.reverseCost)
            sqlite3_bind_int(edgeStmt, 14, edge.isOneway ? 1 : 0)

            if let geom = edge.geometry {
                geom.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(edgeStmt, 15, ptr.baseAddress, Int32(geom.count), SQLITE_TRANSIENT)
                }
            } else {
                sqlite3_bind_null(edgeStmt, 15)
            }

            guard sqlite3_step(edgeStmt) == SQLITE_DONE else {
                sqlite3_finalize(edgeStmt)
                throw BuildError.databaseCreationFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
        sqlite3_finalize(edgeStmt)

        // Create indexes
        try executeSQL(db: db, sql: "CREATE INDEX idx_nodes_lat_lon ON routing_nodes(latitude, longitude)")
        try executeSQL(db: db, sql: "CREATE INDEX idx_edges_from ON routing_edges(from_node)")
        try executeSQL(db: db, sql: "CREATE INDEX idx_edges_to ON routing_edges(to_node)")

        // Insert metadata
        let insertMetaSQL = "INSERT INTO routing_metadata (key, value) VALUES (?, ?)"
        let metaEntries: [(String, String)] = [
            ("version", "1"),
            ("created_at", ISO8601DateFormatter().string(from: Date())),
            ("bounding_box", "\(boundingBox.west),\(boundingBox.south),\(boundingBox.east),\(boundingBox.north)"),
            ("node_count", String(junctionNodeIds.count)),
            ("edge_count", String(edges.count)),
            ("elevation_source", "copernicus_srtm")
        ]

        for (key, value) in metaEntries {
            var metaStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, insertMetaSQL, -1, &metaStmt, nil) == SQLITE_OK else {
                throw BuildError.databaseCreationFailed(String(cString: sqlite3_errmsg(db)))
            }
            sqlite3_bind_text(metaStmt, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(metaStmt, 2, value, -1, SQLITE_TRANSIENT)
            sqlite3_step(metaStmt)
            sqlite3_finalize(metaStmt)
        }

        // Commit transaction
        try executeSQL(db: db, sql: "COMMIT")
    }

    // MARK: - SQLite Helpers

    /// Execute a raw SQL statement on the database.
    private func executeSQL(db: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let msg = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw BuildError.databaseCreationFailed(msg)
        }
    }

    /// Bind a String value or NULL to a prepared statement parameter.
    private func bindTextOrNull(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value = value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
}
