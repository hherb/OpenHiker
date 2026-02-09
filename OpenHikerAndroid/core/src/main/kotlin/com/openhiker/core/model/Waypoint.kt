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
 * A geographic point of interest (waypoint) saved during or after a hike.
 *
 * Waypoints can have photos (stored as BLOBs in the app database),
 * belong to a category, and optionally be linked to a saved hike.
 * The JSON serialisation format matches the iOS Waypoint struct for
 * cross-platform sync compatibility.
 *
 * @property id Unique identifier (UUID string).
 * @property latitude WGS84 latitude in degrees.
 * @property longitude WGS84 longitude in degrees.
 * @property altitude Elevation in metres above sea level, or null if unknown.
 * @property timestamp ISO-8601 creation timestamp.
 * @property label Short display name for the waypoint.
 * @property category Waypoint type (viewpoint, water source, etc.).
 * @property note Longer description or notes.
 * @property hasPhoto Whether a photo is stored in the database for this waypoint.
 * @property hikeId UUID of the associated saved hike, or null if standalone.
 * @property modifiedAt ISO-8601 timestamp of last modification (for sync).
 */
@Serializable
data class Waypoint(
    val id: String,
    val latitude: Double,
    val longitude: Double,
    val altitude: Double? = null,
    val timestamp: String,
    val label: String,
    val category: WaypointCategory,
    val note: String = "",
    val hasPhoto: Boolean = false,
    val hikeId: String? = null,
    val modifiedAt: String? = null
) {
    /** The waypoint's geographic coordinate. */
    val coordinate: Coordinate get() = Coordinate(latitude, longitude)

    /**
     * Formatted coordinate string with 5 decimal places (~1.1m precision).
     *
     * @return A string like "47.26543, 11.39354".
     */
    val formattedCoordinate: String
        get() = "%.5f, %.5f".format(latitude, longitude)
}
