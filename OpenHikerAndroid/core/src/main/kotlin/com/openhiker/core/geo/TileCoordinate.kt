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
import kotlinx.serialization.Serializable
import kotlin.math.PI
import kotlin.math.atan
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.sinh
import kotlin.math.tan

/**
 * A Web Mercator tile coordinate (x, y, z) following the slippy map convention.
 *
 * In the slippy map (XYZ) convention, y=0 is at the top (north pole).
 * MBTiles databases use the TMS convention where y=0 is at the bottom.
 * Use [tmsY] to convert between conventions.
 *
 * The tile grid at zoom level z has 2^z tiles per axis, so valid ranges are:
 *   x: [0, 2^z)
 *   y: [0, 2^z)
 *   z: [0, 22]
 *
 * @property x Tile column (0 = leftmost, increasing eastward).
 * @property y Tile row in slippy map convention (0 = top/north).
 * @property z Zoom level (0 = whole world in one tile, 22 = maximum detail).
 */
@Serializable
data class TileCoordinate(
    val x: Int,
    val y: Int,
    val z: Int
) {
    /** Number of tiles per axis at this zoom level: 2^z. */
    val tilesPerAxis: Int get() = 1 shl z

    /**
     * TMS Y-coordinate (used by MBTiles databases).
     *
     * TMS convention has y=0 at the bottom (south pole), which is the
     * inverse of the slippy map convention. The conversion formula is:
     *   tmsY = (2^z - 1) - y
     *
     * This is critical for correct tile lookup in MBTiles files.
     * Both iOS and Android implementations must use this same formula.
     */
    val tmsY: Int get() = (tilesPerAxis - 1) - y

    /**
     * Whether this tile coordinate has valid indices for its zoom level.
     *
     * @return True if x and y are in [0, 2^z) and z is in [0, 22].
     */
    val isValid: Boolean
        get() = z in MIN_ZOOM..MAX_ZOOM &&
            x in 0 until tilesPerAxis &&
            y in 0 until tilesPerAxis

    /**
     * Geographic coordinate of the tile's north-west (top-left) corner.
     */
    val northWest: Coordinate
        get() = tileToLatLon(x, y, z)

    /**
     * Geographic coordinate of the tile's south-east (bottom-right) corner.
     */
    val southEast: Coordinate
        get() = tileToLatLon(x + 1, y + 1, z)

    /**
     * Geographic coordinate of the tile's centre point.
     */
    val center: Coordinate
        get() {
            val nw = northWest
            val se = southEast
            return Coordinate(
                latitude = (nw.latitude + se.latitude) / 2.0,
                longitude = (nw.longitude + se.longitude) / 2.0
            )
        }

    /**
     * Parent tile at the next lower zoom level (zoomed out one step).
     *
     * @return The parent tile, or null if already at zoom level 0.
     */
    val parent: TileCoordinate?
        get() = if (z > 0) TileCoordinate(x / 2, y / 2, z - 1) else null

    /**
     * The four child tiles at the next higher zoom level (zoomed in one step).
     *
     * @return List of 4 child tiles, or empty if at maximum zoom.
     */
    val children: List<TileCoordinate>
        get() = if (z >= MAX_ZOOM) emptyList()
        else listOf(
            TileCoordinate(x * 2, y * 2, z + 1),
            TileCoordinate(x * 2 + 1, y * 2, z + 1),
            TileCoordinate(x * 2, y * 2 + 1, z + 1),
            TileCoordinate(x * 2 + 1, y * 2 + 1, z + 1)
        )

    /**
     * The 8 neighbouring tiles (N, NE, E, SE, S, SW, W, NW).
     *
     * Filters out tiles that fall outside the valid grid range.
     *
     * @return List of valid neighbouring tile coordinates (up to 8).
     */
    val neighbors: List<TileCoordinate>
        get() {
            val offsets = listOf(
                -1 to -1, 0 to -1, 1 to -1,
                -1 to 0, /*self*/ 1 to 0,
                -1 to 1, 0 to 1, 1 to 1
            )
            return offsets.mapNotNull { (dx, dy) ->
                val nx = x + dx
                val ny = y + dy
                val tile = TileCoordinate(nx, ny, z)
                if (tile.isValid) tile else null
            }
        }

    /**
     * Approximate metres per pixel at this tile's latitude.
     *
     * Accounts for Mercator projection compression at higher latitudes.
     * Used for scale bar display and distance calculations on the map.
     *
     * @return Ground resolution in metres per pixel.
     */
    val metersPerPixel: Double
        get() {
            val latRadians = Math.toRadians(center.latitude)
            return EARTH_CIRCUMFERENCE_METRES * cos(latRadians) /
                (tilesPerAxis.toDouble() * TILE_SIZE_PIXELS)
        }

    companion object {
        /** Standard tile size in pixels. */
        const val TILE_SIZE_PIXELS = 256

        /** Minimum valid zoom level. */
        const val MIN_ZOOM = 0

        /** Maximum valid zoom level. */
        const val MAX_ZOOM = 22

        /** Earth's equatorial circumference in metres. */
        private const val EARTH_CIRCUMFERENCE_METRES = 40_075_016.686

        /**
         * Converts a geographic coordinate to a tile coordinate at the given zoom level.
         *
         * Uses the standard Web Mercator projection formula:
         *   x = floor((lon + 180) / 360 * 2^z)
         *   y = floor((1 - ln(tan(lat) + sec(lat)) / pi) / 2 * 2^z)
         *
         * @param latitude WGS84 latitude in degrees (-85.051 to +85.051).
         * @param longitude WGS84 longitude in degrees (-180 to +180).
         * @param zoom Zoom level (0 to 22).
         * @return The tile coordinate containing the given lat/lon.
         */
        fun fromLatLon(latitude: Double, longitude: Double, zoom: Int): TileCoordinate {
            val n = 1 shl zoom
            val latRad = Math.toRadians(latitude)

            val x = floor((longitude + 180.0) / 360.0 * n).toInt()
                .coerceIn(0, n - 1)
            val y = floor((1.0 - ln(tan(latRad) + 1.0 / cos(latRad)) / PI) / 2.0 * n).toInt()
                .coerceIn(0, n - 1)

            return TileCoordinate(x, y, zoom)
        }

        /**
         * Converts tile grid indices back to a geographic coordinate.
         *
         * Returns the coordinate at the top-left corner of the tile cell
         * at (tileX, tileY). Passing (x+1, y+1) gives the bottom-right corner.
         *
         * @param tileX Tile column index (may be equal to 2^z for the right edge).
         * @param tileY Tile row index (may be equal to 2^z for the bottom edge).
         * @param zoom Zoom level.
         * @return Geographic coordinate at the specified tile corner.
         */
        fun tileToLatLon(tileX: Int, tileY: Int, zoom: Int): Coordinate {
            val n = (1 shl zoom).toDouble()
            val lon = tileX / n * 360.0 - 180.0
            val latRad = atan(sinh(PI * (1.0 - 2.0 * tileY / n)))
            val lat = Math.toDegrees(latRad)
            return Coordinate(lat, lon)
        }
    }
}
