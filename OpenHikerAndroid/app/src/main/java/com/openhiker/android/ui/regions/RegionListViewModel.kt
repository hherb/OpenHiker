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

package com.openhiker.android.ui.regions

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.openhiker.android.data.repository.RegionRepository
import com.openhiker.core.model.RegionMetadata
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject

/**
 * Display information for a downloaded region in the list.
 *
 * Enriches [RegionMetadata] with computed fields like formatted file size
 * and area that require filesystem access.
 *
 * @property metadata The underlying region metadata.
 * @property fileSizeBytes Size of the MBTiles file on disk.
 * @property fileSizeFormatted Human-readable file size.
 * @property areaKm2 Approximate area in square kilometres.
 */
data class RegionDisplayItem(
    val metadata: RegionMetadata,
    val fileSizeBytes: Long,
    val fileSizeFormatted: String,
    val areaKm2: Double
)

/**
 * ViewModel for the region list and management screen.
 *
 * Provides the list of downloaded regions with computed display fields,
 * and supports rename, delete, and storage usage calculation.
 * All mutations are persisted through [RegionRepository].
 */
@HiltViewModel
class RegionListViewModel @Inject constructor(
    private val regionRepository: RegionRepository
) : ViewModel() {

    /** Observable list of all downloaded regions. */
    val regions: StateFlow<List<RegionMetadata>> = regionRepository.regions
        .stateIn(viewModelScope, SharingStarted.Lazily, emptyList())

    private val _renameDialogRegion = MutableStateFlow<RegionMetadata?>(null)
    /** Region currently being renamed, or null if no rename dialog is showing. */
    val renameDialogRegion: StateFlow<RegionMetadata?> = _renameDialogRegion.asStateFlow()

    private val _deleteDialogRegion = MutableStateFlow<RegionMetadata?>(null)
    /** Region pending deletion confirmation, or null if no delete dialog is showing. */
    val deleteDialogRegion: StateFlow<RegionMetadata?> = _deleteDialogRegion.asStateFlow()

    init {
        viewModelScope.launch {
            regionRepository.loadAll()
        }
    }

    /**
     * Builds a display item for a region by reading file size from disk.
     *
     * @param metadata The region metadata.
     * @return A [RegionDisplayItem] with computed display fields.
     */
    fun buildDisplayItem(metadata: RegionMetadata): RegionDisplayItem {
        val mbtilesFile = File(regionRepository.mbtilesPath(metadata.id))
        val fileSize = if (mbtilesFile.exists()) mbtilesFile.length() else 0L
        return RegionDisplayItem(
            metadata = metadata,
            fileSizeBytes = fileSize,
            fileSizeFormatted = formatFileSize(fileSize),
            areaKm2 = metadata.boundingBox.areaKm2
        )
    }

    /**
     * Calculates the total storage used by all downloaded regions.
     *
     * Sums the file sizes of all MBTiles and routing database files.
     *
     * @return Total storage in bytes.
     */
    fun totalStorageBytes(): Long {
        return regions.value.sumOf { metadata ->
            val mbtiles = File(regionRepository.mbtilesPath(metadata.id))
            val routing = File(regionRepository.routingDbPath(metadata.id))
            (if (mbtiles.exists()) mbtiles.length() else 0L) +
                (if (routing.exists()) routing.length() else 0L)
        }
    }

    /**
     * Shows the rename dialog for a region.
     *
     * @param region The region to rename.
     */
    fun showRenameDialog(region: RegionMetadata) {
        _renameDialogRegion.value = region
    }

    /**
     * Dismisses the rename dialog.
     */
    fun dismissRenameDialog() {
        _renameDialogRegion.value = null
    }

    /**
     * Renames a region and persists the change.
     *
     * @param regionId The region UUID to rename.
     * @param newName The new display name.
     */
    fun renameRegion(regionId: String, newName: String) {
        viewModelScope.launch {
            regionRepository.rename(regionId, newName)
            _renameDialogRegion.value = null
        }
    }

    /**
     * Shows the delete confirmation dialog for a region.
     *
     * @param region The region to potentially delete.
     */
    fun showDeleteDialog(region: RegionMetadata) {
        _deleteDialogRegion.value = region
    }

    /**
     * Dismisses the delete confirmation dialog.
     */
    fun dismissDeleteDialog() {
        _deleteDialogRegion.value = null
    }

    /**
     * Deletes a region: removes metadata, MBTiles file, and routing database.
     *
     * @param regionId The region UUID to delete.
     */
    fun deleteRegion(regionId: String) {
        viewModelScope.launch {
            regionRepository.delete(regionId)
            _deleteDialogRegion.value = null
        }
    }

    /**
     * Formats a byte count as a human-readable size string.
     *
     * @param bytes The size in bytes.
     * @return Formatted string like "15.2 MB" or "1.3 GB".
     */
    private fun formatFileSize(bytes: Long): String {
        val kb = bytes / 1024.0
        val mb = kb / 1024.0
        val gb = mb / 1024.0
        return when {
            gb >= 1.0 -> "%.1f GB".format(gb)
            mb >= 1.0 -> "%.1f MB".format(mb)
            kb >= 1.0 -> "%.1f KB".format(kb)
            else -> "$bytes B"
        }
    }
}
