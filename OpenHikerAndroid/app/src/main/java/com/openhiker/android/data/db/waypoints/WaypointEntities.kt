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

package com.openhiker.android.data.db.waypoints

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Room entity for waypoints (points of interest).
 *
 * Stores waypoint metadata, coordinates, and optional photo data.
 * Photos are stored as JPEG BLOBs directly in the database: [photo]
 * for the full resolution image and [thumbnail] for the 100x100 preview.
 */
@Entity(tableName = "waypoints")
data class WaypointEntity(
    @PrimaryKey
    val id: String,
    val latitude: Double,
    val longitude: Double,
    val altitude: Double?,
    val timestamp: String,
    val label: String,
    val category: String,
    val note: String = "",
    @ColumnInfo(name = "has_photo") val hasPhoto: Boolean = false,
    @ColumnInfo(name = "hike_id") val hikeId: String? = null,
    @ColumnInfo(typeAffinity = ColumnInfo.BLOB) val photo: ByteArray? = null,
    @ColumnInfo(typeAffinity = ColumnInfo.BLOB) val thumbnail: ByteArray? = null,
    @ColumnInfo(name = "modified_at") val modifiedAt: String? = null
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is WaypointEntity) return false
        return id == other.id
    }

    override fun hashCode(): Int = id.hashCode()
}
