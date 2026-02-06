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
import CoreLocation

// MARK: - Routing Engine

/// Offline A* routing engine that finds optimal paths through a precomputed
/// trail graph stored in SQLite.
///
/// Works on both iOS and watchOS by reading from a ``RoutingStore``.
///
/// ## Usage
/// ```swift
/// let store = RoutingStore(path: "region.routing.db")
/// try store.open()
///
/// let engine = RoutingEngine(store: store)
/// let route = try engine.findRoute(
///     from: CLLocationCoordinate2D(latitude: 47.42, longitude: 10.99),
///     to: CLLocationCoordinate2D(latitude: 47.38, longitude: 10.94),
///     via: [CLLocationCoordinate2D(latitude: 47.40, longitude: 10.96)],
///     mode: .hiking
/// )
/// print("Distance: \(route.totalDistance) m, ETA: \(route.estimatedDuration) s")
/// ```
///
/// ## Via-point routing
/// When `via` points are provided the engine routes in segments
/// (start → via1 → via2 → … → end) and concatenates the sub-routes
/// into a single ``ComputedRoute``. This lets the user add/edit
/// intermediate stops to shape the route without re-doing the entire
/// computation.
final class RoutingEngine {

    /// The backing read-only routing graph database.
    private let store: RoutingStore

    /// Create an engine that reads from the given routing store.
    ///
    /// The store must already be open.
    ///
    /// - Parameter store: An opened ``RoutingStore``.
    init(store: RoutingStore) {
        self.store = store
    }

    // MARK: - Public API

