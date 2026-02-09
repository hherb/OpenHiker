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
import com.openhiker.core.model.TurnDirection
import com.openhiker.core.model.TurnInstruction
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [RouteFollower] navigation state updates.
 *
 * Uses a simple north-bound route from the equator with three waypoints:
 * start (0,0), midpoint (0.005,0), and end (0.01,0), giving a total
 * distance of approximately 1113 metres. A turn instruction is placed
 * at the midpoint so we can test turn-approaching and at-turn detection.
 */
class RouteFollowerTest {

    // ── Test route setup ──────────────────────────────────────────

    /** Route start point at the equator/prime meridian intersection. */
    private val routeStart = Coordinate(0.0, 0.0)

    /** Route midpoint ~556m north of start, where a turn instruction is placed. */
    private val routeMid = Coordinate(0.005, 0.0)

    /** Route endpoint ~1113m north of start. */
    private val routeEnd = Coordinate(0.01, 0.0)

    /** Simple three-point route polyline heading due north. */
    private val routeCoordinates = listOf(routeStart, routeMid, routeEnd)

    /** Total route distance in metres (~1113m). */
    private val totalDistance = Haversine.polylineDistance(routeCoordinates)

    /** Distance from start to midpoint in metres (~556m). */
    private val distToMid = Haversine.distance(routeStart, routeMid)

    /** Turn instructions: START at origin, RIGHT at midpoint, ARRIVE at end. */
    private val instructions = listOf(
        TurnInstruction(
            coordinate = routeStart,
            direction = TurnDirection.START,
            bearing = 0.0,
            distanceFromPrevious = 0.0,
            cumulativeDistance = 0.0,
            description = "Start heading north"
        ),
        TurnInstruction(
            coordinate = routeMid,
            direction = TurnDirection.RIGHT,
            bearing = 90.0,
            distanceFromPrevious = distToMid,
            cumulativeDistance = distToMid,
            description = "Turn right"
        ),
        TurnInstruction(
            coordinate = routeEnd,
            direction = TurnDirection.ARRIVE,
            bearing = 0.0,
            distanceFromPrevious = Haversine.distance(routeMid, routeEnd),
            cumulativeDistance = totalDistance,
            description = "Arrive at destination"
        )
    )

    // ── Default state ─────────────────────────────────────────────

    @Test
    fun `default NavigationState has no arrival and no turn approaching`() {
        val state = NavigationState()
        assertNull("currentInstruction should be null by default", state.currentInstruction)
        assertEquals("distanceToNextTurn should default to 0", 0.0, state.distanceToNextTurn, 0.001)
        assertEquals("progress should default to 0", 0f, state.progress, 0.001f)
        assertEquals("remainingDistance should default to 0", 0.0, state.remainingDistance, 0.001)
        assertFalse("isApproachingTurn should be false by default", state.isApproachingTurn)
        assertFalse("isAtTurn should be false by default", state.isAtTurn)
        assertFalse("hasArrived should be false by default", state.hasArrived)
    }

    // ── Update on route ───────────────────────────────────────────

    @Test
    fun `update near route start returns valid state with low progress`() {
        val follower = RouteFollower(routeCoordinates, instructions, totalDistance)
        // Position slightly north of start, having walked ~100m
        val pos = Haversine.destination(routeStart, 0.0, 100.0)
        val state = follower.update(pos.latitude, pos.longitude, 100.0)

        assertFalse("Should not have arrived near the start", state.hasArrived)
        assertTrue("Progress should be small near start", state.progress < 0.2f)
        assertTrue("Remaining distance should be most of the route", state.remainingDistance > 900.0)
    }

    @Test
    fun `update at route midpoint shows roughly 50 percent progress`() {
        val follower = RouteFollower(routeCoordinates, instructions, totalDistance)
        val state = follower.update(routeMid.latitude, routeMid.longitude, distToMid)

        assertFalse("Should not have arrived at midpoint", state.hasArrived)
        assertEquals("Progress should be approximately 0.5", 0.5f, state.progress, 0.05f)
    }

