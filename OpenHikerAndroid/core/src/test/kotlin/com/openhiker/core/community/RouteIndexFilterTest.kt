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

import com.openhiker.core.model.RoutingMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Unit tests for [RouteIndexFilter] pure filtering and sorting functions. */
class RouteIndexFilterTest {

    private val sampleEntries = listOf(
        makeEntry("1", "Mount Tamalpais Loop", RoutingMode.HIKING, "US", "California",
            distance = 15000.0, elevation = 800.0, date = "2025-06-15T10:00:00Z",
            north = 37.95, south = 37.85, east = -122.55, west = -122.65),
        makeEntry("2", "Rhine Valley Cycle", RoutingMode.CYCLING, "DE", "Rheinland-Pfalz",
            distance = 45000.0, elevation = 200.0, date = "2025-07-01T08:00:00Z",
            north = 50.4, south = 49.9, east = 7.9, west = 7.5),
        makeEntry("3", "Blue Ridge Trail", RoutingMode.HIKING, "US", "Virginia",
            distance = 8000.0, elevation = 1200.0, date = "2025-05-20T14:00:00Z",
            north = 37.5, south = 37.3, east = -79.8, west = -80.1),
        makeEntry("4", "Tirol Summit Hike", RoutingMode.HIKING, "AT", "Tirol",
            distance = 12000.0, elevation = 1500.0, date = "2025-08-10T06:00:00Z",
            north = 47.3, south = 47.1, east = 11.5, west = 11.2)
    )

    // ── filterByQuery ────────────────────────────────────────────

    @Test
    fun `filterByQuery returns all entries for blank query`() {
        assertEquals(4, RouteIndexFilter.filterByQuery(sampleEntries, "").size)
        assertEquals(4, RouteIndexFilter.filterByQuery(sampleEntries, "  ").size)
    }

    @Test
    fun `filterByQuery matches name case-insensitively`() {
        val result = RouteIndexFilter.filterByQuery(sampleEntries, "mount")
        assertEquals(1, result.size)
        assertEquals("1", result[0].id)
    }

    @Test
    fun `filterByQuery matches area field`() {
        val result = RouteIndexFilter.filterByQuery(sampleEntries, "Tirol")
        assertEquals(1, result.size)
        assertEquals("4", result[0].id)
    }

    @Test
    fun `filterByQuery returns empty for no match`() {
        assertTrue(RouteIndexFilter.filterByQuery(sampleEntries, "nonexistent").isEmpty())
    }

    // ── filterByActivityType ─────────────────────────────────────

    @Test
    fun `filterByActivityType returns all for null type`() {
        assertEquals(4, RouteIndexFilter.filterByActivityType(sampleEntries, null).size)
    }

    @Test
    fun `filterByActivityType filters hiking routes`() {
        val result = RouteIndexFilter.filterByActivityType(sampleEntries, RoutingMode.HIKING)
        assertEquals(3, result.size)
        assertTrue(result.all { it.activityType == RoutingMode.HIKING })
    }

    @Test
    fun `filterByActivityType filters cycling routes`() {
        val result = RouteIndexFilter.filterByActivityType(sampleEntries, RoutingMode.CYCLING)
        assertEquals(1, result.size)
        assertEquals("2", result[0].id)
    }

    // ── filterByCountry ──────────────────────────────────────────

    @Test
    fun `filterByCountry returns all for null code`() {
        assertEquals(4, RouteIndexFilter.filterByCountry(sampleEntries, null).size)
    }

    @Test
    fun `filterByCountry returns all for blank code`() {
        assertEquals(4, RouteIndexFilter.filterByCountry(sampleEntries, "").size)
    }

    @Test
    fun `filterByCountry filters by US`() {
        val result = RouteIndexFilter.filterByCountry(sampleEntries, "US")
        assertEquals(2, result.size)
    }

    @Test
    fun `filterByCountry is case-insensitive`() {
        val result = RouteIndexFilter.filterByCountry(sampleEntries, "de")
        assertEquals(1, result.size)
        assertEquals("2", result[0].id)
    }

    // ── filterByViewport ─────────────────────────────────────────

    @Test
    fun `filterByViewport returns all for null viewport`() {
        assertEquals(4, RouteIndexFilter.filterByViewport(sampleEntries, null).size)
    }

    @Test
    fun `filterByViewport filters to California area`() {
        val viewport = SharedBoundingBox(north = 38.0, south = 37.0, east = -122.0, west = -123.0)
        val result = RouteIndexFilter.filterByViewport(sampleEntries, viewport)
        assertEquals(1, result.size)
        assertEquals("1", result[0].id)
    }

