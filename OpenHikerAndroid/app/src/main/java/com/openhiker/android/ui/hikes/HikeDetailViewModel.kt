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

package com.openhiker.android.ui.hikes

import android.util.Log
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.openhiker.android.data.db.routes.SavedRouteEntity
import com.openhiker.android.data.db.waypoints.WaypointSummary
import com.openhiker.android.data.repository.RouteRepository
import com.openhiker.android.data.repository.WaypointRepository
import com.openhiker.core.compression.TrackCompression
import com.openhiker.core.compression.TrackPoint
import com.openhiker.core.geo.Haversine
import com.openhiker.core.model.Coordinate
import com.openhiker.core.model.ElevationPoint
import com.openhiker.core.model.HikeStatsFormatter
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI state for the hike detail screen.
 *
 * Contains all data needed to render the detail view: route metadata,
 * formatted statistics, decompressed track coordinates for the map,
 * elevation profile data for the chart, and associated waypoints.
 *
 * @property isLoading True while the route is being loaded and track data decompressed.
 * @property error Non-null error message if loading failed.
 * @property route The raw saved route entity, or null if not yet loaded.
 * @property hikeName Display name of the hike.
 * @property startTime ISO-8601 start timestamp.
 * @property endTime ISO-8601 end timestamp.
 * @property formattedDistance Human-readable distance (e.g. "12.4 km").
 * @property formattedElevationGain Human-readable elevation gain (e.g. "850 m").
 * @property formattedElevationLoss Human-readable elevation loss (e.g. "720 m").
 * @property formattedDuration Human-readable total duration (e.g. "03:45:12").
 * @property formattedWalkingTime Human-readable walking time.
 * @property formattedRestingTime Human-readable resting time.
 * @property formattedAvgHeartRate Formatted average heart rate, or null if unavailable.
 * @property formattedMaxHeartRate Formatted max heart rate, or null if unavailable.
 * @property formattedCalories Formatted estimated calories, or null if unavailable.
 * @property comment User comment for the hike.
 * @property trackCoordinates Decompressed track as map-ready coordinates.
 * @property elevationProfile Elevation profile data points for the chart.
 * @property waypoints Waypoints associated with this hike.
 * @property isRenameDialogVisible True when the rename dialog is shown.
 * @property isDeleteDialogVisible True when the delete confirmation dialog is shown.
 */
data class HikeDetailUiState(
    val isLoading: Boolean = true,
    val error: String? = null,
    val route: SavedRouteEntity? = null,
    val hikeName: String = "",
    val startTime: String = "",
    val endTime: String = "",
    val formattedDistance: String = "",
    val formattedElevationGain: String = "",
    val formattedElevationLoss: String = "",
    val formattedDuration: String = "",
    val formattedWalkingTime: String = "",
    val formattedRestingTime: String = "",
    val formattedAvgHeartRate: String? = null,
    val formattedMaxHeartRate: String? = null,
    val formattedCalories: String? = null,
    val comment: String = "",
    val trackCoordinates: List<Coordinate> = emptyList(),
    val elevationProfile: List<ElevationPoint> = emptyList(),
    val waypoints: List<WaypointSummary> = emptyList(),
    val isRenameDialogVisible: Boolean = false,
    val isDeleteDialogVisible: Boolean = false,
    val isDeleted: Boolean = false
)

/**
 * ViewModel for the hike detail screen.
 *
 * Loads a single saved route by ID (obtained from navigation arguments via
 * [SavedStateHandle]), decompresses its binary track data using
 * [TrackCompression], and prepares display-ready state including:
 *
 * - Formatted statistics (distance, elevation, duration, heart rate, calories)
 * - Map-ready coordinate list for track overlay rendering
 * - Elevation profile data points for chart display
 * - Associated waypoints from [WaypointRepository]
 *
 * Supports rename and delete operations with confirmation dialogs.
 * All state is exposed as a single [StateFlow] of [HikeDetailUiState].
 *
 * @param routeRepository Provides access to saved route entities.
 * @param waypointRepository Provides access to waypoints linked to this hike.
 * @param savedStateHandle Contains the "hikeId" navigation argument.
 */
