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

import kotlinx.serialization.Serializable

/**
 * A rectangular range of tiles at a single zoom level.
 *
 * Defines the bounding tile indices for a geographic region at a
 * given zoom level. Used to enumerate all tiles needed for a download
 * and to check whether a tile falls within a downloaded region.
 *
 * @property minX Leftmost tile column (inclusive).
 * @property maxX Rightmost tile column (inclusive).
 * @property minY Topmost tile row in slippy map convention (inclusive).
 * @property maxY Bottommost tile row in slippy map convention (inclusive).
 * @property zoom Zoom level for this tile range.
 */
@Serializable
data class TileRange(
    val minX: Int,
    val maxX: Int,
    val minY: Int,
    val maxY: Int,
    val zoom: Int
) {
    /**
     * Total number of tiles in this range.
     *
     * Calculated as (width + 1) * (height + 1) since both min and max are inclusive.
     */
    val tileCount: Int
        get() = (maxX - minX + 1) * (maxY - minY + 1)

    /**
     * Enumerates all tile coordinates in this range.
     *
     * Iterates row by row (y outer, x inner) over all tiles within
     * the bounding indices, producing a flat list.
     *
     * @return List of all [TileCoordinate] values in this range.
     */
    fun allTiles(): List<TileCoordinate> {
        val tiles = mutableListOf<TileCoordinate>()
        for (y in minY..maxY) {
            for (x in minX..maxX) {
                tiles.add(TileCoordinate(x, y, zoom))
            }
        }
        return tiles
    }

    /**
     * Checks whether a tile coordinate is within this range.
     *
     * @param tile The tile coordinate to check.
     * @return True if the tile's x, y, and zoom match this range.
     */
    fun contains(tile: TileCoordinate): Boolean =
        tile.z == zoom &&
            tile.x in minX..maxX &&
            tile.y in minY..maxY

    companion object {
        /**
         * Creates a tile range from a geographic bounding box at the given zoom level.
         *
         * Converts the north-west and south-east corners of the bounding box
         * to tile coordinates, then uses those as the min/max bounds.
         *
         * @param boundingBox The geographic area to cover.
         * @param zoom The zoom level for tile calculation.
         * @return A [TileRange] covering the entire bounding box at the given zoom.
         */
        fun fromBoundingBox(boundingBox: BoundingBox, zoom: Int): TileRange {
            val topLeft = TileCoordinate.fromLatLon(boundingBox.north, boundingBox.west, zoom)
            val bottomRight = TileCoordinate.fromLatLon(boundingBox.south, boundingBox.east, zoom)

            return TileRange(
                minX = topLeft.x,
                maxX = bottomRight.x,
                minY = topLeft.y,
                maxY = bottomRight.y,
                zoom = zoom
            )
        }

        /**
         * Calculates the total tile count for a bounding box across multiple zoom levels.
         *
         * Useful for estimating download size before starting a region download.
         *
         * @param boundingBox The geographic area to cover.
         * @param zoomLevels The range of zoom levels to include.
         * @return Total number of tiles across all specified zoom levels.
         */
        fun estimateTileCount(boundingBox: BoundingBox, zoomLevels: IntRange): Int {
            return zoomLevels.sumOf { zoom ->
                fromBoundingBox(boundingBox, zoom).tileCount
            }
        }
    }
}
