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

package com.openhiker.android.service.sync

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ListenableWorker
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.openhiker.android.data.repository.UserPreferencesRepository
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import kotlinx.coroutines.flow.first
import java.util.concurrent.TimeUnit

/**
 * WorkManager worker for periodic cloud drive sync.
 *
 * Runs every [SYNC_INTERVAL_MINUTES] minutes when the device is connected
 * to a network (Wi-Fi or cellular). Reads the cloud folder URI from
 * [UserPreferencesRepository] and delegates to [CloudDriveSyncEngine].
 *
 * Uses [HiltWorker] for dependency injection of the sync engine.
 *
 * @param context Application context.
 * @param params Worker parameters from WorkManager.
 * @param syncEngine The cloud drive sync engine.
 * @param preferencesRepository Source of the sync folder URI and the sync toggle.
 */
@HiltWorker
class SyncWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted params: WorkerParameters,
    private val syncEngine: CloudDriveSyncEngine,
    private val preferencesRepository: UserPreferencesRepository
) : CoroutineWorker(context, params) {

    /**
     * Performs the background sync operation.
     *
     * Reads the cloud folder URI from the user preferences, then runs a
     * full sync cycle. The engine records the errors for the UI's banner.
     *
     * @return The WorkManager result chosen by [workResultFor].
     */
    override suspend fun doWork(): Result {
        val folderUri = getSyncFolderUri() ?: run {
            Log.d(TAG, "Sync disabled or no folder configured, skipping")
            return Result.success()
        }

        return try {
            val result = syncEngine.sync(folderUri)
            if (result.isSuccess) {
                Log.i(TAG, "Sync completed: ${result.uploaded} up, ${result.downloaded} down")
            } else {
                Log.w(TAG, "Sync completed with errors: ${result.errors}")
            }
            workResultFor(result)
        } catch (e: Exception) {
            Log.e(TAG, "Sync worker failed", e)
            Result.retry()
        }
    }

    /**
     * Reads the configured cloud sync folder URI from the user preferences, where the
     * Settings screen stores it.
     *
     * @return The folder URI, or null if not configured or sync is disabled.
     */
    private suspend fun getSyncFolderUri(): Uri? {
        val prefs = preferencesRepository.preferencesFlow.first()
        if (!prefs.syncEnabled) return null
        val uriString = prefs.syncFolderUri ?: return null
        return try {
            Uri.parse(uriString)
        } catch (e: Exception) {
            Log.e(TAG, "Invalid sync folder URI", e)
            null
        }
    }

    companion object {
        private const val TAG = "SyncWorker"

        /**
         * Chooses the WorkManager result for a finished sync.
         *
         * A revoked folder permission is a failure: retrying cannot help until the
         * user picks the folder again, and the next period still runs. Other errors may clear
         * by themselves (a provider offline), so they are retried with WorkManager's backoff.
         *
         * @param result The sync's result.
         * @return success, failure or retry.
         */
        internal fun workResultFor(result: SyncResult): ListenableWorker.Result = when {
            result.isSuccess -> Result.success()
            result.folderUnavailable -> Result.failure()
            else -> Result.retry()
        }

        /** Sync interval in minutes. */
        private const val SYNC_INTERVAL_MINUTES = 15L

        /** Unique work name for the periodic sync job. */
        private const val WORK_NAME = "openhiker_cloud_sync"

        /**
         * Schedules periodic cloud sync via WorkManager.
         *
         * The sync runs every [SYNC_INTERVAL_MINUTES] minutes with network
         * connectivity required. Uses [ExistingPeriodicWorkPolicy.KEEP] to
         * avoid duplicate scheduling.
         *
         * @param context Application context.
         */
        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val request = PeriodicWorkRequestBuilder<SyncWorker>(
                SYNC_INTERVAL_MINUTES, TimeUnit.MINUTES
            )
                .setConstraints(constraints)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )

            Log.i(TAG, "Periodic sync scheduled every $SYNC_INTERVAL_MINUTES minutes")
        }

        /**
         * Cancels the periodic cloud sync job.
         *
         * @param context Application context.
         */
        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            Log.i(TAG, "Periodic sync cancelled")
        }
    }
}
