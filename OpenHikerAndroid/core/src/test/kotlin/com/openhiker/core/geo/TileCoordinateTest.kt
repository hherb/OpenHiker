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

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [TileCoordinate] covering Web Mercator conversions,
 * TMS Y-flipping, tile hierarchy, and validation.
 */
class TileCoordinateTest {

    // ── Lat/Lon ↔ Tile conversion ──────────────────────────────────

    @Test
    fun `fromLatLon converts Innsbruck to correct tile at zoom 14`() {
        // Innsbruck, Austria: approximately 47.26, 11.39
        val tile = TileCoordinate.fromLatLon(47.26, 11.39, 14)
        assertEquals(14, tile.z)
        // At zoom 14, Innsbruck should be around x=8725, y=5765
        assertTrue("x should be around 8725, got ${tile.x}", tile.x in 8720..8730)
        assertTrue("y should be around 5765, got ${tile.y}", tile.y in 5760..5770)
    }

    @Test
    fun `fromLatLon converts 0,0 to centre tile at zoom 1`() {
        val tile = TileCoordinate.fromLatLon(0.0, 0.0, 1)
        assertEquals(1, tile.z)
        assertEquals(1, tile.x) // 0-1 range, 0 degrees is in the right half
        assertEquals(1, tile.y) // equator is at y=1 in a 2x2 grid
    }

    @Test
    fun `tileToLatLon roundtrips correctly`() {
        val lat = 47.26
        val lon = 11.39
        val zoom = 14

        val tile = TileCoordinate.fromLatLon(lat, lon, zoom)
        val nw = tile.northWest
        val se = tile.southEast

        // The original point should be within the tile's bounds
        assertTrue("Lat ${nw.latitude} >= $lat", nw.latitude >= lat)
        assertTrue("Lat ${se.latitude} <= $lat", se.latitude <= lat)
        assertTrue("Lon ${nw.longitude} <= $lon", nw.longitude <= lon)
        assertTrue("Lon ${se.longitude} >= $lon", se.longitude >= lon)
    }

    @Test
    fun `center returns midpoint of tile`() {
        val tile = TileCoordinate(0, 0, 1) // NW quadrant of the world
        val center = tile.center
        assertTrue("Center lat should be positive", center.latitude > 0)
        assertTrue("Center lon should be negative", center.longitude < 0)
    }

    // ── TMS Y-flip ─────────────────────────────────────────────────

    @Test
    fun `tmsY flips y coordinate correctly at zoom 14`() {
        val tile = TileCoordinate(8725, 5765, 14)
        val expectedTmsY = (1 shl 14) - 1 - 5765
        assertEquals(expectedTmsY, tile.tmsY)
    }

    @Test
    fun `tmsY at zoom 0 is always 0`() {
        val tile = TileCoordinate(0, 0, 0)
        assertEquals(0, tile.tmsY)
    }

    @Test
    fun `tmsY double flip returns original y`() {
        val tile = TileCoordinate(100, 200, 10)
        val tmsY = tile.tmsY
        val restored = (1 shl 10) - 1 - tmsY
        assertEquals(tile.y, restored)
    }

    // ── Validation ─────────────────────────────────────────────────

    @Test
    fun `valid tile at zoom 14`() {
        val tile = TileCoordinate(8725, 5765, 14)
        assertTrue(tile.isValid)
    }

    @Test
    fun `invalid tile with negative x`() {
        val tile = TileCoordinate(-1, 0, 10)
        assertFalse(tile.isValid)
    }

    @Test
    fun `invalid tile with x exceeding grid`() {
        val tile = TileCoordinate(1024, 0, 10) // 2^10 = 1024, max valid is 1023
        assertFalse(tile.isValid)
    }

    @Test
    fun `invalid tile with zoom exceeding max`() {
        val tile = TileCoordinate(0, 0, 23)
        assertFalse(tile.isValid)
    }

    // ── Tile hierarchy ─────────────────────────────────────────────

    @Test
    fun `parent reduces zoom by 1 and halves coordinates`() {
        val tile = TileCoordinate(100, 200, 10)
        val parent = tile.parent
        assertNotNull(parent)
        assertEquals(9, parent!!.z)
        assertEquals(50, parent.x)
        assertEquals(100, parent.y)
    }

    @Test
    fun `parent of zoom 0 is null`() {
        val tile = TileCoordinate(0, 0, 0)
        assertNull(tile.parent)
    }

    @Test
    fun `children produces 4 tiles at zoom+1`() {
        val tile = TileCoordinate(50, 100, 9)
        val children = tile.children
        assertEquals(4, children.size)
        assertTrue(children.all { it.z == 10 })
        assertTrue(children.any { it.x == 100 && it.y == 200 })
        assertTrue(children.any { it.x == 101 && it.y == 200 })
        assertTrue(children.any { it.x == 100 && it.y == 201 })
        assertTrue(children.any { it.x == 101 && it.y == 201 })
    }

    @Test
    fun `neighbors returns up to 8 valid tiles`() {
        val tile = TileCoordinate(5, 5, 4) // Well within grid
        val neighbors = tile.neighbors
        assertEquals(8, neighbors.size)
        assertTrue(neighbors.all { it.isValid })
        assertTrue(neighbors.none { it.x == tile.x && it.y == tile.y })
    }

    @Test
    fun `neighbors at corner returns fewer tiles`() {
        val tile = TileCoordinate(0, 0, 4)
        val neighbors = tile.neighbors
        assertTrue(neighbors.size < 8)
        assertTrue(neighbors.all { it.isValid })
    }

    // ── tilesPerAxis ───────────────────────────────────────────────

    @Test
    fun `tilesPerAxis at zoom 0 is 1`() {
        assertEquals(1, TileCoordinate(0, 0, 0).tilesPerAxis)
    }

    @Test
    fun `tilesPerAxis at zoom 14 is 16384`() {
        assertEquals(16384, TileCoordinate(0, 0, 14).tilesPerAxis)
    }

    // ── metersPerPixel ─────────────────────────────────────────────

    @Test
    fun `metersPerPixel decreases with higher zoom`() {
        val zoom10 = TileCoordinate(512, 340, 10).metersPerPixel
        val zoom14 = TileCoordinate(8192, 5440, 14).metersPerPixel
        assertTrue("Zoom 14 should have finer resolution", zoom14 < zoom10)
    }
}
