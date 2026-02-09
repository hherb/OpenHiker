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

package com.openhiker.android.service.routing

import android.util.Log
import com.openhiker.android.data.db.routing.WritableRoutingStore
import com.openhiker.android.service.elevation.ElevationDataManager
import com.openhiker.core.geo.Haversine
import com.openhiker.core.model.RoutingMode
import com.openhiker.core.overpass.OsmData
import com.openhiker.core.overpass.OsmNode
import com.openhiker.core.overpass.OsmWay
import com.openhiker.core.routing.CostFunction
import com.openhiker.core.routing.RoutingCostConfig
import com.openhiker.core.routing.RoutingEdge
import com.openhiker.core.routing.RoutingNode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Progress state for graph building.
 *
 * @property phase Current build phase description.
 * @property progress Completion fraction (0.0 to 1.0).
 * @property nodeCount Number of nodes inserted so far.
 * @property edgeCount Number of edges inserted so far.
 */
data class GraphBuildProgress(
    val phase: String = "",
    val progress: Float = 0f,
    val nodeCount: Int = 0,
    val edgeCount: Int = 0
)

/**
 * Builds a routing graph database from parsed OSM data and elevation data.
 *
 * The build pipeline:
 * 1. Filter ways to routable highway types
 * 2. Identify junction nodes (referenced by 2+ ways)
 * 3. Split ways at junctions into directed edges
 * 4. Lookup elevation for all nodes
 * 5. Compute forward and reverse edge costs via [CostFunction]
 * 6. Write nodes, edges, and metadata to [WritableRoutingStore]
 *
 * Reports progress via [buildProgress] StateFlow for UI updates.
 *
 * @param elevationManager Provides elevation data for nodes.
 */
