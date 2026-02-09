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

package com.openhiker.core.geo

import com.openhiker.core.model.Coordinate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Unit tests for [Haversine] distance and bearing calculations. */
class HaversineTest {

    // ── Distance ───────────────────────────────────────────────────

    @Test
    fun `distance between same point is zero`() {
        val point = Coordinate(47.26, 11.39)
        assertEquals(0.0, Haversine.distance(point, point), 0.001)
    }

    @Test
    fun `distance between Innsbruck and Vienna is approximately 380 km`() {
        val innsbruck = Coordinate(47.26, 11.39)
        val vienna = Coordinate(48.21, 16.37)
        val distance = Haversine.distance(innsbruck, vienna)
        // Known distance: ~380 km
        assertEquals(380_000.0, distance, 10_000.0)
    }

    @Test
    fun `distance between equator points is approximately longitude difference`() {
        val p1 = Coordinate(0.0, 0.0)
        val p2 = Coordinate(0.0, 1.0)
        // 1 degree longitude at equator ≈ 111.32 km
        val distance = Haversine.distance(p1, p2)
        assertEquals(111_320.0, distance, 1_000.0)
    }

    @Test
    fun `raw coordinates overload matches Coordinate overload`() {
        val d1 = Haversine.distance(Coordinate(47.26, 11.39), Coordinate(48.21, 16.37))
        val d2 = Haversine.distance(47.26, 11.39, 48.21, 16.37)
        assertEquals(d1, d2, 0.001)
    }

    // ── Bearing ────────────────────────────────────────────────────

    @Test
    fun `bearing due north is approximately 0 degrees`() {
        val from = Coordinate(47.0, 11.0)
        val to = Coordinate(48.0, 11.0)
        val bearing = Haversine.bearing(from, to)
        assertEquals(0.0, bearing, 1.0)
    }

    @Test
    fun `bearing due east is approximately 90 degrees`() {
        val from = Coordinate(0.0, 0.0)
        val to = Coordinate(0.0, 1.0)
        val bearing = Haversine.bearing(from, to)
        assertEquals(90.0, bearing, 1.0)
    }

    @Test
    fun `bearing due south is approximately 180 degrees`() {
        val from = Coordinate(48.0, 11.0)
        val to = Coordinate(47.0, 11.0)
        val bearing = Haversine.bearing(from, to)
        assertEquals(180.0, bearing, 1.0)
    }

    @Test
    fun `bearing due west is approximately 270 degrees`() {
        val from = Coordinate(0.0, 1.0)
        val to = Coordinate(0.0, 0.0)
        val bearing = Haversine.bearing(from, to)
        assertEquals(270.0, bearing, 1.0)
    }

    // ── Destination ────────────────────────────────────────────────

    @Test
    fun `destination north 1000m from equator`() {
        val from = Coordinate(0.0, 0.0)
        val dest = Haversine.destination(from, 0.0, 1000.0)
        assertTrue("Destination should be north", dest.latitude > from.latitude)
        assertEquals(0.0, dest.longitude, 0.001)
    }

    @Test
    fun `destination roundtrip matches distance`() {
        val from = Coordinate(47.26, 11.39)
        val dest = Haversine.destination(from, 45.0, 5000.0)
        val dist = Haversine.distance(from, dest)
        assertEquals(5000.0, dist, 1.0)
    }

    // ── Polyline distance ──────────────────────────────────────────

    @Test
    fun `polylineDistance of empty list is zero`() {
        assertEquals(0.0, Haversine.polylineDistance(emptyList()), 0.001)
    }

    @Test
    fun `polylineDistance of single point is zero`() {
        assertEquals(0.0, Haversine.polylineDistance(listOf(Coordinate(47.26, 11.39))), 0.001)
    }

    @Test
    fun `polylineDistance sums segment distances`() {
        val points = listOf(
            Coordinate(47.26, 11.39),
            Coordinate(47.27, 11.39),
            Coordinate(47.27, 11.40)
        )
        val total = Haversine.polylineDistance(points)
        val seg1 = Haversine.distance(points[0], points[1])
        val seg2 = Haversine.distance(points[1], points[2])
        assertEquals(seg1 + seg2, total, 0.01)
    }

    // ── Bearing delta normalization ────────────────────────────────

    @Test
    fun `normalizeBearingDelta normalizes positive delta`() {
        assertEquals(10.0, Haversine.normalizeBearingDelta(10.0), 0.001)
        assertEquals(-10.0, Haversine.normalizeBearingDelta(350.0), 0.001)
    }

    @Test
    fun `normalizeBearingDelta normalizes negative delta`() {
        assertEquals(-10.0, Haversine.normalizeBearingDelta(-10.0), 0.001)
        assertEquals(10.0, Haversine.normalizeBearingDelta(-350.0), 0.001)
    }

    // ── Cardinal direction ─────────────────────────────────────────

    @Test
    fun `cardinal directions are correct`() {
        assertEquals("north", Haversine.cardinalDirection(0.0))
        assertEquals("north", Haversine.cardinalDirection(360.0))
        assertEquals("east", Haversine.cardinalDirection(90.0))
        assertEquals("south", Haversine.cardinalDirection(180.0))
        assertEquals("west", Haversine.cardinalDirection(270.0))
        assertEquals("northeast", Haversine.cardinalDirection(45.0))
        assertEquals("southeast", Haversine.cardinalDirection(135.0))
        assertEquals("southwest", Haversine.cardinalDirection(225.0))
        assertEquals("northwest", Haversine.cardinalDirection(315.0))
    }
}
