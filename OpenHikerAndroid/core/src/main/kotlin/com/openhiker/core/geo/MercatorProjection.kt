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
import kotlin.math.PI
import kotlin.math.atan
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.tan

/**
 * Pure functions for converting between geographic coordinates (WGS84)
 * and Web Mercator pixel coordinates at a given zoom level.
 *
 * Web Mercator (EPSG:3857) is the standard projection used by all
 * major web tile providers. The pixel coordinate system has origin
 * at the top-left corner of the world map, with x increasing east
 * and y increasing south.
 *
 * Total pixel dimensions at zoom level z: (256 * 2^z) x (256 * 2^z)
 */
object MercatorProjection {

    /** Standard tile size in pixels. */
    private const val TILE_SIZE = 256.0

    /**
     * Converts a geographic coordinate to absolute pixel coordinates
     * at the specified zoom level.
     *
     * @param coordinate WGS84 coordinate.
     * @param zoom Zoom level (0–22).
     * @return Pair of (pixelX, pixelY) in the global pixel grid.
     */
    fun coordinateToPixel(coordinate: Coordinate, zoom: Int): Pair<Double, Double> {
        val mapSize = TILE_SIZE * (1 shl zoom)
        val pixelX = (coordinate.longitude + 180.0) / 360.0 * mapSize
        val latRad = Math.toRadians(coordinate.latitude)
        val pixelY = (1.0 - ln(tan(latRad) + 1.0 / kotlin.math.cos(latRad)) / PI) / 2.0 * mapSize
        return pixelX to pixelY
    }

    /**
     * Converts absolute pixel coordinates back to a geographic coordinate.
     *
     * @param pixelX X pixel position in the global pixel grid.
     * @param pixelY Y pixel position in the global pixel grid.
     * @param zoom Zoom level (0–22).
     * @return WGS84 coordinate at the given pixel position.
     */
    fun pixelToCoordinate(pixelX: Double, pixelY: Double, zoom: Int): Coordinate {
        val mapSize = TILE_SIZE * (1 shl zoom)
        val longitude = pixelX / mapSize * 360.0 - 180.0
        val n = PI - 2.0 * PI * pixelY / mapSize
        val latitude = Math.toDegrees(atan(0.5 * (exp(n) - exp(-n))))
        return Coordinate(latitude, longitude)
    }

    /**
     * Calculates the ground resolution in metres per pixel at a given latitude and zoom.
     *
     * @param latitude WGS84 latitude in degrees.
     * @param zoom Zoom level (0–22).
     * @return Ground resolution in metres per pixel.
     */
    fun metersPerPixel(latitude: Double, zoom: Int): Double {
        val latRad = Math.toRadians(latitude)
        return Haversine.EARTH_RADIUS_METRES * 2.0 * PI * kotlin.math.cos(latRad) /
            (TILE_SIZE * (1 shl zoom))
    }
}
