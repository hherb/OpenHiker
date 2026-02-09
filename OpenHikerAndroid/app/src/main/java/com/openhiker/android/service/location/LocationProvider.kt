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

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import com.openhiker.core.geo.Haversine
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Wraps the Android LocationManager and SensorManager to provide
 * GPS location and compass heading as observable [StateFlow] values.
 *
 * This is the Phase 2 location provider for map display and navigation.
 * The full hike recording (track point recording, auto-save, pause/resume)
 * will be added in Phase 3.
 *
 * Key features:
 * - GPS location updates via LocationManager (no Play Services dependency)
 * - Compass heading via rotation vector sensor
 * - Distance filter: ignores updates < [MIN_DISPLACEMENT_METRES] apart
 * - Cumulative distance tracking via Haversine
 *
 * @param context Application context.
 * @param locationManager Android location system service.
 */
@Singleton
class LocationProvider @Inject constructor(
    @ApplicationContext private val context: Context,
    private val locationManager: LocationManager
) : LocationListener, SensorEventListener {

    private val _location = MutableStateFlow<Location?>(null)
    private val _heading = MutableStateFlow<Float?>(null)
    private val _cumulativeDistance = MutableStateFlow(0.0)

    /** Current GPS location, or null if unavailable. */
    val location: StateFlow<Location?> = _location.asStateFlow()

    /** Compass heading in degrees (0 = north, 90 = east), or null if sensor unavailable. */
    val heading: StateFlow<Float?> = _heading.asStateFlow()

    /** Cumulative distance walked in metres since tracking started. */
    val cumulativeDistance: StateFlow<Double> = _cumulativeDistance.asStateFlow()

    private var lastAcceptedLocation: Location? = null
    private var isTracking = false
    private var sensorManager: SensorManager? = null
    private val rotationMatrix = FloatArray(9)
    private val orientationAngles = FloatArray(3)

    /**
     * Starts receiving GPS location updates and compass heading.
     *
     * Requires ACCESS_FINE_LOCATION permission. If the permission is not
     * granted, this method returns false without starting.
     *
     * @return True if tracking started successfully, false if permission is missing.
     */
    fun startTracking(): Boolean {
        if (isTracking) return true

        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "Location permission not granted")
            return false
        }

        try {
            // Request GPS updates
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                UPDATE_INTERVAL_MS,
                MIN_DISPLACEMENT_METRES,
                this,
                Looper.getMainLooper()
            )

            // Also request network provider as supplement
            if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    UPDATE_INTERVAL_MS * 2,
                    MIN_DISPLACEMENT_METRES * 2,
                    this,
                    Looper.getMainLooper()
                )
            }

            // Start compass heading
            startHeadingSensor()

            isTracking = true
            Log.d(TAG, "Location tracking started")
            return true
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception starting location updates", e)
            return false
        }
    }

    /**
     * Stops GPS location updates and compass heading.
     *
     * Safe to call even if tracking is not active.
     */
    fun stopTracking() {
        if (!isTracking) return

        locationManager.removeUpdates(this)
        stopHeadingSensor()

        isTracking = false
        Log.d(TAG, "Location tracking stopped")
    }

    /**
     * Resets the cumulative distance counter to zero.
     *
     * Call this when starting a new navigation session.
     */
    fun resetDistance() {
        _cumulativeDistance.value = 0.0
        lastAcceptedLocation = null
    }

    // ── LocationListener ─────────────────────────────────────────────

    override fun onLocationChanged(location: Location) {
        val lastLoc = lastAcceptedLocation

        // Distance filter: ignore updates too close together (GPS jitter)
        if (lastLoc != null) {
            val distance = Haversine.distance(
                lastLoc.latitude, lastLoc.longitude,
                location.latitude, location.longitude
            )
            if (distance < MIN_DISPLACEMENT_METRES) return

            _cumulativeDistance.value += distance
        }

        _location.value = location
        lastAcceptedLocation = location
    }

    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {
        // Required for API < 29 compatibility
    }

    override fun onProviderEnabled(provider: String) {
        Log.d(TAG, "Provider enabled: $provider")
    }

    override fun onProviderDisabled(provider: String) {
        Log.w(TAG, "Provider disabled: $provider")
    }

    // ── SensorEventListener (Compass) ────────────────────────────────

    override fun onSensorChanged(event: SensorEvent?) {
        event ?: return
        if (event.sensor.type == Sensor.TYPE_ROTATION_VECTOR) {
            SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
            SensorManager.getOrientation(rotationMatrix, orientationAngles)
            // orientationAngles[0] is azimuth in radians (-PI to PI)
            val azimuthDeg = Math.toDegrees(orientationAngles[0].toDouble()).toFloat()
            _heading.value = (azimuthDeg + 360f) % 360f
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Not used
    }

    // ── Private helpers ──────────────────────────────────────────────

    /**
     * Registers the rotation vector sensor for compass heading.
     */
    private fun startHeadingSensor() {
        val manager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        sensorManager = manager
        val rotationSensor = manager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        if (rotationSensor != null) {
            manager.registerListener(this, rotationSensor, SensorManager.SENSOR_DELAY_UI)
        } else {
            Log.w(TAG, "Rotation vector sensor not available")
        }
    }

    /**
     * Unregisters the compass heading sensor.
     */
    private fun stopHeadingSensor() {
        sensorManager?.unregisterListener(this)
        sensorManager = null
    }

    companion object {
        private const val TAG = "LocationProvider"

        /** Minimum time between GPS updates in milliseconds (2 seconds). */
        private const val UPDATE_INTERVAL_MS = 2000L

        /**
         * Minimum displacement in metres to accept a GPS update.
         *
         * Updates closer than this are ignored to prevent GPS jitter
         * from inflating distance calculations.
         */
        const val MIN_DISPLACEMENT_METRES = 5f
    }
}
