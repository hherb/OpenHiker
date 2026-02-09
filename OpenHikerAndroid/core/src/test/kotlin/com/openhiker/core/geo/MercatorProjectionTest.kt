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

/**
 * Unit tests for [MercatorProjection] coordinate-to-pixel conversions.
 *
 * Web Mercator (EPSG:3857) maps the world onto a square grid where:
 * - At zoom 0 the entire world fits in 256x256 pixels
 * - The origin (0,0) in lat/lng maps to the centre of the pixel grid
 * - x increases eastward, y increases southward
 *
 * Known reference values are derived from the standard Web Mercator
 * formulae used by OpenStreetMap and Google Maps tile servers.
 */
class MercatorProjectionTest {

    /** Tile size constant used in expected value calculations. */
    private val tileSize = 256.0

    // ── coordinateToPixel for known coordinates ───────────────────

    @Test
    fun `equator origin maps to centre of world at zoom 0`() {
        val (px, py) = MercatorProjection.coordinateToPixel(Coordinate(0.0, 0.0), 0)
        // At zoom 0: mapSize = 256, centre = (128, 128)
        assertEquals("Pixel X for (0,0) at zoom 0", 128.0, px, 0.01)
        assertEquals("Pixel Y for (0,0) at zoom 0", 128.0, py, 0.01)
    }

    @Test
    fun `longitude -180 maps to left edge at zoom 0`() {
        val (px, _) = MercatorProjection.coordinateToPixel(Coordinate(0.0, -180.0), 0)
        assertEquals("Pixel X for lon=-180 should be 0", 0.0, px, 0.01)
    }

    @Test
    fun `longitude 180 maps to right edge at zoom 0`() {
        val (px, _) = MercatorProjection.coordinateToPixel(Coordinate(0.0, 180.0), 0)
        assertEquals("Pixel X for lon=180 should be 256", 256.0, px, 0.01)
    }

    @Test
    fun `northern latitude maps to smaller Y (higher on screen)`() {
        val equator = MercatorProjection.coordinateToPixel(Coordinate(0.0, 0.0), 10)
        val north = MercatorProjection.coordinateToPixel(Coordinate(45.0, 0.0), 10)
        assertTrue(
            "Northern latitude should have smaller Y than equator",
            north.second < equator.second
        )
    }

    @Test
    fun `southern latitude maps to larger Y (lower on screen)`() {
        val equator = MercatorProjection.coordinateToPixel(Coordinate(0.0, 0.0), 10)
        val south = MercatorProjection.coordinateToPixel(Coordinate(-45.0, 0.0), 10)
        assertTrue(
            "Southern latitude should have larger Y than equator",
            south.second > equator.second
        )
    }

    // ── pixelToCoordinate roundtrip ───────────────────────────────

    @Test
    fun `pixelToCoordinate roundtrip at equator origin zoom 10`() {
        val original = Coordinate(0.0, 0.0)
        val zoom = 10
        val (px, py) = MercatorProjection.coordinateToPixel(original, zoom)
        val recovered = MercatorProjection.pixelToCoordinate(px, py, zoom)

        assertEquals("Latitude roundtrip", original.latitude, recovered.latitude, 0.0001)
        assertEquals("Longitude roundtrip", original.longitude, recovered.longitude, 0.0001)
    }

    @Test
    fun `pixelToCoordinate roundtrip at Innsbruck zoom 15`() {
        val innsbruck = Coordinate(47.2654, 11.3928)
        val zoom = 15
        val (px, py) = MercatorProjection.coordinateToPixel(innsbruck, zoom)
        val recovered = MercatorProjection.pixelToCoordinate(px, py, zoom)

        assertEquals("Latitude roundtrip for Innsbruck", innsbruck.latitude, recovered.latitude, 0.0001)
        assertEquals("Longitude roundtrip for Innsbruck", innsbruck.longitude, recovered.longitude, 0.0001)
    }

    @Test
    fun `pixelToCoordinate roundtrip at southern hemisphere zoom 12`() {
        val sydney = Coordinate(-33.8688, 151.2093)
        val zoom = 12
        val (px, py) = MercatorProjection.coordinateToPixel(sydney, zoom)
        val recovered = MercatorProjection.pixelToCoordinate(px, py, zoom)

        assertEquals("Latitude roundtrip for Sydney", sydney.latitude, recovered.latitude, 0.0001)
        assertEquals("Longitude roundtrip for Sydney", sydney.longitude, recovered.longitude, 0.0001)
    }

