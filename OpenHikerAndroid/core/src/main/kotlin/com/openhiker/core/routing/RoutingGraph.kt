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

import com.openhiker.core.model.Coordinate
import kotlinx.serialization.Serializable

/**
 * Interface for querying the routing graph.
 *
 * Implemented by the Room DAO in the Android app module.
 * The A* router depends only on this interface, keeping the core
 * routing algorithm free of any database or Android framework dependency.
 *
 * All methods may perform database queries and should be called from
 * a background thread / coroutine dispatcher.
 */
interface RoutingGraph {

    /**
     * Retrieves a routing node by its OSM node ID.
     *
     * @param id The OSM node ID.
     * @return The node if found, or null if not in the graph.
     */
    fun getNode(id: Long): RoutingNode?

    /**
     * Retrieves all outgoing edges from a given node.
     *
     * For bidirectional edges, both forward and reverse edges are
     * stored separately in the database with their respective costs.
     *
     * @param nodeId The OSM node ID to query edges from.
     * @return List of edges originating from this node (may be empty).
     */
    fun getEdgesFrom(nodeId: Long): List<RoutingEdge>

    /**
     * Finds the nearest routing node to a given coordinate.
     *
     * Used to snap user-placed start/end/via points to the road network.
     * The search radius is limited to [RoutingCostConfig.NEAREST_NODE_SEARCH_RADIUS_METRES].
     *
     * @param lat Latitude in degrees.
     * @param lon Longitude in degrees.
     * @return The nearest node, or null if no node is within the search radius.
     */
    fun findNearestNode(lat: Double, lon: Double): RoutingNode?
}

/**
 * A node in the routing graph, representing an OSM node at a trail junction.
 *
 * Nodes are the vertices of the graph. Edges connect pairs of nodes.
 * The [elevation] is populated from SRTM/ASTER data during graph building.
 *
 * @property id OSM node ID (unique within the graph).
 * @property latitude WGS84 latitude in degrees.
 * @property longitude WGS84 longitude in degrees.
 * @property elevation Elevation in metres above sea level, or null if unavailable.
 */
@Serializable
data class RoutingNode(
    val id: Long,
    val latitude: Double,
    val longitude: Double,
    val elevation: Double? = null
) {
    /** Geographic coordinate of this node. */
    val coordinate: Coordinate get() = Coordinate(latitude, longitude)
}

/**
 * A directed edge in the routing graph, connecting two nodes.
 *
 * Each edge represents a segment of trail or road between two junction nodes.
 * Bidirectional ways generate two edges (forward and reverse) with potentially
 * different costs due to elevation direction.
 *
 * @property id Auto-incremented edge ID in the database.
 * @property fromNode OSM node ID of the edge's starting node.
 * @property toNode OSM node ID of the edge's ending node.
 * @property distance Edge length in metres (Haversine distance).
 * @property elevationGain Uphill elevation change in metres (forward direction).
 * @property elevationLoss Downhill elevation change in metres (forward direction).
 * @property surface OSM surface tag value (e.g., "gravel", "asphalt"), or null.
 * @property highwayType OSM highway tag value (e.g., "footway", "path"), or null.
 * @property sacScale SAC hiking scale tag value (e.g., "mountain_hiking"), or null.
 * @property trailVisibility OSM trail_visibility tag value, or null.
 * @property name Trail or road name from the OSM `name` tag, or null.
 * @property osmWayId Original OSM way ID for attribution, or null.
 * @property cost Forward traversal cost (weighted by distance, elevation, surface).
 * @property reverseCost Reverse traversal cost.
 * @property isOneway Whether this edge is one-way (e.g., steps going downhill only).
 */
@Serializable
data class RoutingEdge(
    val id: Long,
    val fromNode: Long,
    val toNode: Long,
    val distance: Double,
    val elevationGain: Double = 0.0,
    val elevationLoss: Double = 0.0,
    val surface: String? = null,
    val highwayType: String? = null,
    val sacScale: String? = null,
    val trailVisibility: String? = null,
    val name: String? = null,
    val osmWayId: Long? = null,
    val cost: Double,
    val reverseCost: Double,
    val isOneway: Boolean = false
)

/**
 * The result of an A* route computation.
 *
 * Contains the complete route geometry, turn instructions, and statistics.
 * Can be converted to a [com.openhiker.core.model.PlannedRoute] for persistence.
 *
 * @property nodes Ordered list of junction nodes along the route.
 * @property edges Ordered list of traversed edges.
 * @property totalDistance Total route distance in metres.
 * @property totalCost Total abstract routing cost (not in any physical unit).
 * @property estimatedDuration Estimated travel time in seconds.
 * @property elevationGain Cumulative uphill elevation in metres.
 * @property elevationLoss Cumulative downhill elevation in metres.
 * @property coordinates Full route polyline (including intermediate edge geometry).
 * @property viaPoints The requested via-points that were routed through.
 */
@Serializable
data class ComputedRoute(
    val nodes: List<RoutingNode>,
    val edges: List<RoutingEdge>,
    val totalDistance: Double,
    val totalCost: Double,
    val estimatedDuration: Double,
    val elevationGain: Double,
    val elevationLoss: Double,
    val coordinates: List<Coordinate>,
    val viaPoints: List<Coordinate> = emptyList()
)

/**
 * Errors that can occur during route computation.
 *
 * Each error carries enough context for a meaningful user-facing message.
 */
sealed class RoutingError : Exception() {
    /** No routing database is loaded for the selected region. */
    data object NoRoutingData : RoutingError() {
        private fun readResolve(): Any = NoRoutingData
        override val message: String get() = "No routing data available for this region"
    }

    /** No graph node found within the search radius of the given coordinate. */
    data class NoNearbyNode(val coordinate: Coordinate) : RoutingError() {
        override val message: String
            get() = "No trail found near ${coordinate.formatted()}"
    }

    /** A* exhausted the open set without reaching the destination. */
    data class NoRouteFound(
        val exploredNodes: Int,
        val closestApproachMetres: Double
    ) : RoutingError() {
        override val message: String
            get() = "No route found (explored $exploredNodes nodes, " +
                "closest approach: %.0f m)".format(closestApproachMetres)
    }

    /** One of the via-points could not be reached from the previous point. */
    data class ViaPointNotReachable(
        val index: Int,
        val coordinate: Coordinate
    ) : RoutingError() {
        override val message: String
            get() = "Via-point ${index + 1} at ${coordinate.formatted()} is not reachable"
    }

    /** A* exceeded the maximum node expansion limit without finding a route. */
    data class NodeExpansionLimitExceeded(
        val expandedNodes: Int,
        val closestApproachMetres: Double
    ) : RoutingError() {
        override val message: String
            get() = "Route search exceeded limit ($expandedNodes nodes explored, " +
                "closest approach: %.0f m). Try shorter segments.".format(closestApproachMetres)
    }

    /** The routing database is corrupt or has an unexpected schema. */
    data class DatabaseCorrupted(val detail: String) : RoutingError() {
        override val message: String get() = "Routing database error: $detail"
    }
}
