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

import com.openhiker.core.model.RegionMetadata
import kotlinx.coroutines.flow.StateFlow

/**
 * Abstraction for region metadata operations.
 *
 * Provides the public API surface for [RegionRepository], enabling
 * unit testing of ViewModels without requiring an Android Context.
 * Production code uses [RegionRepository]; tests use a fake implementation.
 */
interface RegionDataSource {

    /** Observable list of all downloaded region metadata. */
    val regions: StateFlow<List<RegionMetadata>>

    /** File path for a region's MBTiles file. */
    fun mbtilesPath(regionId: String): String

    /** File path for a region's routing database. */
    fun routingDbPath(regionId: String): String

    /** Loads all region metadata from disk into the [regions] StateFlow. */
    suspend fun loadAll()

    /** Saves a new region's metadata and adds it to the in-memory list. */
    suspend fun save(metadata: RegionMetadata)

    /** Updates the name of an existing region. */
    suspend fun rename(regionId: String, newName: String)

    /** Deletes a region: removes metadata, MBTiles file, and routing database. */
    suspend fun delete(regionId: String)
}
