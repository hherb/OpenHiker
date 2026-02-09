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

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Parser for NASA SRTM HGT binary elevation data files.
 *
 * HGT files contain a regular grid of 16-bit signed big-endian integers
 * representing elevation in metres above sea level. Each file covers
 * exactly 1 degree of latitude by 1 degree of longitude.
 *
 * Two resolutions are supported:
 * - SRTM1 (1 arc-second): 3601 x 3601 samples, file size 25,934,402 bytes
 * - SRTM3 (3 arc-second): 1201 x 1201 samples, file size 2,884,802 bytes
 *
 * The grid origin is the **south-west** corner of the tile, with rows
 * ordered from north to south (row 0 = north edge).
 *
 * Pure functions only — no file I/O, no Android dependencies.
 *
 * @see <a href="https://www.usgs.gov/centers/eros/science/usgs-eros-archive-digital-elevation-shuttle-radar-topography-mission-srtm-1">USGS SRTM documentation</a>
 */
object HgtParser {

    /** Sentinel value indicating no elevation data (void). */
    const val VOID_VALUE: Short = -32768

    /** Number of samples per row/column in SRTM1 (1 arc-second) data. */
    const val SRTM1_SAMPLES = 3601

    /** Number of samples per row/column in SRTM3 (3 arc-second) data. */
    const val SRTM3_SAMPLES = 1201

    /** Expected file size in bytes for SRTM1 data. */
    const val SRTM1_FILE_SIZE = SRTM1_SAMPLES * SRTM1_SAMPLES * 2L

    /** Expected file size in bytes for SRTM3 data. */
    const val SRTM3_FILE_SIZE = SRTM3_SAMPLES * SRTM3_SAMPLES * 2L

    /**
     * Parses raw HGT bytes into an [HgtGrid].
     *
     * Automatically detects SRTM1 vs SRTM3 resolution from the byte array
     * size. The bytes must be the raw (uncompressed) HGT file content.
     *
     * @param bytes Raw HGT file content (big-endian 16-bit signed integers).
     * @param southwestLatitude Latitude of the tile's south-west corner (integer degrees).
     * @param southwestLongitude Longitude of the tile's south-west corner (integer degrees).
     * @return An [HgtGrid] containing the parsed elevation samples.
     * @throws IllegalArgumentException if the byte array size does not match
     *         either SRTM1 or SRTM3 expected sizes.
     */
    fun parse(
        bytes: ByteArray,
        southwestLatitude: Int,
        southwestLongitude: Int
    ): HgtGrid {
        val samples = when (bytes.size.toLong()) {
            SRTM1_FILE_SIZE -> SRTM1_SAMPLES
            SRTM3_FILE_SIZE -> SRTM3_SAMPLES
            else -> throw IllegalArgumentException(
                "Invalid HGT file size: ${bytes.size} bytes. " +
                    "Expected $SRTM1_FILE_SIZE (SRTM1) or $SRTM3_FILE_SIZE (SRTM3)."
            )
        }

        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        val elevations = ShortArray(samples * samples)
        buffer.asShortBuffer().get(elevations)

        return HgtGrid(
            elevations = elevations,
            samples = samples,
            southwestLatitude = southwestLatitude,
            southwestLongitude = southwestLongitude
        )
    }

    /**
     * Derives the HGT filename for a given coordinate.
     *
     * The filename encodes the south-west corner of the 1-degree tile.
     * For example, coordinate (47.2, 11.3) maps to "N47E011.hgt".
     *
     * @param latitude Latitude in degrees.
     * @param longitude Longitude in degrees.
     * @return The HGT filename (e.g., "N47E011.hgt").
     */
    fun hgtFilename(latitude: Double, longitude: Double): String {
        val lat = kotlin.math.floor(latitude).toInt()
        val lon = kotlin.math.floor(longitude).toInt()

        val latPrefix = if (lat >= 0) "N" else "S"
        val lonPrefix = if (lon >= 0) "E" else "W"

        val latAbs = kotlin.math.abs(lat)
        val lonAbs = kotlin.math.abs(lon)

        return "%s%02d%s%03d.hgt".format(latPrefix, latAbs, lonPrefix, lonAbs)
    }

    /**
     * Derives the Skadi download path for a given coordinate.
     *
     * The path follows the Tilezen Skadi directory structure:
     * `{N|S}{lat}/{N|S}{lat}{E|W}{lon}.hgt.gz`
     *
     * @param latitude Latitude in degrees.
     * @param longitude Longitude in degrees.
     * @return The Skadi path (e.g., "N47/N47E011.hgt.gz").
     */
    fun skadiPath(latitude: Double, longitude: Double): String {
        val lat = kotlin.math.floor(latitude).toInt()
        val lon = kotlin.math.floor(longitude).toInt()

        val latPrefix = if (lat >= 0) "N" else "S"
        val lonPrefix = if (lon >= 0) "E" else "W"

        val latAbs = kotlin.math.abs(lat)
        val lonAbs = kotlin.math.abs(lon)

        val dirName = "%s%02d".format(latPrefix, latAbs)
        val fileName = "%s%02d%s%03d.hgt.gz".format(latPrefix, latAbs, lonPrefix, lonAbs)

        return "$dirName/$fileName"
    }
}

/**
 * Parsed HGT elevation grid.
 *
 * Contains the 2D array of elevation samples as a flat [ShortArray],
 * plus the metadata needed to map geographic coordinates to grid cells.
 *
 * Row 0 is the **north** edge; row (samples - 1) is the **south** edge.
 * Column 0 is the **west** edge; column (samples - 1) is the **east** edge.
 *
 * @property elevations Flat array of elevation values in metres (row-major, north-to-south).
 * @property samples Number of samples per row and column (3601 for SRTM1, 1201 for SRTM3).
 * @property southwestLatitude Integer latitude of the tile's south-west corner.
 * @property southwestLongitude Integer longitude of the tile's south-west corner.
 */
data class HgtGrid(
    val elevations: ShortArray,
    val samples: Int,
    val southwestLatitude: Int,
    val southwestLongitude: Int
) {
    /**
     * Retrieves the elevation at a specific grid cell.
     *
     * @param row Row index (0 = north edge).
     * @param col Column index (0 = west edge).
     * @return Elevation in metres, or null if the cell is void.
     */
    fun elevationAt(row: Int, col: Int): Short? {
        if (row < 0 || row >= samples || col < 0 || col >= samples) return null
        val value = elevations[row * samples + col]
        return if (value == HgtParser.VOID_VALUE) null else value
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is HgtGrid) return false
        return samples == other.samples &&
            southwestLatitude == other.southwestLatitude &&
            southwestLongitude == other.southwestLongitude &&
            elevations.contentEquals(other.elevations)
    }

    override fun hashCode(): Int {
        var result = elevations.contentHashCode()
        result = 31 * result + samples
        result = 31 * result + southwestLatitude
        result = 31 * result + southwestLongitude
        return result
    }
}
