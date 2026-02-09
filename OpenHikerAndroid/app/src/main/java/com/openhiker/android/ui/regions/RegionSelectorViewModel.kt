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
import com.openhiker.android.service.download.TileDownloadService
import com.openhiker.core.geo.BoundingBox
import com.openhiker.core.geo.TileRange
import com.openhiker.core.model.RegionDownloadProgress
import com.openhiker.core.model.TileServer
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI state for the region selector screen.
 *
 * @property selectedBounds The user-selected geographic area, or null if no selection yet.
 * @property minZoom Minimum zoom level for tile download.
 * @property maxZoom Maximum zoom level for tile download.
 * @property tileServer Selected tile server for download.
 * @property estimatedTileCount Calculated tile count for the current selection.
 * @property regionName User-entered name for the region.
 * @property showConfirmDialog Whether the download confirmation dialog is showing.
 */
data class RegionSelectorUiState(
    val selectedBounds: BoundingBox? = null,
    val minZoom: Int = DEFAULT_MIN_ZOOM,
    val maxZoom: Int = DEFAULT_MAX_ZOOM,
    val tileServer: TileServer = TileServer.OPEN_TOPO_MAP,
    val estimatedTileCount: Int = 0,
    val regionName: String = "",
    val showConfirmDialog: Boolean = false
) {
    /**
     * Estimated download size assuming average tile size of 30 KB.
     *
     * @return Formatted size string like "15.2 MB".
     */
    val estimatedSizeFormatted: String
        get() {
            val sizeBytes = estimatedTileCount * AVERAGE_TILE_SIZE_BYTES
            val mb = sizeBytes / (1024.0 * 1024.0)
            return if (mb >= 1024) {
                "%.1f GB".format(mb / 1024.0)
            } else {
                "%.1f MB".format(mb)
            }
        }

    companion object {
        const val DEFAULT_MIN_ZOOM = 12
        const val DEFAULT_MAX_ZOOM = 16
        /** Average PNG tile size in bytes for size estimation. */
        private const val AVERAGE_TILE_SIZE_BYTES = 30_000L
    }
}

/**
 * ViewModel for the region selection and download screen.
 *
 * Manages the region selection bounds, zoom range configuration,
 * tile count estimation, and download initiation. The tile count
 * is recalculated in real time as the user adjusts the selection
 * or zoom range.
 *
 * Downloads are delegated to [TileDownloadService] which reports
 * progress via a StateFlow. The ViewModel observes this progress
 * to update the UI.
 */
@HiltViewModel
class RegionSelectorViewModel @Inject constructor(
    private val downloadService: TileDownloadService
) : ViewModel() {

    private val _uiState = MutableStateFlow(RegionSelectorUiState())
    /** Current UI state for the region selector. */
    val uiState: StateFlow<RegionSelectorUiState> = _uiState.asStateFlow()

    /** Download progress from the tile download service. */
    val downloadProgress: StateFlow<RegionDownloadProgress?> = downloadService.progress
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(), null)

    /** Whether a download is currently in progress. */
    val isDownloading: StateFlow<Boolean> = downloadService.isDownloading
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(), false)

    private var downloadJob: Job? = null

    /**
     * Updates the selected geographic bounds and recalculates tile count.
     *
     * Called when the user completes a drag-to-select gesture or when
     * the selection snaps to a default region.
     *
     * @param bounds The new geographic bounds.
     */
    fun updateBounds(bounds: BoundingBox) {
        val current = _uiState.value
        val tileCount = TileRange.estimateTileCount(
            bounds,
            current.minZoom..current.maxZoom
        )
        _uiState.value = current.copy(
            selectedBounds = bounds,
            estimatedTileCount = tileCount
        )
    }

    /**
     * Updates the zoom level range and recalculates tile count.
     *
     * @param minZoom New minimum zoom level.
     * @param maxZoom New maximum zoom level.
     */
    fun updateZoomRange(minZoom: Int, maxZoom: Int) {
        val current = _uiState.value
        val tileCount = current.selectedBounds?.let { bounds ->
            TileRange.estimateTileCount(bounds, minZoom..maxZoom)
        } ?: 0
        _uiState.value = current.copy(
            minZoom = minZoom,
            maxZoom = maxZoom,
            estimatedTileCount = tileCount
        )
    }

    /**
     * Updates the selected tile server for download.
     *
     * @param server The tile server to use for downloading.
     */
    fun updateTileServer(server: TileServer) {
        _uiState.value = _uiState.value.copy(tileServer = server)
    }

    /**
     * Updates the user-entered region name.
     *
     * @param name The new region name.
     */
    fun updateRegionName(name: String) {
        _uiState.value = _uiState.value.copy(regionName = name)
    }

    /**
     * Shows the download confirmation dialog.
     */
    fun showConfirmDialog() {
        _uiState.value = _uiState.value.copy(showConfirmDialog = true)
    }

    /**
     * Dismisses the download confirmation dialog.
     */
    fun dismissConfirmDialog() {
        _uiState.value = _uiState.value.copy(showConfirmDialog = false)
    }

    /**
     * Starts downloading tiles for the selected region.
     *
     * Delegates to [TileDownloadService] which handles rate limiting,
     * retry logic, and progress reporting. The download runs in a
     * coroutine scope that can be cancelled.
     */
    fun startDownload() {
        val state = _uiState.value
        val bounds = state.selectedBounds ?: return
        val name = state.regionName.ifBlank { "Region" }

        _uiState.value = state.copy(showConfirmDialog = false)

        downloadJob = viewModelScope.launch {
            downloadService.downloadRegion(
                name = name,
                boundingBox = bounds,
                minZoom = state.minZoom,
                maxZoom = state.maxZoom,
                tileServer = state.tileServer
            )
        }
    }

    /**
     * Cancels the current download.
     */
    fun cancelDownload() {
        downloadJob?.cancel()
        downloadJob = null
    }
}