@HiltViewModel
class HikeDetailViewModel @Inject constructor(
    private val routeRepository: RouteRepository,
    private val waypointRepository: WaypointRepository,
    savedStateHandle: SavedStateHandle
) : ViewModel() {

    private val _uiState = MutableStateFlow(HikeDetailUiState())

    /** Observable UI state for the hike detail screen. */
    val uiState: StateFlow<HikeDetailUiState> = _uiState.asStateFlow()

    /** The hike ID extracted from navigation arguments. */
    private val hikeId: String? = savedStateHandle.get<String>(NAV_ARG_HIKE_ID)

    init {
        if (hikeId != null) {
            loadHike(hikeId)
        } else {
            _uiState.update { it.copy(isLoading = false, error = "No hike ID provided") }
            Log.w(TAG, "HikeDetailViewModel created without a hikeId navigation argument")
        }
    }

    /**
     * Loads a saved hike by ID and populates the UI state.
     *
     * Performs three operations in sequence:
     * 1. Fetches the route entity from the database
     * 2. Decompresses track data and builds coordinates + elevation profile
     * 3. Loads associated waypoints
     *
     * All work runs in [viewModelScope] on the default dispatcher,
     * with Room handling the IO thread switch internally.
     *
     * @param id The UUID of the saved route to load.
     */
    private fun loadHike(id: String) {
        viewModelScope.launch {
            try {
                val route = routeRepository.getById(id)
                if (route == null) {
                    _uiState.update {
                        it.copy(isLoading = false, error = "Hike not found")
                    }
                    Log.w(TAG, "Saved route not found for id: $id")
                    return@launch
                }

                val trackPoints = decompressTrackData(route.trackData)
                val coordinates = trackPointsToCoordinates(trackPoints)
                val elevationProfile = buildElevationProfile(trackPoints)
                val waypoints = waypointRepository.getByHike(id)

                _uiState.update {
                    it.copy(
                        isLoading = false,
                        error = null,
                        route = route,
                        hikeName = route.name,
                        startTime = route.startTime,
                        endTime = route.endTime,
                        formattedDistance = HikeStatsFormatter.formatDistance(route.totalDistance),
                        formattedElevationGain = HikeStatsFormatter.formatElevation(
                            route.elevationGain
                        ),
                        formattedElevationLoss = HikeStatsFormatter.formatElevation(
                            route.elevationLoss
                        ),
                        formattedDuration = HikeStatsFormatter.formatDuration(
                            route.walkingTime + route.restingTime
                        ),
                        formattedWalkingTime = HikeStatsFormatter.formatDuration(
                            route.walkingTime
                        ),
                        formattedRestingTime = HikeStatsFormatter.formatDuration(
                            route.restingTime
                        ),
                        formattedAvgHeartRate = route.averageHeartRate?.let {
                            hr -> HikeStatsFormatter.formatHeartRate(hr)
                        },
                        formattedMaxHeartRate = route.maxHeartRate?.let {
                            hr -> HikeStatsFormatter.formatHeartRate(hr)
                        },
                        formattedCalories = route.estimatedCalories?.let {
                            cal -> HikeStatsFormatter.formatCalories(cal)
                        },
                        comment = route.comment,
                        trackCoordinates = coordinates,
                        elevationProfile = elevationProfile,
                        waypoints = waypoints
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load hike: $id", e)
                _uiState.update {
                    it.copy(isLoading = false, error = "Failed to load hike: ${e.message}")
                }
            }
        }
    }

    /**
     * Decompresses binary track data into a list of track points.
     *
     * Uses [TrackCompression.decompress] which handles both zlib-compressed
     * and legacy uncompressed formats transparently.
     *
     * @param data The compressed binary track data from the database.
     * @return List of decompressed GPS track points.
     */
    private fun decompressTrackData(data: ByteArray): List<TrackPoint> {
        return TrackCompression.decompress(data)
    }

    /**
     * Converts a list of track points to map-ready [Coordinate] instances.
     *
     * Extracts only latitude and longitude, discarding altitude and timestamp
     * which are not needed for the map polyline overlay.
     *
     * @param trackPoints The decompressed GPS track points.
     * @return List of coordinates suitable for map rendering.
     */
    private fun trackPointsToCoordinates(trackPoints: List<TrackPoint>): List<Coordinate> {
        return trackPoints.map { point ->
            Coordinate(
                latitude = point.latitude,
                longitude = point.longitude
            )
        }
    }

    /**
     * Builds an elevation profile from track points.
     *
     * Computes cumulative Haversine distance from the start for each point
     * and pairs it with the altitude, producing [ElevationPoint] instances
     * suitable for rendering an elevation chart.
     *
     * Uses [Haversine.distance] for accurate great-circle segment lengths
     * between consecutive GPS points.
     *
     * @param trackPoints The decompressed GPS track points.
     * @return List of elevation profile data points, ordered by distance.
     */
    private fun buildElevationProfile(trackPoints: List<TrackPoint>): List<ElevationPoint> {
        if (trackPoints.isEmpty()) return emptyList()

        val profile = mutableListOf<ElevationPoint>()
        var cumulativeDistance = 0.0

        profile.add(ElevationPoint(distance = 0.0, elevation = trackPoints[0].altitude))

        for (i in 1 until trackPoints.size) {
            val prev = trackPoints[i - 1]
            val curr = trackPoints[i]

            cumulativeDistance += Haversine.distance(
                prev.latitude, prev.longitude,
                curr.latitude, curr.longitude
            )

            profile.add(
                ElevationPoint(
                    distance = cumulativeDistance,
                    elevation = curr.altitude
                )
            )
        }

        return profile
    }

    /**
     * Shows the rename dialog for the current hike.
     */
    fun showRenameDialog() {
        _uiState.update { it.copy(isRenameDialogVisible = true) }
    }

    /**
     * Dismisses the rename dialog without saving changes.
     */
    fun dismissRenameDialog() {
        _uiState.update { it.copy(isRenameDialogVisible = false) }
    }

    /**
     * Renames the current hike and persists the change.
     *
     * Updates the route entity in the database with the new name,
     * then refreshes the local UI state. The rename dialog is dismissed
     * automatically on success.
     *
     * @param newName The new display name for the hike.
     */
    fun renameHike(newName: String) {
        val route = _uiState.value.route ?: return
        viewModelScope.launch {
            try {
                val updatedRoute = route.copy(name = newName)
                routeRepository.save(updatedRoute)
                _uiState.update {
                    it.copy(
                        route = updatedRoute,
                        hikeName = newName,
                        isRenameDialogVisible = false
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to rename hike: ${route.id}", e)
                _uiState.update {
                    it.copy(
                        error = "Failed to rename hike: ${e.message}",
                        isRenameDialogVisible = false
                    )
                }
            }
        }
    }

    /**
     * Shows the delete confirmation dialog.
     */
    fun showDeleteDialog() {
        _uiState.update { it.copy(isDeleteDialogVisible = true) }
    }

    /**
     * Dismisses the delete confirmation dialog without deleting.
     */
    fun dismissDeleteDialog() {
        _uiState.update { it.copy(isDeleteDialogVisible = false) }
    }

    /**
     * Confirms and executes deletion of the current hike.
     *
     * Deletes the saved route from the database via [RouteRepository].
     * After deletion, the UI should navigate back to the list screen;
     * the composable observes [isDeleted] to trigger navigation.
     *
     * @return True if the delete was initiated, false if no route was loaded.
     */
    fun confirmDelete() {
        val route = _uiState.value.route ?: return
        viewModelScope.launch {
            try {
                routeRepository.delete(route.id)
                _uiState.update {
                    it.copy(
                        isDeleteDialogVisible = false,
                        isDeleted = true,
                        error = null
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete hike: ${route.id}", e)
                _uiState.update {
                    it.copy(
                        error = "Failed to delete hike: ${e.message}",
                        isDeleteDialogVisible = false
                    )
                }
            }
        }
    }

    /**
     * Reloads the hike data from the database.
     *
     * Useful after external modifications (e.g. cloud sync update)
     * or to retry after a transient error.
     */
    fun refresh() {
        val id = hikeId ?: return
        _uiState.update { it.copy(isLoading = true, error = null) }
        loadHike(id)
    }

    companion object {
        private const val TAG = "HikeDetailViewModel"

        /** Navigation argument key for the hike ID. */
        const val NAV_ARG_HIKE_ID = "hikeId"
    }
}
