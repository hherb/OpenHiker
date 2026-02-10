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
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.openhiker.android.data.db.routing.RoutingStore
import com.openhiker.android.data.repository.PlannedRouteRepository
import com.openhiker.android.data.repository.RegionRepository
import com.openhiker.core.model.Coordinate
import com.openhiker.core.model.PlannedRoute
import com.openhiker.core.model.RoutingMode
import com.openhiker.core.model.TurnInstruction
import com.openhiker.core.routing.AStarRouter
import com.openhiker.core.routing.ComputedRoute
import com.openhiker.core.routing.RoutingError
import com.openhiker.core.routing.TurnDetector
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID
import javax.inject.Inject

/**
 * UI state for the route planning screen.
 *
 * @property selectedRegionId Currently selected region for routing.
 * @property waypoints Ordered waypoints placed by the user. First = start, last = end.
 * @property routingMode Hiking or cycling.
 * @property isLoopRoute Whether the last computed route is a loop (returns to start).
 * @property computedRoute The computed route result, or null.
 * @property instructions Turn-by-turn instructions for the route.
 * @property isComputing True while route computation is in progress.
 * @property errorMessage Error message from last failed computation, or null.
 * @property isSaveDialogVisible Whether the save route dialog is shown.
 */
data class RoutePlanningUiState(
    val selectedRegionId: String? = null,
    val waypoints: List<Coordinate> = emptyList(),
    val routingMode: RoutingMode = RoutingMode.HIKING,
    val isLoopRoute: Boolean = false,
    val computedRoute: ComputedRoute? = null,
    val instructions: List<TurnInstruction> = emptyList(),
    val isComputing: Boolean = false,
    val errorMessage: String? = null,
    val isSaveDialogVisible: Boolean = false
)

/**
 * ViewModel for the route planning screen.
 *
 * Users place sequential waypoints on the map, then choose "Start → End" (one-way)
 * or "Back to Start" (loop) to compute a route through all waypoints in order.
 *
 * @param regionRepository Access to downloaded region metadata and file paths.
 * @param plannedRouteRepository Persistence for planned routes.
 */
