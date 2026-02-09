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
import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.openhiker.android.service.sync.CloudDriveSyncEngine
import com.openhiker.android.service.sync.SyncWorker
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI state for the settings screen.
 *
 * @property syncEnabled Whether cloud sync is enabled.
 * @property syncFolderUri The configured cloud folder URI, or null.
 * @property syncFolderName Display name of the sync folder.
 * @property isSyncing True while a manual sync is in progress.
 * @property lastSyncResult Human-readable result of the last sync.
 * @property error Error message for display, or null.
 */
data class SettingsUiState(
    val syncEnabled: Boolean = false,
    val syncFolderUri: String? = null,
    val syncFolderName: String = "Not configured",
    val isSyncing: Boolean = false,
    val lastSyncResult: String? = null,
    val error: String? = null
)

/**
 * ViewModel for the settings screen.
 *
 * Manages cloud sync configuration: enabling/disabling sync, selecting
 * the cloud folder, and triggering manual sync operations.
 *
 * @param application Application context for SharedPreferences and WorkManager.
 * @param syncEngine Cloud drive sync engine for manual sync operations.
 */
@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val application: Application,
    private val syncEngine: CloudDriveSyncEngine
) : ViewModel() {

    private val _uiState = MutableStateFlow(SettingsUiState())

    /** Observable UI state. */
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    init {
        loadSyncSettings()
    }

    /**
     * Sets the cloud sync folder from a SAF tree URI.
     *
     * Persists the URI in SharedPreferences and schedules periodic sync.
     *
     * @param uri The SAF tree URI selected by the user.
     */
    fun setSyncFolder(uri: Uri) {
        val prefs = application.getSharedPreferences(SyncWorker.PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(SyncWorker.PREF_SYNC_FOLDER_URI, uri.toString())
            .apply()

        // Take persistable URI permission
        try {
            application.contentResolver.takePersistableUriPermission(
                uri,
                android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to take persistable URI permission", e)
        }

        _uiState.value = _uiState.value.copy(
            syncFolderUri = uri.toString(),
            syncFolderName = uri.lastPathSegment ?: "Cloud folder",
            syncEnabled = true
        )

        SyncWorker.schedule(application)
    }

    /**
     * Toggles cloud sync on or off.
     *
     * When disabled, cancels the periodic WorkManager job.
     * When enabled, schedules the periodic sync (requires a folder to be set).
     *
     * @param enabled True to enable, false to disable.
     */
    fun setSyncEnabled(enabled: Boolean) {
        _uiState.value = _uiState.value.copy(syncEnabled = enabled)

        if (enabled && _uiState.value.syncFolderUri != null) {
            SyncWorker.schedule(application)
        } else {
            SyncWorker.cancel(application)
        }

        val prefs = application.getSharedPreferences(SyncWorker.PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putBoolean(PREF_SYNC_ENABLED, enabled).apply()
    }

    /**
     * Triggers a manual sync operation immediately.
     */
    fun syncNow() {
        val folderUri = _uiState.value.syncFolderUri ?: run {
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

    /**
     * Clears the error message after display.
     */
    fun clearError() {
        _uiState.value = _uiState.value.copy(error = null)
    }

    /** Loads saved sync preferences on init. */
    private fun loadSyncSettings() {
        val prefs = application.getSharedPreferences(SyncWorker.PREFS_NAME, Context.MODE_PRIVATE)
        val folderUri = prefs.getString(SyncWorker.PREF_SYNC_FOLDER_URI, null)
        val enabled = prefs.getBoolean(PREF_SYNC_ENABLED, false)

        _uiState.value = SettingsUiState(
            syncEnabled = enabled,
            syncFolderUri = folderUri,
            syncFolderName = folderUri?.let { Uri.parse(it).lastPathSegment } ?: "Not configured"
        )
    }

    companion object {
        private const val TAG = "SettingsVM"
        private const val PREF_SYNC_ENABLED = "sync_enabled"
    }
}