    // ── Arrival detection ─────────────────────────────────────────

    @Test
    fun `update at destination sets hasArrived to true`() {
        val follower = RouteFollower(routeCoordinates, instructions, totalDistance)
        val state = follower.update(routeEnd.latitude, routeEnd.longitude, totalDistance)

        assertTrue("hasArrived should be true at destination", state.hasArrived)
        assertEquals("Progress should be 1.0 on arrival", 1.0f, state.progress, 0.001f)
        assertEquals("Remaining distance should be 0 on arrival", 0.0, state.remainingDistance, 0.001)
    }

    @Test
    fun `update within arrived threshold of destination sets hasArrived`() {
        val follower = RouteFollower(routeCoordinates, instructions, totalDistance)
        // Position 20m south of the endpoint (within 30m ARRIVED_DISTANCE_METRES)
        val nearEnd = Haversine.destination(routeEnd, 180.0, 20.0)
        val state = follower.update(nearEnd.latitude, nearEnd.longitude, totalDistance - 20.0)

        assertTrue("hasArrived should be true within arrived threshold", state.hasArrived)
    }

    // ── Approaching turn detection ────────────────────────────────

    @Test
    fun `approaching turn is true within approaching threshold of next instruction`() {
        val follower = RouteFollower(routeCoordinates, instructions, totalDistance)
        // Position 80m south of the midpoint turn (within 100m APPROACHING_TURN_DISTANCE_METRES)
        val nearTurn = Haversine.destination(routeMid, 180.0, 80.0)
        val walked = distToMid - 80.0
        val state = follower.update(nearTurn.latitude, nearTurn.longitude, walked)

        assertTrue("isApproachingTurn should be true within approaching threshold", state.isApproachingTurn)
        assertFalse("hasArrived should be false when approaching a mid-route turn", state.hasArrived)
    }

    @Test
    fun `approaching turn is false when far from next instruction`() {
        val follower = RouteFollower(routeCoordinates, instructions, totalDistance)
        // Position 200m north of start — well beyond 100m from the START instruction
        // but the START instruction is behind us, so the current instruction should advance
        // Let's position ourselves 200m from start, which is >100m from midpoint turn
        val farFromTurn = Haversine.destination(routeStart, 0.0, 200.0)
        val state = follower.update(farFromTurn.latitude, farFromTurn.longitude, 200.0)

        assertFalse("isApproachingTurn should be false when far from next turn", state.isApproachingTurn)
    }

    // ── At turn detection ─────────────────────────────────────────

    @Test
    fun `isAtTurn is true within at-turn threshold of next instruction`() {
        val follower = RouteFollower(routeCoordinates, instructions, totalDistance)
        // Position 20m south of the midpoint turn (within 30m AT_TURN_DISTANCE_METRES)
        val atTurn = Haversine.destination(routeMid, 180.0, 20.0)
        val walked = distToMid - 20.0
        val state = follower.update(atTurn.latitude, atTurn.longitude, walked)

        assertTrue("isAtTurn should be true within at-turn threshold", state.isAtTurn)
        assertTrue("isApproachingTurn should also be true when at turn", state.isApproachingTurn)
    }

    // ── Empty inputs ──────────────────────────────────────────────

    @Test
    fun `update with empty route returns default state`() {
        val follower = RouteFollower(emptyList(), instructions, 0.0)
        val state = follower.update(0.0, 0.0, 0.0)

        assertNull("currentInstruction should be null for empty route", state.currentInstruction)
        assertFalse("hasArrived should be false for empty route", state.hasArrived)
    }

    @Test
    fun `update with empty instructions returns default state`() {
        val follower = RouteFollower(routeCoordinates, emptyList(), totalDistance)
        val state = follower.update(0.0, 0.0, 0.0)

        assertNull("currentInstruction should be null for empty instructions", state.currentInstruction)
        assertFalse("hasArrived should be false for empty instructions", state.hasArrived)
    }
}
