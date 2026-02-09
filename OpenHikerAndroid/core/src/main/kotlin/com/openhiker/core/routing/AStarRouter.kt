/*
 * OpenHiker - Offline Hiking Navigation
 * Copyright (C) 2024 - 2026 Dr Horst Herb
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package com.openhiker.core.routing

import com.openhiker.core.geo.Haversine
import com.openhiker.core.model.Coordinate
import com.openhiker.core.model.RoutingMode
import java.util.PriorityQueue

/**
 * A* pathfinding algorithm for offline hiking and cycling route computation.
 *
 * Uses the Haversine straight-line distance as an admissible heuristic
 * (never overestimates real trail distance), guaranteeing optimal routes.
 *
 * Depends only on the [RoutingGraph] interface — no database or Android
 * framework dependencies. The graph implementation is injected, making
 * this class fully unit-testable with mock graphs.
 *
 * Supports multi-segment routing through via-points: the route is computed
 * as a series of A* searches between consecutive waypoints and concatenated
 * into a single [ComputedRoute].
 *
 * @param graph The routing graph to search (typically a Room DAO wrapper).
 */
class AStarRouter(private val graph: RoutingGraph) {

    /**
     * Finds the optimal route between two coordinates, optionally
     * passing through a sequence of via-points.
     *
     * Each coordinate is snapped to the nearest routing node within
     * [RoutingCostConfig.NEAREST_NODE_SEARCH_RADIUS_METRES]. Via-points
     * are processed in order and the resulting sub-routes are concatenated.
     *
     * @param from Start coordinate.
     * @param to End coordinate.
     * @param via Ordered intermediate waypoints (may be empty).
     * @param mode Routing mode (hiking or cycling).
     * @return A [ComputedRoute] with the full path and statistics.
     * @throws RoutingError if a node cannot be snapped, no path exists,
     *         or the graph is unavailable.
     */
    fun findRoute(
        from: Coordinate,
        to: Coordinate,
        via: List<Coordinate> = emptyList(),
        mode: RoutingMode
    ): ComputedRoute {
        // Build the ordered waypoint list: start, via..., end
        val waypoints = mutableListOf(from)
        waypoints.addAll(via)
        waypoints.add(to)

        // Snap every waypoint to its nearest routing node
        val snappedNodes = waypoints.mapIndexed { index, coord ->
            graph.findNearestNode(coord.latitude, coord.longitude)
                ?: throw when (index) {
                    0 -> RoutingError.NoNearbyNode(coord)
                    waypoints.size - 1 -> RoutingError.NoNearbyNode(coord)
                    else -> RoutingError.ViaPointNotReachable(index - 1, coord)
                }
        }

        // Route each consecutive pair and concatenate
        var allNodes = mutableListOf<RoutingNode>()
        var allEdges = mutableListOf<RoutingEdge>()
        var totalDistance = 0.0
        var totalCost = 0.0
        var totalGain = 0.0
        var totalLoss = 0.0
        var allCoordinates = mutableListOf<Coordinate>()

        for (i in 0 until snappedNodes.size - 1) {
            val startNode = snappedNodes[i]
            val endNode = snappedNodes[i + 1]

            // Short-circuit if start == end
            if (startNode.id == endNode.id) {
                if (allNodes.isEmpty()) {
                    allNodes.add(startNode)
                    allCoordinates.add(startNode.coordinate)
                }
                continue
            }

            val segment = astar(startNode, endNode, mode)

            // Merge: skip the first node/coordinate of each segment after
            // the first to avoid duplication at junctions
            if (allNodes.isEmpty()) {
                allNodes.addAll(segment.nodes)
                allCoordinates.addAll(segment.coordinates)
            } else {
                allNodes.addAll(segment.nodes.drop(1))
                allCoordinates.addAll(segment.coordinates.drop(1))
            }
            allEdges.addAll(segment.edges)

            totalDistance += segment.totalDistance
            totalCost += segment.totalCost
            totalGain += segment.elevationGain
            totalLoss += segment.elevationLoss
        }

        val baseSpeed = when (mode) {
            RoutingMode.HIKING -> RoutingCostConfig.HIKING_BASE_SPEED_MPS
            RoutingMode.CYCLING -> RoutingCostConfig.CYCLING_BASE_SPEED_MPS
        }
        val estimatedDuration = if (baseSpeed > 0) totalCost else 0.0

        return ComputedRoute(
            nodes = allNodes,
            edges = allEdges,
            totalDistance = totalDistance,
            totalCost = totalCost,
            estimatedDuration = estimatedDuration,
            elevationGain = totalGain,
            elevationLoss = totalLoss,
            coordinates = allCoordinates,
            viaPoints = via
        )
    }

