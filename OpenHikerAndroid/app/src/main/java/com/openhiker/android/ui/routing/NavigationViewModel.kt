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

package com.openhiker.android.ui.routing

import android.util.Log
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.openhiker.android.data.repository.PlannedRouteRepository
import com.openhiker.android.service.location.LocationProvider
import com.openhiker.android.service.navigation.NavigationService
import com.openhiker.core.model.Coordinate
import com.openhiker.core.model.PlannedRoute
import com.openhiker.core.model.TurnInstruction
import com.openhiker.core.navigation.NavigationState
import com.openhiker.core.navigation.OffRouteState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI state for the navigation screen.
 *
 * @property routeName Display name of the route being navigated.
 * @property isNavigating True while turn-by-turn navigation is active.
 * @property elapsedSeconds Elapsed navigation time in seconds.
 * @property isStopDialogVisible True when the stop confirmation dialog is shown.
 */
data class NavigationUiState(
    val routeName: String = "",
    val isNavigating: Boolean = false,
    val elapsedSeconds: Long = 0L,
    val isStopDialogVisible: Boolean = false
)

/**
 * ViewModel for the turn-by-turn navigation screen.
 *
 * Coordinates between [NavigationService] (which manages route following and
 * haptic feedback), [LocationProvider] (GPS position and heading), and the
 * Compose UI. Loads a planned route by ID from [PlannedRouteRepository] and
 * starts the navigation session.
 *
 * @param navigationService Handles route following and haptic feedback.
 * @param locationProvider Provides GPS location and compass heading.
 * @param plannedRouteRepository Access to saved planned routes.
 * @param savedStateHandle Contains the route ID navigation argument.
 */
@HiltViewModel
class NavigationViewModel @Inject constructor(
    private val navigationService: NavigationService,
    private val locationProvider: LocationProvider,
    private val plannedRouteRepository: PlannedRouteRepository,
    savedStateHandle: SavedStateHandle
) : ViewModel() {

    private val _uiState = MutableStateFlow(NavigationUiState())

    /** Observable UI state for the navigation screen. */
    val uiState: StateFlow<NavigationUiState> = _uiState.asStateFlow()

    /** Navigation state from the route follower (instruction, distance, progress). */
    val navigationState: StateFlow<NavigationState> = navigationService.navigationState

    /** Off-route detection state. */
    val offRouteState: StateFlow<OffRouteState> = navigationService.offRouteState

    /** Current GPS location for the map marker. */
    val currentLocation = locationProvider.location

    /** Compass heading for the map camera rotation. */
    val currentHeading = locationProvider.heading

    /** Cumulative distance walked in metres. */
    val distanceWalked = locationProvider.cumulativeDistance

    /** Whether the navigation service is active. */
    val isNavigating: StateFlow<Boolean> = navigationService.isNavigating
        .stateIn(viewModelScope, SharingStarted.Eagerly, false)

    private var timerJob: kotlinx.coroutines.Job? = null
    private var navigationStartTimeMs: Long = 0L

    init {
        val routeId = savedStateHandle.get<String>("routeId")
        if (routeId != null) {
            loadAndStartNavigation(routeId)
        }
    }

    /**
     * Loads a planned route by ID and starts turn-by-turn navigation.
     *
     * @param routeId The UUID of the planned route to navigate.
     */
    private fun loadAndStartNavigation(routeId: String) {
        viewModelScope.launch {
            val route = plannedRouteRepository.getById(routeId)
            if (route != null) {
                startNavigation(route)
            } else {
                Log.w(TAG, "Route not found: $routeId")
            }
        }
    }

    /**
     * Starts navigation for the given planned route.
     *
     * Configures the navigation service with the route coordinates and
     * instructions, then starts the elapsed time timer.
     *
     * @param route The planned route to navigate.
     */
    fun startNavigation(route: PlannedRoute) {
        navigationService.startNavigation(
            routeCoordinates = route.coordinates,
            instructions = route.turnInstructions,
            totalDistance = route.totalDistance
        )

        _uiState.value = _uiState.value.copy(
            routeName = route.name,
            isNavigating = true,
            elapsedSeconds = 0L
        )

        startTimer()
    }

    /**
     * Starts navigation directly from route data (without a saved route).
     *
     * Used when navigating immediately after route computation, before
     * the route has been saved.
     *
     * @param coordinates The route polyline coordinates.
     * @param instructions Turn-by-turn instructions.
     * @param totalDistance Total route distance in metres.
     * @param routeName Display name for the navigation screen.
     */
    fun startNavigationDirect(
        coordinates: List<Coordinate>,
        instructions: List<TurnInstruction>,
        totalDistance: Double,
        routeName: String = "Navigation"
    ) {
        navigationService.startNavigation(
            routeCoordinates = coordinates,
            instructions = instructions,
            totalDistance = totalDistance
        )

        _uiState.value = _uiState.value.copy(
            routeName = routeName,
            isNavigating = true,
            elapsedSeconds = 0L
        )

        startTimer()
    }

    /**
     * Shows the stop navigation confirmation dialog.
     */
    fun showStopDialog() {
        _uiState.value = _uiState.value.copy(isStopDialogVisible = true)
    }

    /**
     * Hides the stop navigation confirmation dialog.
     */
    fun dismissStopDialog() {
        _uiState.value = _uiState.value.copy(isStopDialogVisible = false)
    }

    /**
     * Stops the current navigation session.
     *
     * Stops the navigation service, location tracking timer, and
     * resets the UI state.
     */
    fun stopNavigation() {
        navigationService.stopNavigation()
        timerJob?.cancel()
        timerJob = null

        _uiState.value = _uiState.value.copy(
            isNavigating = false,
            isStopDialogVisible = false
        )
    }

    /**
     * Starts an elapsed-time counter that updates every second.
     */
    private fun startTimer() {
        timerJob?.cancel()
        navigationStartTimeMs = System.currentTimeMillis()

        timerJob = viewModelScope.launch {
            while (true) {
                kotlinx.coroutines.delay(TIMER_UPDATE_INTERVAL_MS)
                val elapsed = (System.currentTimeMillis() - navigationStartTimeMs) / MILLIS_PER_SECOND
                _uiState.value = _uiState.value.copy(elapsedSeconds = elapsed)
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        navigationService.stopNavigation()
        timerJob?.cancel()
    }

    companion object {
        private const val TAG = "NavigationViewModel"
        private const val TIMER_UPDATE_INTERVAL_MS = 1000L
        private const val MILLIS_PER_SECOND = 1000L
    }
}
