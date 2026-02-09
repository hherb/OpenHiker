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

package com.openhiker.android.testutil

import com.openhiker.android.data.repository.RegionDataSource
import com.openhiker.core.model.RegionMetadata
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File

/**
 * Fake implementation of [RegionDataSource] for unit testing.
 *
 * All data is stored in-memory. File path methods return paths within the
 * provided [tempDir] so that tests can create actual files for size checks.
 *
 * @param tempDir Temporary directory used by file path methods.
 */
class FakeRegionDataSource(
    private val tempDir: File
) : RegionDataSource {

    private val _regions = MutableStateFlow<List<RegionMetadata>>(emptyList())

    override val regions: StateFlow<List<RegionMetadata>> = _regions.asStateFlow()

    /** Directory mirroring the real regions directory structure. */
    val regionsDir: File
        get() = File(tempDir, "regions").also { it.mkdirs() }

    override fun mbtilesPath(regionId: String): String =
        File(regionsDir, "$regionId.mbtiles").absolutePath

    override fun routingDbPath(regionId: String): String =
        File(regionsDir, "$regionId.routing.db").absolutePath

    override suspend fun loadAll() {
        // No-op — data is set directly via setRegions() in tests.
    }

    override suspend fun save(metadata: RegionMetadata) {
        val current = _regions.value.toMutableList()
        current.removeAll { it.id == metadata.id }
        current.add(metadata)
        _regions.value = current
    }

    override suspend fun rename(regionId: String, newName: String) {
        _regions.value = _regions.value.map { region ->
            if (region.id == regionId) region.copy(name = newName)
            else region
        }
    }

    override suspend fun delete(regionId: String) {
        _regions.value = _regions.value.filterNot { it.id == regionId }
        File(mbtilesPath(regionId)).delete()
        File(routingDbPath(regionId)).delete()
    }

    /**
     * Test helper: directly sets the in-memory region list.
     *
     * @param regions The regions to populate.
     */
    fun setRegions(regions: List<RegionMetadata>) {
        _regions.value = regions
    }

    /**
     * Test helper: creates a fake MBTiles file of the specified size.
     *
     * @param regionId The region ID to create a file for.
     * @param sizeBytes The desired file size in bytes.
     */
    fun createMbtilesFile(regionId: String, sizeBytes: Long) {
        val file = File(mbtilesPath(regionId))
        file.parentFile?.mkdirs()
        file.writeBytes(ByteArray(sizeBytes.toInt()))
    }

    /**
     * Test helper: creates a fake routing database file of the specified size.
     *
     * @param regionId The region ID to create a file for.
     * @param sizeBytes The desired file size in bytes.
     */
    fun createRoutingFile(regionId: String, sizeBytes: Long) {
        val file = File(routingDbPath(regionId))
        file.parentFile?.mkdirs()
        file.writeBytes(ByteArray(sizeBytes.toInt()))
    }
}
