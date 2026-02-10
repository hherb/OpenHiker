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

/// Read-only SQLite access to a precomputed routing graph.
///
/// Follows the same serial-queue pattern as ``TileStore``: all database
/// calls are dispatched on a private serial queue for thread safety,
/// and the class is `@unchecked Sendable` because it manages its own
/// synchronisation.
///
/// ## Typical lifecycle
/// ```swift
/// let store = RoutingStore(path: "/path/to/region.routing.db")
/// try store.open()
/// let node = try store.getNode(12345)
/// let edges = try store.getEdgesFrom(12345)
/// store.close()
/// ```
///
/// ## SQLite schema expected
/// ```
/// routing_nodes(id, latitude, longitude, elevation)
/// routing_edges(id, from_node, to_node, distance, elevation_gain, elevation_loss,
///               surface, highway_type, sac_scale, trail_visibility, name,
///               osm_way_id, cost, reverse_cost, is_oneway, geometry)
/// routing_metadata(key, value)
/// ```
final class RoutingStore: @unchecked Sendable {

    // MARK: - Properties

    /// The underlying SQLite database connection (`nil` when closed).
    private var db: OpaquePointer?

    /// File path to the `.routing.db` file.
    private let path: String

    /// Serial dispatch queue ensuring thread-safe database access.
    private let queue = DispatchQueue(label: "com.openhiker.routingstore", qos: .userInitiated)

    // MARK: - Lifecycle

    /// Create a routing store for the database at the given path.
    ///
    /// The database is not opened until ``open()`` is called.
    ///
    /// - Parameter path: Absolute file path to the routing SQLite database.
    init(path: String) {
        self.path = path
    }

    deinit {
        close()
    }

    /// Open the routing database in read-only mode.
    ///
    /// - Throws: ``RoutingError/databaseError(_:)`` if the file is missing
    ///   or SQLite cannot open it.
    func open() throws {
        try queue.sync {
            guard FileManager.default.fileExists(atPath: path) else {
                throw RoutingError.databaseError("Routing database not found at: \(path)")
            }

            var dbPointer: OpaquePointer?
            let result = sqlite3_open_v2(
                path,
                &dbPointer,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
                nil
            )

            guard result == SQLITE_OK, let openedDb = dbPointer else {
                let msg = String(cString: sqlite3_errmsg(dbPointer))
                sqlite3_close(dbPointer)
                throw RoutingError.databaseError(msg)
            }
            self.db = openedDb
        }
    }

    /// Close the database connection and release resources.
    ///
    /// Safe to call multiple times — subsequent calls are no-ops.
    func close() {
        queue.sync {
            if let db = db {
                sqlite3_close(db)
                self.db = nil
            }
        }
    }

    /// Whether the database is currently open.
    var isOpen: Bool {
        queue.sync { db != nil }
    }

    // MARK: - Node Queries

    /// Fetch a single routing node by its OSM node ID.
    ///
    /// - Parameter id: The OSM node ID.
    /// - Returns: The ``RoutingNode``, or `nil` if not found.
    /// - Throws: ``RoutingError/databaseError(_:)`` on SQLite failure.
    func getNode(_ id: Int64) throws -> RoutingNode? {
        try queue.sync {
            guard let db = db else { throw RoutingError.noRoutingData }

            let sql = "SELECT id, latitude, longitude, elevation FROM routing_nodes WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw RoutingError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, id)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return nodeFromStatement(stmt)
        }
    }