    @Test
    fun `filterByViewport returns empty when no routes in viewport`() {
        val viewport = SharedBoundingBox(north = 60.0, south = 59.0, east = 10.0, west = 9.0)
        assertTrue(RouteIndexFilter.filterByViewport(sampleEntries, viewport).isEmpty())
    }

    // ── applyFilters ─────────────────────────────────────────────

    @Test
    fun `applyFilters combines query and activity type`() {
        val result = RouteIndexFilter.applyFilters(
            sampleEntries,
            query = "trail",
            activityType = RoutingMode.HIKING
        )
        assertEquals(1, result.size)
        assertEquals("3", result[0].id)
    }

    @Test
    fun `applyFilters with no filters returns all`() {
        assertEquals(4, RouteIndexFilter.applyFilters(sampleEntries).size)
    }

    // ── sort functions ───────────────────────────────────────────

    @Test
    fun `sortByDateDescending sorts newest first`() {
        val sorted = RouteIndexFilter.sortByDateDescending(sampleEntries)
        assertEquals("4", sorted[0].id)
        assertEquals("3", sorted[3].id)
    }

    @Test
    fun `sortByDistanceDescending sorts longest first`() {
        val sorted = RouteIndexFilter.sortByDistanceDescending(sampleEntries)
        assertEquals("2", sorted[0].id) // 45000m
        assertEquals("3", sorted[3].id) // 8000m
    }

    @Test
    fun `sortByElevationDescending sorts highest first`() {
        val sorted = RouteIndexFilter.sortByElevationDescending(sampleEntries)
        assertEquals("4", sorted[0].id) // 1500m
        assertEquals("2", sorted[3].id) // 200m
    }

    @Test
    fun `sortByNameAscending sorts alphabetically`() {
        val sorted = RouteIndexFilter.sortByNameAscending(sampleEntries)
        assertEquals("3", sorted[0].id) // Blue Ridge
        assertEquals("4", sorted[3].id) // Tirol Summit
    }

    // ── distinctCountries ────────────────────────────────────────

    @Test
    fun `distinctCountries returns sorted unique codes`() {
        val countries = RouteIndexFilter.distinctCountries(sampleEntries)
        assertEquals(listOf("AT", "DE", "US"), countries)
    }

    // ── boundingBoxesIntersect ────────────────────────────────────

    @Test
    fun `overlapping boxes intersect`() {
        val a = SharedBoundingBox(north = 10.0, south = 0.0, east = 10.0, west = 0.0)
        val b = SharedBoundingBox(north = 5.0, south = -5.0, east = 5.0, west = -5.0)
        assertTrue(RouteIndexFilter.boundingBoxesIntersect(a, b))
    }

    @Test
    fun `non-overlapping boxes do not intersect`() {
        val a = SharedBoundingBox(north = 10.0, south = 5.0, east = 10.0, west = 5.0)
        val b = SharedBoundingBox(north = 3.0, south = 0.0, east = 3.0, west = 0.0)
        assertFalse(RouteIndexFilter.boundingBoxesIntersect(a, b))
    }

    @Test
    fun `touching edges intersect`() {
        val a = SharedBoundingBox(north = 10.0, south = 5.0, east = 10.0, west = 5.0)
        val b = SharedBoundingBox(north = 5.0, south = 0.0, east = 5.0, west = 0.0)
        assertTrue(RouteIndexFilter.boundingBoxesIntersect(a, b))
    }

    // ── helpers ──────────────────────────────────────────────────

    private fun makeEntry(
        id: String, name: String, activity: RoutingMode, country: String, area: String,
        distance: Double, elevation: Double, date: String,
        north: Double, south: Double, east: Double, west: Double
    ) = RouteIndexEntry(
        id = id,
        name = name,
        activityType = activity,
        author = "Test Author",
        summary = "A test route in $area",
        createdAt = date,
        region = RouteRegion(country = country, area = area),
        stats = RouteStats(
            distanceMeters = distance,
            elevationGainMeters = elevation,
            elevationLossMeters = elevation * 0.9,
            durationSeconds = distance / 1.2
        ),
        boundingBox = SharedBoundingBox(north = north, south = south, east = east, west = west),
        path = "routes/$country/${name.lowercase().replace(" ", "-")}",
        photoCount = 0,
        waypointCount = 0
    )
}
