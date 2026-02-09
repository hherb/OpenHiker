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

package com.openhiker.android.data.db.routes

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Room entity for saved (recorded) hikes.
 *
 * The [trackData] column stores zlib-compressed binary GPS track data
 * produced by [com.openhiker.core.compression.TrackCompression]. This
 * format is cross-platform compatible with the iOS app's track storage.
 */
@Entity(tableName = "saved_routes")
data class SavedRouteEntity(
    @PrimaryKey
    val id: String,
    val name: String,
    @ColumnInfo(name = "start_latitude") val startLatitude: Double,
    @ColumnInfo(name = "start_longitude") val startLongitude: Double,
    @ColumnInfo(name = "end_latitude") val endLatitude: Double,
    @ColumnInfo(name = "end_longitude") val endLongitude: Double,
    @ColumnInfo(name = "start_time") val startTime: String,
    @ColumnInfo(name = "end_time") val endTime: String,
    @ColumnInfo(name = "total_distance") val totalDistance: Double,
    @ColumnInfo(name = "elevation_gain") val elevationGain: Double,
    @ColumnInfo(name = "elevation_loss") val elevationLoss: Double,
    @ColumnInfo(name = "walking_time") val walkingTime: Double,
    @ColumnInfo(name = "resting_time") val restingTime: Double,
    @ColumnInfo(name = "average_heart_rate") val averageHeartRate: Double?,
    @ColumnInfo(name = "max_heart_rate") val maxHeartRate: Double?,
    @ColumnInfo(name = "estimated_calories") val estimatedCalories: Double?,
    val comment: String = "",
    @ColumnInfo(name = "region_id") val regionId: String?,
    @ColumnInfo(name = "track_data", typeAffinity = ColumnInfo.BLOB)
    val trackData: ByteArray,
    @ColumnInfo(name = "modified_at") val modifiedAt: String? = null
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SavedRouteEntity) return false
        return id == other.id
    }

    override fun hashCode(): Int = id.hashCode()
}
