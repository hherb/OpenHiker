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

package com.openhiker.android.service.location

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.openhiker.android.MainActivity
import com.openhiker.android.R
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

/**
 * Foreground service that keeps GPS tracking alive when the app is in the background.
 *
 * Required for continuous GPS updates during navigation — Android kills
 * background location access after a few minutes without a foreground service.
 *
 * This is the Phase 2 minimal implementation. Phase 3 will add:
 * - Track point recording to in-memory list
 * - Auto-save drafts to disk every 5 minutes
 * - Pause/resume via notification actions
 * - Distance/duration stats in the notification
 *
 * Declared in AndroidManifest.xml with `foregroundServiceType="location"`.
 */
@AndroidEntryPoint
class HikeTrackingService : Service() {

    @Inject
    lateinit var locationProvider: LocationProvider

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    /**
     * Starts the foreground service and begins GPS tracking.
     *
     * Expects [ACTION_START] to start tracking or [ACTION_STOP] to stop.
     */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startForeground(NOTIFICATION_ID, createNotification())
                locationProvider.startTracking()
                Log.d(TAG, "Hike tracking service started")
            }
            ACTION_STOP -> {
                locationProvider.stopTracking()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                Log.d(TAG, "Hike tracking service stopped")
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        locationProvider.stopTracking()
        super.onDestroy()
    }

    /**
     * Creates the notification channel for the foreground service.
     *
     * Required on Android 8+ (API 26).
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Hike Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when OpenHiker is tracking your location"
                setShowBadge(false)
            }

            val notificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    /**
     * Creates the persistent foreground service notification.
     *
     * Tapping the notification opens the app. Phase 3 will add
     * pause/resume and stop actions.
     */
    private fun createNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("OpenHiker")
            .setContentText("Tracking your location")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    companion object {
        private const val TAG = "HikeTrackingService"
        private const val CHANNEL_ID = "hike_tracking"
        private const val NOTIFICATION_ID = 1001

        /** Intent action to start tracking. */
        const val ACTION_START = "com.openhiker.android.action.START_TRACKING"

        /** Intent action to stop tracking. */
        const val ACTION_STOP = "com.openhiker.android.action.STOP_TRACKING"

        /**
         * Starts the hike tracking foreground service.
         *
         * @param context Android context.
         */
        fun start(context: Context) {
            val intent = Intent(context, HikeTrackingService::class.java).apply {
                action = ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /**
         * Stops the hike tracking foreground service.
         *
         * @param context Android context.
         */
        fun stop(context: Context) {
            val intent = Intent(context, HikeTrackingService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
}
