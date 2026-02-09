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
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Pure functions for geographic distance and bearing calculations
 * using the Haversine formula on a spherical Earth model.
 *
 * The Haversine formula provides accuracy within ~0.3% for distances
 * on Earth, which is more than sufficient for hiking navigation.
 * All functions are stateless and thread-safe.
 */
object Haversine {

    /** Mean Earth radius in metres (WGS84 mean radius). */
    const val EARTH_RADIUS_METRES = 6_371_000.0

    /**
     * Calculates the great-circle distance between two coordinates.
     *
     * Uses the Haversine formula which is numerically stable for both
     * small and large distances. Returns the shortest path distance
     * along the surface of a sphere.
     *
     * @param from Starting coordinate.
     * @param to Ending coordinate.
     * @return Distance in metres.
     */
    fun distance(from: Coordinate, to: Coordinate): Double =
        distance(from.latitude, from.longitude, to.latitude, to.longitude)

    /**
     * Calculates the great-circle distance between two points given as raw degrees.
     *
     * This overload avoids Coordinate allocation in tight loops (e.g.,
     * summing distances along a GPS track with thousands of points).
     *
     * @param lat1 Latitude of the first point in degrees.
     * @param lon1 Longitude of the first point in degrees.
     * @param lat2 Latitude of the second point in degrees.
     * @param lon2 Longitude of the second point in degrees.
     * @return Distance in metres.
     */
    fun distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val lat1Rad = Math.toRadians(lat1)
        val lat2Rad = Math.toRadians(lat2)

        val a = sin(dLat / 2.0) * sin(dLat / 2.0) +
            cos(lat1Rad) * cos(lat2Rad) *
            sin(dLon / 2.0) * sin(dLon / 2.0)
        val c = 2.0 * asin(sqrt(a))

        return EARTH_RADIUS_METRES * c
    }

    /**
     * Calculates the initial bearing (forward azimuth) from one coordinate to another.
     *
     * Uses the spherical law of cosines to compute the bearing. The result
     * is normalised to [0, 360) degrees, where 0 = north, 90 = east.
     *
     * @param from Starting coordinate.
     * @param to Destination coordinate.
     * @return Initial bearing in degrees [0, 360).
     */
    fun bearing(from: Coordinate, to: Coordinate): Double {
        val lat1 = Math.toRadians(from.latitude)
        val lat2 = Math.toRadians(to.latitude)
        val dLon = Math.toRadians(to.longitude - from.longitude)

        val y = sin(dLon) * cos(lat2)
        val x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)

        val bearingRad = atan2(y, x)
        return (Math.toDegrees(bearingRad) + 360.0) % 360.0
    }

    /**
     * Calculates a destination coordinate given a starting point, bearing, and distance.
     *
     * Useful for computing waypoint positions offset from a known location.
     *
     * @param from Starting coordinate.
     * @param bearingDegrees Initial bearing in degrees [0, 360).
     * @param distanceMetres Distance to travel in metres.
     * @return The destination coordinate.
     */
    fun destination(from: Coordinate, bearingDegrees: Double, distanceMetres: Double): Coordinate {
        val lat1 = Math.toRadians(from.latitude)
        val lon1 = Math.toRadians(from.longitude)
        val brng = Math.toRadians(bearingDegrees)
        val d = distanceMetres / EARTH_RADIUS_METRES

        val lat2 = asin(
            sin(lat1) * cos(d) +
                cos(lat1) * sin(d) * cos(brng)
        )
        val lon2 = lon1 + atan2(
            sin(brng) * sin(d) * cos(lat1),
            cos(d) - sin(lat1) * sin(lat2)
        )

        return Coordinate(
            latitude = Math.toDegrees(lat2),
            longitude = Math.toDegrees(lon2)
        )
    }

    /**
     * Calculates the total distance along a polyline of coordinates.
     *
     * Sums the Haversine distance between consecutive points.
     * Returns 0 for lists with fewer than 2 points.
     *
     * @param coordinates Ordered list of coordinates forming the polyline.
     * @return Total distance in metres.
     */
    fun polylineDistance(coordinates: List<Coordinate>): Double {
        if (coordinates.size < 2) return 0.0
        var total = 0.0
        for (i in 0 until coordinates.size - 1) {
            total += distance(coordinates[i], coordinates[i + 1])
        }
        return total
    }

    /**
     * Normalises a bearing delta to the range [-180, +180] degrees.
     *
     * Used for turn direction classification: negative = left, positive = right.
     *
     * @param delta Raw bearing difference in degrees.
     * @return Normalised delta in [-180, +180].
     */
    fun normalizeBearingDelta(delta: Double): Double {
        var d = delta % 360.0
        if (d > 180.0) d -= 360.0
        if (d < -180.0) d += 360.0
        return d
    }

    /**
     * Returns a cardinal direction name for a bearing.
     *
     * Divides the compass into 8 sectors of 45 degrees each.
     *
     * @param degrees Bearing in degrees [0, 360).
     * @return Cardinal direction string (e.g., "north", "southeast").
     */
    fun cardinalDirection(degrees: Double): String {
        val normalised = ((degrees % 360.0) + 360.0) % 360.0
        return when {
            normalised < 22.5 || normalised >= 337.5 -> "north"
            normalised < 67.5 -> "northeast"
            normalised < 112.5 -> "east"
            normalised < 157.5 -> "southeast"
            normalised < 202.5 -> "south"
            normalised < 247.5 -> "southwest"
            normalised < 292.5 -> "west"
            else -> "northwest"
        }
    }
}
