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

package com.openhiker.android.ui.sync

import android.net.Uri
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.openhiker.android.data.repository.UserPreferencesRepository
import com.openhiker.android.data.sync.SyncState
import com.openhiker.android.data.sync.SyncStateStore
import com.openhiker.android.service.sync.CloudDriveSyncEngine
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * What the sync banner above every tab shows.
 *
 * @property messages Lines to show; the banner is hidden when this is empty.
 * @property isSyncing True while a sync runs: the banner shows a spinner instead of "Retry".
 * @property canRetry True when the last sync failed and a sync folder is set, so "Retry" can run.
 */
data class SyncBannerState(
    val messages: List<String> = emptyList(),
    val isSyncing: Boolean = false,
    val canRetry: Boolean = false
)

/**
 * Builds the banner lines from the stored sync state (#72).
 *
 * The last sync's errors come first, under a heading. The reset notice follows: it is not a
 * sync error, so it does not hold back the last-sync time, but it stays until dismissed.
 * [actionError] is a failure of the banner's own Retry or Dismiss.
 *
 * @param state The stored sync state, or null before it was first read.
 * @param actionError The last Retry or Dismiss failure, or null.
 * @return The lines to show, empty when there is nothing to report.
 */
internal fun syncBannerMessages(state: SyncState?, actionError: String?): List<String> = buildList {
    val errors = state?.lastErrors.orEmpty()
    if (errors.isNotEmpty()) add(SYNC_FAILED_HEADING)
    addAll(errors)
    if (state?.stateWasReset == true) add(STATE_RESET_NOTICE)
    actionError?.let { add(it) }
}

/** Heading above the last sync's errors. */
internal const val SYNC_FAILED_HEADING = "Cloud sync failed:"

/** Shown after a corrupt sync state file was replaced by a fresh one. */
internal const val STATE_RESET_NOTICE =
    "This device's sync records were damaged and have been reset. Items you deleted before " +
        "the next sync may come back; delete them again."

/**
 * Backs the sync banner shown above every tab, the Android counterpart of Apple's
 * `CloudSyncErrorBanner` (#72).
 *
 * The errors come from [SyncStateStore], where every sync, background or "Sync now", records
 * them, so a background failure shows the next time the app is open.
 *
 * @param syncEngine Runs the sync for "Retry" and reports whether a sync is running.
 * @param syncStateStore Holds the last sync's errors and the reset notice.
 * @param preferencesRepository Source of the sync folder URI.
 */
@HiltViewModel
class SyncStatusViewModel @Inject constructor(
    private val syncEngine: CloudDriveSyncEngine,
    private val syncStateStore: SyncStateStore,
    private val preferencesRepository: UserPreferencesRepository
) : ViewModel() {

    private val actionError = MutableStateFlow<String?>(null)

    /** The banner's content; empty messages hide it. */
    val bannerState: StateFlow<SyncBannerState> = combine(
        syncStateStore.state,
        syncEngine.isSyncing,
        preferencesRepository.preferencesFlow,
        actionError
    ) { state, syncing, prefs, error ->
        SyncBannerState(
            messages = syncBannerMessages(state, error),
            isSyncing = syncing,
            canRetry = state?.lastErrors?.isNotEmpty() == true && prefs.syncFolderUri != null
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(STOP_TIMEOUT_MS), SyncBannerState())

    init {
        // The store publishes its state only once read; a background sync may have failed
        // while the app was closed.
        viewModelScope.launch {
            runReporting("Cannot read the sync status") { syncStateStore.load() }
        }
    }

    /** Runs a sync of the configured folder again; the result reaches the banner via the store. */
    fun retry() {
        viewModelScope.launch {
            val folderUri = preferencesRepository.preferencesFlow.first().syncFolderUri
                ?: return@launch
            runReporting("Sync failed") { syncEngine.sync(Uri.parse(folderUri)) }
        }
    }

    /** Hides the errors and the reset notice until a later sync fails again. */
    fun dismiss() {
        viewModelScope.launch {
            runReporting("Cannot dismiss the sync errors") { syncStateStore.dismissErrors() }
        }
    }

    /**
     * Runs [action], clearing any earlier [actionError] first, and shows a failure in the banner.
     *
     * @param what Prefix for the banner line, saying what failed.
     * @param action The work to run.
     */
    private suspend fun runReporting(what: String, action: suspend () -> Unit) {
        actionError.value = null
        try {
            action()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, what, e)
            actionError.value = "$what: ${e.message}"
        }
    }

    private companion object {
        const val TAG = "SyncStatusVM"

        /** Keeps the banner flow alive briefly across configuration changes. */
        const val STOP_TIMEOUT_MS = 5_000L
    }
}
