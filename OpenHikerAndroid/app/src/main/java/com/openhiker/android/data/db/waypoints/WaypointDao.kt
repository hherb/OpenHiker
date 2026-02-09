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

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

/**
 * Room DAO for waypoint database operations.
 *
 * Provides CRUD access to waypoints including photo BLOBs.
 * All query methods return [Flow] for reactive Compose UI updates.
 */
@Dao
interface WaypointDao {

    /**
     * Observes all waypoints, ordered by timestamp (newest first).
     *
     * Note: This query excludes photo/thumbnail BLOBs for efficiency.
     * Use [getById] to fetch the full entity with photo data.
     *
     * @return A [Flow] emitting the waypoint list on every change.
     */
    @Query(
        """SELECT id, latitude, longitude, altitude, timestamp, label,
           category, note, has_photo, hike_id, modified_at
           FROM waypoints ORDER BY timestamp DESC"""
    )
    fun observeAll(): Flow<List<WaypointSummary>>

    /**
     * Retrieves a single waypoint with full photo data.
     *
     * @param id The waypoint UUID.
     * @return The full entity including photo BLOBs, or null.
     */
    @Query("SELECT * FROM waypoints WHERE id = :id")
    suspend fun getById(id: String): WaypointEntity?

    /**
     * Retrieves all waypoints for a specific hike.
     *
     * @param hikeId The saved route UUID.
     * @return List of waypoints linked to the hike.
     */
    @Query(
        """SELECT id, latitude, longitude, altitude, timestamp, label,
           category, note, has_photo, hike_id, modified_at
           FROM waypoints WHERE hike_id = :hikeId ORDER BY timestamp ASC"""
    )
    suspend fun getByHike(hikeId: String): List<WaypointSummary>

    /**
     * Retrieves waypoints filtered by category.
     *
     * @param category The waypoint category raw value (e.g., "viewpoint").
     * @return List of matching waypoints.
     */
    @Query(
        """SELECT id, latitude, longitude, altitude, timestamp, label,
           category, note, has_photo, hike_id, modified_at
           FROM waypoints WHERE category = :category ORDER BY timestamp DESC"""
    )
    suspend fun getByCategory(category: String): List<WaypointSummary>

    /**
     * Inserts a new waypoint, replacing any existing entry with the same ID.
     *
     * @param waypoint The waypoint entity to insert.
     */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(waypoint: WaypointEntity)

    /**
     * Updates an existing waypoint.
     *
     * @param waypoint The waypoint entity with updated fields.
     */
    @Update
    suspend fun update(waypoint: WaypointEntity)

    /**
     * Deletes a waypoint by ID.
     *
     * @param id The waypoint UUID to delete.
     */
    @Query("DELETE FROM waypoints WHERE id = :id")
    suspend fun deleteById(id: String)

    /**
     * Returns the total count of waypoints.
     */
    @Query("SELECT COUNT(*) FROM waypoints")
    suspend fun count(): Int
}

/**
 * Lightweight projection of a waypoint without photo BLOBs.
 *
 * Used for list queries where loading full-resolution photos
 * would waste memory. The [hasPhoto] flag indicates whether
 * photo data exists for lazy loading.
 */
data class WaypointSummary(
    val id: String,
    val latitude: Double,
    val longitude: Double,
    val altitude: Double?,
    val timestamp: String,
    val label: String,
    val category: String,
    val note: String,
    @androidx.room.ColumnInfo(name = "has_photo") val hasPhoto: Boolean,
    @androidx.room.ColumnInfo(name = "hike_id") val hikeId: String?,
    @androidx.room.ColumnInfo(name = "modified_at") val modifiedAt: String?
)
