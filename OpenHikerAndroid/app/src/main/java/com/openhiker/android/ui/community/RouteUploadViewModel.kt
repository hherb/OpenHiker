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
import com.openhiker.core.model.PlannedRoute
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI state for the route upload screen.
 *
 * @property route The planned route to upload, or null if not found.
 * @property author Author display name entered by the user.
 * @property description Route description entered by the user.
 * @property country ISO country code (e.g., "US", "DE").
 * @property area State or region name (e.g., "California").
 * @property isUploading True while the upload is in progress.
 * @property uploadSuccess True after a successful upload.
 * @property pullRequestUrl URL of the created PR, or null.
 * @property error Error message for display, or null.
 */
data class RouteUploadUiState(
    val route: PlannedRoute? = null,
    val author: String = "",
    val description: String = "",
    val country: String = "",
    val area: String = "",
    val isUploading: Boolean = false,
    val uploadSuccess: Boolean = false,
    val pullRequestUrl: String? = null,
    val error: String? = null
)

/**
 * ViewModel for the route upload screen.
 *
 * Loads a [PlannedRoute] by ID from [PlannedRouteRepository], collects
 * user-provided metadata (author, description, country, area), converts
 * to a [SharedRoute] via [CommunityRouteConverter], and uploads via
 * [GitHubRouteService].
 *
 * The route ID is extracted from the navigation argument "routeId".
 *
 * @param savedStateHandle Provides the "routeId" navigation argument.
 * @param plannedRouteRepository Repository for loading the route to upload.
 * @param gitHubRouteService Service for uploading to the community repository.
 */
@HiltViewModel
class RouteUploadViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val plannedRouteRepository: PlannedRouteRepository,
    private val gitHubRouteService: GitHubRouteService
) : ViewModel() {

    private val routeId: String = savedStateHandle.get<String>("routeId") ?: ""

    private val _uiState = MutableStateFlow(RouteUploadUiState())

    /** Observable UI state for the upload screen. */
    val uiState: StateFlow<RouteUploadUiState> = _uiState.asStateFlow()

    init {
        loadRoute()
    }

    /**
     * Updates the author field.
     *
     * @param author The new author display name.
     */
    fun setAuthor(author: String) {
        _uiState.value = _uiState.value.copy(author = author)
    }

    /**
     * Updates the description field.
     *
     * @param description The new route description.
     */
    fun setDescription(description: String) {
        _uiState.value = _uiState.value.copy(description = description)
    }

    /**
     * Updates the country code field.
     *
     * @param country ISO 3166-1 alpha-2 country code.
     */
    fun setCountry(country: String) {
        _uiState.value = _uiState.value.copy(country = country)
    }

    /**
     * Updates the area/region field.
     *
     * @param area State or region name.
     */
    fun setArea(area: String) {
        _uiState.value = _uiState.value.copy(area = area)
    }

    /**
     * Validates form input and uploads the route to the community repository.
     *
     * Converts the [PlannedRoute] to a [SharedRoute] with user-provided
     * metadata, then calls [GitHubRouteService.uploadRoute].
     */
    fun upload() {
        val state = _uiState.value
        val route = state.route ?: return

        if (state.author.isBlank()) {
            _uiState.value = state.copy(error = "Please enter your name or alias")
            return
        }
        if (state.country.length != COUNTRY_CODE_LENGTH) {
            _uiState.value = state.copy(error = "Please enter a 2-letter country code (e.g., US, DE)")
            return
        }
        if (state.area.isBlank()) {
            _uiState.value = state.copy(error = "Please enter the area or region name")
            return
        }

        _uiState.value = state.copy(isUploading = true, error = null)

        viewModelScope.launch {
            try {
                val sharedRoute = CommunityRouteConverter.plannedRouteToSharedRoute(
                    route = route,
                    author = state.author.trim(),
                    description = state.description.trim(),
                    country = state.country.uppercase().trim(),
                    area = state.area.trim()
                )

                val prUrl = gitHubRouteService.uploadRoute(sharedRoute)
                if (prUrl != null) {
                    _uiState.value = _uiState.value.copy(
                        isUploading = false,
                        uploadSuccess = true,
                        pullRequestUrl = prUrl
                    )
                } else {
                    _uiState.value = _uiState.value.copy(
                        isUploading = false,
                        error = "Upload failed. Please check your internet connection and try again."
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Route upload failed", e)
                _uiState.value = _uiState.value.copy(
                    isUploading = false,
                    error = "Upload failed: ${e.message}"
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

    /** Loads the planned route by ID from the repository. */
    private fun loadRoute() {
        if (routeId.isBlank()) return
        viewModelScope.launch {
            try {
                val route = plannedRouteRepository.getById(routeId)
                _uiState.value = _uiState.value.copy(route = route)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load route: $routeId", e)
                _uiState.value = _uiState.value.copy(
                    error = "Failed to load route: ${e.message}"
                )
            }
        }
    }

    companion object {
        private const val TAG = "RouteUploadVM"
        private const val COUNTRY_CODE_LENGTH = 2
    }
}
