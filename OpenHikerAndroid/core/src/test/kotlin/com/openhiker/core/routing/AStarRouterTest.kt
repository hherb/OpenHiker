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
import com.openhiker.core.model.RoutingMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [AStarRouter] using mock [RoutingGraph] implementations.
 *
 * Tests cover basic pathfinding, via-point routing, unreachable destinations,
 * and mode-specific edge filtering.
 */
class AStarRouterTest {

    // ── Simple direct route ──────────────────────────────────────────

    @Test
    fun `findRoute returns direct route between two adjacent nodes`() {
        val graph = SimpleLineGraph()
        val router = AStarRouter(graph)

        val route = router.findRoute(
            from = Coordinate(47.0, 11.0),
            to = Coordinate(47.001, 11.0),
            mode = RoutingMode.HIKING
        )

        assertEquals(2, route.nodes.size)
        assertEquals(1, route.edges.size)
        assertTrue(route.totalDistance > 0)
        assertEquals(2, route.coordinates.size)
    }

    @Test
    fun `findRoute traverses multiple edges`() {
        val graph = SimpleLineGraph()
        val router = AStarRouter(graph)

        val route = router.findRoute(
            from = Coordinate(47.0, 11.0),
            to = Coordinate(47.002, 11.0),
            mode = RoutingMode.HIKING
        )

        assertEquals(3, route.nodes.size)
        assertEquals(2, route.edges.size)
        assertTrue(route.totalDistance > 0)
    }

    // ── Via-point routing ────────────────────────────────────────────

    @Test
    fun `findRoute with via-point visits intermediate node`() {
        val graph = SimpleLineGraph()
        val router = AStarRouter(graph)

        val route = router.findRoute(
            from = Coordinate(47.0, 11.0),
            to = Coordinate(47.002, 11.0),
            via = listOf(Coordinate(47.001, 11.0)),
            mode = RoutingMode.HIKING
        )

        // Should visit all three nodes
        assertTrue(route.nodes.size >= 3)
        assertEquals(listOf(Coordinate(47.001, 11.0)), route.viaPoints)
    }

    @Test
    fun `findRoute with same start and end via short-circuits`() {
        val graph = SimpleLineGraph()
        val router = AStarRouter(graph)

        val route = router.findRoute(
            from = Coordinate(47.0, 11.0),
            to = Coordinate(47.0, 11.0),
            mode = RoutingMode.HIKING
        )

        assertEquals(1, route.nodes.size)
        assertEquals(0, route.edges.size)
        assertEquals(0.0, route.totalDistance, 0.01)
    }

    // ── Error handling ───────────────────────────────────────────────

    @Test(expected = RoutingError.NoNearbyNode::class)
    fun `findRoute throws NoNearbyNode when start is not near any node`() {
        val graph = EmptyGraph()
        val router = AStarRouter(graph)

        router.findRoute(
            from = Coordinate(0.0, 0.0),
            to = Coordinate(1.0, 1.0),
            mode = RoutingMode.HIKING
        )
    }

    @Test(expected = RoutingError.NoRouteFound::class)
    fun `findRoute throws NoRouteFound for disconnected graph`() {
        val graph = DisconnectedGraph()
        val router = AStarRouter(graph)

        router.findRoute(
            from = Coordinate(47.0, 11.0),
            to = Coordinate(48.0, 12.0),
            mode = RoutingMode.HIKING
        )
    }

    // ── Mode-specific filtering ──────────────────────────────────────

    @Test(expected = RoutingError.NoRouteFound::class)
    fun `findRoute cycling mode avoids steps`() {
        val graph = GraphWithSteps()
        val router = AStarRouter(graph)

        // The only path goes through steps — cycling should fail
        router.findRoute(
            from = Coordinate(47.0, 11.0),
            to = Coordinate(47.001, 11.0),
            mode = RoutingMode.CYCLING
        )
    }

    @Test
    fun `findRoute hiking mode traverses steps`() {
        val graph = GraphWithSteps()
        val router = AStarRouter(graph)

        val route = router.findRoute(
            from = Coordinate(47.0, 11.0),
            to = Coordinate(47.001, 11.0),
            mode = RoutingMode.HIKING
        )

        assertEquals(2, route.nodes.size)
    }

    // ── Elevation gain/loss ──────────────────────────────────────────

    @Test
    fun `findRoute accumulates elevation gain and loss`() {
        val graph = GraphWithElevation()
        val router = AStarRouter(graph)

        val route = router.findRoute(
            from = Coordinate(47.0, 11.0),
            to = Coordinate(47.002, 11.0),
            mode = RoutingMode.HIKING
        )

        assertTrue(route.elevationGain > 0)
        assertTrue(route.elevationLoss > 0)
    }

    // ── Optimal path selection ───────────────────────────────────────

    @Test
    fun `findRoute chooses cheaper path when two paths exist`() {
        val graph = DiamondGraph()
        val router = AStarRouter(graph)

        val route = router.findRoute(
            from = Coordinate(47.0, 11.0),
            to = Coordinate(47.002, 11.0),
            mode = RoutingMode.HIKING
        )

        // Should choose the cheaper path (through node 2, not node 3)
        assertEquals(3, route.nodes.size)
        assertEquals(2L, route.nodes[1].id) // cheaper middle node
    }

    // ── Mock graphs ──────────────────────────────────────────────────

    /**
     * A simple 3-node linear graph: N1 — N2 — N3 (north-south line).
     */
    private class SimpleLineGraph : RoutingGraph {
        private val nodes = mapOf(
            1L to RoutingNode(1, 47.0, 11.0),
            2L to RoutingNode(2, 47.001, 11.0),
            3L to RoutingNode(3, 47.002, 11.0)
        )