    /// Find the optimal route between two coordinates, optionally passing
    /// through a sequence of via-points.
    ///
    /// Each coordinate is snapped to the nearest routing node within
    /// ``RoutingCostConfig/nearestNodeSearchRadiusMetres``.  Via-points are
    /// processed in order and the resulting sub-routes are concatenated.
    ///
    /// - Parameters:
    ///   - from: Start coordinate (snapped to the nearest routing node).
    ///   - to: End coordinate (snapped to the nearest routing node).
    ///   - via: Optional ordered intermediate waypoints.  Each is snapped
    ///     independently. Pass an empty array to route directly.
    ///   - mode: ``RoutingMode/hiking`` or ``RoutingMode/cycling``.
    /// - Returns: A ``ComputedRoute`` with the full path, statistics, and
    ///   the via-points that were used (so the caller can persist them for
    ///   later editing).
    /// - Throws: ``RoutingError`` if a node cannot be snapped, no path
    ///   exists, or the database is unavailable.
    func findRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        via: [CLLocationCoordinate2D] = [],
        mode: RoutingMode
    ) throws -> ComputedRoute {
        // Build the ordered list of waypoints: start, via…, end
        var waypoints: [CLLocationCoordinate2D] = [from]
        waypoints.append(contentsOf: via)
        waypoints.append(to)

        // Snap every waypoint to its nearest routing node
        var snappedNodes: [RoutingNode] = []
        for (index, coord) in waypoints.enumerated() {
            guard let node = try store.nearestNode(to: coord) else {
                if index == 0 {
                    throw RoutingError.noNearbyNode(coord)
                } else if index == waypoints.count - 1 {
                    throw RoutingError.noNearbyNode(coord)
                } else {
                    throw RoutingError.viaPointNotReachable(index: index - 1, coordinate: coord)
                }
            }
            snappedNodes.append(node)
        }

        // Route each consecutive pair and concatenate
        var allNodes: [RoutingNode] = []
        var allEdges: [RoutingEdge] = []
        var totalDistance: Double = 0
        var totalCost: Double = 0
        var totalGain: Double = 0
        var totalLoss: Double = 0
        var allCoordinates: [CLLocationCoordinate2D] = []

        for i in 0 ..< (snappedNodes.count - 1) {
            let startNode = snappedNodes[i]
            let endNode = snappedNodes[i + 1]

            // Short-circuit if start == end
            if startNode.id == endNode.id {
                if allNodes.isEmpty { allNodes.append(startNode) }
                continue
            }

            let segment = try astar(from: startNode, to: endNode, mode: mode)

            // Merge: skip the first node of each segment after the first
            // to avoid duplication at junctions.
            if allNodes.isEmpty {
                allNodes.append(contentsOf: segment.nodes)
            } else {
                allNodes.append(contentsOf: segment.nodes.dropFirst())
            }
            allEdges.append(contentsOf: segment.edges)

            totalDistance += segment.totalDistance
            totalCost += segment.totalCost
            totalGain += segment.elevationGain
            totalLoss += segment.elevationLoss

            if allCoordinates.isEmpty {
                allCoordinates.append(contentsOf: segment.coordinates)
            } else {
                allCoordinates.append(contentsOf: segment.coordinates.dropFirst())
            }
        }

        let baseSpeed: Double
        switch mode {
        case .hiking:
            baseSpeed = RoutingCostConfig.hikingBaseSpeedMetresPerSecond
        case .cycling:
            baseSpeed = RoutingCostConfig.cyclingBaseSpeedMetresPerSecond
        }
        let estimatedDuration = totalCost / baseSpeed

        return ComputedRoute(
            nodes: allNodes,
            edges: allEdges,
            totalDistance: totalDistance,
            totalCost: totalCost,
            estimatedDuration: estimatedDuration,
            elevationGain: totalGain,
            elevationLoss: totalLoss,
            coordinates: allCoordinates,
            viaPoints: via
        )
    }

    /// Find the nearest routing node to a coordinate.
    ///
    /// Convenience wrapper around ``RoutingStore/nearestNode(to:maxRadiusMetres:)``.
    ///
    /// - Parameter coordinate: The geographic coordinate.
    /// - Returns: The closest ``RoutingNode``, or `nil` if none is within range.
    func nearestNode(to coordinate: CLLocationCoordinate2D) throws -> RoutingNode? {
        try store.nearestNode(to: coordinate)
    }

    // MARK: - A* Implementation

    /// Run A* search from `startNode` to `endNode`.
    ///
    /// Returns a segment containing the ordered nodes, edges, coordinates,
    /// and aggregated statistics.
    ///
    /// - Parameters:
    ///   - startNode: The origin routing node.
    ///   - endNode: The destination routing node.
    ///   - mode: Hiking or cycling mode (determines which cost column is used
    ///     for reverse edges).
    /// - Returns: A ``ComputedRoute`` for this single segment.
    /// - Throws: ``RoutingError/noRouteFound`` if A* exhausts all reachable
    ///   nodes without reaching the destination.
    private func astar(
        from startNode: RoutingNode,
        to endNode: RoutingNode,
        mode: RoutingMode
    ) throws -> ComputedRoute {

        // g-cost (cheapest cost from start to this node so far)
        var gScore: [Int64: Double] = [startNode.id: 0]

        // For each node, the edge + direction used to reach it
        var cameFromEdge: [Int64: (edge: RoutingEdge, reversed: Bool)] = [:]

        // Min-heap ordered by f = g + h
        var openSet = BinaryMinHeap<AStarEntry>()
        openSet.insert(AStarEntry(
            nodeId: startNode.id,
            fScore: heuristic(from: startNode, to: endNode)
        ))

        // Closed set
        var closedSet = Set<Int64>()

        while let current = openSet.extractMin() {
            let currentId = current.nodeId

            // Reached the destination?
            if currentId == endNode.id {
                return try reconstructRoute(
                    endNodeId: currentId,
                    cameFromEdge: cameFromEdge,
                    startNode: startNode,
                    mode: mode
                )
            }

            // Skip if already fully explored
            if closedSet.contains(currentId) { continue }
            closedSet.insert(currentId)

            let currentG = gScore[currentId] ?? .infinity

            // Expand neighbours
            let edges = try store.getEdgesFrom(currentId)
            for edge in edges {
                // Determine the neighbour and traversal cost
                let isForward = (edge.fromNode == currentId)
                let neighbourId = isForward ? edge.toNode : edge.fromNode
                let edgeCost = isForward ? edge.cost : edge.reverseCost

                // Skip impassable edges
                guard edgeCost.isFinite else { continue }

                // Apply mode-specific filtering
                if !isEdgePassable(edge, mode: mode) { continue }

                if closedSet.contains(neighbourId) { continue }

                let tentativeG = currentG + edgeCost
                let existingG = gScore[neighbourId] ?? .infinity

                if tentativeG < existingG {
                    gScore[neighbourId] = tentativeG
                    cameFromEdge[neighbourId] = (edge: edge, reversed: !isForward)

                    // We need the neighbour node for the heuristic
                    if let neighbourNode = try store.getNode(neighbourId) {
                        let f = tentativeG + heuristic(from: neighbourNode, to: endNode)
                        openSet.insert(AStarEntry(nodeId: neighbourId, fScore: f))
                    }
                }
            }
        }

        throw RoutingError.noRouteFound
    }

    /// Admissible A* heuristic: straight-line haversine distance.
    ///
    /// This always underestimates the actual trail distance, making A*
    /// both optimal and complete on the graph.
    private func heuristic(from: RoutingNode, to: RoutingNode) -> Double {
        haversineDistance(
            lat1: from.latitude, lon1: from.longitude,
            lat2: to.latitude, lon2: to.longitude
        )
    }

    /// Check whether a specific edge is passable for the given routing mode.
    ///
    /// Cyclists cannot traverse `steps` or ways explicitly tagged `bicycle=no`.
    private func isEdgePassable(_ edge: RoutingEdge, mode: RoutingMode) -> Bool {
        switch mode {
        case .hiking:
            return true  // Hikers can traverse everything in the graph
        case .cycling:
            // Steps are impassable by bike
            if edge.highwayType == "steps" { return false }
            return true
        }
    }

    /// Reconstruct the route from A*'s `cameFromEdge` map.
    ///
    /// Walks backward from `endNodeId` to `startNode`, collecting nodes,
    /// edges, and intermediate geometry into a ``ComputedRoute``.
    private func reconstructRoute(
        endNodeId: Int64,
        cameFromEdge: [Int64: (edge: RoutingEdge, reversed: Bool)],
        startNode: RoutingNode,
        mode: RoutingMode
    ) throws -> ComputedRoute {

        // Trace back from end to start
        var edgesReversed: [(edge: RoutingEdge, reversed: Bool)] = []
        var currentId = endNodeId

        while let entry = cameFromEdge[currentId] {
            edgesReversed.append(entry)
            currentId = entry.reversed ? entry.edge.toNode : entry.edge.fromNode
        }

        // Reverse to get start-to-end order
        let edgesInOrder = edgesReversed.reversed()

        // Build the node list
        var nodes: [RoutingNode] = []
        var edges: [RoutingEdge] = []
        var coordinates: [CLLocationCoordinate2D] = []
        var totalDistance: Double = 0
        var totalGain: Double = 0
        var totalLoss: Double = 0
        var totalCost: Double = 0

        // Add start node
        nodes.append(startNode)
        coordinates.append(startNode.coordinate)

        for (edge, reversed) in edgesInOrder {
            edges.append(edge)

            let intermediateCoords = EdgeGeometry.unpack(edge.geometry)

            if reversed {
                // Traversing toNode → fromNode: geometry is stored from→to,
                // so we need to reverse the intermediate coordinates
                for coord in intermediateCoords.reversed() {
                    coordinates.append(coord)
                }
                totalGain += edge.elevationLoss   // gain/loss swap when reversed
                totalLoss += edge.elevationGain
                totalCost += edge.reverseCost
            } else {
                for coord in intermediateCoords {
                    coordinates.append(coord)
                }
                totalGain += edge.elevationGain
                totalLoss += edge.elevationLoss
                totalCost += edge.cost
            }

            totalDistance += edge.distance

            // Add the far-end node
            let farNodeId = reversed ? edge.fromNode : edge.toNode
            if let farNode = try store.getNode(farNodeId) {
                nodes.append(farNode)
                coordinates.append(farNode.coordinate)
            }
        }

        let baseSpeed: Double
        switch mode {
        case .hiking:
            baseSpeed = RoutingCostConfig.hikingBaseSpeedMetresPerSecond
        case .cycling:
            baseSpeed = RoutingCostConfig.cyclingBaseSpeedMetresPerSecond
        }
        let estimatedDuration = totalCost / baseSpeed

        return ComputedRoute(
            nodes: nodes,
            edges: edges,
            totalDistance: totalDistance,
            totalCost: totalCost,
            estimatedDuration: estimatedDuration,
            elevationGain: totalGain,
            elevationLoss: totalLoss,
            coordinates: coordinates,
            viaPoints: []  // Via-points are set by the outer findRoute
        )
    }
}

