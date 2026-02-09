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
import com.openhiker.core.model.ElevationPoint
import com.openhiker.core.model.PlannedRoute
import com.openhiker.core.model.TurnInstruction
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import javax.inject.Inject

/**
 * UI state for the route detail screen.
 *
 * Holds all data needed to render the [RouteDetailScreen], including
 * route metadata, statistics, and loading/error states.
 *
 * @property routeId The unique identifier of the planned route.
 * @property routeName User-editable display name of the route.
 * @property routingMode Activity mode used for the route ("hiking" or "cycling").
 * @property totalDistance Total route distance in metres.
 * @property estimatedDuration Estimated travel time in seconds.
 * @property elevationGain Cumulative elevation gain in metres.
 * @property elevationLoss Cumulative elevation loss in metres.
 * @property createdAt ISO-8601 creation timestamp.
 * @property isLoading True while the route is being loaded from disk.
 * @property errorMessage Error message if loading or an operation failed, or null.
 */
data class RouteDetailUiState(
    val routeId: String = "",
    val routeName: String = "",
    val routingMode: String = "",
    val totalDistance: Double = 0.0,
    val estimatedDuration: Double = 0.0,
    val elevationGain: Double = 0.0,
    val elevationLoss: Double = 0.0,
    val createdAt: String = "",
    val isLoading: Boolean = true,
    val errorMessage: String? = null
)

/**
 * ViewModel for the route detail screen.
 *
 * Loads a planned route by ID from [PlannedRouteRepository], exposes its
 * data, turn instructions, and elevation profile as observable StateFlows,
 * and provides rename and delete operations.
 *
 * The route ID is extracted from the navigation arguments via [SavedStateHandle].
 *
 * @param plannedRouteRepository Repository for reading, updating, and deleting planned routes.
 * @param savedStateHandle Contains the "routeId" navigation argument.
 */
@HiltViewModel
class RouteDetailViewModel @Inject constructor(
    private val plannedRouteRepository: PlannedRouteRepository,
    savedStateHandle: SavedStateHandle
) : ViewModel() {

    private val _uiState = MutableStateFlow(RouteDetailUiState())

    /** Observable UI state for the route detail screen. */
    val uiState: StateFlow<RouteDetailUiState> = _uiState.asStateFlow()

    private val _instructions = MutableStateFlow<List<TurnInstruction>>(emptyList())

    /** Observable list of turn-by-turn instructions for the route. */
    val instructions: StateFlow<List<TurnInstruction>> = _instructions.asStateFlow()

    private val _elevationProfile = MutableStateFlow<List<ElevationPoint>>(emptyList())

    /** Observable elevation profile data for chart rendering. */
    val elevationProfile: StateFlow<List<ElevationPoint>> = _elevationProfile.asStateFlow()

    /** In-memory reference to the full planned route, used for updates. */
    private var currentRoute: PlannedRoute? = null

    init {
        val routeId = savedStateHandle.get<String>("routeId")
        if (routeId != null) {
            loadRoute(routeId)
        } else {
            _uiState.value = RouteDetailUiState(
                isLoading = false,
                errorMessage = "No route ID provided."
            )
        }
    }

    /**
     * Loads a planned route from the repository by ID.
     *
     * On success, populates the UI state, instructions, and elevation profile.
     * On failure (route not found or deserialization error), sets an error message.
     *
     * @param routeId The UUID of the planned route to load.
     */
    private fun loadRoute(routeId: String) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)

            try {
                val route = withContext(Dispatchers.IO) {
                    plannedRouteRepository.getById(routeId)
                }

                if (route != null) {
                    currentRoute = route
                    _uiState.value = RouteDetailUiState(
                        routeId = route.id,
                        routeName = route.name,
                        routingMode = route.mode.name.lowercase(),
                        totalDistance = route.totalDistance,
                        estimatedDuration = route.estimatedDuration,
                        elevationGain = route.elevationGain,
                        elevationLoss = route.elevationLoss,
                        createdAt = route.createdAt,
                        isLoading = false,
                        errorMessage = null
                    )
                    _instructions.value = route.turnInstructions
                    _elevationProfile.value = route.elevationProfile ?: emptyList()
                } else {
                    _uiState.value = RouteDetailUiState(
                        routeId = routeId,
                        isLoading = false,
                        errorMessage = "Route not found."
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load route: $routeId", e)
                _uiState.value = RouteDetailUiState(
                    routeId = routeId,
                    isLoading = false,
                    errorMessage = "Failed to load route: ${e.message}"
                )
            }
        }
    }

    /**
     * Renames the currently loaded route.
     *
     * Updates the route name both in the repository (persisted to disk)
     * and in the local UI state. If the route has not been loaded yet,
     * this operation is a no-op.
     *
     * @param newName The new display name for the route. Must not be blank.
     */
    fun renameRoute(newName: String) {
        val route = currentRoute ?: return
        if (newName.isBlank()) return

        val updatedRoute = route.copy(
            name = newName,
            modifiedAt = Instant.now().toString()
        )

        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    plannedRouteRepository.save(updatedRoute)
                }
                currentRoute = updatedRoute
                _uiState.value = _uiState.value.copy(routeName = newName)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to rename route: ${route.id}", e)
                _uiState.value = _uiState.value.copy(
                    errorMessage = "Failed to rename route: ${e.message}"
                )
            }
        }
    }

    /**
     * Deletes the currently loaded route from the repository.
     *
     * After successful deletion, the route data is cleared from the UI state.
     * If the route has not been loaded yet, this operation is a no-op.
     */
    fun deleteRoute() {
        val route = currentRoute ?: return

        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    plannedRouteRepository.delete(route.id)
                }
                currentRoute = null
                _instructions.value = emptyList()
                _elevationProfile.value = emptyList()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete route: ${route.id}", e)
                _uiState.value = _uiState.value.copy(
                    errorMessage = "Failed to delete route: ${e.message}"
                )
            }
        }
    }

    companion object {
        private const val TAG = "RouteDetailViewModel"
    }
}
