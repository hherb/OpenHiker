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

package com.openhiker.core.community

import com.openhiker.core.model.Coordinate
import com.openhiker.core.model.PlannedRoute
import java.util.UUID

/**
 * Pure functions for converting between community-shared route formats
 * and the app's internal data models.
 *
 * Handles bidirectional conversion:
 * - [SharedRoute] -> [PlannedRoute] (downloading a community route for local use)
 * - [PlannedRoute] -> [SharedRoute] (uploading a local route to the community)
 *
 * All functions are stateless and produce new objects without side effects.
 */
object CommunityRouteConverter {

    /**
     * Converts a community [SharedRoute] into a local [PlannedRoute].
     *
     * The resulting PlannedRoute can be saved to the local planned routes
     * directory and used for turn-by-turn navigation. The route coordinates
     * are extracted from the SharedRoute's track points.
     *
     * @param shared The community route to convert.
     * @param regionId Optional UUID of the local map region to associate with.
     * @return A new PlannedRoute populated from the shared route data.
     */
    fun sharedRouteToPlannedRoute(
        shared: SharedRoute,
        regionId: String? = null
    ): PlannedRoute {
        val coordinates = shared.track.map { point ->
            Coordinate(point.lat, point.lon)
        }

        val startCoord = coordinates.firstOrNull() ?: Coordinate.ZERO
        val endCoord = coordinates.lastOrNull() ?: Coordinate.ZERO

        return PlannedRoute(
            id = UUID.randomUUID().toString(),
            name = shared.name,
            mode = shared.activityType,
            startCoordinate = startCoord,
            endCoordinate = endCoord,
            coordinates = coordinates,
            totalDistance = shared.stats.distanceMeters,
            estimatedDuration = shared.stats.durationSeconds,
            elevationGain = shared.stats.elevationGainMeters,
            elevationLoss = shared.stats.elevationLossMeters,
            createdAt = shared.createdAt,
            regionId = regionId,
            modifiedAt = shared.createdAt
        )
    }

    /**
     * Converts a local [PlannedRoute] into a [SharedRoute] for community upload.
     *
     * The caller must provide author, description, and region metadata
     * that are not present in the PlannedRoute data model.
     *
     * @param route The local planned route to convert.
     * @param author Display name of the route author.
     * @param description Freeform description of the route.
     * @param country ISO 3166-1 alpha-2 country code (e.g., "US", "DE").
     * @param area State or region name (e.g., "California", "Tirol").
     * @return A new SharedRoute ready for JSON serialisation and upload.
     */
    fun plannedRouteToSharedRoute(
        route: PlannedRoute,
        author: String,
        description: String,
        country: String,
        area: String
    ): SharedRoute {
        val trackPoints = route.coordinates.map { coord ->
            SharedTrackPoint(
                lat = roundTo5Decimals(coord.latitude),
                lon = roundTo5Decimals(coord.longitude),
                ele = 0.0,
                time = route.createdAt
            )
        }

        val boundingBox = computeBoundingBox(route.coordinates)

        return SharedRoute(
            id = route.id,
            version = SHARED_ROUTE_VERSION,
            name = route.name,
            activityType = route.mode,
            author = author,
            description = description,
            createdAt = route.createdAt,
            region = RouteRegion(country = country, area = area),
            stats = RouteStats(
                distanceMeters = route.totalDistance,
                elevationGainMeters = route.elevationGain,
                elevationLossMeters = route.elevationLoss,
                durationSeconds = route.estimatedDuration
            ),
            boundingBox = boundingBox,
            track = trackPoints
        )
    }

    /**
     * Computes the geographic bounding box of a list of coordinates.
     *
     * Returns a zero-sized box at the origin if the list is empty.
     *
     * @param coordinates Ordered list of route coordinates.
     * @return The smallest bounding box containing all coordinates.
     */
    fun computeBoundingBox(coordinates: List<Coordinate>): SharedBoundingBox {
        if (coordinates.isEmpty()) {
            return SharedBoundingBox(north = 0.0, south = 0.0, east = 0.0, west = 0.0)
        }

        var north = coordinates[0].latitude
        var south = coordinates[0].latitude
        var east = coordinates[0].longitude
        var west = coordinates[0].longitude

        for (coord in coordinates) {
            if (coord.latitude > north) north = coord.latitude
            if (coord.latitude < south) south = coord.latitude
            if (coord.longitude > east) east = coord.longitude
            if (coord.longitude < west) west = coord.longitude
        }

        return SharedBoundingBox(
            north = roundTo5Decimals(north),
            south = roundTo5Decimals(south),
            east = roundTo5Decimals(east),
            west = roundTo5Decimals(west)
        )
    }

    /**
     * Rounds a double to 5 decimal places (~1.1m GPS precision).
     *
     * @param value The value to round.
     * @return The value rounded to 5 decimal places.
     */
    fun roundTo5Decimals(value: Double): Double =
        Math.round(value * FIVE_DECIMAL_FACTOR) / FIVE_DECIMAL_FACTOR

    /** Current SharedRoute schema version. */
    private const val SHARED_ROUTE_VERSION = 1

    /** Multiplication factor for rounding to 5 decimal places. */
    private const val FIVE_DECIMAL_FACTOR = 100_000.0
}
