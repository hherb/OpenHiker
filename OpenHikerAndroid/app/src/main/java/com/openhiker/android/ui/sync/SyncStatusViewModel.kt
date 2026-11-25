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
import com.openhiker.android.data.repository.PlannedRouteRepository
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
 * @property canRetry True when "Retry" can run; see [canRetry].
 * @property unreadableRouteFiles Names of planned-route files that cannot be read; the banner
 *   offers to delete them when this is not empty.
 */
data class SyncBannerState(
    val messages: List<String> = emptyList(),
    val isSyncing: Boolean = false,
    val canRetry: Boolean = false,
    val unreadableRouteFiles: List<String> = emptyList()
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

/**
 * Whether the banner offers "Retry": only after a failed sync, while sync is on and a folder is
 * set. The reset notice alone is not a failure, so it offers no Retry.
 *
 * @param state The stored sync state, or null before it was first read.
 * @param syncEnabled Whether the user has sync turned on.
 * @param folderUri The sync folder URI, or null if none is set.
 * @return True if "Retry" should show.
 */
internal fun canRetry(state: SyncState?, syncEnabled: Boolean, folderUri: String?): Boolean =
    state?.lastErrors?.isNotEmpty() == true && syncEnabled && folderUri != null

/** What the banner does after deleting unreadable planned-route files. */
internal enum class AfterRouteFileDelete {
    /** Sync, so the errors clear and any cloud copy of the routes comes back. */
    SYNC,

    /** Clear the stored errors: no sync can replace them, and the files are gone. */
    CLEAR_ERRORS,

    /** Leave the stored errors: some files are still there. */
    NOTHING
}

/**
 * Chooses what follows a delete of unreadable route files (#77, #104). It syncs only with sync
 * on and a folder set (#107), and after a partial failure too, as some files may be gone.
 *
 * @param allDeleted Whether every confirmed file was deleted.
 * @param syncEnabled Whether the user has sync turned on.
 * @param folderUri The sync folder URI, or null if none is set.
 * @return The step to run next.
 */
internal fun afterRouteFileDelete(
    allDeleted: Boolean,
    syncEnabled: Boolean,
    folderUri: String?
): AfterRouteFileDelete = when {
    syncEnabled && folderUri != null -> AfterRouteFileDelete.SYNC
    allDeleted -> AfterRouteFileDelete.CLEAR_ERRORS
    else -> AfterRouteFileDelete.NOTHING
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
    private val preferencesRepository: UserPreferencesRepository,
    private val plannedRouteRepository: PlannedRouteRepository
) : ViewModel() {

    private val actionError = MutableStateFlow<String?>(null)

    /** The banner's content; empty messages hide it. */
    val bannerState: StateFlow<SyncBannerState> = combine(
        syncStateStore.state,
        syncEngine.isSyncing,
        preferencesRepository.preferencesFlow,
        actionError,
        plannedRouteRepository.skippedFiles
    ) { state, syncing, prefs, error, skipped ->
        SyncBannerState(
            messages = syncBannerMessages(state, error),
            isSyncing = syncing,
            canRetry = canRetry(state, prefs.syncEnabled, prefs.syncFolderUri),
            unreadableRouteFiles = skipped.map { it.fileName }
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(STOP_TIMEOUT_MS), SyncBannerState())

    init {
        // The store publishes its state only once read; a background sync may have failed
        // while the app was closed.
        viewModelScope.launch {
            runReporting("Cannot read the sync status") { syncStateStore.load() }
            // Finds unreadable route files, so the banner can offer to delete them. Not via
            // runReporting, which would clear a failure above; sync reports a folder error too.
            try {
                plannedRouteRepository.loadAll()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "Cannot read the planned routes", e)
            }
        }
    }

    /**
     * Runs a sync of the configured folder again, if sync is on (#107); the result reaches the
     * banner via the store.
     */
    fun retry() {
        viewModelScope.launch {
            val prefs = preferencesRepository.preferencesFlow.first()
            val folderUri = prefs.syncFolderUri ?: return@launch
            if (!prefs.syncEnabled) return@launch
            runReporting("Sync failed") { syncEngine.sync(Uri.parse(folderUri)) }
        }
    }

    /**
     * Deletes the unreadable planned-route files the user confirmed, then, with sync on and a
     * folder set, syncs again so the errors clear and any cloud copy of those routes comes back
     * (#77, #107). It syncs after a partial failure too, as some files may be gone, and still
     * shows why the others were not deleted (#104).
     *
     * With sync off or no sync folder, no sync can replace the stored errors, so once every
     * file is deleted all stored errors are cleared instead; the reset notice is kept (#104,
     * #107). After a partial failure there, the stored errors are left as they are. See
     * [afterRouteFileDelete].
     *
     * @param fileNames The files the confirmation dialog listed, from the sync banner or the
     *   planned-route list.
     */
    fun deleteUnreadableRouteFiles(fileNames: List<String>) {
        viewModelScope.launch {
            val deleteError = runReporting("Cannot delete the unreadable route files") {
                plannedRouteRepository.deleteSkippedFiles(fileNames)
            }
            val prefs = preferencesRepository.preferencesFlow.first()
            val folderUri = prefs.syncFolderUri
            val next = afterRouteFileDelete(deleteError == null, prefs.syncEnabled, folderUri)
            val nextError = when (next) {
                // SYNC implies a folder is set.
                AfterRouteFileDelete.SYNC -> runReporting("Sync failed") {
                    syncEngine.sync(Uri.parse(checkNotNull(folderUri)))
                }
                AfterRouteFileDelete.CLEAR_ERRORS -> runReporting("Cannot clear the sync errors") {
                    syncStateStore.recordOutcome(emptyList())
                }
                AfterRouteFileDelete.NOTHING -> null
            }
            // A next step or a concurrent Retry/Dismiss may have cleared the delete failure; the
            // user must still see it.
            if (deleteError != null) {
                actionError.value = listOfNotNull(deleteError, nextError).joinToString("\n")
            }
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
     * @return The banner line of the failure, or null on success. Callers use this, not
     *   [actionError], which a concurrent Retry or Dismiss may change meanwhile (#107).
     */
    private suspend fun runReporting(what: String, action: suspend () -> Unit): String? {
        actionError.value = null
        return try {
            action()
            null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, what, e)
            "$what: ${e.message}".also { actionError.value = it }
        }
    }

    private companion object {
        const val TAG = "SyncStatusVM"

        /** Keeps the banner flow alive briefly across configuration changes. */
        const val STOP_TIMEOUT_MS = 5_000L
    }
}
