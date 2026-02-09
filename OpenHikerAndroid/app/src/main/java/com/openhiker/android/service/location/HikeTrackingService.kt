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
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.openhiker.android.MainActivity
import com.openhiker.android.R
import com.openhiker.android.data.db.routes.SavedRouteEntity
import com.openhiker.android.data.repository.RouteRepository
import com.openhiker.core.compression.TrackCompression
import com.openhiker.core.compression.TrackPoint
import com.openhiker.core.geo.Haversine
import com.openhiker.core.model.CalorieEstimator
import com.openhiker.core.model.HikeStatisticsConfig
import com.openhiker.core.model.HikeStatsFormatter
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.File
import java.time.Instant
import java.util.UUID
import javax.inject.Inject

/**
 * State of the hike recording.
 */
enum class HikeRecordingState {
    /** No hike is being recorded. */
    IDLE,
    /** Actively recording GPS track points. */
    RECORDING,
    /** Recording is paused (GPS still active but points not saved). */
    PAUSED
}

/**
 * Live statistics updated during hike recording.
 *
 * @property totalDistance Total distance walked in metres.
 * @property elevationGain Cumulative uphill elevation change in metres.
 * @property elevationLoss Cumulative downhill elevation change in metres.
 * @property walkingTime Time spent moving in seconds.
 * @property restingTime Time spent stationary in seconds.
 * @property averageSpeed Average moving speed in m/s.
 * @property maxSpeed Peak speed in m/s.
 * @property trackPointCount Number of GPS points recorded.
 * @property elapsedSeconds Total elapsed time since hike start in seconds.
 */
data class LiveHikeStats(
    val totalDistance: Double = 0.0,
    val elevationGain: Double = 0.0,
    val elevationLoss: Double = 0.0,
    val walkingTime: Double = 0.0,
    val restingTime: Double = 0.0,
    val averageSpeed: Double = 0.0,
    val maxSpeed: Double = 0.0,
    val trackPointCount: Int = 0,
    val elapsedSeconds: Long = 0L
)

/**
 * Android foreground service for continuous GPS hike recording.
 *
 * Keeps GPS active while the app is in the background via a persistent
 * notification. Records track points, accumulates statistics (distance,
 * elevation gain/loss, walking/resting time), and auto-saves a draft
 * every [AUTO_SAVE_INTERVAL_MS] for crash recovery.
 *
 * Lifecycle:
 * 1. Activity binds and calls [startRecording]
 * 2. Service promotes to foreground with a notification
 * 3. GPS updates flow from [LocationProvider] into the track buffer
 * 4. Activity can [pauseRecording] / [resumeRecording]
 * 5. [stopRecording] compresses the track and returns the saved entity ID
 *
 * Notification actions: Pause/Resume and Stop with live distance/time stats.
 *
 * Declared in AndroidManifest.xml with `foregroundServiceType="location"`.
 */
@AndroidEntryPoint
class HikeTrackingService : Service() {

    @Inject
    lateinit var locationProvider: LocationProvider

    @Inject
    lateinit var routeRepository: RouteRepository

    private val binder = HikeTrackingBinder()
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private val _recordingState = MutableStateFlow(HikeRecordingState.IDLE)
    private val _liveStats = MutableStateFlow(LiveHikeStats())

    /** Current recording state (idle, recording, paused). */
    val recordingState: StateFlow<HikeRecordingState> = _recordingState.asStateFlow()

    /** Live statistics updated on each GPS fix during recording. */
    val liveStats: StateFlow<LiveHikeStats> = _liveStats.asStateFlow()

    private val trackPoints = mutableListOf<TrackPoint>()
    private var locationJob: Job? = null
    private var timerJob: Job? = null
    private var autoSaveJob: Job? = null

    private var hikeStartTime: Instant? = null
    private var lastPauseTime: Instant? = null
    private var totalPausedMs: Long = 0L
    private var lastSignificantElevation: Double? = null
    private var lastPointTime: Long = 0L
    private var currentMaxSpeed: Double = 0.0
    private var totalMovingTime: Double = 0.0

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PAUSE -> pauseRecording()
            ACTION_RESUME -> resumeRecording()
            ACTION_STOP -> {
                serviceScope.launch {
                    stopRecording()
                }
            }
            // Legacy Phase 2 actions (kept for compatibility)
            ACTION_START_LEGACY -> {
                startForeground(NOTIFICATION_ID, buildNotification())
                locationProvider.startTracking()
            }
            ACTION_STOP_LEGACY -> {
                locationProvider.stopTracking()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        locationJob?.cancel()
        timerJob?.cancel()
        autoSaveJob?.cancel()
        super.onDestroy()
    }