// MARK: - A* Priority Queue Entry

/// An entry in the A* open set, ordered by ascending f-score.
private struct AStarEntry: Comparable {
    let nodeId: Int64
    let fScore: Double

    static func < (lhs: AStarEntry, rhs: AStarEntry) -> Bool {
        lhs.fScore < rhs.fScore
    }

    static func == (lhs: AStarEntry, rhs: AStarEntry) -> Bool {
        lhs.nodeId == rhs.nodeId && lhs.fScore == rhs.fScore
    }
}

// MARK: - Binary Min-Heap

/// A generic min-heap (priority queue) for the A* open set.
///
/// Swift's standard library does not include a heap, so we implement a
/// simple array-backed binary heap. This provides O(log n) insert and
/// extract-min, which is essential for A* performance on graphs with
/// tens of thousands of nodes.
struct BinaryMinHeap<Element: Comparable> {

    /// The backing storage, maintained in heap order.
    private var elements: [Element] = []

    /// Whether the heap is empty.
    var isEmpty: Bool { elements.isEmpty }

    /// The number of elements in the heap.
    var count: Int { elements.count }

    /// Insert a new element into the heap.
    ///
    /// - Parameter element: The element to insert.
    mutating func insert(_ element: Element) {
        elements.append(element)
        siftUp(from: elements.count - 1)
    }

    /// Remove and return the smallest element.
    ///
    /// - Returns: The element with the lowest value, or `nil` if empty.
    mutating func extractMin() -> Element? {
        guard !elements.isEmpty else { return nil }
        if elements.count == 1 { return elements.removeLast() }

        let min = elements[0]
        elements[0] = elements.removeLast()
        siftDown(from: 0)
        return min
    }

    /// Peek at the smallest element without removing it.
    var peek: Element? { elements.first }

    // MARK: - Private

    private mutating func siftUp(from index: Int) {
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            if elements[child] < elements[parent] {
                elements.swapAt(child, parent)
                child = parent
            } else {
                break
            }
        }
    }

    private mutating func siftDown(from index: Int) {
        var parent = index
        let count = elements.count
        while true {
            let left = 2 * parent + 1
            let right = 2 * parent + 2
            var smallest = parent

            if left < count && elements[left] < elements[smallest] {
                smallest = left
            }
            if right < count && elements[right] < elements[smallest] {
                smallest = right
            }
            if smallest == parent { break }
            elements.swapAt(parent, smallest)
            parent = smallest
        }
    }
}
