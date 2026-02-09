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

package com.openhiker.core.model

import kotlinx.serialization.Serializable

/**
 * A planned (not yet hiked) route with turn-by-turn instructions.
 *
 * Created by the routing engine when a user plans a route between
 * start/end/via points on an offline map. Stored as a JSON file
 * and used by the navigation service for turn-by-turn guidance.
 *
 * The JSON format matches the iOS PlannedRoute struct for cross-platform
 * route sharing via cloud sync and community uploads.
 *
 * @property id Unique identifier (UUID string).
 * @property name User-editable route name.
 * @property mode Activity type used for cost computation (hiking or cycling).
 * @property startCoordinate Starting point of the route.
 * @property endCoordinate Destination point of the route.
 * @property viaPoints Intermediate waypoints the route passes through.
 * @property coordinates Full route polyline as an ordered list of coordinates.
 * @property turnInstructions Turn-by-turn navigation instructions at junctions.
 * @property totalDistance Total route distance in metres.
 * @property estimatedDuration Estimated travel time in seconds.
 * @property elevationGain Total uphill elevation change in metres.
 * @property elevationLoss Total downhill elevation change in metres.
 * @property createdAt ISO-8601 creation timestamp.
 * @property regionId UUID of the map region this route was planned in, or null.
 * @property elevationProfile Pre-computed elevation profile for chart display, or null.
 * @property modifiedAt ISO-8601 last modification timestamp (for sync).
 */
@Serializable
data class PlannedRoute(
    val id: String,
    val name: String,
    val mode: RoutingMode,
    val startCoordinate: Coordinate,
    val endCoordinate: Coordinate,
    val viaPoints: List<Coordinate> = emptyList(),
    val coordinates: List<Coordinate> = emptyList(),
    val turnInstructions: List<TurnInstruction> = emptyList(),
    val totalDistance: Double = 0.0,
    val estimatedDuration: Double = 0.0,
    val elevationGain: Double = 0.0,
    val elevationLoss: Double = 0.0,
    val createdAt: String,
    val regionId: String? = null,
    val elevationProfile: List<ElevationPoint>? = null,
    val modifiedAt: String? = null
) {
    /**
     * Formats the total distance for display.
     *
     * @param useMetric True for km, false for miles.
     * @return Formatted string like "12.3 km".
     */
    fun formattedDistance(useMetric: Boolean = true): String =
        HikeStatsFormatter.formatDistance(totalDistance, useMetric)

    /**
     * Formats the estimated duration for display.
     *
     * @return Formatted string like "03:45:00".
     */
    fun formattedDuration(): String =
        HikeStatsFormatter.formatDuration(estimatedDuration)
}