    // ── Tile corner coordinates via pixelToCoordinate ─────────────

    @Test
    fun `tile 0,0 at zoom 0 corresponds to top-left of world map`() {
        // Tile (0,0) at zoom 0 starts at pixel (0,0): top-left corner of the world
        val topLeft = MercatorProjection.pixelToCoordinate(0.0, 0.0, 0)
        // Top-left should be approximately (85.05, -180)
        assertEquals("Top-left latitude should be ~85.05", 85.05, topLeft.latitude, 0.1)
        assertEquals("Top-left longitude should be -180", -180.0, topLeft.longitude, 0.01)
    }

    @Test
    fun `tile 1,0 at zoom 1 corresponds to top-right quadrant`() {
        // At zoom 1: 2x2 tiles, each 256px. Tile (1,0) starts at pixel (256, 0).
        val topOfTile = MercatorProjection.pixelToCoordinate(256.0, 0.0, 1)
        // Pixel (256,0) at zoom 1 is the top of the eastern hemisphere
        assertEquals("Longitude at tile (1,0) zoom 1 should be 0", 0.0, topOfTile.longitude, 0.01)
        assertEquals("Latitude at top row should be ~85.05", 85.05, topOfTile.latitude, 0.1)
    }

    @Test
    fun `tile 0,1 at zoom 1 corresponds to bottom-left quadrant`() {
        // At zoom 1: tile (0,1) starts at pixel (0, 256) — southern hemisphere
        val bottomLeft = MercatorProjection.pixelToCoordinate(0.0, 256.0, 1)
        assertEquals("Longitude at tile (0,1) zoom 1 should be -180", -180.0, bottomLeft.longitude, 0.01)
        assertEquals("Latitude at tile (0,1) zoom 1 should be ~0", 0.0, bottomLeft.latitude, 0.1)
    }

    // ── Zoom level affects pixel coordinates ──────────────────────

    @Test
    fun `higher zoom level doubles pixel coordinates`() {
        val coord = Coordinate(47.2654, 11.3928)
        val (px10, py10) = MercatorProjection.coordinateToPixel(coord, 10)
        val (px11, py11) = MercatorProjection.coordinateToPixel(coord, 11)

        assertEquals("Pixel X at zoom 11 should be 2x zoom 10", px10 * 2.0, px11, 0.01)
        assertEquals("Pixel Y at zoom 11 should be 2x zoom 10", py10 * 2.0, py11, 0.01)
    }

    @Test
    fun `zoom 0 gives pixels in 0 to 256 range`() {
        val coord = Coordinate(30.0, 60.0)
        val (px, py) = MercatorProjection.coordinateToPixel(coord, 0)

        assertTrue("Pixel X at zoom 0 should be in [0, 256]", px in 0.0..256.0)
        assertTrue("Pixel Y at zoom 0 should be in [0, 256]", py in 0.0..256.0)
    }

    @Test
    fun `zoom 1 gives pixels in 0 to 512 range`() {
        val coord = Coordinate(30.0, 60.0)
        val (px, py) = MercatorProjection.coordinateToPixel(coord, 1)

        assertTrue("Pixel X at zoom 1 should be in [0, 512]", px in 0.0..512.0)
        assertTrue("Pixel Y at zoom 1 should be in [0, 512]", py in 0.0..512.0)
    }

    // ── metersPerPixel ────────────────────────────────────────────

    @Test
    fun `metersPerPixel at equator zoom 0 is approximately 156543`() {
        // Standard value: C / 256 ≈ 156543 m/px at zoom 0 equator
        val mpp = MercatorProjection.metersPerPixel(0.0, 0)
        assertEquals("Metres per pixel at equator zoom 0", 156543.0, mpp, 500.0)
    }

    @Test
    fun `metersPerPixel halves with each zoom level`() {
        val mpp0 = MercatorProjection.metersPerPixel(0.0, 0)
        val mpp1 = MercatorProjection.metersPerPixel(0.0, 1)
        assertEquals("Metres per pixel should halve at zoom+1", mpp0 / 2.0, mpp1, 1.0)
    }

    @Test
    fun `metersPerPixel decreases at higher latitudes`() {
        val mppEquator = MercatorProjection.metersPerPixel(0.0, 10)
        val mpp60 = MercatorProjection.metersPerPixel(60.0, 10)
        assertTrue(
            "Metres per pixel should be smaller at 60 degrees latitude than at equator",
            mpp60 < mppEquator
        )
    }
}
