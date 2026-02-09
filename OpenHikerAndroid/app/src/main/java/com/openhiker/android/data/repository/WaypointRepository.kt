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

package com.openhiker.android.data.repository

import com.openhiker.android.data.db.waypoints.WaypointDao
import com.openhiker.android.data.db.waypoints.WaypointEntity
import com.openhiker.android.data.db.waypoints.WaypointSummary
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Repository for waypoints (points of interest with photos).
 *
 * Provides a clean API layer over the Room [WaypointDao].
 * Photo BLOBs are only loaded on demand (via [getById]) to
 * avoid excessive memory usage in list queries.
 */
@Singleton
class WaypointRepository @Inject constructor(
    private val waypointDao: WaypointDao
) {
    /**
     * Observes all waypoints (without photo BLOBs), newest first.
     *
     * @return A [Flow] emitting waypoint summaries on every change.
     */
    fun observeAll(): Flow<List<WaypointSummary>> = waypointDao.observeAll()

    /**
     * Retrieves a single waypoint with full photo data.
     *
     * @param id The waypoint UUID.
     * @return The full entity including photos, or null.
     */
    suspend fun getById(id: String): WaypointEntity? = waypointDao.getById(id)

    /**
     * Retrieves waypoints linked to a specific hike.
     *
     * @param hikeId The saved route UUID.
     * @return List of waypoint summaries for the hike.
     */
    suspend fun getByHike(hikeId: String): List<WaypointSummary> =
        waypointDao.getByHike(hikeId)

    /**
     * Retrieves waypoints filtered by category.
     *
     * @param category The category raw value (e.g., "viewpoint").
     * @return List of matching waypoint summaries.
     */
    suspend fun getByCategory(category: String): List<WaypointSummary> =
        waypointDao.getByCategory(category)

    /**
     * Saves a new or updated waypoint.
     *
     * @param waypoint The waypoint entity to save (may include photo BLOBs).
     */
    suspend fun save(waypoint: WaypointEntity) = waypointDao.insert(waypoint)

    /**
     * Deletes a waypoint by ID.
     *
     * @param id The waypoint UUID to delete.
     */
    suspend fun delete(id: String) = waypointDao.deleteById(id)
}