    /**
     * Runs A* search from [startNode] to [endNode].
     *
     * Uses a min-heap (PriorityQueue) ordered by f = g + h, where g is
     * the best-known cost from start and h is the Haversine heuristic.
     *
     * @param startNode Origin routing node.
     * @param endNode Destination routing node.
     * @param mode Hiking or cycling (affects edge passability).
     * @return A [ComputedRoute] for this single segment.
     * @throws RoutingError.NoRouteFound if A* exhausts all reachable nodes.
     */
    private fun astar(
        startNode: RoutingNode,
        endNode: RoutingNode,
        mode: RoutingMode
    ): ComputedRoute {
        // g-cost: cheapest known cost from start to each node
        val gScore = HashMap<Long, Double>()
        gScore[startNode.id] = 0.0

        // For each node, the edge used to reach it and whether it was traversed in reverse
        val cameFromEdge = HashMap<Long, EdgeTraversal>()

        // Min-heap ordered by f = g + h
        val openSet = PriorityQueue<AStarEntry>()
        openSet.add(
            AStarEntry(
                nodeId = startNode.id,
                fScore = heuristic(startNode, endNode)
            )
        )

        // Closed set: fully explored nodes
        val closedSet = HashSet<Long>()

        // Track closest approach for diagnostics
        var closestApproachMetres = heuristic(startNode, endNode)

        while (openSet.isNotEmpty()) {
            val current = openSet.poll()
            val currentId = current.nodeId

            // Reached the destination?
            if (currentId == endNode.id) {
                return reconstructRoute(currentId, cameFromEdge, startNode, mode)
            }

            // Skip if already fully explored
            if (!closedSet.add(currentId)) continue

            val currentG = gScore[currentId] ?: Double.MAX_VALUE

            // Expand neighbours
            val edges = graph.getEdgesFrom(currentId)
            for (edge in edges) {
                val isForward = edge.fromNode == currentId
                val neighbourId = if (isForward) edge.toNode else edge.fromNode
                val edgeCost = if (isForward) edge.cost else edge.reverseCost

                // Skip impassable edges
                if (!edgeCost.isFinite()) continue

                // Apply mode-specific filtering
                if (!isEdgePassable(edge, mode)) continue

                // Skip already-explored nodes
                if (closedSet.contains(neighbourId)) continue

                val tentativeG = currentG + edgeCost
                val existingG = gScore[neighbourId] ?: Double.MAX_VALUE

                if (tentativeG < existingG) {
                    gScore[neighbourId] = tentativeG
                    cameFromEdge[neighbourId] = EdgeTraversal(edge, reversed = !isForward)

                    val neighbourNode = graph.getNode(neighbourId)
                    if (neighbourNode != null) {
                        val h = heuristic(neighbourNode, endNode)
                        closestApproachMetres = minOf(closestApproachMetres, h)
                        openSet.add(AStarEntry(neighbourId, tentativeG + h))
                    }
                }
            }
        }

        throw RoutingError.NoRouteFound(
            exploredNodes = closedSet.size,
            closestApproachMetres = closestApproachMetres
        )
    }

    /**
     * Admissible A* heuristic: Haversine straight-line distance.
     *
     * Never overestimates the actual trail distance, guaranteeing
     * A* finds the optimal path.
     */
    private fun heuristic(from: RoutingNode, to: RoutingNode): Double =
        Haversine.distance(from.latitude, from.longitude, to.latitude, to.longitude)

    /**
     * Checks whether an edge is passable for the given routing mode.
     *
     * Cyclists cannot traverse steps; hikers can traverse everything.
     */
    private fun isEdgePassable(edge: RoutingEdge, mode: RoutingMode): Boolean =
        when (mode) {
            RoutingMode.HIKING -> true
            RoutingMode.CYCLING -> edge.highwayType != RoutingCostConfig.HIGHWAY_STEPS
        }

    /**
     * Reconstructs the route from A*'s cameFromEdge map.
     *
     * Walks backward from the end node to the start node, collecting
     * nodes, edges, and coordinates, then reverses to start-to-end order.
     */
    private fun reconstructRoute(
        endNodeId: Long,
        cameFromEdge: Map<Long, EdgeTraversal>,
        startNode: RoutingNode,
        mode: RoutingMode
    ): ComputedRoute {
        // Trace back from end to start
        val edgesReversed = mutableListOf<EdgeTraversal>()
        var currentId = endNodeId

        while (true) {
            val entry = cameFromEdge[currentId] ?: break
            edgesReversed.add(entry)
            currentId = if (entry.reversed) entry.edge.toNode else entry.edge.fromNode
        }

        // Reverse to get start-to-end order
        edgesReversed.reverse()

        // Build the result
        val nodes = mutableListOf<RoutingNode>()
        val edges = mutableListOf<RoutingEdge>()
        val coordinates = mutableListOf<Coordinate>()
        var totalDistance = 0.0
        var totalGain = 0.0
        var totalLoss = 0.0
        var totalCost = 0.0

        // Add start node
        nodes.add(startNode)
        coordinates.add(startNode.coordinate)

        for (traversal in edgesReversed) {
            val edge = traversal.edge
            edges.add(edge)

            if (traversal.reversed) {
                // Traversing toNode -> fromNode: swap gain/loss
                totalGain += edge.elevationLoss
                totalLoss += edge.elevationGain
                totalCost += edge.reverseCost
            } else {
                totalGain += edge.elevationGain
                totalLoss += edge.elevationLoss
                totalCost += edge.cost
            }

            totalDistance += edge.distance

            // Add the far-end node
            val farNodeId = if (traversal.reversed) edge.fromNode else edge.toNode
            val farNode = graph.getNode(farNodeId)
            if (farNode != null) {
                nodes.add(farNode)
                coordinates.add(farNode.coordinate)
            }
        }

        val estimatedDuration = totalCost

        return ComputedRoute(
            nodes = nodes,
            edges = edges,
            totalDistance = totalDistance,
            totalCost = totalCost,
            estimatedDuration = estimatedDuration,
            elevationGain = totalGain,
            elevationLoss = totalLoss,
            coordinates = coordinates,
            viaPoints = emptyList()
        )
    }
}

/**
 * An entry in the A* open set, ordered by ascending f-score.
 *
 * @property nodeId The routing node ID.
 * @property fScore The f-score (g + h) for priority ordering.
 */
private data class AStarEntry(
    val nodeId: Long,
    val fScore: Double
) : Comparable<AStarEntry> {
    override fun compareTo(other: AStarEntry): Int = fScore.compareTo(other.fScore)
}

/**
 * Records how an edge was traversed during A* path reconstruction.
 *
 * @property edge The routing edge.
 * @property reversed True if the edge was traversed from toNode to fromNode.
 */
private data class EdgeTraversal(
    val edge: RoutingEdge,
    val reversed: Boolean
)