    /**
     * Starts recording a new hike.
     *
     * Promotes the service to foreground, starts GPS tracking, and begins
     * accumulating track points and statistics.
     *
     * @return True if recording started successfully, false if permission missing.
     */
    fun startRecording(): Boolean {
        if (_recordingState.value != HikeRecordingState.IDLE) return true

        if (!locationProvider.startTracking()) {
            Log.w(TAG, "Cannot start recording: location permission not granted")
            return false
        }

        trackPoints.clear()
        hikeStartTime = Instant.now()
        lastPauseTime = null
        totalPausedMs = 0L
        lastSignificantElevation = null
        lastPointTime = 0L
        currentMaxSpeed = 0.0
        totalMovingTime = 0.0
        locationProvider.resetDistance()

        _recordingState.value = HikeRecordingState.RECORDING
        _liveStats.value = LiveHikeStats()

        startForeground(NOTIFICATION_ID, buildNotification())
        startLocationCollection()
        startTimer()
        startAutoSave()

        Log.d(TAG, "Hike recording started")
        return true
    }

    /**
     * Pauses the recording. GPS stays active but points are not saved.
     */
    fun pauseRecording() {
        if (_recordingState.value != HikeRecordingState.RECORDING) return

        _recordingState.value = HikeRecordingState.PAUSED
        lastPauseTime = Instant.now()

        updateNotification()
        Log.d(TAG, "Hike recording paused")
    }

    /**
     * Resumes a paused recording.
     */
    fun resumeRecording() {
        if (_recordingState.value != HikeRecordingState.PAUSED) return

        lastPauseTime?.let { pauseStart ->
            totalPausedMs += Instant.now().toEpochMilli() - pauseStart.toEpochMilli()
        }
        lastPauseTime = null

        _recordingState.value = HikeRecordingState.RECORDING

        updateNotification()
        Log.d(TAG, "Hike recording resumed")
    }

    /**
     * Stops recording, compresses the track, and saves to the database.
     *
     * @return The saved route entity ID, or null if no points were recorded.
     */
    suspend fun stopRecording(): String? {
        if (_recordingState.value == HikeRecordingState.IDLE) return null

        locationJob?.cancel()
        timerJob?.cancel()
        autoSaveJob?.cancel()

        val routeId = saveHike()

        _recordingState.value = HikeRecordingState.IDLE
        locationProvider.stopTracking()
        deleteDraft()

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()

        Log.d(TAG, "Hike recording stopped, saved as: $routeId")
        return routeId
    }

    // ── GPS Collection ───────────────────────────────────────────────

    /**
     * Collects GPS location updates and records track points.
     */
    private fun startLocationCollection() {
        locationJob?.cancel()
        locationJob = serviceScope.launch {
            locationProvider.location.collect { location ->
                location ?: return@collect
                if (_recordingState.value != HikeRecordingState.RECORDING) return@collect

                val now = System.currentTimeMillis()
                val altitude = if (location.hasAltitude()) location.altitude else 0.0

                val trackPoint = TrackPoint(
                    latitude = location.latitude,
                    longitude = location.longitude,
                    altitude = altitude,
                    timestamp = now.toDouble() / MILLIS_PER_SECOND
                )

                trackPoints.add(trackPoint)

                // Update elevation gain/loss with noise filter
                updateElevation(altitude)

                // Update speed statistics
                if (lastPointTime > 0L && trackPoints.size >= 2) {
                    val prev = trackPoints[trackPoints.size - 2]
                    val dist = Haversine.distance(
                        prev.latitude, prev.longitude,
                        trackPoint.latitude, trackPoint.longitude
                    )
                    val timeDelta = (now - lastPointTime).toDouble() / MILLIS_PER_SECOND
                    if (timeDelta > 0) {
                        val speed = dist / timeDelta
                        if (speed > currentMaxSpeed) {
                            currentMaxSpeed = speed
                        }
                        if (speed > HikeStatisticsConfig.RESTING_SPEED_THRESHOLD) {
                            totalMovingTime += timeDelta
                        }
                    }
                }

                lastPointTime = now
                updateLiveStats()
                updateNotification()
            }
        }
    }