@HiltViewModel
class RoutePlanningViewModel @Inject constructor(
    private val regionRepository: RegionRepository,
    private val plannedRouteRepository: PlannedRouteRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(RoutePlanningUiState())

    /** Observable UI state. */
    val uiState: StateFlow<RoutePlanningUiState> = _uiState.asStateFlow()

    /** Available regions for route planning. */
    val regions: StateFlow<List<com.openhiker.core.model.RegionMetadata>> =
        regionRepository.regions

    private var computeJob: Job? = null
    private var routingStore: RoutingStore? = null

    /**
     * Selects a region for route planning.
     *
     * Opens the routing database for that region.
     *
     * @param regionId The region identifier.
     */
    fun selectRegion(regionId: String) {
        _uiState.value = _uiState.value.copy(
            selectedRegionId = regionId,
            waypoints = emptyList(),
            computedRoute = null,
            instructions = emptyList(),
            errorMessage = null
        )

        // Open the routing database for this region
        viewModelScope.launch(Dispatchers.IO) {
            routingStore?.close()
            val dbPath = regionRepository.routingDbPath(regionId)

            try {
                val store = RoutingStore(dbPath)
                store.open()
                routingStore = store
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    errorMessage = "No routing data for this region. Download routing data first."
                )
            }
        }
    }

    /**
     * Adds a waypoint at the given coordinate.
     *
     * Waypoints are ordered sequentially. Clears any previously computed route.
     *
     * @param coordinate The waypoint coordinate (from map tap).
     */
    fun addWaypoint(coordinate: Coordinate) {
        _uiState.value = _uiState.value.copy(
            waypoints = _uiState.value.waypoints + coordinate,
            computedRoute = null,
            instructions = emptyList(),
            errorMessage = null
        )
    }

    /**
     * Moves an existing waypoint to a new coordinate.
     *
     * @param index The waypoint index to move.
     * @param coordinate The new coordinate.
     */
    fun moveWaypoint(index: Int, coordinate: Coordinate) {
        val updated = _uiState.value.waypoints.toMutableList()
        if (index in updated.indices) {
            updated[index] = coordinate
            _uiState.value = _uiState.value.copy(
                waypoints = updated,
                computedRoute = null,
                instructions = emptyList()
            )
        }
    }

    /**
     * Removes a waypoint by index.
     *
     * @param index The waypoint index to remove.
     */
    fun removeWaypoint(index: Int) {
        val updated = _uiState.value.waypoints.toMutableList()
        if (index in updated.indices) {
            updated.removeAt(index)
            _uiState.value = _uiState.value.copy(
                waypoints = updated,
                computedRoute = null,
                instructions = emptyList()
            )
        }
    }

    /**
     * Switches the routing mode between hiking and cycling.
     *
     * @param mode The new routing mode.
     */
    fun setRoutingMode(mode: RoutingMode) {
        _uiState.value = _uiState.value.copy(
            routingMode = mode,
            computedRoute = null,
            instructions = emptyList()
        )
    }

    /**
     * Clears all waypoints and computed route.
     */
    fun clearRoute() {
        computeJob?.cancel()
        _uiState.value = _uiState.value.copy(
            waypoints = emptyList(),
            computedRoute = null,
            instructions = emptyList(),
            errorMessage = null,
            isComputing = false
        )
    }

    /**
     * Computes a route through all waypoints in order.
     *
     * Uses the first waypoint as start and last as end, with all intermediate
     * waypoints as via-points. If [loop] is true, the route returns to the start.
     *
     * @param loop If true, routes back to the first waypoint (round-trip).
     */
    fun computeRoute(loop: Boolean) {
        val state = _uiState.value
        val waypoints = state.waypoints
        if (waypoints.size < 2) return

        val store = routingStore ?: run {
            _uiState.value = state.copy(errorMessage = "No routing data loaded")
            return
        }

        val start = waypoints.first()
        val end = if (loop) waypoints.first() else waypoints.last()
        val via = if (loop) {
            // Loop: 1→2→3→4→5→1, via = waypoints[1..<count]
            waypoints.drop(1)
        } else {
            // One-way: 1→2→3→4→5, via = waypoints[1..<count-1]
            if (waypoints.size > 2) waypoints.subList(1, waypoints.size - 1) else emptyList()
        }

        computeJob?.cancel()
        _uiState.value = state.copy(
            isComputing = true,
            isLoopRoute = loop,
            errorMessage = null,
            computedRoute = null,
            instructions = emptyList()
        )

        computeJob = viewModelScope.launch(Dispatchers.IO) {
            try {
                val router = AStarRouter(store)
                val route = router.findRoute(
                    from = start,
                    to = end,
                    via = via,
                    mode = state.routingMode
                )

                val instructions = TurnDetector.generateInstructions(route)

                withContext(Dispatchers.Main) {
                    _uiState.value = _uiState.value.copy(
                        computedRoute = route,
                        instructions = instructions,
                        isComputing = false,
                        errorMessage = null
                    )
                }
            } catch (e: RoutingError) {
                withContext(Dispatchers.Main) {
                    _uiState.value = _uiState.value.copy(
                        isComputing = false,
                        errorMessage = e.message
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Route computation failed", e)
                withContext(Dispatchers.Main) {
                    _uiState.value = _uiState.value.copy(
                        isComputing = false,
                        errorMessage = "Route computation failed: ${e.message}"
                    )
                }
            }
        }
    }

    /**
     * Shows the save route dialog.
     */
    fun showSaveDialog() {
        _uiState.value = _uiState.value.copy(isSaveDialogVisible = true)
    }

    /**
     * Hides the save route dialog.
     */
    fun dismissSaveDialog() {
        _uiState.value = _uiState.value.copy(isSaveDialogVisible = false)
    }

    /**
     * Saves the computed route with the given name.
     *
     * @param name User-provided route name.
     */
    fun saveRoute(name: String) {
        val state = _uiState.value
        val route = state.computedRoute ?: return
        val waypoints = state.waypoints
        if (waypoints.size < 2) return

        viewModelScope.launch(Dispatchers.IO) {
            val plannedRoute = PlannedRoute(
                id = UUID.randomUUID().toString(),
                name = name,
                mode = state.routingMode,
                startCoordinate = waypoints.first(),
                endCoordinate = if (state.isLoopRoute) waypoints.first() else waypoints.last(),
                viaPoints = route.viaPoints,
                coordinates = route.coordinates,
                turnInstructions = state.instructions,
                totalDistance = route.totalDistance,
                estimatedDuration = route.estimatedDuration,
                elevationGain = route.elevationGain,
                elevationLoss = route.elevationLoss,
                createdAt = java.time.Instant.now().toString(),
                regionId = state.selectedRegionId
            )
            plannedRouteRepository.save(plannedRoute)

            withContext(Dispatchers.Main) {
                _uiState.value = _uiState.value.copy(isSaveDialogVisible = false)
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        routingStore?.close()
    }

    companion object {
        private const val TAG = "RoutePlanningViewModel"
    }
}
