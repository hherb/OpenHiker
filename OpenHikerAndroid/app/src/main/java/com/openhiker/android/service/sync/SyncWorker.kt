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
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.concurrent.TimeUnit

/**
 * WorkManager worker for periodic cloud drive sync.
 *
 * Runs every [SYNC_INTERVAL_MINUTES] minutes when the device is connected
 * to a network (Wi-Fi or cellular). Reads the cloud folder URI from
 * SharedPreferences and delegates to [CloudDriveSyncEngine].
 *
 * Uses [HiltWorker] for dependency injection of the sync engine.
 *
 * @param context Application context.
 * @param params Worker parameters from WorkManager.
 * @param syncEngine The cloud drive sync engine.
 */
@HiltWorker
class SyncWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted params: WorkerParameters,
    private val syncEngine: CloudDriveSyncEngine
) : CoroutineWorker(context, params) {

    /**
     * Performs the background sync operation.
     *
     * Reads the cloud folder URI from shared preferences, then runs a
     * full sync cycle. Returns [Result.success] on success or
     * [Result.retry] on transient failures.
     *
     * @return [Result.success] if sync completed, [Result.retry] on failure.
     */
    override suspend fun doWork(): Result {
        val folderUri = getSyncFolderUri() ?: run {
            Log.d(TAG, "No sync folder configured, skipping")
            return Result.success()
        }

        return try {
            val result = syncEngine.sync(folderUri)
            if (result.isSuccess) {
                Log.i(TAG, "Sync completed: ${result.uploaded} up, ${result.downloaded} down")
                Result.success()
            } else {
                Log.w(TAG, "Sync completed with errors: ${result.errors}")
                Result.retry()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Sync worker failed", e)
            Result.retry()
        }
    }

    /**
     * Reads the configured cloud sync folder URI from SharedPreferences.
     *
     * @return The folder URI, or null if not configured.
     */
    private fun getSyncFolderUri(): Uri? {
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val uriString = prefs.getString(PREF_SYNC_FOLDER_URI, null) ?: return null
        return try {
            Uri.parse(uriString)
        } catch (e: Exception) {
            Log.e(TAG, "Invalid sync folder URI", e)
            null
        }
    }

    companion object {
        private const val TAG = "SyncWorker"

        /** SharedPreferences file name for sync settings. */
        const val PREFS_NAME = "openhiker_sync_prefs"

        /** Preference key for the cloud sync folder URI. */
        const val PREF_SYNC_FOLDER_URI = "sync_folder_uri"

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