    /**
     * Accumulates elevation gain and loss with a noise filter.
     *
     * Changes smaller than [ELEVATION_NOISE_THRESHOLD_METRES] are ignored
     * to prevent GPS altitude noise from inflating totals.
     *
     * @param currentAltitude Current altitude in metres from GPS.
     */
    private fun updateElevation(currentAltitude: Double) {
        val lastElev = lastSignificantElevation
        if (lastElev == null) {
            lastSignificantElevation = currentAltitude
            return
        }

        val delta = currentAltitude - lastElev
        if (kotlin.math.abs(delta) >= ELEVATION_NOISE_THRESHOLD_METRES) {
            val stats = _liveStats.value
            if (delta > 0) {
                _liveStats.value = stats.copy(elevationGain = stats.elevationGain + delta)
            } else {
                _liveStats.value = stats.copy(elevationLoss = stats.elevationLoss + (-delta))
            }
            lastSignificantElevation = currentAltitude
        }
    }

    /**
     * Updates the live statistics from current data.
     */
    private fun updateLiveStats() {
        val distance = locationProvider.cumulativeDistance.value
        val elapsed = elapsedSeconds()
        val restingTime = elapsed - totalMovingTime
        val avgSpeed = if (totalMovingTime > 0) distance / totalMovingTime else 0.0

        _liveStats.value = _liveStats.value.copy(
            totalDistance = distance,
            walkingTime = totalMovingTime,
            restingTime = if (restingTime > 0) restingTime else 0.0,
            averageSpeed = avgSpeed,
            maxSpeed = currentMaxSpeed,
            trackPointCount = trackPoints.size,
            elapsedSeconds = elapsed.toLong()
        )
    }

    /**
     * Returns elapsed recording time in seconds, excluding paused periods.
     */
    private fun elapsedSeconds(): Double {
        val start = hikeStartTime ?: return 0.0
        val now = Instant.now().toEpochMilli()
        val currentPause = if (_recordingState.value == HikeRecordingState.PAUSED) {
            lastPauseTime?.let { now - it.toEpochMilli() } ?: 0L
        } else {
            0L
        }
        return (now - start.toEpochMilli() - totalPausedMs - currentPause).toDouble() /
            MILLIS_PER_SECOND
    }

    // ── Timer & Auto-save ────────────────────────────────────────────

    /**
     * Starts a timer that updates elapsed time every second.
     */
    private fun startTimer() {
        timerJob?.cancel()
        timerJob = serviceScope.launch {
            while (true) {
                delay(TIMER_UPDATE_INTERVAL_MS)
                if (_recordingState.value != HikeRecordingState.IDLE) {
                    _liveStats.value = _liveStats.value.copy(
                        elapsedSeconds = elapsedSeconds().toLong()
                    )
                }
            }
        }
    }

    /**
     * Auto-saves the track draft every [AUTO_SAVE_INTERVAL_MS] for crash recovery.
     *
     * The draft is a zlib-compressed binary file in the app's files directory.
     * On crash recovery, it can be decoded with [TrackCompression.decompress].
     */
    private fun startAutoSave() {
        autoSaveJob?.cancel()
        autoSaveJob = serviceScope.launch(Dispatchers.IO) {
            while (true) {
                delay(AUTO_SAVE_INTERVAL_MS)
                if (trackPoints.isNotEmpty()) {
                    try {
                        val compressed = TrackCompression.compress(trackPoints.toList())
                        getDraftFile().writeBytes(compressed)
                        Log.d(TAG, "Auto-saved ${trackPoints.size} track points")
                    } catch (e: Exception) {
                        Log.e(TAG, "Auto-save failed", e)
                    }
                }
            }
        }
    }

    // ── Save ─────────────────────────────────────────────────────────

    /**
     * Compresses the track and saves the completed hike to the database.
     *
     * @return The saved route entity ID, or null if no points recorded.
     */
    private suspend fun saveHike(): String? {
        if (trackPoints.isEmpty()) return null

        val id = UUID.randomUUID().toString()
        val startTime = hikeStartTime?.toString() ?: Instant.now().toString()
        val endTime = Instant.now().toString()
        val stats = _liveStats.value
        val compressed = TrackCompression.compress(trackPoints.toList())

        val first = trackPoints.first()
        val last = trackPoints.last()

        val calories = CalorieEstimator.estimate(
            distanceMetres = stats.totalDistance,
            elevationGainMetres = stats.elevationGain,
            durationSeconds = stats.elapsedSeconds.toDouble()
        )

        val entity = SavedRouteEntity(
            id = id,
            name = "Hike — ${java.time.LocalDate.now()}",
            startLatitude = first.latitude,
            startLongitude = first.longitude,
            endLatitude = last.latitude,
            endLongitude = last.longitude,
            startTime = startTime,
            endTime = endTime,
            totalDistance = stats.totalDistance,
            elevationGain = stats.elevationGain,
            elevationLoss = stats.elevationLoss,
            walkingTime = stats.walkingTime,
            restingTime = stats.restingTime,
            averageHeartRate = null,
            maxHeartRate = null,
            estimatedCalories = calories,
            comment = "",
            regionId = null,
            trackData = compressed,
            modifiedAt = Instant.now().toString()
        )

        routeRepository.save(entity)
        return id
    }

