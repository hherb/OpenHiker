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
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.openhiker.android.service.community.GitHubRouteService
import com.openhiker.core.community.RouteIndexEntry
import com.openhiker.core.community.RouteIndexFilter
import com.openhiker.core.model.HikeStatsFormatter
import com.openhiker.core.model.RoutingMode
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Available sort criteria for the community route list.
 */
enum class CommunitySortOption {
    /** Sort by creation date, newest first. */
    DATE,
    /** Sort by total distance, longest first. */
    DISTANCE,
    /** Sort by elevation gain, highest first. */
    ELEVATION,
    /** Sort alphabetically by name. */
    NAME
}

/**
 * Display-ready summary of a community route for the browse list.
 *
 * Pre-formats statistics to avoid formatting during recomposition.
 *
 * @property id Route UUID for navigation to detail screen.
 * @property name Route display name.
 * @property author Route creator's display name.
 * @property summary First 200 characters of the description.
 * @property activityType Hiking or cycling icon indicator.
 * @property country ISO country code for flag display.
 * @property area Region/state name.
 * @property formattedDistance Human-readable distance (e.g., "12.4 km").
 * @property formattedElevation Human-readable elevation gain (e.g., "850 m").
 * @property formattedDuration Human-readable duration (e.g., "03:45:00").
 * @property path Repository path for fetching full route detail.
 * @property photoCount Number of photos attached.
 * @property waypointCount Number of waypoints.
 * @property createdAt ISO-8601 creation timestamp for sorting.
 */
data class CommunityRouteListItem(
    val id: String,
    val name: String,
    val author: String,
    val summary: String,
    val activityType: RoutingMode,
    val country: String,
    val area: String,
    val formattedDistance: String,
    val formattedElevation: String,
    val formattedDuration: String,
    val path: String,
    val photoCount: Int,
    val waypointCount: Int,
    val createdAt: String
)

/**
 * UI state for the community browse screen.
 *
 * @property routes The filtered, sorted list of community routes.
 * @property searchQuery Current search text.
 * @property sortOption Current sort criterion.
 * @property activityFilter Current activity type filter, or null for all.
 * @property countryFilter Current country code filter, or null for all.
 * @property availableCountries List of country codes available for filtering.
 * @property isLoading True during initial or refresh fetch.
 * @property isRefreshing True during pull-to-refresh.
 * @property isEmpty True when the repository has no routes at all.
 * @property error Error message for display, or null.
 */
data class CommunityBrowseUiState(
    val routes: List<CommunityRouteListItem> = emptyList(),
    val searchQuery: String = "",
    val sortOption: CommunitySortOption = CommunitySortOption.DATE,
    val activityFilter: RoutingMode? = null,
    val countryFilter: String? = null,
    val availableCountries: List<String> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val isEmpty: Boolean = false,
    val error: String? = null
)

/**
 * ViewModel for the community route browse screen.
 *
 * Fetches the route index from [GitHubRouteService], applies search/filter/sort
 * using [RouteIndexFilter] pure functions, and exposes the results as a
 * [StateFlow] of [CommunityBrowseUiState].
 *
 * Supports pull-to-refresh, text search, activity type filtering,
 * country filtering, and multiple sort criteria.
 *
 * @param gitHubRouteService Service for fetching community route data.
 */
