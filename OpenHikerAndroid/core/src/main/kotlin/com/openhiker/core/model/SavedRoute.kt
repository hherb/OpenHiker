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
 * A completed (recorded) hike with GPS track data and statistics.
 *
 * The GPS track is stored as compressed binary data (zlib-compressed
 * sequence of 20-byte records). Use [com.openhiker.core.compression.TrackCompression]
 * to encode/decode the track data.
 *
 * Start/end coordinates are stored as separate latitude/longitude fields
 * (not as Coordinate objects) to match the iOS SavedRoute struct's JSON format
 * for cross-platform sync compatibility.
 *
 * @property id Unique identifier (UUID string).
 * @property name User-editable hike name. Auto-generated as "Hike — {date}".
 * @property startLatitude Latitude of the first GPS point.
 * @property startLongitude Longitude of the first GPS point.
 * @property endLatitude Latitude of the last GPS point.
 * @property endLongitude Longitude of the last GPS point.
 * @property startTime ISO-8601 timestamp of hike start.
 * @property endTime ISO-8601 timestamp of hike end.
 * @property totalDistance Total distance in metres.
 * @property elevationGain Cumulative elevation gain in metres.
 * @property elevationLoss Cumulative elevation loss in metres.
 * @property walkingTime Active walking time in seconds.
 * @property restingTime Stationary time in seconds.
 * @property averageHeartRate Mean heart rate in BPM, or null.
 * @property maxHeartRate Peak heart rate in BPM, or null.
 * @property estimatedCalories Estimated kilocalories burned, or null.
 * @property comment User annotation text.
 * @property regionId UUID of the associated map region, or null.
 * @property modifiedAt ISO-8601 last modification timestamp (for sync).
 */
@Serializable
data class SavedRoute(
    val id: String,
    val name: String,
    val startLatitude: Double,
    val startLongitude: Double,
    val endLatitude: Double,
    val endLongitude: Double,
    val startTime: String,
    val endTime: String,
    val totalDistance: Double,
    val elevationGain: Double,
    val elevationLoss: Double,
    val walkingTime: Double,
    val restingTime: Double,
    val averageHeartRate: Double? = null,
    val maxHeartRate: Double? = null,
    val estimatedCalories: Double? = null,
    val comment: String = "",
    val regionId: String? = null,
    val modifiedAt: String? = null
) {
    /** Start coordinate as a [Coordinate] object. */
    val startCoordinate: Coordinate get() = Coordinate(startLatitude, startLongitude)

    /** End coordinate as a [Coordinate] object. */
    val endCoordinate: Coordinate get() = Coordinate(endLatitude, endLongitude)

    /** Total elapsed time (end - start) in seconds. Computed from timestamps. */
    // Duration calculation requires parsing ISO timestamps; done at the app layer.
}
