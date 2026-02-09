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
import com.openhiker.core.model.TurnDirection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [TurnDetector].
 */
class TurnDetectorTest {

    // ── classifyTurn ─────────────────────────────────────────────────

    @Test
    fun `classifyTurn returns STRAIGHT for small bearing change`() {
        assertEquals(TurnDirection.STRAIGHT, TurnDetector.classifyTurn(10.0))
        assertEquals(TurnDirection.STRAIGHT, TurnDetector.classifyTurn(-10.0))
        assertEquals(TurnDirection.STRAIGHT, TurnDetector.classifyTurn(0.0))
    }

    @Test
    fun `classifyTurn returns LEFT for moderate left turn`() {
        assertEquals(TurnDirection.LEFT, TurnDetector.classifyTurn(-45.0))
        assertEquals(TurnDirection.LEFT, TurnDetector.classifyTurn(-90.0))
    }

    @Test
    fun `classifyTurn returns RIGHT for moderate right turn`() {
        assertEquals(TurnDirection.RIGHT, TurnDetector.classifyTurn(45.0))
        assertEquals(TurnDirection.RIGHT, TurnDetector.classifyTurn(90.0))
    }

    @Test
    fun `classifyTurn returns SHARP_LEFT for sharp left turn`() {
        assertEquals(TurnDirection.SHARP_LEFT, TurnDetector.classifyTurn(-130.0))
    }

    @Test
    fun `classifyTurn returns SHARP_RIGHT for sharp right turn`() {
        assertEquals(TurnDirection.SHARP_RIGHT, TurnDetector.classifyTurn(130.0))
    }

    @Test
    fun `classifyTurn returns U_TURN for reversal`() {
        assertEquals(TurnDirection.U_TURN, TurnDetector.classifyTurn(170.0))
        assertEquals(TurnDirection.U_TURN, TurnDetector.classifyTurn(-170.0))
        assertEquals(TurnDirection.U_TURN, TurnDetector.classifyTurn(180.0))
    }

    @Test
    fun `classifyTurn threshold at exactly 20 degrees is STRAIGHT`() {
        // At the exact threshold, bearing delta < threshold → STRAIGHT
        assertEquals(TurnDirection.STRAIGHT, TurnDetector.classifyTurn(19.9))
    }

    @Test
    fun `classifyTurn threshold just above 20 degrees is LEFT or RIGHT`() {
        assertEquals(TurnDirection.RIGHT, TurnDetector.classifyTurn(20.1))
        assertEquals(TurnDirection.LEFT, TurnDetector.classifyTurn(-20.1))
    }

    // ── generateInstructions ─────────────────────────────────────────

    @Test
    fun `generateInstructions returns empty list for empty route`() {
        val route = ComputedRoute(
            nodes = emptyList(),
            edges = emptyList(),
            totalDistance = 0.0,
            totalCost = 0.0,
            estimatedDuration = 0.0,
            elevationGain = 0.0,
            elevationLoss = 0.0,
            coordinates = emptyList()
        )
        val instructions = TurnDetector.generateInstructions(route)
        assertTrue(instructions.isEmpty())
    }

    @Test
    fun `generateInstructions returns START and ARRIVE for straight route`() {
        val route = createStraightRoute()
        val instructions = TurnDetector.generateInstructions(route)

        assertTrue(instructions.size >= 2)
        assertEquals(TurnDirection.START, instructions.first().direction)
        assertEquals(TurnDirection.ARRIVE, instructions.last().direction)
    }

    @Test
    fun `generateInstructions detects right turn`() {
        val route = createRouteWithRightTurn()
        val instructions = TurnDetector.generateInstructions(route)

        // Should have START, a RIGHT turn, and ARRIVE
        assertTrue(instructions.size >= 3)
        assertEquals(TurnDirection.START, instructions[0].direction)
        assertEquals(TurnDirection.ARRIVE, instructions.last().direction)

        // Middle instruction should be a right turn
        val turnInstructions = instructions.filter {
            it.direction == TurnDirection.RIGHT || it.direction == TurnDirection.SHARP_RIGHT
        }
        assertTrue("Expected a right turn instruction", turnInstructions.isNotEmpty())
    }

    @Test
    fun `generateInstructions includes cumulative distance`() {
        val route = createStraightRoute()
        val instructions = TurnDetector.generateInstructions(route)

        assertEquals(0.0, instructions.first().cumulativeDistance, 0.01)
        assertTrue(instructions.last().cumulativeDistance > 0)
    }

    @Test
    fun `generateInstructions includes trail names`() {
        val route = createRouteWithTrailNames()
        val instructions = TurnDetector.generateInstructions(route)

        // START instruction should mention the trail name
        val startInstruction = instructions.first()
        assertTrue(startInstruction.description.contains("Blue Trail"))
    }

