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
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Unit tests for [BoundingBox] geometry and containment. */
class BoundingBoxTest {

    private val innsbruckBox = BoundingBox(
        north = 47.30,
        south = 47.20,
        east = 11.45,
        west = 11.35
    )

    @Test
    fun `center returns midpoint`() {
        val center = innsbruckBox.center
        assertEquals(47.25, center.latitude, 0.001)
        assertEquals(11.40, center.longitude, 0.001)
    }

    @Test
    fun `contains point inside box`() {
        assertTrue(innsbruckBox.contains(Coordinate(47.26, 11.40)))
    }

    @Test
    fun `contains point on edge`() {
        assertTrue(innsbruckBox.contains(Coordinate(47.30, 11.40)))
    }

    @Test
    fun `does not contain point outside box`() {
        assertFalse(innsbruckBox.contains(Coordinate(48.0, 11.40)))
        assertFalse(innsbruckBox.contains(Coordinate(47.25, 12.0)))
    }

    @Test
    fun `areaKm2 is reasonable for Innsbruck region`() {
        // ~0.1 degrees lat x ~0.1 degrees lon near 47 degrees
        // Should be roughly 11 km x 7.5 km = ~83 km2
        val area = innsbruckBox.areaKm2
        assertTrue("Area should be > 50 km2, got $area", area > 50)
        assertTrue("Area should be < 150 km2, got $area", area < 150)
    }

    @Test
    fun `fromCenter creates symmetric box`() {
        val center = Coordinate(47.26, 11.39)
        val box = BoundingBox.fromCenter(center, 5000.0) // 5km radius

        assertTrue(box.contains(center))
        assertTrue(box.north > center.latitude)
        assertTrue(box.south < center.latitude)
        assertTrue(box.east > center.longitude)
        assertTrue(box.west < center.longitude)

        // Should be roughly 10km x 10km
        val area = box.areaKm2
        assertTrue("Area should be > 80 km2, got $area", area > 80)
        assertTrue("Area should be < 120 km2, got $area", area < 120)
    }

    @Test
    fun `widthDegrees and heightDegrees are correct`() {
        assertEquals(0.10, innsbruckBox.heightDegrees, 0.001)
        assertEquals(0.10, innsbruckBox.widthDegrees, 0.001)
    }
}
