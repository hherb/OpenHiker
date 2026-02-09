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

package com.openhiker.core.community

import com.openhiker.core.model.Coordinate
import com.openhiker.core.model.PlannedRoute
import com.openhiker.core.model.RoutingMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

/** Unit tests for [CommunityRouteConverter] format conversion functions. */
class CommunityRouteConverterTest {

    // ── sharedRouteToPlannedRoute ────────────────────────────────

    @Test
    fun `converts shared route to planned route with correct coordinates`() {
        val shared = makeSampleSharedRoute()
        val planned = CommunityRouteConverter.sharedRouteToPlannedRoute(shared)

        assertEquals(shared.name, planned.name)
        assertEquals(shared.activityType, planned.mode)
        assertEquals(shared.stats.distanceMeters, planned.totalDistance, 0.01)
        assertEquals(shared.stats.elevationGainMeters, planned.elevationGain, 0.01)
        assertEquals(shared.stats.elevationLossMeters, planned.elevationLoss, 0.01)
        assertEquals(shared.stats.durationSeconds, planned.estimatedDuration, 0.01)
    }

    @Test
    fun `converts shared route with start and end coordinates from track`() {
        val shared = makeSampleSharedRoute()
        val planned = CommunityRouteConverter.sharedRouteToPlannedRoute(shared)

        assertEquals(47.26543, planned.startCoordinate.latitude, 0.0001)
        assertEquals(11.39354, planned.startCoordinate.longitude, 0.0001)
        assertEquals(47.27000, planned.endCoordinate.latitude, 0.0001)
        assertEquals(11.40000, planned.endCoordinate.longitude, 0.0001)
    }

    @Test
    fun `converts shared route with region ID`() {
        val shared = makeSampleSharedRoute()
        val planned = CommunityRouteConverter.sharedRouteToPlannedRoute(shared, "region-123")
        assertEquals("region-123", planned.regionId)
    }

    @Test
    fun `generates new UUID for converted planned route`() {
        val shared = makeSampleSharedRoute()
        val planned = CommunityRouteConverter.sharedRouteToPlannedRoute(shared)
        assertNotNull(planned.id)
        // Must be a valid UUID format (36 chars with dashes)
        assertEquals(36, planned.id.length)
    }

    @Test
    fun `converts shared route track points to coordinates`() {
        val shared = makeSampleSharedRoute()
        val planned = CommunityRouteConverter.sharedRouteToPlannedRoute(shared)

        assertEquals(3, planned.coordinates.size)
        assertEquals(47.26543, planned.coordinates[0].latitude, 0.0001)
        assertEquals(11.39354, planned.coordinates[0].longitude, 0.0001)
    }

    @Test
    fun `handles empty track gracefully`() {
        val shared = makeSampleSharedRoute().copy(track = emptyList())
        val planned = CommunityRouteConverter.sharedRouteToPlannedRoute(shared)

        assertEquals(Coordinate.ZERO, planned.startCoordinate)
        assertEquals(Coordinate.ZERO, planned.endCoordinate)
        assertEquals(0, planned.coordinates.size)
    }

    // ── plannedRouteToSharedRoute ────────────────────────────────

    @Test
    fun `converts planned route to shared route with metadata`() {
        val planned = makeSamplePlannedRoute()
        val shared = CommunityRouteConverter.plannedRouteToSharedRoute(
            route = planned,
            author = "Test Hiker",
            description = "A lovely mountain hike",
            country = "AT",
            area = "Tirol"
        )

        assertEquals(planned.name, shared.name)
        assertEquals(planned.mode, shared.activityType)
        assertEquals("Test Hiker", shared.author)
        assertEquals("A lovely mountain hike", shared.description)
        assertEquals("AT", shared.region.country)
        assertEquals("Tirol", shared.region.area)
    }

    @Test
    fun `converts planned route stats correctly`() {
        val planned = makeSamplePlannedRoute()
        val shared = CommunityRouteConverter.plannedRouteToSharedRoute(
            planned, "Author", "Desc", "US", "California"
        )

        assertEquals(planned.totalDistance, shared.stats.distanceMeters, 0.01)
        assertEquals(planned.elevationGain, shared.stats.elevationGainMeters, 0.01)
        assertEquals(planned.elevationLoss, shared.stats.elevationLossMeters, 0.01)
        assertEquals(planned.estimatedDuration, shared.stats.durationSeconds, 0.01)
    }

    @Test
    fun `converts coordinates to track points`() {
        val planned = makeSamplePlannedRoute()
        val shared = CommunityRouteConverter.plannedRouteToSharedRoute(
            planned, "Author", "Desc", "US", "CA"
        )

        assertEquals(planned.coordinates.size, shared.track.size)
        assertEquals(47.26543, shared.track[0].lat, 0.0001)
    }

