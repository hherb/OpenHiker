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

import android.content.Context
import com.openhiker.core.model.PlannedRoute
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Repository for planned routes (route computations saved for navigation).
 *
 * Planned routes are stored as individual JSON files in the
 * `planned_routes/` directory. This matches the iOS PlannedRouteStore
 * file-based storage approach for cross-platform sync compatibility.
 */
@Singleton
class PlannedRouteRepository @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
    }

    private val _routes = MutableStateFlow<List<PlannedRoute>>(emptyList())

    /** Observable list of all planned routes. */
    val routes: StateFlow<List<PlannedRoute>> = _routes.asStateFlow()

    /** Directory for storing planned route JSON files. */
    private val storageDirectory: File
        get() = File(context.filesDir, ROUTES_DIR).also { it.mkdirs() }

    /**
     * Loads all planned routes from disk.
     *
     * Reads all JSON files in the `planned_routes/` directory and
     * deserializes them into [PlannedRoute] objects. Invalid files
     * are silently skipped.
     */
    suspend fun loadAll() = withContext(Dispatchers.IO) {
        val dir = storageDirectory
        if (!dir.exists()) {
            _routes.value = emptyList()
            return@withContext
        }

        val routes = dir.listFiles { file -> file.extension == "json" }
            ?.mapNotNull { file ->
                try {
                    json.decodeFromString<PlannedRoute>(file.readText())
                } catch (_: Exception) {
                    null
                }
            }
            ?.sortedByDescending { it.createdAt }
            ?: emptyList()

        _routes.value = routes
    }

    /**
     * Saves a planned route to disk as a JSON file.
     *
     * @param route The planned route to save.
     */
    suspend fun save(route: PlannedRoute) = withContext(Dispatchers.IO) {
        val file = File(storageDirectory, "${route.id}.json")
        file.writeText(json.encodeToString(route))

        val current = _routes.value.toMutableList()
        current.removeAll { it.id == route.id }
        current.add(0, route)
        _routes.value = current
    }

    /**
     * Retrieves a single planned route by ID.
     *
     * @param id The route UUID.
     * @return The planned route, or null if not found.
     */
    suspend fun getById(id: String): PlannedRoute? = withContext(Dispatchers.IO) {
        val file = File(storageDirectory, "$id.json")
        if (!file.exists()) return@withContext null
        try {
            json.decodeFromString<PlannedRoute>(file.readText())
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Retrieves all planned routes for a specific region.
     *
     * @param regionId The region UUID.
     * @return List of planned routes associated with the region.
     */
    suspend fun getByRegion(regionId: String): List<PlannedRoute> =
        _routes.value.filter { it.regionId == regionId }

    /**
     * Deletes a planned route from disk and the in-memory list.
     *
     * @param id The route UUID to delete.
     */
    suspend fun delete(id: String) = withContext(Dispatchers.IO) {
        File(storageDirectory, "$id.json").delete()
        _routes.value = _routes.value.filterNot { it.id == id }
    }

    companion object {
        private const val ROUTES_DIR = "planned_routes"
    }
}
