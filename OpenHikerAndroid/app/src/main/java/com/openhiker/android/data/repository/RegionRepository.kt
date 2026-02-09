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
import android.util.Log
import com.openhiker.core.model.RegionMetadata
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
 * Repository for managing downloaded map region metadata.
 *
 * Region metadata is persisted as a JSON array in `regions_metadata.json`
 * within the app's internal files directory. MBTiles tile files and routing
 * databases are stored in `regions/` subdirectory.
 *
 * This repository manages the metadata only; tile data is handled by
 * [com.openhiker.android.data.db.tiles.TileStore] and
 * [com.openhiker.android.data.db.tiles.WritableTileStore].
 */
@Singleton
class RegionRepository @Inject constructor(
    @ApplicationContext private val context: Context
) : RegionDataSource {
    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
    }

    private val _regions = MutableStateFlow<List<RegionMetadata>>(emptyList())

    /** Observable list of all downloaded region metadata. */
    override val regions: StateFlow<List<RegionMetadata>> = _regions.asStateFlow()

    /** Directory for storing region MBTiles and routing database files. */
    val regionsDirectory: File
        get() = File(context.filesDir, REGIONS_DIR).also { it.mkdirs() }

    /** File path for a region's MBTiles file. */
    override fun mbtilesPath(regionId: String): String =
        File(regionsDirectory, "$regionId.mbtiles").absolutePath

    /** File path for a region's routing database. */
    override fun routingDbPath(regionId: String): String =
        File(regionsDirectory, "$regionId.routing.db").absolutePath

    /**
     * Loads all region metadata from the JSON file on disk.
     *
     * Should be called at app startup to populate the [regions] StateFlow.
     */
    override suspend fun loadAll() = withContext(Dispatchers.IO) {
        val file = metadataFile()
        if (file.exists()) {
            try {
                val content = file.readText()
                val metadata = json.decodeFromString<List<RegionMetadata>>(content)
                _regions.value = metadata
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load region metadata from disk", e)
                _regions.value = emptyList()
            }
        }
    }

    /**
     * Saves a new region's metadata and adds it to the in-memory list.
     *
     * @param metadata The region metadata to save.
     */
    override suspend fun save(metadata: RegionMetadata) = withContext(Dispatchers.IO) {
        val current = _regions.value.toMutableList()
        current.removeAll { it.id == metadata.id }
        current.add(metadata)
        _regions.value = current
        persistMetadata(current)
    }

    /**
     * Updates the name of an existing region.
     *
     * @param regionId The region UUID.
     * @param newName The new display name.
     */
    override suspend fun rename(regionId: String, newName: String) = withContext(Dispatchers.IO) {
        val current = _regions.value.map { region ->
            if (region.id == regionId) region.copy(name = newName)
            else region
        }
        _regions.value = current
        persistMetadata(current)
    }

    /**
     * Deletes a region: removes metadata, MBTiles file, and routing database.
     *
     * @param regionId The region UUID to delete.
     */
    override suspend fun delete(regionId: String) = withContext(Dispatchers.IO) {
        val current = _regions.value.filterNot { it.id == regionId }
        _regions.value = current
        persistMetadata(current)

        // Delete associated files
        if (!File(mbtilesPath(regionId)).delete()) {
            Log.w(TAG, "Failed to delete MBTiles file for region $regionId")
        }
        if (!File(routingDbPath(regionId)).delete()) {
            Log.w(TAG, "Failed to delete routing database for region $regionId")
        }
    }

    /**
     * Writes the metadata list to disk as JSON.
     *
     * Logs an error if the write fails but does not propagate the exception,
     * since the in-memory state has already been updated.
     */
    private fun persistMetadata(metadata: List<RegionMetadata>) {
        try {
            val file = metadataFile()
            file.writeText(json.encodeToString(metadata))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to persist region metadata to disk", e)
        }
    }

    /** Returns the metadata JSON file, creating the parent directory if needed. */
    private fun metadataFile(): File {
        context.filesDir.mkdirs()
        return File(context.filesDir, METADATA_FILENAME)
    }

    companion object {
        private const val TAG = "RegionRepository"
        private const val METADATA_FILENAME = "regions_metadata.json"
        private const val REGIONS_DIR = "regions"
    }
}