@Singleton
class RoutingGraphBuilder @Inject constructor(
    private val elevationManager: ElevationDataManager
) {
    private val _buildProgress = MutableStateFlow(GraphBuildProgress())

    /** Observable build progress for UI updates. */
    val buildProgress: StateFlow<GraphBuildProgress> = _buildProgress.asStateFlow()

    /**
     * Builds a routing graph from OSM data and writes it to a database file.
     *
     * @param osmData Parsed OSM nodes and ways from [OsmXmlParser].
     * @param outputPath Absolute path for the output .routing.db file.
     * @param regionId Unique region identifier for metadata.
     * @throws Exception if graph building fails.
     */
    suspend fun buildGraph(
        osmData: OsmData,
        outputPath: String,
        regionId: String
    ) = withContext(Dispatchers.IO) {
        val store = WritableRoutingStore(outputPath)
        try {
            store.create()

            // Step 1: Filter to routable ways
            emitProgress("Filtering routable ways", 0.05f)
            val routableWays = osmData.ways.filter { way ->
                way.highway in RoutingCostConfig.ROUTABLE_HIGHWAY_VALUES
            }
            Log.d(TAG, "Routable ways: ${routableWays.size} / ${osmData.ways.size}")

            // Step 2: Identify junction nodes (referenced by 2+ ways)
            emitProgress("Identifying junctions", 0.10f)
            val nodeRefCount = mutableMapOf<Long, Int>()
            for (way in routableWays) {
                for (nodeRef in way.nodeRefs) {
                    nodeRefCount[nodeRef] = (nodeRefCount[nodeRef] ?: 0) + 1
                }
            }
            // Junction nodes: referenced by 2+ ways, or endpoints of any way
            val junctionNodeIds = mutableSetOf<Long>()
            for (way in routableWays) {
                // Endpoints are always junctions
                junctionNodeIds.add(way.nodeRefs.first())
                junctionNodeIds.add(way.nodeRefs.last())
                // Interior nodes referenced by multiple ways
                for (nodeRef in way.nodeRefs) {
                    if ((nodeRefCount[nodeRef] ?: 0) >= 2) {
                        junctionNodeIds.add(nodeRef)
                    }
                }
            }
            Log.d(TAG, "Junction nodes: ${junctionNodeIds.size}")

            // Step 3: Build routing nodes with elevation
            emitProgress("Looking up elevations", 0.20f)
            val routingNodes = mutableMapOf<Long, RoutingNode>()
            val junctionList = junctionNodeIds.toList()
            for ((index, nodeId) in junctionList.withIndex()) {
                val osmNode = osmData.nodes[nodeId] ?: continue
                val elevation = try {
                    elevationManager.getElevation(osmNode.latitude, osmNode.longitude)
                } catch (_: Exception) {
                    null
                }
                routingNodes[nodeId] = RoutingNode(
                    id = nodeId,
                    latitude = osmNode.latitude,
                    longitude = osmNode.longitude,
                    elevation = elevation
                )
                if (index % 1000 == 0) {
                    val progress = 0.20f + 0.30f * (index.toFloat() / junctionList.size)
                    emitProgress("Looking up elevations", progress, nodeCount = index)
                }
            }

            // Step 4: Write nodes to database
            emitProgress("Writing nodes", 0.50f, nodeCount = routingNodes.size)
            val nodeChunks = routingNodes.values.chunked(NODE_BATCH_SIZE)
            for (chunk in nodeChunks) {
                store.insertNodes(chunk)
            }

            // Step 5: Split ways at junctions and compute edge costs
            emitProgress("Building edges", 0.55f, nodeCount = routingNodes.size)
            val allEdges = mutableListOf<RoutingEdge>()
            var edgeId = 1L

            for ((wayIndex, way) in routableWays.withIndex()) {
                val edges = splitWayIntoEdges(
                    way, osmData.nodes, routingNodes, junctionNodeIds, edgeId
                )
                allEdges.addAll(edges)
                edgeId += edges.size

                if (wayIndex % 500 == 0) {
                    val progress = 0.55f + 0.30f * (wayIndex.toFloat() / routableWays.size)
                    emitProgress(
                        "Building edges", progress,
                        nodeCount = routingNodes.size,
                        edgeCount = allEdges.size
                    )
                }
            }
            Log.d(TAG, "Total edges: ${allEdges.size}")

            // Step 6: Write edges to database
            emitProgress("Writing edges", 0.85f, routingNodes.size, allEdges.size)
            val edgeChunks = allEdges.chunked(EDGE_BATCH_SIZE)
            for (chunk in edgeChunks) {
                store.insertEdges(chunk)
            }

            // Step 7: Write metadata
            emitProgress("Writing metadata", 0.95f, routingNodes.size, allEdges.size)
            store.setMetadata("region_id", regionId)
            store.setMetadata("node_count", routingNodes.size.toString())
            store.setMetadata("edge_count", allEdges.size.toString())
            store.setMetadata("build_date", java.time.Instant.now().toString())

            emitProgress("Complete", 1.0f, routingNodes.size, allEdges.size)
            Log.d(TAG, "Graph build complete: ${routingNodes.size} nodes, ${allEdges.size} edges")
        } finally {
            store.close()
        }
    }

    /**
     * Splits an OSM way into routing edges at junction nodes.
     *
     * Each segment between two consecutive junction nodes becomes one edge
     * (or two edges for bidirectional ways). The edge distance is the sum
     * of Haversine distances between consecutive nodes.
     *
     * @param way The OSM way to split.
     * @param allOsmNodes All OSM nodes by ID (for coordinate lookup).
     * @param routingNodes Junction routing nodes (for elevation lookup).
     * @param junctionIds Set of node IDs that are junctions.
     * @param startEdgeId Starting edge ID for this batch.
     * @return List of directed routing edges.
     */
    private fun splitWayIntoEdges(
        way: OsmWay,
        allOsmNodes: Map<Long, OsmNode>,
        routingNodes: Map<Long, RoutingNode>,
        junctionIds: Set<Long>,
        startEdgeId: Long
    ): List<RoutingEdge> {
        val edges = mutableListOf<RoutingEdge>()
        var edgeId = startEdgeId
        var segmentStart = 0

        for (i in 1 until way.nodeRefs.size) {
            val nodeId = way.nodeRefs[i]
            val isJunction = nodeId in junctionIds
            val isEnd = i == way.nodeRefs.size - 1

            if (isJunction || isEnd) {
                // Create an edge from segmentStart to i
                val fromNodeId = way.nodeRefs[segmentStart]
                val toNodeId = nodeId

                val fromNode = routingNodes[fromNodeId]
                val toNode = routingNodes[toNodeId]
                if (fromNode == null || toNode == null) {
                    segmentStart = i
                    continue
                }

                // Compute edge distance as sum of sub-segments
                var distance = 0.0
                for (j in segmentStart until i) {
                    val n1 = allOsmNodes[way.nodeRefs[j]]
                    val n2 = allOsmNodes[way.nodeRefs[j + 1]]
                    if (n1 != null && n2 != null) {
                        distance += Haversine.distance(
                            n1.latitude, n1.longitude,
                            n2.latitude, n2.longitude
                        )
                    }
                }

                // Compute elevation gain/loss
                val elevGain: Double
                val elevLoss: Double
                if (fromNode.elevation != null && toNode.elevation != null) {
                    val diff = toNode.elevation!! - fromNode.elevation!!
                    elevGain = if (diff > 0) diff else 0.0
                    elevLoss = if (diff < 0) -diff else 0.0
                } else {
                    elevGain = 0.0
                    elevLoss = 0.0
                }

                // Compute costs for both directions
                val forwardCost = CostFunction.edgeCost(
                    distance, elevGain, elevLoss,
                    way.surface, way.highway, way.sacScale,
                    RoutingMode.HIKING
                )
                val reverseCost = if (way.isOneway) {
                    RoutingCostConfig.IMPASSABLE_COST
                } else {
                    CostFunction.edgeCost(
                        distance, elevLoss, elevGain, // swap gain/loss
                        way.surface, way.highway, way.sacScale,
                        RoutingMode.HIKING
                    )
                }

                // Forward edge
                edges.add(
                    RoutingEdge(
                        id = edgeId++,
                        fromNode = fromNodeId,
                        toNode = toNodeId,
                        distance = distance,
                        elevationGain = elevGain,
                        elevationLoss = elevLoss,
                        surface = way.surface,
                        highwayType = way.highway,
                        sacScale = way.sacScale,
                        trailVisibility = way.trailVisibility,
                        name = way.name,
                        osmWayId = way.id,
                        cost = forwardCost,
                        reverseCost = reverseCost,
                        isOneway = way.isOneway
                    )
                )

                // Reverse edge (for bidirectional graph traversal)
                if (!way.isOneway) {
                    edges.add(
                        RoutingEdge(
                            id = edgeId++,
                            fromNode = toNodeId,
                            toNode = fromNodeId,
                            distance = distance,
                            elevationGain = elevLoss, // swapped
                            elevationLoss = elevGain, // swapped
                            surface = way.surface,
                            highwayType = way.highway,
                            sacScale = way.sacScale,
                            trailVisibility = way.trailVisibility,
                            name = way.name,
                            osmWayId = way.id,
                            cost = reverseCost,
                            reverseCost = forwardCost,
                            isOneway = false
                        )
                    )
                }

                segmentStart = i
            }
        }

        return edges
    }

    /**
     * Emits a progress update to the StateFlow.
     */
    private fun emitProgress(
        phase: String,
        progress: Float,
        nodeCount: Int = 0,
        edgeCount: Int = 0
    ) {
        _buildProgress.value = GraphBuildProgress(phase, progress, nodeCount, edgeCount)
    }

    companion object {
        private const val TAG = "RoutingGraphBuilder"
        private const val NODE_BATCH_SIZE = 10_000
        private const val EDGE_BATCH_SIZE = 10_000
    }
}
