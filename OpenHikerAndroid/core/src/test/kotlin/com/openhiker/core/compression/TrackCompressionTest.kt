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

package com.openhiker.core.compression

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [TrackCompression] encode/decode roundtrip.
 *
 * Verifies cross-platform binary format compatibility:
 * 20 bytes per point (Float32 lat, Float32 lon, Float32 alt, Float64 time),
 * little-endian, zlib-compressed.
 */
class TrackCompressionTest {

    @Test
    fun `empty list compresses to empty byte array`() {
        val compressed = TrackCompression.compress(emptyList())
        assertEquals(0, compressed.size)
    }

    @Test
    fun `empty byte array decompresses to empty list`() {
        val decompressed = TrackCompression.decompress(ByteArray(0))
        assertTrue(decompressed.isEmpty())
    }

    @Test
    fun `single point roundtrips correctly`() {
        val original = listOf(
            TrackPoint(47.26543, 11.39354, 574.0, 1700000000.0)
        )

        val compressed = TrackCompression.compress(original)
        assertTrue("Compressed data should not be empty", compressed.isNotEmpty())

        val decompressed = TrackCompression.decompress(compressed)
        assertEquals(1, decompressed.size)

        val point = decompressed[0]
        // Float32 precision: ~5-6 significant digits
        assertEquals(47.265, point.latitude, 0.001)
        assertEquals(11.394, point.longitude, 0.001)
        assertEquals(574.0, point.altitude, 1.0)
        assertEquals(1700000000.0, point.timestamp, 0.001)
    }

    @Test
    fun `multiple points roundtrip correctly`() {
        val original = listOf(
            TrackPoint(47.26543, 11.39354, 574.0, 1700000000.0),
            TrackPoint(47.26601, 11.39412, 580.0, 1700000005.0),
            TrackPoint(47.26698, 11.39501, 595.0, 1700000010.0),
            TrackPoint(47.26750, 11.39550, 602.0, 1700000015.0),
            TrackPoint(47.26810, 11.39610, 610.0, 1700000020.0)
        )

        val compressed = TrackCompression.compress(original)
        val decompressed = TrackCompression.decompress(compressed)

        assertEquals(original.size, decompressed.size)

        for (i in original.indices) {
            assertEquals(original[i].latitude, decompressed[i].latitude, 0.001)
            assertEquals(original[i].longitude, decompressed[i].longitude, 0.001)
            assertEquals(original[i].altitude, decompressed[i].altitude, 1.0)
            assertEquals(original[i].timestamp, decompressed[i].timestamp, 0.001)
        }
    }

    @Test
    fun `compression reduces data size`() {
        // Create a realistic hiking track with 100 points
        val points = (0 until 100).map { i ->
            TrackPoint(
                latitude = 47.26 + i * 0.0001,
                longitude = 11.39 + i * 0.0001,
                altitude = 574.0 + i * 0.5,
                timestamp = 1700000000.0 + i * 5.0
            )
        }

        val compressed = TrackCompression.compress(points)
        val uncompressedSize = points.size * TrackCompression.BYTES_PER_POINT

        assertTrue(
            "Compressed (${compressed.size}) should be smaller than uncompressed ($uncompressedSize)",
            compressed.size < uncompressedSize
        )
    }

    @Test
    fun `decompression handles legacy uncompressed format`() {
        // Create uncompressed binary data directly (legacy format fallback)
        val point = TrackPoint(47.26543, 11.39354, 574.0, 1700000000.0)

        val buffer = java.nio.ByteBuffer.allocate(TrackCompression.BYTES_PER_POINT)
            .order(java.nio.ByteOrder.LITTLE_ENDIAN)
        buffer.putFloat(point.latitude.toFloat())
        buffer.putFloat(point.longitude.toFloat())
        buffer.putFloat(point.altitude.toFloat())
        buffer.putDouble(point.timestamp)

        val rawData = buffer.array()
        val decompressed = TrackCompression.decompress(rawData)

        assertEquals(1, decompressed.size)
        assertEquals(47.265, decompressed[0].latitude, 0.001)
    }

    @Test
    fun `bytes per point is 20`() {
        // This is a cross-platform contract: must be exactly 20 bytes
        assertEquals(20, TrackCompression.BYTES_PER_POINT)
    }

    @Test
    fun `negative coordinates roundtrip correctly`() {
        val original = listOf(
            TrackPoint(-33.8688, 151.2093, 5.0, 1700000000.0), // Sydney
            TrackPoint(-22.9068, -43.1729, 11.0, 1700000005.0) // Rio de Janeiro
        )

        val compressed = TrackCompression.compress(original)
        val decompressed = TrackCompression.decompress(compressed)

        assertEquals(2, decompressed.size)
        assertEquals(-33.869, decompressed[0].latitude, 0.001)
        assertEquals(151.209, decompressed[0].longitude, 0.001)
        assertEquals(-22.907, decompressed[1].latitude, 0.001)
        assertEquals(-43.173, decompressed[1].longitude, 0.001)
    }
}
