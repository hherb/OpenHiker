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

package com.openhiker.android.service.sync

import com.openhiker.android.data.db.routes.SavedRouteEntity
import com.openhiker.android.data.db.waypoints.WaypointEntity
import com.openhiker.core.model.SavedRoute
import com.openhiker.core.model.Waypoint
import com.openhiker.core.model.WaypointCategory
import kotlinx.serialization.Serializable
import java.util.Base64

/**
 * A saved route (recorded hike) as written to `saved_routes/{uuid}.json` in the cloud folder.
 *
 * @property route The hike's metadata and statistics.
 * @property trackData The compressed GPS track ([SavedRouteEntity.trackData]), Base64-encoded.
 */
@Serializable
data class SavedRouteRecord(
    val route: SavedRoute,
    val trackData: String
)

/**
 * A waypoint as written to `waypoints/{uuid}.json` in the cloud folder.
 *
 * @property waypoint The waypoint's fields; its category serialises as the shared raw value.
 * @property photo The full-resolution photo, Base64-encoded, or null if there is none.
 * @property thumbnail The 100x100 thumbnail, Base64-encoded, or null if there is none.
 */
@Serializable
data class WaypointRecord(
    val waypoint: Waypoint,
    val photo: String? = null,
    val thumbnail: String? = null
)

/**
 * Converts a stored hike into its cloud record.
 *
 * @receiver The Room entity.
 * @return The record, with the track Base64-encoded.
 */
internal fun SavedRouteEntity.toSyncRecord() = SavedRouteRecord(
    route = SavedRoute(
        id = id,
        name = name,
        startLatitude = startLatitude,
        startLongitude = startLongitude,
        endLatitude = endLatitude,
        endLongitude = endLongitude,
        startTime = startTime,
        endTime = endTime,
        totalDistance = totalDistance,
        elevationGain = elevationGain,
        elevationLoss = elevationLoss,
        walkingTime = walkingTime,
        restingTime = restingTime,
        averageHeartRate = averageHeartRate,
        maxHeartRate = maxHeartRate,
        estimatedCalories = estimatedCalories,
        comment = comment,
        regionId = regionId,
        modifiedAt = modifiedAt
    ),
    trackData = Base64.getEncoder().encodeToString(trackData)
)

/**
 * Converts a cloud record back into a Room entity.
 *
 * @receiver The record read from the cloud folder.
 * @return The entity to store.
 * @throws IllegalArgumentException if [SavedRouteRecord.trackData] is not valid Base64.
 */
internal fun SavedRouteRecord.toEntity() = SavedRouteEntity(
    id = route.id,
    name = route.name,
    startLatitude = route.startLatitude,
    startLongitude = route.startLongitude,
    endLatitude = route.endLatitude,
    endLongitude = route.endLongitude,
    startTime = route.startTime,
    endTime = route.endTime,
    totalDistance = route.totalDistance,
    elevationGain = route.elevationGain,
    elevationLoss = route.elevationLoss,
    walkingTime = route.walkingTime,
    restingTime = route.restingTime,
    averageHeartRate = route.averageHeartRate,
    maxHeartRate = route.maxHeartRate,
    estimatedCalories = route.estimatedCalories,
    comment = route.comment,
    regionId = route.regionId,
    trackData = Base64.getDecoder().decode(trackData),
    modifiedAt = route.modifiedAt
)

/**
 * Converts a stored waypoint into its cloud record.
 *
 * A stored category that matches no [WaypointCategory] becomes [WaypointCategory.CUSTOM], the
 * same fallback the UI shows for it.
 *
 * @receiver The Room entity.
 * @return The record, with photo and thumbnail Base64-encoded.
 */
internal fun WaypointEntity.toSyncRecord() = WaypointRecord(
    waypoint = Waypoint(
        id = id,
        latitude = latitude,
        longitude = longitude,
        altitude = altitude,
        timestamp = timestamp,
        label = label,
        category = WaypointCategory.fromStored(category) ?: WaypointCategory.CUSTOM,
        note = note,
        hasPhoto = hasPhoto,
        hikeId = hikeId,
        modifiedAt = modifiedAt
    ),
    photo = photo?.let { Base64.getEncoder().encodeToString(it) },
    thumbnail = thumbnail?.let { Base64.getEncoder().encodeToString(it) }
)

/**
 * Converts a cloud record back into a Room entity, storing the category's raw value.
 *
 * @receiver The record read from the cloud folder.
 * @return The entity to store.
 * @throws IllegalArgumentException if the photo or thumbnail is not valid Base64.
 */
internal fun WaypointRecord.toEntity() = WaypointEntity(
    id = waypoint.id,
    latitude = waypoint.latitude,
    longitude = waypoint.longitude,
    altitude = waypoint.altitude,
    timestamp = waypoint.timestamp,
    label = waypoint.label,
    category = waypoint.category.rawValue,
    note = waypoint.note,
    hasPhoto = waypoint.hasPhoto,
    hikeId = waypoint.hikeId,
    photo = photo?.let { Base64.getDecoder().decode(it) },
    thumbnail = thumbnail?.let { Base64.getDecoder().decode(it) },
    modifiedAt = waypoint.modifiedAt
)
