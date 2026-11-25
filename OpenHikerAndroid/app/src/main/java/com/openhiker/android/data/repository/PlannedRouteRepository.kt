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
import com.openhiker.android.data.sync.SyncStateStore
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
import java.io.IOException
import java.nio.file.Files
import javax.inject.Inject
import javax.inject.Singleton

/**
 * A planned-route file that could not be read or parsed.
 *
 * @property fileName The file's name in `planned_routes/`, for example `<uuid>.json`.
 * @property reason Why it could not be read.
 */
data class SkippedRouteFile(val fileName: String, val reason: String) {
    /** The route id the file would hold: its name without `.json`. */
    val id: String get() = fileName.removeSuffix(".json")

    /** "file name: reason", for logs and the sync banner. */
    val message: String get() = "$fileName: $reason"
}

/**
 * Repository for planned routes (route computations saved for navigation).
 *
 * Planned routes are stored as individual JSON files in the
 * `planned_routes/` directory. This matches the iOS PlannedRouteStore
 * file-based storage approach for cross-platform sync compatibility.
 */
@Singleton
class PlannedRouteRepository internal constructor(
    private val filesDir: File,
    private val syncState: SyncStateStore
) {
    /**
     * Hilt constructor: stores routes under the app's private files directory.
     *
     * @param context Application context whose `filesDir` holds the `planned_routes/` directory.
     * @param syncState Records deletions for cloud sync.
     */
    @Inject
    constructor(
        @ApplicationContext context: Context,
        syncState: SyncStateStore
    ) : this(context.filesDir, syncState)

    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
    }

    private val _routes = MutableStateFlow<List<PlannedRoute>>(emptyList())

    /** Observable list of all planned routes. */
    val routes: StateFlow<List<PlannedRoute>> = _routes.asStateFlow()

    private val _skippedFiles = MutableStateFlow<List<SkippedRouteFile>>(emptyList())

    /** Route files the last [loadAll] could not read; empty until it runs. */
    val skippedFiles: StateFlow<List<SkippedRouteFile>> = _skippedFiles.asStateFlow()

    /**
     * Directory for storing planned route JSON files, created if missing.
     *
     * @throws IOException If the directory does not exist and cannot be created.
     */
    private val storageDirectory: File
        get() = File(filesDir, ROUTES_DIR).also {
            if (!it.mkdirs() && !it.isDirectory) {
                throw IOException("Cannot create planned route directory ${it.path}")
            }
        }

    /**
     * Loads all planned routes from disk into [routes].
     *
     * Reads every JSON file in the `planned_routes/` directory. A file that cannot be read or
     * parsed is skipped, listed in the result and published in [skippedFiles], so the caller can
     * log it and the sync banner can offer to delete it.
     *
     * @return The skipped files; empty if every file loaded.
     * @throws IOException If the directory cannot be created or listed. [routes] and
     *   [skippedFiles] are then left unchanged: an empty list would make cloud sync treat every
     *   route as missing locally.
     */
    suspend fun loadAll(): List<SkippedRouteFile> = withContext(Dispatchers.IO) {
        val dir = storageDirectory
        val files = dir.listFiles { file -> file.extension == "json" }
            ?: throw IOException("Cannot list planned route directory ${dir.path}")

        val skipped = mutableListOf<SkippedRouteFile>()
        _routes.value = files
            .mapNotNull { file ->
                try {
                    json.decodeFromString<PlannedRoute>(file.readText())
                } catch (e: Exception) {
                    skipped.add(SkippedRouteFile(file.name, e.message ?: e.javaClass.simpleName))
                    null
                }
            }
            .sortedByDescending { it.createdAt }
        _skippedFiles.value = skipped
        skipped
    }

    /**
     * Deletes every route file that [loadAll] cannot read, after the user confirmed it.
     *
     * No deletion is recorded for sync: the user discards a broken local copy, not the route.
     * If the sync folder holds a copy of the route, the next sync brings it back (#77).
     *
     * @throws IOException If the directory cannot be listed, or a file cannot be deleted. The
     *   files left are then still in [skippedFiles].
     */
    suspend fun deleteSkippedFiles() = withContext(Dispatchers.IO) {
        // Read again, so a file that became readable meanwhile is kept.
        val reasons = mutableListOf<String>()
        val failed = loadAll().filter { skipped ->
            try {
                // A file already gone (sync applied a deletion meanwhile) counts as deleted.
                Files.deleteIfExists(File(storageDirectory, skipped.fileName).toPath())
                false
            } catch (e: IOException) {
                reasons.add("${skipped.fileName}: ${e.message ?: e.javaClass.simpleName}")
                true
            }
        }
        _skippedFiles.value = failed
        if (reasons.isNotEmpty()) throw IOException("Cannot delete ${reasons.joinToString("; ")}")
    }

    /**
     * Saves a planned route to disk as a JSON file, then updates the in-memory list.
     *
     * The JSON goes to a temporary file that is then renamed over the old one, so a failed write
     * (for example a full disk) never destroys the route already saved under that ID.
     *
     * @param route The planned route to save.
     * @throws IOException If the file cannot be written. The file on disk and the in-memory list
     *   are then left unchanged, so callers must catch this and tell the user the route was not saved.
     */
    suspend fun save(route: PlannedRoute) = withContext(Dispatchers.IO) {
        val file = File(storageDirectory, "${route.id}.json")
        // ".json.tmp" has extension "tmp", so loadAll never reads a leftover temp file.
        val tmp = File(file.parentFile, "${file.name}.tmp")
        tmp.writeText(json.encodeToString(route))
        if (!tmp.renameTo(file)) {
            tmp.delete()
            throw IOException("Cannot replace planned route file ${file.path}")
        }

        val current = _routes.value.toMutableList()
        current.removeAll { it.id == route.id }
        current.add(0, route)
        _routes.value = current
    }

    /**
     * Retrieves a single planned route by ID.
     *
     * @param id The route UUID.
     * @return The planned route, or null if no route with this ID is stored.
     * @throws IOException If the route file exists but cannot be read or parsed, so callers can
     *   tell "not found" apart from "found but broken".
     */
    suspend fun getById(id: String): PlannedRoute? = withContext(Dispatchers.IO) {
        val file = File(storageDirectory, "$id.json")
        if (!file.exists()) return@withContext null
        try {
            json.decodeFromString<PlannedRoute>(file.readText())
        } catch (e: Exception) {
            throw IOException("Cannot read planned route $id: ${e.message}", e)
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
     * Deletes a planned route from disk and the in-memory list, and records the deletion for
     * cloud sync.
     *
     * @param id The route UUID to delete.
     * @throws IOException If the route file exists but cannot be deleted. The route then stays in
     *   the in-memory list, because it would reappear at the next [loadAll]. The deletion is still
     *   recorded, so the next cloud sync removes the route.
     */
    suspend fun delete(id: String) = withContext(Dispatchers.IO) {
        // Tombstone first: if the delete then fails, the next sync deletes the file anyway.
        syncState.recordDeletion(id)
        val file = File(storageDirectory, "$id.json")
        if (!file.delete() && file.exists()) {
            throw IOException("Failed to delete route file for route $id")
        }
        _routes.value = _routes.value.filterNot { it.id == id }
    }

    companion object {
        private const val ROUTES_DIR = "planned_routes"
    }
}
