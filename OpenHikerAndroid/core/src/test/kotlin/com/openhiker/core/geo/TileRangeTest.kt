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
import org.junit.Assert.assertTrue
import org.junit.Test

/** Unit tests for [TileRange] tile enumeration and containment. */
class TileRangeTest {

    private val innsbruckBox = BoundingBox(
        north = 47.30,
        south = 47.20,
        east = 11.45,
        west = 11.35
    )

    @Test
    fun `tileCount matches allTiles size`() {
        val range = TileRange.fromBoundingBox(innsbruckBox, 14)
        assertEquals(range.tileCount, range.allTiles().size)
    }

    @Test
    fun `tileCount increases with zoom level`() {
        val count12 = TileRange.fromBoundingBox(innsbruckBox, 12).tileCount
        val count14 = TileRange.fromBoundingBox(innsbruckBox, 14).tileCount
        val count16 = TileRange.fromBoundingBox(innsbruckBox, 16).tileCount

        assertTrue("Count at z14 ($count14) > z12 ($count12)", count14 > count12)
        assertTrue("Count at z16 ($count16) > z14 ($count14)", count16 > count14)
    }

    @Test
    fun `allTiles are valid`() {
        val range = TileRange.fromBoundingBox(innsbruckBox, 14)
        assertTrue(range.allTiles().all { it.isValid })
    }

    @Test
    fun `allTiles have correct zoom`() {
        val range = TileRange.fromBoundingBox(innsbruckBox, 14)
        assertTrue(range.allTiles().all { it.z == 14 })
    }

    @Test
    fun `contains returns true for tile in range`() {
        val range = TileRange.fromBoundingBox(innsbruckBox, 14)
        val firstTile = range.allTiles().first()
        assertTrue(range.contains(firstTile))
    }

    @Test
    fun `contains returns false for tile outside range`() {
        val range = TileRange.fromBoundingBox(innsbruckBox, 14)
        assertFalse(range.contains(TileCoordinate(0, 0, 14)))
    }

    @Test
    fun `contains returns false for wrong zoom`() {
        val range = TileRange.fromBoundingBox(innsbruckBox, 14)
        val tile = range.allTiles().first()
        assertFalse(range.contains(TileCoordinate(tile.x, tile.y, 15)))
    }

    @Test
    fun `estimateTileCount sums across zoom levels`() {
        val totalCount = TileRange.estimateTileCount(innsbruckBox, 12..16)
        val sumManual = (12..16).sumOf {
            TileRange.fromBoundingBox(innsbruckBox, it).tileCount
        }
        assertEquals(sumManual, totalCount)
    }

    @Test
    fun `estimateTileCount for typical hiking region is reasonable`() {
        // ~10km x 10km region at zoom 12-16 should be a few thousand tiles
        val count = TileRange.estimateTileCount(innsbruckBox, 12..16)
        assertTrue("Count should be > 100, got $count", count > 100)
        assertTrue("Count should be < 50000, got $count", count < 50000)
    }
}
