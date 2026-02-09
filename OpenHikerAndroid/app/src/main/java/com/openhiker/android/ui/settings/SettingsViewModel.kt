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

package com.openhiker.android.ui.settings

import android.app.Application
import android.net.Uri
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.openhiker.android.data.repository.GpsAccuracyMode
import com.openhiker.android.data.repository.UnitSystem
import com.openhiker.android.data.repository.UserPreferences
import com.openhiker.android.data.repository.UserPreferencesRepository
import com.openhiker.android.service.sync.CloudDriveSyncEngine
import com.openhiker.android.service.sync.SyncWorker
import com.openhiker.core.model.TileServer
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI state for the settings screen.
 *
 * Combines user preferences with transient UI state (sync progress,
 * storage calculations, errors). The [preferences] field mirrors the
 * persisted [UserPreferences] while the remaining fields are ephemeral.
 *
 * @property preferences Current user preferences from DataStore.
 * @property isSyncing True while a manual sync operation is running.
 * @property lastSyncResult Human-readable result of the last sync operation.
 * @property elevationCacheSizeBytes Size of cached elevation HGT files.
 * @property osmCacheSizeBytes Size of cached OSM XML data.
 * @property totalRegionSizeBytes Total size of all downloaded MBTiles regions.
 * @property error Error message for snackbar display, or null.
 * @property syncFolderDisplayName Display name of the selected sync folder.
 */
data class SettingsUiState(
    val preferences: UserPreferences = UserPreferences(),
    val isSyncing: Boolean = false,
    val lastSyncResult: String? = null,
    val elevationCacheSizeBytes: Long = 0L,
    val osmCacheSizeBytes: Long = 0L,
    val totalRegionSizeBytes: Long = 0L,
    val error: String? = null,
    val syncFolderDisplayName: String = "Not configured"
)

/**
 * ViewModel for the settings screen.
 *
 * Manages all user preferences via [UserPreferencesRepository] (DataStore)
 * and handles cloud sync operations. Settings changes are persisted
 * immediately and propagated reactively to all consumers via Flow.
 *
 * Sections managed:
 * - Map: default tile server
 * - GPS: accuracy mode
 * - Navigation: unit system, haptic feedback, audio cues, screen-on
 * - Downloads: default zoom range, concurrent download limit
 * - Cloud Sync: folder selection, enable/disable, manual sync
 * - Storage: cache sizes, clear operations
 * - About: version info and license
 *
 * @param application Application context for file system access and WorkManager.
 * @param preferencesRepository DataStore-backed preferences persistence.
 * @param syncEngine Cloud drive sync engine for manual sync operations.
 */
