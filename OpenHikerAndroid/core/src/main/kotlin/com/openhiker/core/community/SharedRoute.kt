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

import com.openhiker.core.model.RoutingMode
import kotlinx.serialization.Serializable

/**
 * A community-shared route stored in the OpenHikerRoutes GitHub repository.
 *
 * The JSON format matches the iOS SharedRoute struct for cross-platform
 * route sharing. Both platforms can read and display routes uploaded
 * by either platform.
 *
 * @property id UUID string.
 * @property version Schema version (currently 1).
 * @property name Route name.
 * @property activityType Hiking or cycling.
 * @property author Display name of the route creator.
 * @property description Freeform description text.
 * @property createdAt ISO-8601 creation timestamp.
 * @property region Country and area information.
 * @property stats Distance, elevation, and duration statistics.
 * @property boundingBox Geographic extent of the route.
 * @property track Ordered list of GPS track points.
 * @property waypoints Points of interest along the route.
 * @property photos Photo metadata (actual images are separate files).
 */
@Serializable
data class SharedRoute(
    val id: String,
    val version: Int = 1,
    val name: String,
    val activityType: RoutingMode,
    val author: String,
    val description: String,
    val createdAt: String,
    val region: RouteRegion,
    val stats: RouteStats,
    val boundingBox: SharedBoundingBox,
    val track: List<SharedTrackPoint>,
    val waypoints: List<SharedWaypoint> = emptyList(),
    val photos: List<RoutePhoto> = emptyList()
)

/**
 * Geographic region (country and area) for a shared route.
 *
 * @property country ISO 3166-1 alpha-2 country code (e.g., "US", "DE").
 * @property area State or region name (e.g., "California", "Tirol").
 */
@Serializable
data class RouteRegion(
    val country: String,
    val area: String
)

/**
 * Summary statistics for a shared route.
 *
 * @property distanceMeters Total route distance in metres.
 * @property elevationGainMeters Total uphill elevation in metres.
 * @property elevationLossMeters Total downhill elevation in metres.
 * @property durationSeconds Estimated or actual duration in seconds.
 */
@Serializable
data class RouteStats(
    val distanceMeters: Double,
    val elevationGainMeters: Double,
    val elevationLossMeters: Double,
    val durationSeconds: Double
)

/**
 * Bounding box for a shared route's geographic extent.
 *
 * @property north Northern latitude in degrees.
 * @property south Southern latitude in degrees.
 * @property east Eastern longitude in degrees.
 * @property west Western longitude in degrees.
 */
@Serializable
data class SharedBoundingBox(
    val north: Double,
    val south: Double,
    val east: Double,
    val west: Double
) {
    /** Latitude of the centre point. */
    val centerLatitude: Double get() = (north + south) / 2.0

    /** Longitude of the centre point. */
    val centerLongitude: Double get() = (east + west) / 2.0

    /**
     * Checks whether a coordinate falls within this bounding box.
     *
     * @param latitude Latitude to test.
     * @param longitude Longitude to test.
     * @return True if the point is within the box.
     */
    fun contains(latitude: Double, longitude: Double): Boolean =
        latitude in south..north && longitude in west..east
}

/**
 * A GPS track point in a shared route.
 *
 * Uses shortened field names (lat, lon, ele) for compact JSON serialisation.
 * 5 decimal places (~1.1m precision) is sufficient for hiking GPS accuracy.
 *
 * @property lat Latitude in degrees.
 * @property lon Longitude in degrees.
 * @property ele Elevation in metres above sea level.
 * @property time ISO-8601 timestamp.
 */
@Serializable
data class SharedTrackPoint(
    val lat: Double,
    val lon: Double,
    val ele: Double,
    val time: String
)

/**
 * A waypoint (point of interest) in a shared route.
 *
 * @property id UUID string.
 * @property lat Latitude in degrees.
 * @property lon Longitude in degrees.
 * @property ele Elevation in metres, or null.
 * @property label Short display name.
 * @property category Category raw value (e.g., "viewpoint", "waterSource").
 * @property note Description text.
 */
@Serializable
data class SharedWaypoint(
    val id: String,
    val lat: Double,
    val lon: Double,
    val ele: Double? = null,
    val label: String,
    val category: String,
    val note: String = ""
)

/**
 * Photo metadata in a shared route.
 *
 * The actual image file is stored in the `photos/` subdirectory
 * of the route's GitHub repository path.
 *
 * @property filename Image filename in the photos directory.
 * @property lat Capture latitude, or null if not geotagged.
 * @property lon Capture longitude, or null if not geotagged.
 * @property caption User-provided caption text.
 * @property waypointId Associated waypoint UUID, or null.
 */
@Serializable
data class RoutePhoto(
    val filename: String,
    val lat: Double? = null,
    val lon: Double? = null,
    val caption: String = "",
    val waypointId: String? = null
)
