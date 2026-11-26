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
import com.openhiker.android.data.repository.retryOnReadError
import com.openhiker.android.data.sync.SyncStateStore
import com.openhiker.android.service.sync.CloudDriveSyncEngine
import com.openhiker.android.service.sync.SyncWorker
import com.openhiker.core.model.TileServer
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.io.IOException
import javax.inject.Inject

/**
 * UI state for the settings screen.
 *
 * Combines user preferences with transient UI state (sync progress,
 * storage calculations, errors). The [preferences] field mirrors the
 * persisted [UserPreferences] while the remaining fields are ephemeral.
 *
 * @property preferences Current user preferences from DataStore.
 * @property isSyncing True while a sync runs, manual or in the background.
 * @property lastSuccessfulSync Epoch milliseconds of this device's last error-free sync, or 0.
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
    val lastSuccessfulSync: Long = 0L,
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
 * @param syncStateStore Source of the last error-free sync time.
 */
@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val application: Application,
    private val preferencesRepository: UserPreferencesRepository,
    private val syncEngine: CloudDriveSyncEngine,
    private val syncStateStore: SyncStateStore
) : ViewModel() {

    private val _uiState = MutableStateFlow(SettingsUiState())

    /** Observable UI state combining preferences with transient state. */
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    init {
        observePreferences()
        observeSyncStatus()
        calculateStorageSizes()
    }

    // ── Map Settings ─────────────────────────────────────────────

    /**
     * Sets the default tile server for map display.
     *
     * @param server The tile server to use as default.
     */
    fun setDefaultTileServer(server: TileServer) {
        saveSetting { preferencesRepository.setDefaultTileServer(server.id) }
    }

    // ── GPS Settings ─────────────────────────────────────────────

    /**
     * Sets the GPS accuracy mode controlling update frequency and power usage.
     *
     * @param mode The desired GPS accuracy/power trade-off.
     */
    fun setGpsAccuracyMode(mode: GpsAccuracyMode) {
        saveSetting { preferencesRepository.setGpsAccuracyMode(mode) }
    }

    // ── Navigation Settings ──────────────────────────────────────

    /**
     * Sets the display unit system (metric or imperial).
     *
     * @param unitSystem The unit system to use for distances and elevations.
     */
    fun setUnitSystem(unitSystem: UnitSystem) {
        saveSetting { preferencesRepository.setUnitSystem(unitSystem) }
    }

    /**
     * Toggles haptic feedback during turn-by-turn navigation.
     *
     * @param enabled True to enable vibrations, false to disable.
     */
    fun setHapticFeedbackEnabled(enabled: Boolean) {
        saveSetting { preferencesRepository.setHapticFeedbackEnabled(enabled) }
    }

    /**
     * Toggles audio cues as an alternative to haptic feedback.
     *
     * @param enabled True to enable audio cues for navigation events.
     */
    fun setAudioCuesEnabled(enabled: Boolean) {
        saveSetting { preferencesRepository.setAudioCuesEnabled(enabled) }
    }

    /**
     * Toggles keeping the screen on during active navigation.
     *
     * @param enabled True to prevent screen sleep during navigation.
     */
    fun setKeepScreenOnDuringNavigation(enabled: Boolean) {
        saveSetting { preferencesRepository.setKeepScreenOnDuringNavigation(enabled) }
    }

    // ── Download Settings ────────────────────────────────────────

    /**
     * Sets the default minimum zoom level for new tile downloads.
     *
     * @param zoom Minimum zoom level (valid range: 1-18).
     */
    fun setDefaultMinZoom(zoom: Int) {
        saveSetting {
            // The stored maximum, not the shown one, which may be a default (#115).
            val currentMax = preferencesRepository.preferencesFlow.first().defaultMaxZoom
            preferencesRepository.setDefaultMinZoom(zoom.coerceIn(1, currentMax))
        }
    }

    /**
     * Sets the default maximum zoom level for new tile downloads.
     *
     * Enforces that max zoom is never less than the current min zoom.
     *
     * @param zoom Maximum zoom level (valid range: 1-18).
     */
    fun setDefaultMaxZoom(zoom: Int) {
        saveSetting {
            // The stored minimum, not the shown one, which may be a default (#115).
            val currentMin = preferencesRepository.preferencesFlow.first().defaultMinZoom
            preferencesRepository.setDefaultMaxZoom(zoom.coerceIn(currentMin, 18))
        }
    }

    /**
     * Sets the maximum number of concurrent tile downloads.
     *
     * @param limit Parallel download count (valid range: 2-12).
     */
    fun setConcurrentDownloadLimit(limit: Int) {
        saveSetting { preferencesRepository.setConcurrentDownloadLimit(limit) }
    }

    // ── Cloud Sync Settings ──────────────────────────────────────

    /**
     * Sets the cloud sync folder from a SAF tree URI.
     *
     * Persists the URI, takes persistable permission, enables sync
     * with a scheduled WorkManager job, and syncs once right away.
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
            // Without it every later sync fails, so do not save the folder.
            Log.e(TAG, "Failed to take persistable URI permission", e)
            _uiState.value = _uiState.value.copy(
                error = "Cannot keep access to this folder: ${e.message}. Choose another folder."
            )
            return
        }

        saveSetting {
            preferencesRepository.setSyncFolderUri(uri.toString())
            preferencesRepository.setSyncEnabled(true)
            SyncWorker.schedule(application)

            _uiState.value = _uiState.value.copy(
                syncFolderDisplayName = uri.lastPathSegment ?: "Cloud folder"
            )
            // Sync now: schedule() keeps an existing periodic run, so the banner would show
            // the old "choose the folder again" error until the next period.
            runSync(uri)
        }
    }

    /**
     * Toggles automatic cloud sync on or off.
     *
     * When disabled, cancels the periodic WorkManager job and clears the
     * last sync's errors. When enabled,
     * schedules periodic sync (requires a folder to be configured).
     *
     * @param enabled True to enable, false to disable.
     */
    fun setSyncEnabled(enabled: Boolean) {
        saveSetting {
            preferencesRepository.setSyncEnabled(enabled)

            // Read the folder afresh: the shown settings may be defaults while the file could
            // not be read, and acting on them would cancel sync and clear its errors (#115).
            val folderUri = preferencesRepository.preferencesFlow.first().syncFolderUri
            if (enabled && folderUri != null) {
                SyncWorker.schedule(application)
            } else {
                SyncWorker.cancel(application)
                // No sync will clear them now, so the banner would stay on every tab.
                try {
                    syncStateStore.dismissErrors()
                } catch (e: IOException) {
                    Log.e(TAG, "Cannot clear the sync errors", e)
                    _uiState.value = _uiState.value.copy(
                        error = "Cannot clear the sync errors: ${e.message}"
                    )
                }
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
        _uiState.value = _uiState.value.copy(error = null)

        viewModelScope.launch {
            // Read afresh, as in setSyncEnabled, so unreadable settings are not taken for "no
            // folder".
            val folderUri = try {
                preferencesRepository.preferencesFlow.first().syncFolderUri
            } catch (e: IOException) {
                Log.e(TAG, "Cannot read the settings", e)
                _uiState.value = _uiState.value.copy(error = "Cannot read your settings: ${e.message}")
                return@launch
            }
            if (folderUri == null) {
                _uiState.value = _uiState.value.copy(error = "Please select a cloud folder first")
                return@launch
            }
            runSync(Uri.parse(folderUri))
        }
    }

    /**
     * Syncs [folderUri] now and reports the result via [SettingsUiState.lastSyncResult], or a
     * failure via [SettingsUiState.error].
     *
     * @param folderUri The SAF tree URI of the sync folder.
     */
    private suspend fun runSync(folderUri: Uri) {
        try {
            val result = syncEngine.sync(folderUri)
            _uiState.value = _uiState.value.copy(
                lastSyncResult = if (result.isSuccess) {
                    "Synced: ${result.uploaded} up, ${result.downloaded} down"
                } else {
                    "Sync errors: ${result.errors.joinToString("; ")}"
                }
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "Manual sync failed", e)
            _uiState.value = _uiState.value.copy(error = "Sync failed: ${e.message}")
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
     * Runs [action], which reads or writes the settings, and shows a read or write failure in
     * [SettingsUiState.error] instead of crashing (#115).
     *
     * @param action The settings change to make.
     */
    private fun saveSetting(action: suspend () -> Unit) {
        viewModelScope.launch {
            try {
                action()
            } catch (e: IOException) {
                Log.e(TAG, "Cannot save the setting", e)
                _uiState.value = _uiState.value.copy(error = "Cannot save the setting: ${e.message}")
            }
        }
    }

    /**
     * Observes the DataStore preferences flow and updates the UI state
     * whenever any preference changes. A read failure keeps the values shown and reads again
     * later; the sync banner reports it (#115).
     */
    private fun observePreferences() {
        viewModelScope.launch {
            preferencesRepository.preferencesFlow.retryOnReadError().collect { prefs ->
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
     * Mirrors the engine's running flag and the stored last-sync time into the UI state, so a
     * background sync shows here too.
     */
    private fun observeSyncStatus() {
        viewModelScope.launch {
            syncEngine.isSyncing.collect { syncing ->
                _uiState.value = _uiState.value.copy(isSyncing = syncing)
            }
        }
        viewModelScope.launch {
            syncStateStore.state.collect { state ->
                _uiState.value = _uiState.value.copy(
                    lastSuccessfulSync = state?.lastSyncTimestamp ?: 0L
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
