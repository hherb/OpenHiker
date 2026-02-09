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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [OffRouteDetector] off-route detection with hysteresis.
 *
 * Uses a simple east-west route along the equator from (0,0) to (0,0.01).
 * Positions are offset north (bearing 0) to simulate wandering away from
 * the route. Uses [RouteGuidanceConfig] constants for threshold values:
 * - Off-route trigger: 50m
 * - Off-route clear: 30m
 */
class OffRouteDetectorTest {

    // ── Test route: straight east-west line along the equator ─────

    /** Simple two-point route heading east along the equator. */
    private val routeCoordinates = listOf(
        Coordinate(0.0, 0.0),
        Coordinate(0.0, 0.01)
    )

    /** A point on the route (midpoint). */
    private val onRoute = Coordinate(0.0, 0.005)

    // ── On-route detection ────────────────────────────────────────

    @Test
    fun `position on route is not off-route`() {
        val detector = OffRouteDetector(routeCoordinates)
        val state = detector.check(onRoute.latitude, onRoute.longitude)

        assertFalse("Position directly on route should not be off-route", state.isOffRoute)
        assertEquals("Distance from route should be near zero", 0.0, state.distanceFromRoute, 5.0)
    }

    @Test
    fun `position slightly off route within threshold is not off-route`() {
        val detector = OffRouteDetector(routeCoordinates)
        // 20m north of route — well within the 50m trigger threshold
        val nearRoute = Haversine.destination(onRoute, 0.0, 20.0)
        val state = detector.check(nearRoute.latitude, nearRoute.longitude)

        assertFalse("Position 20m from route should not trigger off-route", state.isOffRoute)
        assertEquals("Distance should be approximately 20m", 20.0, state.distanceFromRoute, 5.0)
    }

    // ── Off-route detection ───────────────────────────────────────

    @Test
    fun `position far from route triggers off-route`() {
        val detector = OffRouteDetector(routeCoordinates)
        // 100m north of route — well beyond the 50m trigger threshold
        val farFromRoute = Haversine.destination(onRoute, 0.0, 100.0)
        val state = detector.check(farFromRoute.latitude, farFromRoute.longitude)

        assertTrue("Position 100m from route should be off-route", state.isOffRoute)
        assertEquals("Distance should be approximately 100m", 100.0, state.distanceFromRoute, 10.0)
    }

    @Test
    fun `position just beyond trigger threshold is off-route`() {
        val detector = OffRouteDetector(routeCoordinates)
        // 55m north — just past the 50m OFF_ROUTE_THRESHOLD_METRES
        val justBeyond = Haversine.destination(onRoute, 0.0, 55.0)
        val state = detector.check(justBeyond.latitude, justBeyond.longitude)

        assertTrue("Position 55m from route should be off-route (threshold is 50m)", state.isOffRoute)
    }

    // ── Return to route ───────────────────────────────────────────

    @Test
    fun `returning to route clears off-route state`() {
        val detector = OffRouteDetector(routeCoordinates)

        // Step 1: Go far off-route (100m)
        val farAway = Haversine.destination(onRoute, 0.0, 100.0)
        val offState = detector.check(farAway.latitude, farAway.longitude)
        assertTrue("Should be off-route at 100m", offState.isOffRoute)

        // Step 2: Return to the route (0m)
        val backOnRoute = detector.check(onRoute.latitude, onRoute.longitude)
        assertFalse("Should be on-route after returning to route", backOnRoute.isOffRoute)
    }

    // ── Hysteresis behaviour ──────────────────────────────────────

    @Test
    fun `hysteresis prevents flapping - must clear below 30m not 50m`() {
        val detector = OffRouteDetector(routeCoordinates)

        // Step 1: Trigger off-route by going 60m away (> 50m threshold)
        val farAway = Haversine.destination(onRoute, 0.0, 60.0)
        val state1 = detector.check(farAway.latitude, farAway.longitude)
        assertTrue("Should be off-route at 60m", state1.isOffRoute)

        // Step 2: Move to 40m — below the 50m trigger but above the 30m clear
        // With hysteresis, should STILL be off-route
        val inHysteresisZone = Haversine.destination(onRoute, 0.0, 40.0)
        val state2 = detector.check(inHysteresisZone.latitude, inHysteresisZone.longitude)
        assertTrue(
            "Should still be off-route at 40m (hysteresis: clear threshold is 30m)",
            state2.isOffRoute
        )

        // Step 3: Move to 25m — below the 30m clear threshold
        // Now the off-route warning should clear
        val backNear = Haversine.destination(onRoute, 0.0, 25.0)
        val state3 = detector.check(backNear.latitude, backNear.longitude)
        assertFalse(
            "Should clear off-route at 25m (below 30m clear threshold)",
            state3.isOffRoute
        )
    }

    @Test
    fun `hysteresis does not trigger at 40m when starting on-route`() {
        val detector = OffRouteDetector(routeCoordinates)

        // Start on-route, then move to 40m — between clear (30m) and trigger (50m)
        // Since we were on-route, the trigger threshold (50m) applies, so we stay on-route
        val at40m = Haversine.destination(onRoute, 0.0, 40.0)
        val state = detector.check(at40m.latitude, at40m.longitude)
        assertFalse(
            "Should NOT be off-route at 40m when starting on-route (trigger is 50m)",
            state.isOffRoute
        )
    }

    // ── Edge cases ────────────────────────────────────────────────

    @Test
    fun `single-point route never reports off-route`() {
        val detector = OffRouteDetector(listOf(Coordinate(0.0, 0.0)))
        val farAway = Coordinate(1.0, 1.0)
        val state = detector.check(farAway.latitude, farAway.longitude)

        assertFalse("Single-point route should never be off-route", state.isOffRoute)
        assertEquals("Distance should be 0 for degenerate route", 0.0, state.distanceFromRoute, 0.001)
    }

    @Test
    fun `empty route never reports off-route`() {
        val detector = OffRouteDetector(emptyList())
        val state = detector.check(0.0, 0.0)

        assertFalse("Empty route should never be off-route", state.isOffRoute)
    }
}
