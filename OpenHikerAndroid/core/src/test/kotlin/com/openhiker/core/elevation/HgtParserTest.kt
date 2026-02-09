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

class HgtParserTest {

    // ── Filename generation ──────────────────────────────────────────

    @Test
    fun `hgtFilename returns correct name for northern eastern hemisphere`() {
        assertEquals("N47E011.hgt", HgtParser.hgtFilename(47.267, 11.393))
    }

    @Test
    fun `hgtFilename returns correct name for southern western hemisphere`() {
        assertEquals("S34W071.hgt", HgtParser.hgtFilename(-33.45, -70.67))
    }

    @Test
    fun `hgtFilename returns correct name for equator prime meridian`() {
        assertEquals("N00E000.hgt", HgtParser.hgtFilename(0.5, 0.5))
    }

    @Test
    fun `hgtFilename handles negative latitude correctly`() {
        assertEquals("S01W001.hgt", HgtParser.hgtFilename(-0.5, -0.5))
    }

    @Test
    fun `hgtFilename pads latitude to 2 digits and longitude to 3 digits`() {
        assertEquals("N05E005.hgt", HgtParser.hgtFilename(5.5, 5.5))
    }

    @Test
    fun `hgtFilename handles longitude 180`() {
        assertEquals("N00E179.hgt", HgtParser.hgtFilename(0.1, 179.9))
    }

    // ── Skadi path ───────────────────────────────────────────────────

    @Test
    fun `skadiPath returns correct directory and filename`() {
        assertEquals("N47/N47E011.hgt.gz", HgtParser.skadiPath(47.267, 11.393))
    }

    @Test
    fun `skadiPath handles southern hemisphere`() {
        assertEquals("S34/S34W071.hgt.gz", HgtParser.skadiPath(-33.45, -70.67))
    }

    // ── Parsing ──────────────────────────────────────────────────────

    @Test
    fun `parse detects SRTM3 from file size`() {
        val samples = HgtParser.SRTM3_SAMPLES
        val bytes = createTestHgtBytes(samples, 1000)
        val grid = HgtParser.parse(bytes, 47, 11)

        assertEquals(samples, grid.samples)
        assertEquals(47, grid.southwestLatitude)
        assertEquals(11, grid.southwestLongitude)
    }

    @Test
    fun `parse detects SRTM1 from file size`() {
        val samples = HgtParser.SRTM1_SAMPLES
        val bytes = createTestHgtBytes(samples, 500)
        val grid = HgtParser.parse(bytes, 47, 11)

        assertEquals(samples, grid.samples)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `parse rejects invalid file size`() {
        val bytes = ByteArray(1000)
        HgtParser.parse(bytes, 47, 11)
    }

    @Test
    fun `parse reads big-endian elevation values`() {
        val samples = HgtParser.SRTM3_SAMPLES
        val elevation: Short = 1234
        val bytes = createTestHgtBytes(samples, elevation)
        val grid = HgtParser.parse(bytes, 47, 11)

        // All cells should be the same elevation
        assertEquals(elevation, grid.elevationAt(0, 0))
        assertEquals(elevation, grid.elevationAt(samples / 2, samples / 2))
        assertEquals(elevation, grid.elevationAt(samples - 1, samples - 1))
    }

    @Test
    fun `parse identifies void values`() {
        val samples = HgtParser.SRTM3_SAMPLES
        val bytes = createTestHgtBytes(samples, HgtParser.VOID_VALUE)
        val grid = HgtParser.parse(bytes, 47, 11)

        assertNull(grid.elevationAt(0, 0))
    }

    @Test
    fun `elevationAt returns null for out-of-bounds indices`() {
        val samples = HgtParser.SRTM3_SAMPLES
        val bytes = createTestHgtBytes(samples, 500)
        val grid = HgtParser.parse(bytes, 47, 11)

        assertNull(grid.elevationAt(-1, 0))
        assertNull(grid.elevationAt(0, -1))
        assertNull(grid.elevationAt(samples, 0))
        assertNull(grid.elevationAt(0, samples))
    }

    @Test
    fun `parse reads specific cell value correctly`() {
        // Create a small SRTM3 grid where cell (0,0) = 100, cell (0,1) = 200
        val samples = HgtParser.SRTM3_SAMPLES
        val buffer = ByteBuffer.allocate(samples * samples * 2).order(ByteOrder.BIG_ENDIAN)
        for (i in 0 until samples * samples) {
            buffer.putShort(0)
        }
        // Set specific cells
        buffer.putShort(0, 100) // row 0, col 0
        buffer.putShort(2, 200) // row 0, col 1
        buffer.putShort((samples * 2).toInt(), 300) // row 1, col 0

        val grid = HgtParser.parse(buffer.array(), 47, 11)
        assertEquals(100.toShort(), grid.elevationAt(0, 0))
        assertEquals(200.toShort(), grid.elevationAt(0, 1))
        assertEquals(300.toShort(), grid.elevationAt(1, 0))
    }

    // ── Constants ────────────────────────────────────────────────────

    @Test
    fun `SRTM1 file size matches specification`() {
        assertEquals(3601L * 3601L * 2L, HgtParser.SRTM1_FILE_SIZE)
    }

    @Test
    fun `SRTM3 file size matches specification`() {
        assertEquals(1201L * 1201L * 2L, HgtParser.SRTM3_FILE_SIZE)
    }

    @Test
    fun `void value is -32768`() {
        assertEquals((-32768).toShort(), HgtParser.VOID_VALUE)
    }

    // ── Helpers ──────────────────────────────────────────────────────

    /**
     * Creates test HGT bytes with all cells set to the same elevation.
     */
    private fun createTestHgtBytes(samples: Int, elevation: Short): ByteArray {
        val buffer = ByteBuffer.allocate(samples * samples * 2).order(ByteOrder.BIG_ENDIAN)
        for (i in 0 until samples * samples) {
            buffer.putShort(elevation)
        }
        return buffer.array()
    }
}
