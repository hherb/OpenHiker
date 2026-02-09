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

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.DataFormatException
import java.util.zip.Deflater
import java.util.zip.Inflater

/**
 * A single GPS track point with position, altitude, and timestamp.
 *
 * @property latitude WGS84 latitude in degrees.
 * @property longitude WGS84 longitude in degrees.
 * @property altitude Altitude in metres above sea level.
 * @property timestamp Seconds since a reference date (platform-specific epoch).
 */
data class TrackPoint(
    val latitude: Double,
    val longitude: Double,
    val altitude: Double,
    val timestamp: Double
)

/**
 * Compresses and decompresses GPS track data in a binary format.
 *
 * The binary format is cross-platform compatible with the iOS TrackCompression
 * implementation — both platforms produce byte-identical output for the same
 * input data. This enables MBTiles region files with embedded tracks to be
 * transferred between iOS and Android devices via cloud sync.
 *
 * Binary format per point (20 bytes, little-endian):
 *   Offset 0:  Float32 — latitude
 *   Offset 4:  Float32 — longitude
 *   Offset 8:  Float32 — altitude (metres)
 *   Offset 12: Float64 — timestamp (seconds since reference date)
 *
 * The raw binary data is then zlib-compressed (DEFLATE algorithm).
 * Decompression includes a legacy fallback: if zlib decompression fails,
 * the data is treated as uncompressed (for backwards compatibility).
 */
object TrackCompression {

    /** Size in bytes of one track point record. */
    const val BYTES_PER_POINT = 20

    /** Extra bytes added to the compression output buffer as safety margin. */
    private const val COMPRESSION_BUFFER_MARGIN = 64

    /** Multiplier for estimating decompression buffer size from compressed size. */
    private const val DECOMPRESSION_BUFFER_MULTIPLIER = 10

    /**
     * Encodes a list of track points to compressed binary format.
     *
     * Packs each point into 20 bytes (little-endian), then compresses
     * the entire buffer with zlib DEFLATE. Returns an empty byte array
     * for empty input (no compression applied to zero-length data).
     *
     * @param points List of GPS track points to encode.
     * @return Zlib-compressed binary data, or empty byte array if input is empty.
     */
    fun compress(points: List<TrackPoint>): ByteArray {
        if (points.isEmpty()) return ByteArray(0)

        val buffer = ByteBuffer.allocate(points.size * BYTES_PER_POINT)
            .order(ByteOrder.LITTLE_ENDIAN)

        for (point in points) {
            buffer.putFloat(point.latitude.toFloat())
            buffer.putFloat(point.longitude.toFloat())
            buffer.putFloat(point.altitude.toFloat())
            buffer.putDouble(point.timestamp)
        }

        val rawData = buffer.array()
        return zlibCompress(rawData)
    }

    /**
     * Decompresses binary data back to a list of track points.
     *
     * First attempts zlib decompression. If that fails (DataFormatException),
     * falls back to parsing the data as uncompressed binary (legacy format).
     * Returns an empty list for empty input.
     *
     * @param data Compressed (or legacy uncompressed) binary track data.
     * @return List of decoded GPS track points.
     */
    fun decompress(data: ByteArray): List<TrackPoint> {
        if (data.isEmpty()) return emptyList()

        val rawData = try {
            zlibDecompress(data)
        } catch (_: DataFormatException) {
            // Fallback: treat as uncompressed legacy format
            data
        }

        return parseRawPoints(rawData)
    }

    /**
     * Parses raw (uncompressed) binary data into track points.
     *
     * Reads 20-byte records from the buffer until fewer than 20 bytes remain.
     * Any trailing partial record is silently ignored.
     *
     * @param data Raw binary data (little-endian, 20 bytes per point).
     * @return List of parsed track points.
     */
    private fun parseRawPoints(data: ByteArray): List<TrackPoint> {
        val buffer = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
        val points = mutableListOf<TrackPoint>()

        while (buffer.remaining() >= BYTES_PER_POINT) {
            points.add(
                TrackPoint(
                    latitude = buffer.float.toDouble(),
                    longitude = buffer.float.toDouble(),
                    altitude = buffer.float.toDouble(),
                    timestamp = buffer.double
                )
            )
        }

        return points
    }

    /**
     * Compresses data using zlib DEFLATE.
     *
     * @param input Raw data to compress.
     * @return Compressed data.
     */
    private fun zlibCompress(input: ByteArray): ByteArray {
        val deflater = Deflater()
        try {
            deflater.setInput(input)
            deflater.finish()
            val output = ByteArray(input.size + COMPRESSION_BUFFER_MARGIN)
            val compressedSize = deflater.deflate(output)
            return output.copyOf(compressedSize)
        } finally {
            deflater.end()
        }
    }

    /**
     * Decompresses zlib-compressed data.
     *
     * @param input Compressed data.
     * @return Decompressed data.
     * @throws DataFormatException If the data is not valid zlib format.
     */
    private fun zlibDecompress(input: ByteArray): ByteArray {
        val inflater = Inflater()
        try {
            inflater.setInput(input)
            val output = ByteArray(input.size * DECOMPRESSION_BUFFER_MULTIPLIER)
            val decompressedSize = inflater.inflate(output)
            return output.copyOf(decompressedSize)
        } finally {
            inflater.end()
        }
    }
}