@HiltViewModel
class CommunityViewModel @Inject constructor(
    private val gitHubRouteService: GitHubRouteService
) : ViewModel() {

    /** Raw route index entries from the last successful fetch. */
    private val _allEntries = MutableStateFlow<List<RouteIndexEntry>>(emptyList())

    /** Current search query text. */
    private val _searchQuery = MutableStateFlow("")

    /** Current sort criterion. */
    private val _sortOption = MutableStateFlow(CommunitySortOption.DATE)

    /** Current activity type filter (null = all). */
    private val _activityFilter = MutableStateFlow<RoutingMode?>(null)

    /** Current country code filter (null = all). */
    private val _countryFilter = MutableStateFlow<String?>(null)

    /** Loading state for initial fetch. */
    private val _isLoading = MutableStateFlow(true)

    /** Refreshing state for pull-to-refresh. */
    private val _isRefreshing = MutableStateFlow(false)

    /** Error message, or null. */
    private val _error = MutableStateFlow<String?>(null)

    /**
     * Combined UI state exposed to the composable.
     *
     * Reactively recomputes whenever any input (entries, search, filter, sort) changes.
     */
    val uiState: StateFlow<CommunityBrowseUiState> = combine(
        _allEntries, _searchQuery, _sortOption, _activityFilter, _countryFilter
    ) { entries, query, sort, activity, country ->
        val filtered = RouteIndexFilter.applyFilters(
            entries = entries,
            query = query,
            activityType = activity,
            countryCode = country
        )

        val sorted = when (sort) {
            CommunitySortOption.DATE -> RouteIndexFilter.sortByDateDescending(filtered)
            CommunitySortOption.DISTANCE -> RouteIndexFilter.sortByDistanceDescending(filtered)
            CommunitySortOption.ELEVATION -> RouteIndexFilter.sortByElevationDescending(filtered)
            CommunitySortOption.NAME -> RouteIndexFilter.sortByNameAscending(filtered)
        }

        val listItems = sorted.map { it.toListItem() }
        val countries = RouteIndexFilter.distinctCountries(entries)

        CommunityBrowseUiState(
            routes = listItems,
            searchQuery = query,
            sortOption = sort,
            activityFilter = activity,
            countryFilter = country,
            availableCountries = countries,
            isLoading = _isLoading.value,
            isRefreshing = _isRefreshing.value,
            isEmpty = entries.isEmpty() && !_isLoading.value,
            error = _error.value
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(STOP_TIMEOUT_MS),
        initialValue = CommunityBrowseUiState()
    )

    init {
        loadIndex()
    }

    /**
     * Refreshes the route index from the network (pull-to-refresh).
     */
    fun refresh() {
        _isRefreshing.value = true
        loadIndex(forceRefresh = true)
    }

    /**
     * Updates the search query and triggers re-filtering.
     *
     * @param query The new search text.
     */
    fun setSearchQuery(query: String) {
        _searchQuery.value = query
    }

    /**
     * Updates the sort criterion and triggers re-sorting.
     *
     * @param option The new sort criterion.
     */
    fun setSortOption(option: CommunitySortOption) {
        _sortOption.value = option
    }

    /**
     * Updates the activity type filter.
     *
     * @param type The activity type to filter by, or null for all.
     */
    fun setActivityFilter(type: RoutingMode?) {
        _activityFilter.value = type
    }

    /**
     * Updates the country filter.
     *
     * @param countryCode ISO country code, or null for all countries.
     */
    fun setCountryFilter(countryCode: String?) {
        _countryFilter.value = countryCode
    }

    /**
     * Clears the error message after it has been displayed.
     */
    fun clearError() {
        _error.value = null
    }

    /**
     * Fetches the route index from the GitHub service.
     *
     * @param forceRefresh If true, bypasses the service cache.
     */
    private fun loadIndex(forceRefresh: Boolean = false) {
        viewModelScope.launch {
            try {
                val index = gitHubRouteService.fetchRouteIndex(forceRefresh)
                if (index != null) {
                    _allEntries.value = index.routes
                    _error.value = null
                } else {
                    _error.value = "Failed to load community routes. Check your internet connection."
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to fetch route index", e)
                _error.value = "Failed to load community routes: ${e.message}"
            } finally {
                _isLoading.value = false
                _isRefreshing.value = false
            }
        }
    }

    /**
     * Converts a [RouteIndexEntry] to a display-ready [CommunityRouteListItem].
     *
     * Pre-formats distance, elevation, and duration statistics.
     */
    private fun RouteIndexEntry.toListItem(): CommunityRouteListItem {
        return CommunityRouteListItem(
            id = id,
            name = name,
            author = author,
            summary = summary,
            activityType = activityType,
            country = region.country,
            area = region.area,
            formattedDistance = HikeStatsFormatter.formatDistance(stats.distanceMeters),
            formattedElevation = HikeStatsFormatter.formatElevation(stats.elevationGainMeters),
            formattedDuration = HikeStatsFormatter.formatDuration(stats.durationSeconds),
            path = path,
            photoCount = photoCount,
            waypointCount = waypointCount,
            createdAt = createdAt
        )
    }

    companion object {
        private const val TAG = "CommunityVM"
        private const val STOP_TIMEOUT_MS = 5_000L
    }
}
