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
import com.openhiker.core.model.TurnDirection
import com.openhiker.core.model.TurnInstruction

/**
 * Generates turn-by-turn navigation instructions from a computed route.
 *
 * Analyses consecutive edges in a route to detect bearing changes at
 * junction nodes. Each significant bearing change produces a
 * [TurnInstruction] with the turn direction, distance, and trail name.
 *
 * Pure functions only — no state, no side effects.
 */
object TurnDetector {

    /**
     * Minimum bearing change in degrees to classify as a turn.
     *
     * Bearing changes smaller than this are treated as "continue straight".
     * This prevents minor trail curves from generating spurious instructions.
     */
    const val STRAIGHT_THRESHOLD_DEGREES = 20.0

    /**
     * Bearing change threshold for a sharp turn (> 120 degrees).
     */
    const val SHARP_TURN_THRESHOLD_DEGREES = 120.0

    /**
     * Bearing change threshold for a U-turn (> 160 degrees).
     */
    const val U_TURN_THRESHOLD_DEGREES = 160.0

    /**
     * Generates turn instructions from a computed route.
     *
     * Creates a START instruction at the beginning, ARRIVE at the end,
     * and turn instructions at each junction where the bearing changes
     * significantly. Consecutive edges on the same trail with no
     * significant bearing change are merged (no instruction emitted).
     *
     * @param route The computed route containing nodes, edges, and coordinates.
     * @return Ordered list of turn instructions along the route.
     */
    fun generateInstructions(route: ComputedRoute): List<TurnInstruction> {
        if (route.nodes.size < 2 || route.edges.isEmpty()) {
            return emptyList()
        }

        val instructions = mutableListOf<TurnInstruction>()
        var cumulativeDistance = 0.0

        // START instruction at the first node
        val startNode = route.nodes.first()
        val firstEdge = route.edges.first()
        val startBearing = Haversine.bearing(
            route.nodes[0].coordinate,
            route.nodes[1].coordinate
        )

        instructions.add(
            TurnInstruction(
                coordinate = startNode.coordinate,
                direction = TurnDirection.START,
                bearing = startBearing,
                distanceFromPrevious = 0.0,
                cumulativeDistance = 0.0,
                trailName = firstEdge.name,
                description = buildStartDescription(startBearing, firstEdge.name)
            )
        )

        // Turn instructions at each junction
        var distanceSinceLastInstruction = 0.0

        for (i in 0 until route.edges.size - 1) {
            val currentEdge = route.edges[i]
            val nextEdge = route.edges[i + 1]
            val junctionNode = route.nodes[i + 1]

            distanceSinceLastInstruction += currentEdge.distance
            cumulativeDistance += currentEdge.distance

            // Compute the bearing change at this junction
            val incomingBearing = computeIncomingBearing(route.nodes, i + 1)
            val outgoingBearing = computeOutgoingBearing(route.nodes, i + 1)
            val bearingDelta = Haversine.normalizeBearingDelta(outgoingBearing - incomingBearing)

            val turnDirection = classifyTurn(bearingDelta)

            // Emit instruction if the turn is significant or trail name changes
            val nameChanged = currentEdge.name != nextEdge.name &&
                nextEdge.name != null
            val isSignificantTurn = turnDirection != TurnDirection.STRAIGHT

            if (isSignificantTurn || nameChanged) {
                instructions.add(
                    TurnInstruction(
                        coordinate = junctionNode.coordinate,
                        direction = turnDirection,
                        bearing = outgoingBearing,
                        distanceFromPrevious = distanceSinceLastInstruction,
                        cumulativeDistance = cumulativeDistance,
                        trailName = nextEdge.name,
                        description = buildTurnDescription(turnDirection, nextEdge.name)
                    )
                )
                distanceSinceLastInstruction = 0.0
            }
        }

        // ARRIVE instruction at the last node
        val lastEdge = route.edges.last()
        cumulativeDistance += lastEdge.distance
        distanceSinceLastInstruction += lastEdge.distance

        val lastNode = route.nodes.last()
        val lastBearing = if (route.nodes.size >= 2) {
            Haversine.bearing(
                route.nodes[route.nodes.size - 2].coordinate,
                lastNode.coordinate
            )
        } else {
            0.0
        }

        instructions.add(
            TurnInstruction(
                coordinate = lastNode.coordinate,
                direction = TurnDirection.ARRIVE,
                bearing = lastBearing,
                distanceFromPrevious = distanceSinceLastInstruction,
                cumulativeDistance = cumulativeDistance,
                trailName = null,
                description = "Arrive at destination"
            )
        )

        return instructions
    }