@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val application: Application,
    private val preferencesRepository: UserPreferencesRepository,
    private val syncEngine: CloudDriveSyncEngine
) : ViewModel() {

    private val _uiState = MutableStateFlow(SettingsUiState())

    /** Observable UI state combining preferences with transient state. */
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    /** Observable user preferences for direct consumption by other screens. */
    val preferences: StateFlow<UserPreferences> = preferencesRepository.preferencesFlow
        .stateIn(viewModelScope, SharingStarted.Eagerly, UserPreferences())

    init {
        observePreferences()
        calculateStorageSizes()
    }

    // ── Map Settings ─────────────────────────────────────────────

    /**
     * Sets the default tile server for map display.
     *
     * @param server The tile server to use as default.
     */
    fun setDefaultTileServer(server: TileServer) {
        viewModelScope.launch {
            preferencesRepository.setDefaultTileServer(server.id)
        }
    }

    // ── GPS Settings ─────────────────────────────────────────────

    /**
     * Sets the GPS accuracy mode controlling update frequency and power usage.
     *
     * @param mode The desired GPS accuracy/power trade-off.
     */
    fun setGpsAccuracyMode(mode: GpsAccuracyMode) {
        viewModelScope.launch {
            preferencesRepository.setGpsAccuracyMode(mode)
        }
    }

    // ── Navigation Settings ──────────────────────────────────────

    /**
     * Sets the display unit system (metric or imperial).
     *
     * @param unitSystem The unit system to use for distances and elevations.
     */
    fun setUnitSystem(unitSystem: UnitSystem) {
        viewModelScope.launch {
            preferencesRepository.setUnitSystem(unitSystem)
        }
    }

    /**
     * Toggles haptic feedback during turn-by-turn navigation.
     *
     * @param enabled True to enable vibrations, false to disable.
     */
    fun setHapticFeedbackEnabled(enabled: Boolean) {
        viewModelScope.launch {
            preferencesRepository.setHapticFeedbackEnabled(enabled)
        }
    }

    /**
     * Toggles audio cues as an alternative to haptic feedback.
     *
     * @param enabled True to enable audio cues for navigation events.
     */
    fun setAudioCuesEnabled(enabled: Boolean) {
        viewModelScope.launch {
            preferencesRepository.setAudioCuesEnabled(enabled)
        }
    }

    /**
     * Toggles keeping the screen on during active navigation.
     *
     * @param enabled True to prevent screen sleep during navigation.
     */
    fun setKeepScreenOnDuringNavigation(enabled: Boolean) {
        viewModelScope.launch {
            preferencesRepository.setKeepScreenOnDuringNavigation(enabled)
        }
    }

    // ── Download Settings ────────────────────────────────────────

    /**
     * Sets the default minimum zoom level for new tile downloads.
     *
     * @param zoom Minimum zoom level (valid range: 1-18).
     */
    fun setDefaultMinZoom(zoom: Int) {
        viewModelScope.launch {
            preferencesRepository.setDefaultMinZoom(zoom.coerceIn(1, 18))
        }
    }

    /**
     * Sets the default maximum zoom level for new tile downloads.
     *
     * @param zoom Maximum zoom level (valid range: 1-18).
     */
    fun setDefaultMaxZoom(zoom: Int) {
        viewModelScope.launch {
            preferencesRepository.setDefaultMaxZoom(zoom.coerceIn(1, 18))
        }
    }

    /**
     * Sets the maximum number of concurrent tile downloads.
     *
     * @param limit Parallel download count (valid range: 2-12).
     */
    fun setConcurrentDownloadLimit(limit: Int) {
        viewModelScope.launch {
            preferencesRepository.setConcurrentDownloadLimit(limit)
        }
    }

    // ── Cloud Sync Settings ──────────────────────────────────────

    /**
     * Sets the cloud sync folder from a SAF tree URI.
     *
     * Persists the URI, takes persistable permission, and enables sync
     * with a scheduled WorkManager job.
     *
     * @param uri The SAF tree URI selected by the user.
     */
    fun setSyncFolder(uri: Uri) {
        // Take persistable URI permission for access across app restarts
        try {
            application.contentResolver.takePersistableUriPermission(
                uri,
                android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to take persistable URI permission", e)
        }

        viewModelScope.launch {
            preferencesRepository.setSyncFolderUri(uri.toString())
            preferencesRepository.setSyncEnabled(true)
            SyncWorker.schedule(application)

            _uiState.value = _uiState.value.copy(
                syncFolderDisplayName = uri.lastPathSegment ?: "Cloud folder"
            )
        }
    }

    /**
     * Toggles automatic cloud sync on or off.
     *
     * When disabled, cancels the periodic WorkManager job. When enabled,
     * schedules periodic sync (requires a folder to be configured).
     *
     * @param enabled True to enable, false to disable.
     */
    fun setSyncEnabled(enabled: Boolean) {
        viewModelScope.launch {
            preferencesRepository.setSyncEnabled(enabled)

            if (enabled && _uiState.value.preferences.syncFolderUri != null) {
                SyncWorker.schedule(application)
            } else {
                SyncWorker.cancel(application)
            }
        }
    }

    /**
     * Triggers a manual sync operation immediately.
     *
     * Runs the sync engine directly (not via WorkManager) and reports
     * the result via [SettingsUiState.lastSyncResult].
     */
    fun syncNow() {
        val folderUri = _uiState.value.preferences.syncFolderUri ?: run {
            _uiState.value = _uiState.value.copy(error = "Please select a cloud folder first")
            return
        }

        _uiState.value = _uiState.value.copy(isSyncing = true, error = null)

        viewModelScope.launch {
            try {
                val result = syncEngine.sync(Uri.parse(folderUri))
                _uiState.value = _uiState.value.copy(
                    isSyncing = false,
                    lastSyncResult = if (result.isSuccess) {
                        "Synced: ${result.uploaded} up, ${result.downloaded} down"
                    } else {
                        "Sync errors: ${result.errors.joinToString("; ")}"
                    }
                )
            } catch (e: Exception) {
                Log.e(TAG, "Manual sync failed", e)
                _uiState.value = _uiState.value.copy(
                    isSyncing = false,
                    error = "Sync failed: ${e.message}"
                )
            }
        }
    }

    // ── Storage Management ───────────────────────────────────────

    /**
     * Deletes all cached elevation HGT files to free storage.
     */
    fun clearElevationCache() {
        viewModelScope.launch {
            try {
                val elevationDir = java.io.File(application.filesDir, "elevation")
                if (elevationDir.exists()) {
                    elevationDir.listFiles()?.forEach { it.delete() }
                }
                calculateStorageSizes()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clear elevation cache", e)
                _uiState.value = _uiState.value.copy(
                    error = "Failed to clear elevation cache: ${e.message}"
                )
            }
        }
    }

    /**
     * Deletes all cached OSM XML data to free storage.
     */
    fun clearOsmCache() {
        viewModelScope.launch {
            try {
                val osmDir = java.io.File(application.filesDir, "osm")
                if (osmDir.exists()) {
                    osmDir.listFiles()?.forEach { it.delete() }
                }
                calculateStorageSizes()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clear OSM cache", e)
                _uiState.value = _uiState.value.copy(
                    error = "Failed to clear OSM cache: ${e.message}"
                )
            }
        }
    }

    // ── Error Handling ───────────────────────────────────────────

    /**
     * Clears the error message after it has been displayed.
     */
    fun clearError() {
        _uiState.value = _uiState.value.copy(error = null)
    }

    // ── Private Helpers ──────────────────────────────────────────

    /**
     * Observes the DataStore preferences flow and updates the UI state
     * whenever any preference changes.
     */
    private fun observePreferences() {
        viewModelScope.launch {
            preferencesRepository.preferencesFlow.collect { prefs ->
                _uiState.value = _uiState.value.copy(
                    preferences = prefs,
                    syncFolderDisplayName = prefs.syncFolderUri?.let { uriString ->
                        Uri.parse(uriString).lastPathSegment ?: "Cloud folder"
                    } ?: "Not configured"
                )
            }
        }
    }

    /**
     * Calculates the sizes of cached data directories for the storage section.
     */
    private fun calculateStorageSizes() {
        viewModelScope.launch {
            val elevationSize = directorySize(java.io.File(application.filesDir, "elevation"))
            val osmSize = directorySize(java.io.File(application.filesDir, "osm"))
            val regionsSize = directorySize(java.io.File(application.filesDir, "regions"))

            _uiState.value = _uiState.value.copy(
                elevationCacheSizeBytes = elevationSize,
                osmCacheSizeBytes = osmSize,
                totalRegionSizeBytes = regionsSize
            )
        }
    }

    companion object {
        private const val TAG = "SettingsVM"

        /**
         * Calculates the total size of all files in a directory.
         *
         * @param dir The directory to measure.
         * @return Total size in bytes, or 0 if the directory doesn't exist.
         */
        fun directorySize(dir: java.io.File): Long {
            if (!dir.exists() || !dir.isDirectory) return 0L
            return dir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
        }
    }
}
