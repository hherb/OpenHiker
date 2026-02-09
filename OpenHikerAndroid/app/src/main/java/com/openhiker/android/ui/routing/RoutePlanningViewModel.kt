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

import android.content.Context
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
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID
import javax.inject.Inject

/**
 * UI state for the route planning screen.
 *
 * @property selectedRegionId Currently selected region for routing.
 * @property startPoint Start coordinate (green marker), or null.
 * @property endPoint End coordinate (red marker), or null.
 * @property viaPoints Ordered intermediate waypoints (blue markers).
 * @property routingMode Hiking or cycling.
 * @property computedRoute The computed route result, or null.
 * @property instructions Turn-by-turn instructions for the route.
 * @property isComputing True while route computation is in progress.
 * @property errorMessage Error message from last failed computation, or null.
 * @property isSaveDialogVisible Whether the save route dialog is shown.
 */
data class RoutePlanningUiState(
    val selectedRegionId: String? = null,
    val startPoint: Coordinate? = null,
    val endPoint: Coordinate? = null,
    val viaPoints: List<Coordinate> = emptyList(),
    val routingMode: RoutingMode = RoutingMode.HIKING,
    val computedRoute: ComputedRoute? = null,
    val instructions: List<TurnInstruction> = emptyList(),
    val isComputing: Boolean = false,
    val errorMessage: String? = null,
    val isSaveDialogVisible: Boolean = false
)

/**
 * ViewModel for the route planning screen.
 *
 * Manages start/end/via-point state, triggers A* route computation,
 * generates turn instructions, and persists planned routes.
 *
 * @param context Application context for file paths.
 * @param regionRepository Access to downloaded region metadata.
 * @param plannedRouteRepository Persistence for planned routes.
 */
@HiltViewModel
class RoutePlanningViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
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
            startPoint = null,
            endPoint = null,
            viaPoints = emptyList(),
            computedRoute = null,
            instructions = emptyList(),
            errorMessage = null
        )

        // Open the routing database for this region
        viewModelScope.launch(Dispatchers.IO) {
            routingStore?.close()
            val dbPath = File(
                context.filesDir,
                "regions/$regionId/$regionId.routing.db"
            ).absolutePath

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
     * Sets the start point.
     *
     * @param coordinate The start coordinate (from map tap).
     */
    fun setStartPoint(coordinate: Coordinate) {
        _uiState.value = _uiState.value.copy(
            startPoint = coordinate,
            computedRoute = null,
            instructions = emptyList(),
            errorMessage = null
        )
    }

    /**
     * Sets the end point.
     *
     * @param coordinate The end coordinate (from map tap).
     */
    fun setEndPoint(coordinate: Coordinate) {
        _uiState.value = _uiState.value.copy(
            endPoint = coordinate,
            computedRoute = null,
            instructions = emptyList(),
            errorMessage = null
        )
    }

    /**
     * Adds a via-point.
     *
     * @param coordinate The via-point coordinate (from long-press).
     */
    fun addViaPoint(coordinate: Coordinate) {
        _uiState.value = _uiState.value.copy(
            viaPoints = _uiState.value.viaPoints + coordinate,
            computedRoute = null,
            instructions = emptyList()
        )
    }

    /**
     * Removes a via-point by index.
     *
     * @param index The index to remove.
     */
    fun removeViaPoint(index: Int) {
        val updated = _uiState.value.viaPoints.toMutableList()
        if (index in updated.indices) {
            updated.removeAt(index)
            _uiState.value = _uiState.value.copy(
                viaPoints = updated,
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
            startPoint = null,
            endPoint = null,
            viaPoints = emptyList(),
            computedRoute = null,
            instructions = emptyList(),
            errorMessage = null,
            isComputing = false
        )
    }

    /**
     * Computes the route from start to end via all via-points.
     *
     * Runs the A* router on the IO dispatcher and updates the UI
     * state with the result or error message.
     */
    fun computeRoute() {
        val state = _uiState.value
        val start = state.startPoint ?: return
        val end = state.endPoint ?: return
        val store = routingStore ?: run {
            _uiState.value = state.copy(errorMessage = "No routing data loaded")
            return
        }

        computeJob?.cancel()
        _uiState.value = state.copy(isComputing = true, errorMessage = null)

        computeJob = viewModelScope.launch(Dispatchers.IO) {
            try {
                val router = AStarRouter(store)
                val route = router.findRoute(
                    from = start,
                    to = end,
                    via = state.viaPoints,
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

        viewModelScope.launch(Dispatchers.IO) {
            val plannedRoute = PlannedRoute(
                id = UUID.randomUUID().toString(),
                name = name,
                mode = state.routingMode,
                startCoordinate = state.startPoint!!,
                endCoordinate = state.endPoint!!,
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
