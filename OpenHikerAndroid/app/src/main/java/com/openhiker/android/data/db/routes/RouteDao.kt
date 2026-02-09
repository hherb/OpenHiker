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

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

/**
 * Room DAO for saved route (recorded hike) database operations.
 *
 * All query methods return [Flow] for reactive UI updates via Compose.
 * Suspend functions are used for write operations to ensure they run
 * on a background thread.
 */
@Dao
interface RouteDao {

    /**
     * Observes all saved routes, ordered by start time (newest first).
     *
     * @return A [Flow] that emits the full list whenever the table changes.
     */
    @Query("SELECT * FROM saved_routes ORDER BY start_time DESC")
    fun observeAll(): Flow<List<SavedRouteEntity>>

    /**
     * Retrieves a single saved route by ID.
     *
     * @param id The route UUID.
     * @return The route entity, or null if not found.
     */
    @Query("SELECT * FROM saved_routes WHERE id = :id")
    suspend fun getById(id: String): SavedRouteEntity?

    /**
     * Retrieves all saved routes for a specific map region.
     *
     * @param regionId The region UUID.
     * @return List of routes associated with the region.
     */
    @Query("SELECT * FROM saved_routes WHERE region_id = :regionId ORDER BY start_time DESC")
    suspend fun getByRegion(regionId: String): List<SavedRouteEntity>

    /**
     * Inserts a new saved route, replacing any existing entry with the same ID.
     *
     * @param route The route entity to insert.
     */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(route: SavedRouteEntity)

    /**
     * Updates an existing saved route.
     *
     * @param route The route entity with updated fields.
     */
    @Update
    suspend fun update(route: SavedRouteEntity)

    /**
     * Deletes a saved route by ID.
     *
     * @param id The route UUID to delete.
     */
    @Query("DELETE FROM saved_routes WHERE id = :id")
    suspend fun deleteById(id: String)

    /**
     * Returns the total count of saved routes.
     *
     * @return Number of routes in the database.
     */
    @Query("SELECT COUNT(*) FROM saved_routes")
    suspend fun count(): Int
}