        private val edges = listOf(
            RoutingEdge(1, 1, 2, 111.0, cost = 83.5, reverseCost = 83.5),
            RoutingEdge(2, 2, 3, 111.0, cost = 83.5, reverseCost = 83.5),
            // Reverse edges for bidirectional traversal
            RoutingEdge(3, 2, 1, 111.0, cost = 83.5, reverseCost = 83.5),
            RoutingEdge(4, 3, 2, 111.0, cost = 83.5, reverseCost = 83.5)
        )

        override fun getNode(id: Long) = nodes[id]
        override fun getEdgesFrom(nodeId: Long) = edges.filter { it.fromNode == nodeId }
        override fun findNearestNode(lat: Double, lon: Double): RoutingNode? {
            return nodes.values.minByOrNull {
                val dLat = it.latitude - lat
                val dLon = it.longitude - lon
                dLat * dLat + dLon * dLon
            }
        }
    }

    /** A graph with no nodes. */
    private class EmptyGraph : RoutingGraph {
        override fun getNode(id: Long) = null
        override fun getEdgesFrom(nodeId: Long) = emptyList<RoutingEdge>()
        override fun findNearestNode(lat: Double, lon: Double) = null
    }

    /** Two nodes with no connecting edges. */
    private class DisconnectedGraph : RoutingGraph {
        private val nodes = mapOf(
            1L to RoutingNode(1, 47.0, 11.0),
            2L to RoutingNode(2, 48.0, 12.0)
        )

        override fun getNode(id: Long) = nodes[id]
        override fun getEdgesFrom(nodeId: Long) = emptyList<RoutingEdge>()
        override fun findNearestNode(lat: Double, lon: Double): RoutingNode? {
            return nodes.values.minByOrNull {
                val dLat = it.latitude - lat
                val dLon = it.longitude - lon
                dLat * dLat + dLon * dLon
            }
        }
    }

    /** Two nodes connected only by a steps edge. */
    private class GraphWithSteps : RoutingGraph {
        private val nodes = mapOf(
            1L to RoutingNode(1, 47.0, 11.0),
            2L to RoutingNode(2, 47.001, 11.0)
        )

        private val edges = listOf(
            RoutingEdge(
                1, 1, 2, 50.0,
                highwayType = "steps",
                cost = 50.0, reverseCost = 50.0
            )
        )

        override fun getNode(id: Long) = nodes[id]
        override fun getEdgesFrom(nodeId: Long) = edges.filter { it.fromNode == nodeId }
        override fun findNearestNode(lat: Double, lon: Double): RoutingNode? {
            return nodes.values.minByOrNull {
                val dLat = it.latitude - lat
                val dLon = it.longitude - lon
                dLat * dLat + dLon * dLon
            }
        }
    }

    /** A graph with elevation gain on the uphill edge and loss on the downhill edge. */
    private class GraphWithElevation : RoutingGraph {
        private val nodes = mapOf(
            1L to RoutingNode(1, 47.0, 11.0, 1000.0),
            2L to RoutingNode(2, 47.001, 11.0, 1100.0),
            3L to RoutingNode(3, 47.002, 11.0, 1050.0)
        )

        private val edges = listOf(
            RoutingEdge(
                1, 1, 2, 111.0,
                elevationGain = 100.0, elevationLoss = 0.0,
                cost = 900.0, reverseCost = 83.5
            ),
            RoutingEdge(
                2, 2, 3, 111.0,
                elevationGain = 0.0, elevationLoss = 50.0,
                cost = 83.5, reverseCost = 500.0
            )
        )

        override fun getNode(id: Long) = nodes[id]
        override fun getEdgesFrom(nodeId: Long) = edges.filter { it.fromNode == nodeId }
        override fun findNearestNode(lat: Double, lon: Double): RoutingNode? {
            return nodes.values.minByOrNull {
                val dLat = it.latitude - lat
                val dLon = it.longitude - lon
                dLat * dLat + dLon * dLon
            }
        }
    }

    /**
     * Diamond graph: two paths from N1 to N4.
     * N1 —(cheap)— N2 —(cheap)— N4
     * N1 —(expensive)— N3 —(expensive)— N4
     */
    private class DiamondGraph : RoutingGraph {
        private val nodes = mapOf(
            1L to RoutingNode(1, 47.0, 11.0),
            2L to RoutingNode(2, 47.001, 11.001), // cheap path
            3L to RoutingNode(3, 47.001, 10.999), // expensive path
            4L to RoutingNode(4, 47.002, 11.0)
        )

        private val edges = listOf(
            // Cheap path: N1 -> N2 -> N4
            RoutingEdge(1, 1, 2, 100.0, cost = 75.0, reverseCost = 75.0),
            RoutingEdge(2, 2, 4, 100.0, cost = 75.0, reverseCost = 75.0),
            // Expensive path: N1 -> N3 -> N4
            RoutingEdge(3, 1, 3, 100.0, cost = 500.0, reverseCost = 500.0),
            RoutingEdge(4, 3, 4, 100.0, cost = 500.0, reverseCost = 500.0)
        )

        override fun getNode(id: Long) = nodes[id]
        override fun getEdgesFrom(nodeId: Long) = edges.filter { it.fromNode == nodeId }
        override fun findNearestNode(lat: Double, lon: Double): RoutingNode? {
            return nodes.values.minByOrNull {
                val dLat = it.latitude - lat
                val dLon = it.longitude - lon
                dLat * dLat + dLon * dLon
            }
        }
    }
}
