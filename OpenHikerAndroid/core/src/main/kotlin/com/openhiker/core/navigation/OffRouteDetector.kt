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

package com.openhiker.core.navigation

import com.openhiker.core.geo.Haversine
import com.openhiker.core.model.Coordinate

/**
 * State of the off-route detector.
 *
 * @property isOffRoute True if the user is currently considered off-route.
 * @property distanceFromRoute Perpendicular distance to the nearest route segment in metres.
 */
data class OffRouteState(
    val isOffRoute: Boolean = false,
    val distanceFromRoute: Double = 0.0
)

/**
 * Detects when the user has strayed too far from the planned route.
 *
 * Uses hysteresis to prevent rapid on/off flapping:
 * - Triggers off-route at [RouteGuidanceConfig.OFF_ROUTE_THRESHOLD_METRES] (50m)
 * - Clears off-route at [RouteGuidanceConfig.OFF_ROUTE_CLEAR_THRESHOLD_METRES] (30m)
 *
 * This means a user must get closer than 30m to the route before the
 * off-route warning is cleared, even though it only triggers at 50m.
 *
 * This class is stateful (tracks current off-route status) and should
 * be created once per navigation session.
 */
class OffRouteDetector(
    private val routeCoordinates: List<Coordinate>
) {
    /** Current off-route state with hysteresis. */
    private var currentlyOffRoute: Boolean = false

    /**
     * Checks whether the user is off-route given their current position.
     *
     * Finds the minimum distance from the current position to any segment
     * of the route polyline, then applies hysteresis thresholds.
     *
     * @param latitude Current GPS latitude.
     * @param longitude Current GPS longitude.
     * @return Updated [OffRouteState] with off-route flag and distance.
     */
    fun check(latitude: Double, longitude: Double): OffRouteState {
        if (routeCoordinates.size < 2) {
            return OffRouteState(isOffRoute = false, distanceFromRoute = 0.0)
        }

        val currentPos = Coordinate(latitude, longitude)
        val minDistance = minimumDistanceToRoute(currentPos)

        // Apply hysteresis
        currentlyOffRoute = if (currentlyOffRoute) {
            // Currently off-route: clear only when closer than clear threshold
            minDistance > RouteGuidanceConfig.OFF_ROUTE_CLEAR_THRESHOLD_METRES
        } else {
            // Currently on-route: trigger only when farther than trigger threshold
            minDistance > RouteGuidanceConfig.OFF_ROUTE_THRESHOLD_METRES
        }

        return OffRouteState(
            isOffRoute = currentlyOffRoute,
            distanceFromRoute = minDistance
        )
    }

    /**
     * Calculates the minimum distance from a point to the route polyline.
     *
     * Checks the distance to each segment of the route (not just nodes)
     * for accurate perpendicular distance measurement.
     *
     * @param point The user's current position.
     * @return Minimum distance in metres to any route segment.
     */
    private fun minimumDistanceToRoute(point: Coordinate): Double {
        var minDist = Double.MAX_VALUE
        for (i in 0 until routeCoordinates.size - 1) {
            val dist = distanceToSegment(
                point,
                routeCoordinates[i],
                routeCoordinates[i + 1]
            )
            if (dist < minDist) {
                minDist = dist
            }
        }
        return minDist
    }

    companion object {
        /**
         * Calculates the minimum distance from a point to a line segment.
         *
         * Projects the point onto the segment and returns the distance to
         * the nearest point on the segment (clamped to the endpoints).
         *
         * @param point The point to measure from.
         * @param segStart Start of the line segment.
         * @param segEnd End of the line segment.
         * @return Distance in metres from the point to the nearest point on the segment.
         */
        fun distanceToSegment(
            point: Coordinate,
            segStart: Coordinate,
            segEnd: Coordinate
        ): Double {
            val d = Haversine.distance(segStart, segEnd)
            if (d < 0.1) {
                // Degenerate segment (< 10cm): just return distance to start
                return Haversine.distance(point, segStart)
            }

            // Project point onto the line using dot product approximation
            // (works well for short segments typical in hiking routes)
            val dStartToPoint = Haversine.distance(segStart, point)
            val dEndToPoint = Haversine.distance(segEnd, point)
            val dStartToEnd = d

            // Use the triangle inequality to check if the projection falls
            // within the segment
            val t = ((dStartToPoint * dStartToPoint -
                dEndToPoint * dEndToPoint +
                dStartToEnd * dStartToEnd) /
                (2.0 * dStartToEnd * dStartToEnd)).coerceIn(0.0, 1.0)

            // Compute the projected point using bearing interpolation
            val bearing = Haversine.bearing(segStart, segEnd)
            val projectedPoint = Haversine.destination(segStart, bearing, t * dStartToEnd)

            return Haversine.distance(point, projectedPoint)
        }
    }
}