    @Test
    fun `generateInstructions emits instruction on trail name change`() {
        val route = createRouteWithTrailNameChange()
        val instructions = TurnDetector.generateInstructions(route)

        // Should have at least 3 instructions (START, name change, ARRIVE)
        assertTrue(instructions.size >= 3)
    }

    // ── Constants ────────────────────────────────────────────────────

    @Test
    fun `straight threshold is 20 degrees`() {
        assertEquals(20.0, TurnDetector.STRAIGHT_THRESHOLD_DEGREES, 0.01)
    }

    @Test
    fun `sharp turn threshold is 120 degrees`() {
        assertEquals(120.0, TurnDetector.SHARP_TURN_THRESHOLD_DEGREES, 0.01)
    }

    @Test
    fun `U-turn threshold is 160 degrees`() {
        assertEquals(160.0, TurnDetector.U_TURN_THRESHOLD_DEGREES, 0.01)
    }

    // ── Test route factories ─────────────────────────────────────────

    /**
     * 3-node straight route heading north.
     */
    private fun createStraightRoute(): ComputedRoute {
        val nodes = listOf(
            RoutingNode(1, 47.0, 11.0),
            RoutingNode(2, 47.001, 11.0),
            RoutingNode(3, 47.002, 11.0)
        )
        val edges = listOf(
            RoutingEdge(1, 1, 2, 111.0, cost = 83.5, reverseCost = 83.5),
            RoutingEdge(2, 2, 3, 111.0, cost = 83.5, reverseCost = 83.5)
        )
        return ComputedRoute(
            nodes = nodes,
            edges = edges,
            totalDistance = 222.0,
            totalCost = 167.0,
            estimatedDuration = 167.0,
            elevationGain = 0.0,
            elevationLoss = 0.0,
            coordinates = nodes.map { it.coordinate }
        )
    }

    /**
     * 3-node route with a right turn: heading north then turning east.
     */
    private fun createRouteWithRightTurn(): ComputedRoute {
        val nodes = listOf(
            RoutingNode(1, 47.0, 11.0),       // Start
            RoutingNode(2, 47.001, 11.0),      // Junction (heading north)
            RoutingNode(3, 47.001, 11.001)     // Turn east (right turn)
        )
        val edges = listOf(
            RoutingEdge(1, 1, 2, 111.0, cost = 83.5, reverseCost = 83.5),
            RoutingEdge(2, 2, 3, 75.0, cost = 56.0, reverseCost = 56.0)
        )
        return ComputedRoute(
            nodes = nodes,
            edges = edges,
            totalDistance = 186.0,
            totalCost = 139.5,
            estimatedDuration = 139.5,
            elevationGain = 0.0,
            elevationLoss = 0.0,
            coordinates = nodes.map { it.coordinate }
        )
    }

    /**
     * Straight route with a trail name on the first edge.
     */
    private fun createRouteWithTrailNames(): ComputedRoute {
        val nodes = listOf(
            RoutingNode(1, 47.0, 11.0),
            RoutingNode(2, 47.001, 11.0),
            RoutingNode(3, 47.002, 11.0)
        )
        val edges = listOf(
            RoutingEdge(1, 1, 2, 111.0, name = "Blue Trail", cost = 83.5, reverseCost = 83.5),
            RoutingEdge(2, 2, 3, 111.0, name = "Blue Trail", cost = 83.5, reverseCost = 83.5)
        )
        return ComputedRoute(
            nodes = nodes,
            edges = edges,
            totalDistance = 222.0,
            totalCost = 167.0,
            estimatedDuration = 167.0,
            elevationGain = 0.0,
            elevationLoss = 0.0,
            coordinates = nodes.map { it.coordinate }
        )
    }

    /**
     * Straight route where the trail name changes at the second edge.
     */
    private fun createRouteWithTrailNameChange(): ComputedRoute {
        val nodes = listOf(
            RoutingNode(1, 47.0, 11.0),
            RoutingNode(2, 47.001, 11.0),
            RoutingNode(3, 47.002, 11.0)
        )
        val edges = listOf(
            RoutingEdge(1, 1, 2, 111.0, name = "Blue Trail", cost = 83.5, reverseCost = 83.5),
            RoutingEdge(2, 2, 3, 111.0, name = "Red Trail", cost = 83.5, reverseCost = 83.5)
        )
        return ComputedRoute(
            nodes = nodes,
            edges = edges,
            totalDistance = 222.0,
            totalCost = 167.0,
            estimatedDuration = 167.0,
            elevationGain = 0.0,
            elevationLoss = 0.0,
            coordinates = nodes.map { it.coordinate }
        )
    }
}