    /**
     * Returns the draft file path for auto-save crash recovery.
     */
    private fun getDraftFile(): File =
        File(filesDir, DRAFT_FILENAME)

    /**
     * Deletes the auto-save draft after a successful save.
     */
    private fun deleteDraft() {
        try {
            getDraftFile().delete()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to delete draft file", e)
        }
    }

    // ── Notification ─────────────────────────────────────────────────

    /**
     * Creates the notification channel (required on Android 8+).
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Hike Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows while OpenHiker is recording your hike"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    /**
     * Builds the foreground notification with live stats and Pause/Resume + Stop actions.
     */
    private fun buildNotification(): Notification {
        val stats = _liveStats.value
        val distanceKm = stats.totalDistance / HikeStatisticsConfig.METRES_PER_KILOMETRE
        val isPaused = _recordingState.value == HikeRecordingState.PAUSED

        val contentText = if (isPaused) {
            "Paused — %.1f km".format(distanceKm)
        } else {
            "%.1f km | %s".format(
                distanceKm,
                HikeStatsFormatter.formatDuration(stats.elapsedSeconds.toDouble())
            )
        }

        // Tap opens the app
        val contentIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("OpenHiker is tracking your hike")
            .setContentText(contentText)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)

        // Pause / Resume action
        if (isPaused) {
            val resumeIntent = Intent(this, HikeTrackingService::class.java).apply {
                action = ACTION_RESUME
            }
            val resumePending = PendingIntent.getService(
                this, 0, resumeIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(
                android.R.drawable.ic_media_play, "Resume", resumePending
            )
        } else {
            val pauseIntent = Intent(this, HikeTrackingService::class.java).apply {
                action = ACTION_PAUSE
            }
            val pausePending = PendingIntent.getService(
                this, 0, pauseIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(
                android.R.drawable.ic_media_pause, "Pause", pausePending
            )
        }

        // Stop action
        val stopIntent = Intent(this, HikeTrackingService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        builder.addAction(android.R.drawable.ic_delete, "Stop", stopPending)

        return builder.build()
    }

    /**
     * Updates the foreground notification with current stats.
     */
    private fun updateNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    // ── Binder ───────────────────────────────────────────────────────

    /**
     * Binder for binding the service to an activity.
     */
    inner class HikeTrackingBinder : Binder() {
        /** Returns the service instance for direct method calls. */
        fun getService(): HikeTrackingService = this@HikeTrackingService
    }

    companion object {
        private const val TAG = "HikeTrackingService"
        private const val CHANNEL_ID = "hike_tracking"
        private const val NOTIFICATION_ID = 1001
        private const val DRAFT_FILENAME = "hike_draft.bin"
        private const val MILLIS_PER_SECOND = 1000.0
        private const val TIMER_UPDATE_INTERVAL_MS = 1000L

        /** Auto-save interval: 5 minutes. */
        private const val AUTO_SAVE_INTERVAL_MS = 5 * 60 * 1000L

        /** Minimum elevation change to count as gain or loss (noise filter). */
        private const val ELEVATION_NOISE_THRESHOLD_METRES = 3.0

        /** Intent action: pause recording from notification. */
        const val ACTION_PAUSE = "com.openhiker.android.PAUSE_HIKE"

        /** Intent action: resume recording from notification. */
        const val ACTION_RESUME = "com.openhiker.android.RESUME_HIKE"

        /** Intent action: stop recording from notification. */
        const val ACTION_STOP = "com.openhiker.android.STOP_HIKE"

        // Legacy Phase 2 actions (kept for backward compatibility)
        private const val ACTION_START_LEGACY = "com.openhiker.android.action.START_TRACKING"
        private const val ACTION_STOP_LEGACY = "com.openhiker.android.action.STOP_TRACKING"

        /**
         * Starts the foreground service (legacy — for Phase 2 callers).
         *
         * For Phase 3 hike recording, bind the service and call [startRecording] instead.
         *
         * @param context Android context.
         */
        fun start(context: Context) {
            val intent = Intent(context, HikeTrackingService::class.java).apply {
                action = ACTION_START_LEGACY
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /**
         * Stops the foreground service (legacy — for Phase 2 callers).
         *
         * @param context Android context.
         */
        fun stop(context: Context) {
            val intent = Intent(context, HikeTrackingService::class.java).apply {
                action = ACTION_STOP_LEGACY
            }
            context.startService(intent)
        }
    }
}
