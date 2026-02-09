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

package com.openhiker.core.navigation

import com.openhiker.core.geo.Haversine
import com.openhiker.core.model.Coordinate
import com.openhiker.core.model.TurnInstruction

/**
 * Navigation state emitted by [RouteFollower.update] for the UI.
 *
 * Contains all the information needed to render the navigation screen:
 * current instruction, distance to next turn, progress, and arrival status.
 *
 * @property currentInstruction The turn instruction the user is approaching, or null.
 * @property distanceToNextTurn Distance in metres to the next turn point.
 * @property progress Route completion as a fraction (0.0 to 1.0).
 * @property remainingDistance Distance left to the destination in metres.
 * @property isApproachingTurn True when within [RouteGuidanceConfig.APPROACHING_TURN_DISTANCE_METRES].
 * @property isAtTurn True when within [RouteGuidanceConfig.AT_TURN_DISTANCE_METRES].
 * @property hasArrived True when within [RouteGuidanceConfig.ARRIVED_DISTANCE_METRES] of destination.
 */
data class NavigationState(
    val currentInstruction: TurnInstruction? = null,
    val distanceToNextTurn: Double = 0.0,
    val progress: Float = 0f,
    val remainingDistance: Double = 0.0,
    val isApproachingTurn: Boolean = false,
    val isAtTurn: Boolean = false,
    val hasArrived: Boolean = false
)

/**
 * Pure function engine for following a route and generating navigation state.
 *
 * Takes the current GPS position, the route polyline, and the instruction list,
 * and produces a [NavigationState] describing where the user is relative to
 * the route. Uses cumulative distance (not raw GPS) for accurate turn detection
 * on winding trails.
 *
 * This class is stateful: it tracks the current instruction index to avoid
 * jumping backwards when GPS fluctuates. Create a new instance for each
 * navigation session.
 */
class RouteFollower(
    private val routeCoordinates: List<Coordinate>,
    private val instructions: List<TurnInstruction>,
    private val totalDistance: Double
) {
    /** Index of the current instruction the user is approaching. */
    private var currentInstructionIndex: Int = 0

    /**
     * Updates the navigation state based on the current position.
     *
     * Finds the nearest point on the route, computes cumulative distance
     * along the route to that point, and determines which instruction
     * the user is approaching. Advances the instruction index when the
     * user passes a turn point.
     *
     * @param latitude Current GPS latitude.
     * @param longitude Current GPS longitude.
     * @param cumulativeDistance Distance walked so far in metres (from GPS track).
     * @return Updated [NavigationState] for the UI.
     */
    fun update(latitude: Double, longitude: Double, cumulativeDistance: Double): NavigationState {
        if (routeCoordinates.isEmpty() || instructions.isEmpty()) {
            return NavigationState()
        }

        val currentPos = Coordinate(latitude, longitude)
        val destination = routeCoordinates.last()

        // Check arrival
        val distToDestination = Haversine.distance(currentPos, destination)
        if (distToDestination <= RouteGuidanceConfig.ARRIVED_DISTANCE_METRES) {
            return NavigationState(
                currentInstruction = instructions.lastOrNull(),
                distanceToNextTurn = 0.0,
                progress = 1.0f,
                remainingDistance = 0.0,
                hasArrived = true
            )
        }

        // Advance instruction index if we've passed the current turn
        while (currentInstructionIndex < instructions.size - 1) {
            val instruction = instructions[currentInstructionIndex]
            val distToTurn = Haversine.distance(currentPos, instruction.coordinate)
            if (distToTurn <= RouteGuidanceConfig.AT_TURN_DISTANCE_METRES &&
                cumulativeDistance >= instruction.cumulativeDistance - RouteGuidanceConfig.AT_TURN_DISTANCE_METRES
            ) {
                currentInstructionIndex++
            } else {
                break
            }
        }

        val currentInstruction = instructions.getOrNull(currentInstructionIndex)
        val distToNextTurn = if (currentInstruction != null) {
            Haversine.distance(currentPos, currentInstruction.coordinate)
        } else {
            distToDestination
        }

        val progress = if (totalDistance > 0) {
            (cumulativeDistance / totalDistance).toFloat().coerceIn(0f, 1f)
        } else {
            0f
        }

        val remainingDistance = (totalDistance - cumulativeDistance).coerceAtLeast(0.0)

        return NavigationState(
            currentInstruction = currentInstruction,
            distanceToNextTurn = distToNextTurn,
            progress = progress,
            remainingDistance = remainingDistance,
            isApproachingTurn = distToNextTurn <= RouteGuidanceConfig.APPROACHING_TURN_DISTANCE_METRES,
            isAtTurn = distToNextTurn <= RouteGuidanceConfig.AT_TURN_DISTANCE_METRES,
            hasArrived = false
        )
    }
}