    @Test
    fun `computes bounding box for shared route`() {
        val planned = makeSamplePlannedRoute()
        val shared = CommunityRouteConverter.plannedRouteToSharedRoute(
            planned, "Author", "Desc", "US", "CA"
        )

        assertEquals(47.27, shared.boundingBox.north, 0.001)
        assertEquals(47.26543, shared.boundingBox.south, 0.001)
        assertEquals(11.4, shared.boundingBox.east, 0.001)
        assertEquals(11.39354, shared.boundingBox.west, 0.001)
    }

    // ── computeBoundingBox ───────────────────────────────────────

    @Test
    fun `bounding box of empty list returns zeros`() {
        val box = CommunityRouteConverter.computeBoundingBox(emptyList())
        assertEquals(0.0, box.north, 0.0)
        assertEquals(0.0, box.south, 0.0)
        assertEquals(0.0, box.east, 0.0)
        assertEquals(0.0, box.west, 0.0)
    }

    @Test
    fun `bounding box of single point`() {
        val coords = listOf(Coordinate(47.5, 11.3))
        val box = CommunityRouteConverter.computeBoundingBox(coords)
        assertEquals(47.5, box.north, 0.001)
        assertEquals(47.5, box.south, 0.001)
        assertEquals(11.3, box.east, 0.001)
        assertEquals(11.3, box.west, 0.001)
    }

    @Test
    fun `bounding box of multiple points`() {
        val coords = listOf(
            Coordinate(47.0, 11.0),
            Coordinate(48.0, 12.0),
            Coordinate(47.5, 11.5)
        )
        val box = CommunityRouteConverter.computeBoundingBox(coords)
        assertEquals(48.0, box.north, 0.001)
        assertEquals(47.0, box.south, 0.001)
        assertEquals(12.0, box.east, 0.001)
        assertEquals(11.0, box.west, 0.001)
    }

    // ── roundTo5Decimals ─────────────────────────────────────────

    @Test
    fun `rounds to 5 decimal places`() {
        assertEquals(47.26543, CommunityRouteConverter.roundTo5Decimals(47.265432789), 0.000001)
        assertEquals(11.39354, CommunityRouteConverter.roundTo5Decimals(11.393541), 0.000001)
    }

    @Test
    fun `rounds zero correctly`() {
        assertEquals(0.0, CommunityRouteConverter.roundTo5Decimals(0.0), 0.0)
    }

    @Test
    fun `rounds negative values correctly`() {
        assertEquals(-122.41942, CommunityRouteConverter.roundTo5Decimals(-122.419423), 0.000001)
    }

    // ── helpers ──────────────────────────────────────────────────

    private fun makeSampleSharedRoute() = SharedRoute(
        id = "route-abc-123",
        version = 1,
        name = "Innsbruck Summit",
        activityType = RoutingMode.HIKING,
        author = "Test Hiker",
        description = "A summit hike above Innsbruck",
        createdAt = "2025-06-15T10:00:00Z",
        region = RouteRegion(country = "AT", area = "Tirol"),
        stats = RouteStats(
            distanceMeters = 12000.0,
            elevationGainMeters = 800.0,
            elevationLossMeters = 750.0,
            durationSeconds = 14400.0
        ),
        boundingBox = SharedBoundingBox(
            north = 47.28, south = 47.26, east = 11.41, west = 11.39
        ),
        track = listOf(
            SharedTrackPoint(47.26543, 11.39354, 600.0, "2025-06-15T10:00:00Z"),
            SharedTrackPoint(47.26800, 11.39700, 750.0, "2025-06-15T11:00:00Z"),
            SharedTrackPoint(47.27000, 11.40000, 900.0, "2025-06-15T12:00:00Z")
        )
    )

    private fun makeSamplePlannedRoute() = PlannedRoute(
        id = "planned-abc-123",
        name = "Innsbruck Summit",
        mode = RoutingMode.HIKING,
        startCoordinate = Coordinate(47.26543, 11.39354),
        endCoordinate = Coordinate(47.27000, 11.40000),
        coordinates = listOf(
            Coordinate(47.26543, 11.39354),
            Coordinate(47.26800, 11.39700),
            Coordinate(47.27000, 11.40000)
        ),
        totalDistance = 12000.0,
        estimatedDuration = 14400.0,
        elevationGain = 800.0,
        elevationLoss = 750.0,
        createdAt = "2025-06-15T10:00:00Z"
    )
}