    /**
     * Classifies a bearing change into a turn direction.
     *
     * Uses thresholds to map the bearing delta (in degrees, negative = left,
     * positive = right) to a [TurnDirection] enum value.
     *
     * @param bearingDelta Normalised bearing change in degrees [-180, +180].
     * @return The classified [TurnDirection].
     */
    fun classifyTurn(bearingDelta: Double): TurnDirection {
        val absDelta = kotlin.math.abs(bearingDelta)
        return when {
            absDelta >= U_TURN_THRESHOLD_DEGREES -> TurnDirection.U_TURN
            absDelta >= SHARP_TURN_THRESHOLD_DEGREES -> {
                if (bearingDelta < 0) TurnDirection.SHARP_LEFT else TurnDirection.SHARP_RIGHT
            }
            absDelta >= STRAIGHT_THRESHOLD_DEGREES -> {
                if (bearingDelta < 0) TurnDirection.LEFT else TurnDirection.RIGHT
            }
            else -> TurnDirection.STRAIGHT
        }
    }

    /**
     * Computes the incoming bearing at a junction node.
     *
     * Uses the previous node's position to determine the approach direction.
     *
     * @param nodes The ordered list of route nodes.
     * @param junctionIndex Index of the junction node.
     * @return Incoming bearing in degrees [0, 360).
     */
    private fun computeIncomingBearing(nodes: List<RoutingNode>, junctionIndex: Int): Double {
        if (junctionIndex <= 0) return 0.0
        return Haversine.bearing(
            nodes[junctionIndex - 1].coordinate,
            nodes[junctionIndex].coordinate
        )
    }

    /**
     * Computes the outgoing bearing from a junction node.
     *
     * Uses the next node's position to determine the departure direction.
     *
     * @param nodes The ordered list of route nodes.
     * @param junctionIndex Index of the junction node.
     * @return Outgoing bearing in degrees [0, 360).
     */
    private fun computeOutgoingBearing(nodes: List<RoutingNode>, junctionIndex: Int): Double {
        if (junctionIndex >= nodes.size - 1) return 0.0
        return Haversine.bearing(
            nodes[junctionIndex].coordinate,
            nodes[junctionIndex + 1].coordinate
        )
    }

    /**
     * Builds a human-readable description for a START instruction.
     *
     * @param bearing Initial heading in degrees.
     * @param trailName Name of the initial trail, or null.
     * @return Description string (e.g., "Head north on Blue Ridge Trail").
     */
    private fun buildStartDescription(bearing: Double, trailName: String?): String {
        val direction = Haversine.cardinalDirection(bearing)
        return if (trailName != null) {
            "Head $direction on $trailName"
        } else {
            "Head $direction"
        }
    }

    /**
     * Builds a human-readable description for a turn instruction.
     *
     * @param direction The type of turn.
     * @param trailName Name of the trail after the turn, or null.
     * @return Description string (e.g., "Turn left onto Forest Path").
     */
    private fun buildTurnDescription(direction: TurnDirection, trailName: String?): String {
        val turnText = when (direction) {
            TurnDirection.STRAIGHT -> "Continue straight"
            TurnDirection.LEFT -> "Turn left"
            TurnDirection.RIGHT -> "Turn right"
            TurnDirection.SHARP_LEFT -> "Turn sharp left"
            TurnDirection.SHARP_RIGHT -> "Turn sharp right"
            TurnDirection.U_TURN -> "Make a U-turn"
            TurnDirection.START -> "Start"
            TurnDirection.ARRIVE -> "Arrive"
            TurnDirection.SLIGHT_LEFT -> "Bear left"
            TurnDirection.SLIGHT_RIGHT -> "Bear right"
        }
        return if (trailName != null) {
            "$turnText onto $trailName"
        } else {
            turnText
        }
    }
}
