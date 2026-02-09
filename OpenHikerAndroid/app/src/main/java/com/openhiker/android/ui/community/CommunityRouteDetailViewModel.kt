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

package com.openhiker.android.ui.community

import android.util.Log
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.openhiker.android.data.repository.PlannedRouteRepository
import com.openhiker.android.service.community.GitHubRouteService
import com.openhiker.core.community.CommunityRouteConverter
import com.openhiker.core.community.SharedRoute
import com.openhiker.core.model.HikeStatsFormatter
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI state for the community route detail screen.
 *
 * @property route The full shared route data, or null while loading.
 * @property formattedDistance Human-readable distance.
 * @property formattedElevationGain Human-readable elevation gain.
 * @property formattedElevationLoss Human-readable elevation loss.
 * @property formattedDuration Human-readable duration.
 * @property isLoading True while fetching the route.
 * @property isSaving True while saving the route locally.
 * @property savedSuccessfully True after a successful save.
 * @property error Error message for display, or null.
 */
data class CommunityRouteDetailUiState(
    val route: SharedRoute? = null,
    val formattedDistance: String = "",
    val formattedElevationGain: String = "",
    val formattedElevationLoss: String = "",
    val formattedDuration: String = "",
    val isLoading: Boolean = true,
    val isSaving: Boolean = false,
    val savedSuccessfully: Boolean = false,
    val error: String? = null
)

/**
 * ViewModel for the community route detail screen.
 *
 * Fetches the full [SharedRoute] from the GitHub repository via
 * [GitHubRouteService] and supports saving the route locally as a
 * [PlannedRoute] via [CommunityRouteConverter].
 *
 * The route path is extracted from the navigation argument "routePath".
 *
 * @param savedStateHandle Provides the "routePath" navigation argument.
 * @param gitHubRouteService Service for fetching the full route JSON.
 * @param plannedRouteRepository Repository for saving downloaded routes locally.
 */
@HiltViewModel
class CommunityRouteDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val gitHubRouteService: GitHubRouteService,
    private val plannedRouteRepository: PlannedRouteRepository
) : ViewModel() {

    /** The repository-relative path to the route directory (URL-decoded). */
    private val routePath: String = try {
        java.net.URLDecoder.decode(savedStateHandle.get<String>("routePath") ?: "", "UTF-8")
    } catch (_: Exception) {
        savedStateHandle.get<String>("routePath") ?: ""
    }

    private val _uiState = MutableStateFlow(CommunityRouteDetailUiState())

    /** Observable UI state for the detail screen. */
    val uiState: StateFlow<CommunityRouteDetailUiState> = _uiState.asStateFlow()

    init {
        loadRoute()
    }

    /**
     * Saves the displayed community route as a local planned route.
     *
     * Converts the [SharedRoute] to a [PlannedRoute] using
     * [CommunityRouteConverter] and persists it via [PlannedRouteRepository].
     */
    fun saveRouteLocally() {
        val route = _uiState.value.route ?: return
        _uiState.value = _uiState.value.copy(isSaving = true)

        viewModelScope.launch {
            try {
                val planned = CommunityRouteConverter.sharedRouteToPlannedRoute(route)
                plannedRouteRepository.save(planned)
                _uiState.value = _uiState.value.copy(
                    isSaving = false,
                    savedSuccessfully = true
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed to save community route locally", e)
                _uiState.value = _uiState.value.copy(
                    isSaving = false,
                    error = "Failed to save route: ${e.message}"
                )
            }
        }
    }

    /**
     * Clears the error message after display.
     */
    fun clearError() {
        _uiState.value = _uiState.value.copy(error = null)
    }

    /**
     * Clears the save-success flag after the confirmation has been shown.
     */
    fun clearSaveSuccess() {
        _uiState.value = _uiState.value.copy(savedSuccessfully = false)
    }

    /** Fetches the full route JSON from the GitHub repository. */
    private fun loadRoute() {
        if (routePath.isBlank()) {
            _uiState.value = CommunityRouteDetailUiState(
                isLoading = false,
                error = "Invalid route path"
            )
            return
        }

        viewModelScope.launch {
            try {
                val route = gitHubRouteService.fetchRoute(routePath)
                if (route != null) {
                    _uiState.value = CommunityRouteDetailUiState(
                        route = route,
                        formattedDistance = HikeStatsFormatter.formatDistance(
                            route.stats.distanceMeters
                        ),
                        formattedElevationGain = HikeStatsFormatter.formatElevation(
                            route.stats.elevationGainMeters
                        ),
                        formattedElevationLoss = HikeStatsFormatter.formatElevation(
                            route.stats.elevationLossMeters
                        ),
                        formattedDuration = HikeStatsFormatter.formatDuration(
                            route.stats.durationSeconds
                        ),
                        isLoading = false
                    )
                } else {
                    _uiState.value = CommunityRouteDetailUiState(
                        isLoading = false,
                        error = "Failed to load route. Check your internet connection."
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to fetch route: $routePath", e)
                _uiState.value = CommunityRouteDetailUiState(
                    isLoading = false,
                    error = "Failed to load route: ${e.message}"
                )
            }
        }
    }

    companion object {
        private const val TAG = "CommunityDetailVM"
    }
}
