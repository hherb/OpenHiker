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

package com.openhiker.android.service.navigation

import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import com.openhiker.android.service.location.LocationProvider
import com.openhiker.core.model.Coordinate
import com.openhiker.core.model.TurnInstruction
import com.openhiker.core.navigation.NavigationState
import com.openhiker.core.navigation.OffRouteDetector
import com.openhiker.core.navigation.OffRouteState
import com.openhiker.core.navigation.RouteFollower
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manages live turn-by-turn navigation with haptic feedback.
 *
 * Subscribes to [LocationProvider] updates, feeds positions into
 * [RouteFollower] and [OffRouteDetector] from the core module,
 * and provides navigation state via [StateFlow] for the UI.
 *
 * Haptic feedback patterns:
 * - Approaching turn (100m): short medium vibration
 * - At turn (30m): medium strong vibration
 * - Off-route: long-short-long pattern
 * - Arrived: triple pulse
 *
 * @param locationProvider GPS location source.
 * @param vibrator Android vibrator for haptic feedback.
 */
@Singleton
class NavigationService @Inject constructor(
    private val locationProvider: LocationProvider,
    private val vibrator: Vibrator
) {
    private val _navigationState = MutableStateFlow(NavigationState())
    private val _offRouteState = MutableStateFlow(OffRouteState())
    private val _isNavigating = MutableStateFlow(false)

    /** Current navigation state for the UI. */
    val navigationState: StateFlow<NavigationState> = _navigationState.asStateFlow()

    /** Current off-route detection state. */
    val offRouteState: StateFlow<OffRouteState> = _offRouteState.asStateFlow()

    /** Whether navigation is currently active. */
    val isNavigating: StateFlow<Boolean> = _isNavigating.asStateFlow()

    private var routeFollower: RouteFollower? = null
    private var offRouteDetector: OffRouteDetector? = null
    private var locationJob: Job? = null
    private var lastHapticEvent: HapticEvent = HapticEvent.NONE
    private val scope = CoroutineScope(Dispatchers.Main)

    /**
     * Starts turn-by-turn navigation for a planned route.
     *
     * @param routeCoordinates Ordered list of route coordinates.
     * @param instructions Turn-by-turn instruction list.
     * @param totalDistance Total route distance in metres.
     */
    fun startNavigation(
        routeCoordinates: List<Coordinate>,
        instructions: List<TurnInstruction>,
        totalDistance: Double
    ) {
        stopNavigation()

        routeFollower = RouteFollower(routeCoordinates, instructions, totalDistance)
        offRouteDetector = OffRouteDetector(routeCoordinates)

        locationProvider.resetDistance()
        locationProvider.startTracking()

        _isNavigating.value = true
        lastHapticEvent = HapticEvent.NONE

        // Observe location updates
        locationJob = scope.launch {
            locationProvider.location.collect { location ->
                location ?: return@collect

                val navState = routeFollower?.update(
                    location.latitude,
                    location.longitude,
                    locationProvider.cumulativeDistance.value
                ) ?: return@collect

                _navigationState.value = navState

                val offRoute = offRouteDetector?.check(
                    location.latitude,
                    location.longitude
                ) ?: OffRouteState()

                _offRouteState.value = offRoute

                // Trigger haptic feedback
                handleHaptics(navState, offRoute)
            }
        }

        Log.d(TAG, "Navigation started with ${instructions.size} instructions")
    }

    /**
     * Stops the current navigation session.
     *
     * Does not stop the location provider (the foreground service may
     * still be active for map display).
     */
    fun stopNavigation() {
        locationJob?.cancel()
        locationJob = null
        routeFollower = null
        offRouteDetector = null

        _navigationState.value = NavigationState()
        _offRouteState.value = OffRouteState()
        _isNavigating.value = false
        lastHapticEvent = HapticEvent.NONE

        Log.d(TAG, "Navigation stopped")
    }

    /**
     * Handles haptic feedback based on navigation and off-route state.
     *
     * Uses event deduplication to avoid repeating the same vibration
     * on consecutive location updates.
     */
    private fun handleHaptics(navState: NavigationState, offRouteState: OffRouteState) {
        val event = when {
            navState.hasArrived -> HapticEvent.ARRIVED
            offRouteState.isOffRoute -> HapticEvent.OFF_ROUTE
            navState.isAtTurn -> HapticEvent.AT_TURN
            navState.isApproachingTurn -> HapticEvent.APPROACHING_TURN
            else -> HapticEvent.NONE
        }

        if (event != lastHapticEvent && event != HapticEvent.NONE) {
            vibrate(event)
            lastHapticEvent = event
        } else if (event == HapticEvent.NONE) {
            lastHapticEvent = HapticEvent.NONE
        }
    }

    /**
     * Triggers a haptic vibration pattern.
     */
    @Suppress("DEPRECATION")
    private fun vibrate(event: HapticEvent) {
        if (!vibrator.hasVibrator()) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val effect = when (event) {
                HapticEvent.APPROACHING_TURN ->
                    VibrationEffect.createOneShot(APPROACHING_DURATION_MS, APPROACHING_AMPLITUDE)
                HapticEvent.AT_TURN ->
                    VibrationEffect.createOneShot(AT_TURN_DURATION_MS, AT_TURN_AMPLITUDE)
                HapticEvent.OFF_ROUTE ->
                    VibrationEffect.createWaveform(OFF_ROUTE_PATTERN, -1)
                HapticEvent.ARRIVED ->
                    VibrationEffect.createWaveform(ARRIVED_PATTERN, -1)
                HapticEvent.NONE -> return
            }
            vibrator.vibrate(effect)
        } else {
            // Legacy vibration for API < 26
            val durationMs = when (event) {
                HapticEvent.APPROACHING_TURN -> APPROACHING_DURATION_MS
                HapticEvent.AT_TURN -> AT_TURN_DURATION_MS
                HapticEvent.OFF_ROUTE -> 500L
                HapticEvent.ARRIVED -> 300L
                HapticEvent.NONE -> return
            }
            vibrator.vibrate(durationMs)
        }
    }

    companion object {
        private const val TAG = "NavigationService"

        // Haptic parameters from the implementation plan
        private const val APPROACHING_DURATION_MS = 100L
        private const val APPROACHING_AMPLITUDE = 128 // medium
        private const val AT_TURN_DURATION_MS = 200L
        private const val AT_TURN_AMPLITUDE = 255 // strong

        /** Off-route: long-short-long pattern. */
        private val OFF_ROUTE_PATTERN = longArrayOf(0, 300, 100, 100, 100, 300)

        /** Arrived: triple pulse pattern. */
        private val ARRIVED_PATTERN = longArrayOf(0, 100, 50, 100, 50, 100)
    }
}

/**
 * Haptic feedback events for deduplication.
 */
private enum class HapticEvent {
    NONE,
    APPROACHING_TURN,
    AT_TURN,
    OFF_ROUTE,
    ARRIVED
}
