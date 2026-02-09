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

import com.openhiker.android.data.db.routes.RouteDao
import com.openhiker.android.data.db.routes.SavedRouteEntity
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Repository for saved routes (recorded hikes).
 *
 * Provides a clean API layer over the Room [RouteDao], adding
 * any necessary data transformations or business logic. All methods
 * are coroutine-based for non-blocking database access.
 */
@Singleton
class RouteRepository @Inject constructor(
    private val routeDao: RouteDao
) {
    /**
     * Observes all saved routes, ordered by start time (newest first).
     *
     * @return A [Flow] emitting the route list on every database change.
     */
    fun observeAll(): Flow<List<SavedRouteEntity>> = routeDao.observeAll()

    /**
     * Retrieves a single saved route by ID.
     *
     * @param id The route UUID.
     * @return The route entity, or null if not found.
     */
    suspend fun getById(id: String): SavedRouteEntity? = routeDao.getById(id)

    /**
     * Retrieves all saved routes for a specific map region.
     *
     * @param regionId The region UUID.
     * @return List of routes associated with the region.
     */
    suspend fun getByRegion(regionId: String): List<SavedRouteEntity> =
        routeDao.getByRegion(regionId)

    /**
     * Saves a new or updated route to the database.
     *
     * @param route The route entity to save.
     */
    suspend fun save(route: SavedRouteEntity) = routeDao.insert(route)

    /**
     * Deletes a saved route by ID.
     *
     * @param id The route UUID to delete.
     */
    suspend fun delete(id: String) = routeDao.deleteById(id)
}
