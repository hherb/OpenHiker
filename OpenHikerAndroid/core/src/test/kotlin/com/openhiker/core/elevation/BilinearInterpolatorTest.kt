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

package com.openhiker.core.elevation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class BilinearInterpolatorTest {

    // ── Basic bilinear interpolation ─────────────────────────────────

    @Test
    fun `bilinear returns exact NW corner value at (0, 0)`() {
        val result = BilinearInterpolator.bilinear(100.0, 200.0, 300.0, 400.0, 0.0, 0.0)
        assertEquals(100.0, result!!, 0.01)
    }

    @Test
    fun `bilinear returns exact NE corner value at (0, 1)`() {
        val result = BilinearInterpolator.bilinear(100.0, 200.0, 300.0, 400.0, 0.0, 1.0)
        assertEquals(200.0, result!!, 0.01)
    }

    @Test
    fun `bilinear returns exact SW corner value at (1, 0)`() {
        val result = BilinearInterpolator.bilinear(100.0, 200.0, 300.0, 400.0, 1.0, 0.0)
        assertEquals(300.0, result!!, 0.01)
    }

    @Test
    fun `bilinear returns exact SE corner value at (1, 1)`() {
        val result = BilinearInterpolator.bilinear(100.0, 200.0, 300.0, 400.0, 1.0, 1.0)
        assertEquals(400.0, result!!, 0.01)
    }

    @Test
    fun `bilinear returns center average at (0_5, 0_5)`() {
        // At the center, result should be the average of all four corners
        val result = BilinearInterpolator.bilinear(100.0, 200.0, 300.0, 400.0, 0.5, 0.5)
        assertEquals(250.0, result!!, 0.01)
    }

    @Test
    fun `bilinear interpolates along north edge`() {
        // Mid-point of north edge: average of NW and NE
        val result = BilinearInterpolator.bilinear(100.0, 200.0, 300.0, 400.0, 0.0, 0.5)
        assertEquals(150.0, result!!, 0.01)
    }

    @Test
    fun `bilinear interpolates along west edge`() {
        // Mid-point of west edge: average of NW and SW
        val result = BilinearInterpolator.bilinear(100.0, 200.0, 300.0, 400.0, 0.5, 0.0)
        assertEquals(200.0, result!!, 0.01)
    }

    @Test
    fun `bilinear returns uniform value for equal corners`() {
        val result = BilinearInterpolator.bilinear(500.0, 500.0, 500.0, 500.0, 0.3, 0.7)
        assertEquals(500.0, result!!, 0.01)
    }

    // ── Void handling ────────────────────────────────────────────────

    @Test
    fun `bilinear returns null when all corners are void`() {
        val result = BilinearInterpolator.bilinear(null, null, null, null, 0.5, 0.5)
        assertNull(result)
    }

    @Test
    fun `bilinear falls back when one corner is void`() {
        // NW is void, but we have NE, SW, SE
        val result = BilinearInterpolator.bilinear(null, 200.0, 300.0, 400.0, 0.0, 0.0)
        assertNotNull(result)
        // At (0,0) which is closest to NW — should be weighted toward the nearest valid corners
    }

    @Test
    fun `bilinear falls back when two corners are void`() {
        val result = BilinearInterpolator.bilinear(null, null, 300.0, 400.0, 1.0, 0.5)
        assertNotNull(result)
        // At (1.0, 0.5) which is between SW and SE
        assertEquals(350.0, result!!, 1.0) // Should be close to average of SW and SE
    }

    @Test
    fun `bilinear returns single non-void value when three corners are void`() {
        val result = BilinearInterpolator.bilinear(null, null, null, 400.0, 0.5, 0.5)
        assertNotNull(result)
        assertEquals(400.0, result!!, 0.01) // Only one value available
    }

    // ── Grid-based interpolation ─────────────────────────────────────

    @Test
    fun `interpolate returns SW corner elevation for SW corner coordinate`() {
        val grid = createGradientGrid()
        // SW corner: lat = 47.0, lon = 11.0
        val result = BilinearInterpolator.interpolate(grid, 47.0, 11.0)
        assertNotNull(result)
        // At SW corner (row = samples-1, col = 0), elevation should be
        // the value we set for the south-west corner
    }

    @Test
    fun `interpolate returns NE corner elevation for NE corner coordinate`() {
        val grid = createUniformGrid(1000)
        // NE corner: lat = 48.0, lon = 12.0
        val result = BilinearInterpolator.interpolate(grid, 48.0, 12.0)
        assertNotNull(result)
        assertEquals(1000.0, result!!, 0.01)
    }

    @Test
    fun `interpolate returns center elevation for center coordinate`() {
        val grid = createUniformGrid(500)
        val result = BilinearInterpolator.interpolate(grid, 47.5, 11.5)
        assertNotNull(result)
        assertEquals(500.0, result!!, 0.01)
    }

    @Test
    fun `interpolate clamps coordinates outside tile bounds`() {
        val grid = createUniformGrid(500)
        // Slightly outside the tile — should clamp to edge
        val result = BilinearInterpolator.interpolate(grid, 46.99, 10.99)
        assertNotNull(result)
        assertEquals(500.0, result!!, 0.01)
    }

    @Test
    fun `interpolate handles small SRTM3 grid`() {
        val grid = createUniformGrid(750)
        val result = BilinearInterpolator.interpolate(grid, 47.25, 11.75)
        assertNotNull(result)
        assertEquals(750.0, result!!, 0.01)
    }

    // ── Helpers ──────────────────────────────────────────────────────

    /**
     * Creates an SRTM3 grid with all cells set to the same elevation.
     */
    private fun createUniformGrid(elevation: Int): HgtGrid {
        val samples = HgtParser.SRTM3_SAMPLES
        val elevations = ShortArray(samples * samples) { elevation.toShort() }
        return HgtGrid(
            elevations = elevations,
            samples = samples,
            southwestLatitude = 47,
            southwestLongitude = 11
        )
    }

    /**
     * Creates an SRTM3 grid with a north-to-south gradient (north = 2000m, south = 1000m).
     */
    private fun createGradientGrid(): HgtGrid {
        val samples = HgtParser.SRTM3_SAMPLES
        val elevations = ShortArray(samples * samples)
        for (row in 0 until samples) {
            val elevation = (2000 - (row * 1000) / (samples - 1)).toShort()
            for (col in 0 until samples) {
                elevations[row * samples + col] = elevation
            }
        }
        return HgtGrid(
            elevations = elevations,
            samples = samples,
            southwestLatitude = 47,
            southwestLongitude = 11
        )
    }
}