    /// Fetch all routing nodes whose coordinates fall within a bounding box.
    ///
    /// Uses the `idx_nodes_lat_lon` index for an efficient range scan.
    ///
    /// - Parameter bbox: The geographic bounding box.
    /// - Returns: An array of ``RoutingNode`` values inside the box.
    /// - Throws: ``RoutingError/databaseError(_:)`` on SQLite failure.
    func getNodesInBoundingBox(_ bbox: BoundingBox) throws -> [RoutingNode] {
        try queue.sync {
            guard let db = db else { throw RoutingError.noRoutingData }

            let sql = """
                SELECT id, latitude, longitude, elevation
                FROM routing_nodes
                WHERE latitude BETWEEN ? AND ?
                  AND longitude BETWEEN ? AND ?
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw RoutingError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, bbox.south)
            sqlite3_bind_double(stmt, 2, bbox.north)
            sqlite3_bind_double(stmt, 3, bbox.west)
            sqlite3_bind_double(stmt, 4, bbox.east)

            var nodes: [RoutingNode] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                nodes.append(nodeFromStatement(stmt))
            }
            return nodes
        }
    }

    /// Find the routing node nearest to a geographic coordinate.
    ///
    /// First queries a bounding-box rectangle derived from `maxRadiusMetres`,
    /// then sorts by haversine distance to pick the closest.
    ///
    /// - Parameters:
    ///   - coordinate: The geographic coordinate to search near.
    ///   - maxRadiusMetres: Search radius (default from ``RoutingCostConfig``).
    /// - Returns: The closest ``RoutingNode``, or `nil` if none are within range.
    /// - Throws: ``RoutingError/databaseError(_:)`` on SQLite failure.
    func nearestNode(
        to coordinate: CLLocationCoordinate2D,
        maxRadiusMetres: Double = RoutingCostConfig.nearestNodeSearchRadiusMetres
    ) throws -> RoutingNode? {
        let bbox = BoundingBox(center: coordinate, radiusMeters: maxRadiusMetres)
        let candidates = try getNodesInBoundingBox(bbox)

        return candidates.min(by: { a, b in
            let distA = haversineDistance(
                lat1: coordinate.latitude, lon1: coordinate.longitude,
                lat2: a.latitude, lon2: a.longitude
            )
            let distB = haversineDistance(
                lat1: coordinate.latitude, lon1: coordinate.longitude,
                lat2: b.latitude, lon2: b.longitude
            )
            return distA < distB
        })
    }

    // MARK: - Edge Queries

    /// Fetch all outgoing edges from a given node.
    ///
    /// An edge is "outgoing" from `nodeId` if `from_node == nodeId`, or if
    /// `to_node == nodeId` and the edge is **not** one-way. This lets A*
    /// traverse edges in both directions for undirected trails.
    ///
    /// - Parameter nodeId: The routing node ID.
    /// - Returns: An array of ``RoutingEdge`` values.
    /// - Throws: ``RoutingError/databaseError(_:)`` on SQLite failure.
    func getEdgesFrom(_ nodeId: Int64) throws -> [RoutingEdge] {
        try queue.sync {
            guard let db = db else { throw RoutingError.noRoutingData }

            // Forward edges (from_node = nodeId)
            var edges: [RoutingEdge] = []
            edges.append(contentsOf: try queryEdges(db: db,
                sql: edgeSelectSQL + " WHERE from_node = ?",
                bindNodeId: nodeId))

            // Reverse edges (to_node = nodeId, not one-way)
            edges.append(contentsOf: try queryEdges(db: db,
                sql: edgeSelectSQL + " WHERE to_node = ? AND is_oneway = 0",
                bindNodeId: nodeId))

            return edges
        }
    }

    /// Fetch all edges originating from a node (forward direction only).
    ///
    /// - Parameter nodeId: The routing node ID.
    /// - Returns: An array of ``RoutingEdge`` values where `from_node == nodeId`.
    /// - Throws: ``RoutingError/databaseError(_:)`` on SQLite failure.
    func getForwardEdges(from nodeId: Int64) throws -> [RoutingEdge] {
        try queue.sync {
            guard let db = db else { throw RoutingError.noRoutingData }
            return try queryEdges(db: db,
                sql: edgeSelectSQL + " WHERE from_node = ?",
                bindNodeId: nodeId)
        }
    }

    /// Fetch all edges ending at a node (reverse direction only, excluding one-way edges).
    ///
    /// - Parameter nodeId: The routing node ID.
    /// - Returns: An array of ``RoutingEdge`` values where `to_node == nodeId`.
    /// - Throws: ``RoutingError/databaseError(_:)`` on SQLite failure.
    func getReverseEdges(to nodeId: Int64) throws -> [RoutingEdge] {
        try queue.sync {
            guard let db = db else { throw RoutingError.noRoutingData }
            return try queryEdges(db: db,
                sql: edgeSelectSQL + " WHERE to_node = ? AND is_oneway = 0",
                bindNodeId: nodeId)
        }
    }

    // MARK: - Metadata

    /// Retrieve all key-value pairs from the `routing_metadata` table.
    ///
    /// Common keys: `version`, `created_at`, `bounding_box`, `node_count`,
    /// `edge_count`, `osm_data_date`, `elevation_source`.
    ///
    /// - Returns: A dictionary of metadata entries.
    /// - Throws: ``RoutingError/databaseError(_:)`` on SQLite failure.
    func getMetadata() throws -> [String: String] {
        try queue.sync {
            guard let db = db else { throw RoutingError.noRoutingData }

            let sql = "SELECT key, value FROM routing_metadata"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw RoutingError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            var dict: [String: String] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let keyPtr = sqlite3_column_text(stmt, 0),
                   let valPtr = sqlite3_column_text(stmt, 1) {
                    dict[String(cString: keyPtr)] = String(cString: valPtr)
                }
            }
            return dict
        }
    }

    /// Return the total number of routing nodes in the database.
    ///
    /// - Throws: ``RoutingError/databaseError(_:)`` on SQLite failure.
    func nodeCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM routing_nodes")
    }

    /// Return the total number of routing edges in the database.
    ///
    /// - Throws: ``RoutingError/databaseError(_:)`` on SQLite failure.
    func edgeCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM routing_edges")
    }

    // MARK: - Trail Overlay Data

    /// Lightweight edge data for rendering trail overlays on the map.
    ///
    /// Contains only the fields needed to draw a trail polyline:
    /// the highway type (for color selection) and the full coordinate
    /// sequence (fromNode + intermediate geometry + toNode).
    struct TrailEdgeData {
        /// OSM highway type (e.g., "path", "footway", "track").
        let highwayType: String
        /// Full polyline: fromNode coordinate + unpacked geometry + toNode coordinate.
        let coordinates: [CLLocationCoordinate2D]
    }

    /// Fetch all trail edges whose endpoints fall within a geographic bounding box.
    ///
    /// Queries edges where at least one endpoint node (from_node or to_node)
    /// is inside the bounding box, then reconstructs the full polyline for
    /// each edge. Used for rendering trail overlays on the map.
    ///
    /// Edges with a `NULL` highway_type are excluded since they provide no
    /// useful trail classification for rendering.
    ///
    /// - Parameter bbox: The geographic viewport bounding box.
    /// - Returns: An array of ``TrailEdgeData`` for rendering.
    /// - Throws: ``RoutingError/databaseError(_:)`` on SQLite failure.
    func getEdgesInBoundingBox(_ bbox: BoundingBox) throws -> [TrailEdgeData] {
        try queue.sync {
            guard let db = db else { throw RoutingError.noRoutingData }

            let sql = """
                SELECT DISTINCT e.id, e.highway_type, e.geometry,
                       fn.latitude, fn.longitude,
                       tn.latitude, tn.longitude
                FROM routing_edges e
                JOIN routing_nodes fn ON fn.id = e.from_node
                JOIN routing_nodes tn ON tn.id = e.to_node
                WHERE e.highway_type IS NOT NULL
                  AND ((fn.latitude BETWEEN ? AND ? AND fn.longitude BETWEEN ? AND ?)
                    OR (tn.latitude BETWEEN ? AND ? AND tn.longitude BETWEEN ? AND ?))
                """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw RoutingError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            // Bind bounding box for from_node
            sqlite3_bind_double(stmt, 1, bbox.south)
            sqlite3_bind_double(stmt, 2, bbox.north)
            sqlite3_bind_double(stmt, 3, bbox.west)
            sqlite3_bind_double(stmt, 4, bbox.east)
            // Bind bounding box for to_node
            sqlite3_bind_double(stmt, 5, bbox.south)
            sqlite3_bind_double(stmt, 6, bbox.north)
            sqlite3_bind_double(stmt, 7, bbox.west)
            sqlite3_bind_double(stmt, 8, bbox.east)

            var results: [TrailEdgeData] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                // Column 0: e.id (used for DISTINCT, not needed in result)
                guard let typePtr = sqlite3_column_text(stmt, 1) else { continue }
                let highwayType = String(cString: typePtr)

                // Parse geometry blob (column 2)
                var geometry: Data?
                if sqlite3_column_type(stmt, 2) != SQLITE_NULL,
                   let blob = sqlite3_column_blob(stmt, 2) {
                    let size = Int(sqlite3_column_bytes(stmt, 2))
                    geometry = Data(bytes: blob, count: size)
                }

                // Build full polyline: fromNode + intermediate + toNode
                let fromLat = sqlite3_column_double(stmt, 3)
                let fromLon = sqlite3_column_double(stmt, 4)
                let toLat = sqlite3_column_double(stmt, 5)
                let toLon = sqlite3_column_double(stmt, 6)

                var coordinates: [CLLocationCoordinate2D] = []
                coordinates.append(CLLocationCoordinate2D(latitude: fromLat, longitude: fromLon))
                coordinates.append(contentsOf: EdgeGeometry.unpack(geometry))
                coordinates.append(CLLocationCoordinate2D(latitude: toLat, longitude: toLon))

                results.append(TrailEdgeData(highwayType: highwayType, coordinates: coordinates))
            }
            return results
        }
    }

    // MARK: - Edge-Aware Nearest Point

    /// Result of snapping a coordinate to the nearest point on any trail edge.
    struct TrailSnapResult {
        /// The routing node to use for A* (the closer endpoint of the matched edge).
        let node: RoutingNode
        /// Distance in metres from the query coordinate to the closest point on the edge polyline.
        let distanceToTrail: Double
        /// The matched edge.
        let edge: RoutingEdge
    }

    /// Find the nearest point on any trail edge to a geographic coordinate.
    ///
    /// Unlike ``nearestNode(to:maxRadiusMetres:)`` which only considers junction nodes,
    /// this method checks the full polyline of every edge within range — including
    /// intermediate geometry points between junctions. This prevents snapping to a
    /// distant junction when the user taps midway along a trail segment.
    ///
    /// The method returns the closer endpoint node of the best-matching edge,
    /// which A* can then use as its start/end point.
    ///
    /// - Parameters:
    ///   - coordinate: The geographic coordinate to snap.
    ///   - maxRadiusMetres: Search radius (default from ``RoutingCostConfig``).
    /// - Returns: A ``TrailSnapResult`` with the best node, or `nil` if no trail is within range.
    /// - Throws: ``RoutingError/databaseError(_:)`` on SQLite failure.
    func nearestTrailPoint(
        to coordinate: CLLocationCoordinate2D,
        maxRadiusMetres: Double = RoutingCostConfig.nearestNodeSearchRadiusMetres
    ) throws -> TrailSnapResult? {
        try queue.sync {
            guard let db = db else { throw RoutingError.noRoutingData }

            let bbox = BoundingBox(center: coordinate, radiusMeters: maxRadiusMetres)

            // Find edges whose endpoint nodes fall within the bounding box.
            // We check both from_node and to_node so we catch edges that cross the area.
            let sql = """
                SELECT e.id, e.from_node, e.to_node, e.distance, e.elevation_gain, e.elevation_loss,
                       e.surface, e.highway_type, e.sac_scale, e.trail_visibility, e.name,
                       e.osm_way_id, e.cost, e.reverse_cost, e.is_oneway, e.geometry,
                       fn.latitude, fn.longitude, fn.elevation,
                       tn.latitude, tn.longitude, tn.elevation
                FROM routing_edges e
                JOIN routing_nodes fn ON fn.id = e.from_node
                JOIN routing_nodes tn ON tn.id = e.to_node
                WHERE (fn.latitude BETWEEN ? AND ? AND fn.longitude BETWEEN ? AND ?)
                   OR (tn.latitude BETWEEN ? AND ? AND tn.longitude BETWEEN ? AND ?)
                """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw RoutingError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            // Bind bounding box for from_node
            sqlite3_bind_double(stmt, 1, bbox.south)
            sqlite3_bind_double(stmt, 2, bbox.north)
            sqlite3_bind_double(stmt, 3, bbox.west)
            sqlite3_bind_double(stmt, 4, bbox.east)
            // Bind bounding box for to_node
            sqlite3_bind_double(stmt, 5, bbox.south)
            sqlite3_bind_double(stmt, 6, bbox.north)
            sqlite3_bind_double(stmt, 7, bbox.west)
            sqlite3_bind_double(stmt, 8, bbox.east)

            var bestResult: TrailSnapResult?
            var bestDistance = Double.infinity

            while sqlite3_step(stmt) == SQLITE_ROW {
                let edge = edgeFromStatement(stmt)

                // Parse from_node and to_node coordinates (columns 16-21)
                let fromLat = sqlite3_column_double(stmt, 16)
                let fromLon = sqlite3_column_double(stmt, 17)
                let fromElev: Double? = sqlite3_column_type(stmt, 18) == SQLITE_NULL
                    ? nil : sqlite3_column_double(stmt, 18)
                let toLat = sqlite3_column_double(stmt, 19)
                let toLon = sqlite3_column_double(stmt, 20)
                let toElev: Double? = sqlite3_column_type(stmt, 21) == SQLITE_NULL
                    ? nil : sqlite3_column_double(stmt, 21)

                let fromNode = RoutingNode(id: edge.fromNode, latitude: fromLat, longitude: fromLon, elevation: fromElev)
                let toNode = RoutingNode(id: edge.toNode, latitude: toLat, longitude: toLon, elevation: toElev)

                // Build the full polyline: fromNode + intermediate geometry + toNode
                var polyline: [CLLocationCoordinate2D] = [fromNode.coordinate]
                polyline.append(contentsOf: EdgeGeometry.unpack(edge.geometry))
                polyline.append(toNode.coordinate)

                // Find the closest point on this edge's polyline
                let closestDist = closestDistanceToPolyline(
                    from: coordinate, polyline: polyline
                )

                if closestDist < bestDistance {
                    bestDistance = closestDist

                    // Snap to whichever endpoint is closer to the query coordinate
                    let distToFrom = haversineDistance(
                        lat1: coordinate.latitude, lon1: coordinate.longitude,
                        lat2: fromLat, lon2: fromLon
                    )
                    let distToTo = haversineDistance(
                        lat1: coordinate.latitude, lon1: coordinate.longitude,
                        lat2: toLat, lon2: toLon
                    )
                    let snapNode = distToFrom <= distToTo ? fromNode : toNode

                    bestResult = TrailSnapResult(
                        node: snapNode,
                        distanceToTrail: closestDist,
                        edge: edge
                    )
                }
            }

            return bestResult
        }
    }

    /// Compute the minimum distance from a point to any segment of a polyline.
    ///
    /// Uses a simplified planar projection (sufficient at hiking scales) to find
    /// the perpendicular distance from the point to each line segment.
    ///
    /// - Parameters:
    ///   - from: The query coordinate.
    ///   - polyline: Ordered array of coordinates forming the polyline.
    /// - Returns: Minimum distance in metres.
    private func closestDistanceToPolyline(
        from point: CLLocationCoordinate2D,
        polyline: [CLLocationCoordinate2D]
    ) -> Double {
        guard polyline.count >= 2 else {
            if let only = polyline.first {
                return haversineDistance(
                    lat1: point.latitude, lon1: point.longitude,
                    lat2: only.latitude, lon2: only.longitude
                )
            }
            return .infinity
        }

        var minDist = Double.infinity
        for i in 0..<(polyline.count - 1) {
            let dist = distanceToLineSegment(
                point: point, segA: polyline[i], segB: polyline[i + 1]
            )
            minDist = min(minDist, dist)
        }
        return minDist
    }

    /// Compute the distance from a point to a line segment using planar approximation.
    ///
    /// Projects coordinates to a local flat plane using cos(latitude) scaling,
    /// then finds the closest point on the segment (clamped to endpoints).
    ///
    /// - Parameters:
    ///   - point: The query coordinate.
    ///   - segA: Start of the line segment.
    ///   - segB: End of the line segment.
    /// - Returns: Distance in metres.
    private func distanceToLineSegment(
        point: CLLocationCoordinate2D,
        segA: CLLocationCoordinate2D,
        segB: CLLocationCoordinate2D
    ) -> Double {
        // Convert to local metres using equirectangular projection
        let metersPerDegreeLat = 111_320.0
        let cosLat = cos(point.latitude * .pi / 180.0)
        let metersPerDegreeLon = 111_320.0 * cosLat

        let px = (point.longitude - segA.longitude) * metersPerDegreeLon
        let py = (point.latitude - segA.latitude) * metersPerDegreeLat
        let ax: Double = 0
        let ay: Double = 0
        let bx = (segB.longitude - segA.longitude) * metersPerDegreeLon
        let by = (segB.latitude - segA.latitude) * metersPerDegreeLat

        let dx = bx - ax
        let dy = by - ay
        let lenSq = dx * dx + dy * dy

        // Degenerate segment (both endpoints identical)
        if lenSq < 1e-10 {
            return sqrt(px * px + py * py)
        }

        // Project point onto the line, clamped to [0, 1]
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lenSq))
        let projX = ax + t * dx
        let projY = ay + t * dy

        let diffX = px - projX
        let diffY = py - projY
        return sqrt(diffX * diffX + diffY * diffY)
    }

    // MARK: - Private Helpers

    /// The SELECT column list shared by all edge queries.
    private let edgeSelectSQL = """
        SELECT id, from_node, to_node, distance, elevation_gain, elevation_loss,
               surface, highway_type, sac_scale, trail_visibility, name,
               osm_way_id, cost, reverse_cost, is_oneway, geometry
        FROM routing_edges
        """

    /// Execute an edge query that binds a single Int64 node ID parameter.
    private func queryEdges(db: OpaquePointer, sql: String, bindNodeId: Int64) throws -> [RoutingEdge] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RoutingError.databaseError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, bindNodeId)

        var edges: [RoutingEdge] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            edges.append(edgeFromStatement(stmt))
        }
        return edges
    }

    /// Parse a ``RoutingNode`` from the current row of a prepared statement.
    ///
    /// Expects columns: `id, latitude, longitude, elevation`.
    private func nodeFromStatement(_ stmt: OpaquePointer?) -> RoutingNode {
        let id = sqlite3_column_int64(stmt, 0)
        let lat = sqlite3_column_double(stmt, 1)
        let lon = sqlite3_column_double(stmt, 2)
        let elevation: Double? = sqlite3_column_type(stmt, 3) == SQLITE_NULL
            ? nil
            : sqlite3_column_double(stmt, 3)
        return RoutingNode(id: id, latitude: lat, longitude: lon, elevation: elevation)
    }

    /// Parse a ``RoutingEdge`` from the current row of a prepared statement.
    ///
    /// Expects 16 columns in the order defined by ``edgeSelectSQL``.
    private func edgeFromStatement(_ stmt: OpaquePointer?) -> RoutingEdge {
        let id = sqlite3_column_int64(stmt, 0)
        let fromNode = sqlite3_column_int64(stmt, 1)
        let toNode = sqlite3_column_int64(stmt, 2)
        let distance = sqlite3_column_double(stmt, 3)
        let elevationGain = sqlite3_column_double(stmt, 4)
        let elevationLoss = sqlite3_column_double(stmt, 5)

        let surface = columnText(stmt, 6)
        let highwayType = columnText(stmt, 7)
        let sacScale = columnText(stmt, 8)
        let trailVisibility = columnText(stmt, 9)
        let name = columnText(stmt, 10)

        let osmWayId: Int64? = sqlite3_column_type(stmt, 11) == SQLITE_NULL
            ? nil
            : sqlite3_column_int64(stmt, 11)

        let cost = sqlite3_column_double(stmt, 12)
        let reverseCost = sqlite3_column_double(stmt, 13)
        let isOneway = sqlite3_column_int(stmt, 14) != 0

        var geometry: Data?
        if sqlite3_column_type(stmt, 15) != SQLITE_NULL,
           let blob = sqlite3_column_blob(stmt, 15) {
            let size = Int(sqlite3_column_bytes(stmt, 15))
            geometry = Data(bytes: blob, count: size)
        }

        return RoutingEdge(
            id: id, fromNode: fromNode, toNode: toNode,
            distance: distance, elevationGain: elevationGain, elevationLoss: elevationLoss,
            surface: surface, highwayType: highwayType, sacScale: sacScale,
            trailVisibility: trailVisibility, name: name, osmWayId: osmWayId,
            cost: cost, reverseCost: reverseCost, isOneway: isOneway, geometry: geometry
        )
    }

    /// Read a nullable TEXT column, returning `nil` for SQL NULL.
    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let ptr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: ptr)
    }

    /// Execute a scalar query that returns a single INTEGER value.
    private func scalarInt(_ sql: String) throws -> Int {
        try queue.sync {
            guard let db = db else { throw RoutingError.noRoutingData }

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw RoutingError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_step(stmt) == SQLITE_ROW else {
                throw RoutingError.databaseError("Scalar query returned no rows")
            }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }
}
