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

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.openhiker.android.data.db.routes.SavedRouteEntity
import com.openhiker.android.data.repository.RouteRepository
import com.openhiker.core.model.HikeStatsFormatter
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Available sort criteria for the hike list.
 *
 * Each variant defines a different ordering of saved hikes.
 * [DATE] is the default, showing the most recent hike first.
 */
enum class HikeSortOption {
    /** Sort by start time, newest first. */
    DATE,
    /** Sort by total distance, longest first. */
    DISTANCE,
    /** Sort by elevation gain, highest first. */
    ELEVATION,
    /** Sort by total duration (walking + resting), longest first. */
    DURATION
}

/**
 * Display-ready summary of a single saved hike for the list screen.
 *
 * Pre-formats statistics using [HikeStatsFormatter] so the composable
 * layer does not need to perform formatting during recomposition.
 *
 * @property id Unique identifier of the saved route.
 * @property name User-assigned hike name.
 * @property startTime ISO-8601 start timestamp for display and sorting.
 * @property formattedDistance Human-readable distance (e.g. "12.4 km").
 * @property formattedElevationGain Human-readable elevation gain (e.g. "850 m").
 * @property formattedDuration Human-readable duration (e.g. "03:45:12").
 * @property totalDistance Raw distance in metres, used for sorting.
 * @property elevationGain Raw elevation gain in metres, used for sorting.
 * @property durationSeconds Raw total duration in seconds, used for sorting.
 */
data class HikeListItem(
    val id: String,
    val name: String,
    val startTime: String,
    val formattedDistance: String,
    val formattedElevationGain: String,
    val formattedDuration: String,
    val totalDistance: Double,
    val elevationGain: Double,
    val durationSeconds: Double
)

/**
 * UI state for the hike list screen.
 *
 * Encapsulates every piece of data the composable needs to render,
 * following the unidirectional data flow pattern. The ViewModel
 * produces this state; the composable only reads it.
 *
 * @property hikes The filtered, sorted list of hike display items.
 * @property sortOption The currently active sort criterion.
 * @property searchQuery The current search filter text (empty = no filter).
 * @property isLoading True while the initial data load is in progress.
 * @property isEmpty True when no hikes exist at all (ignoring search/sort).
 * @property deleteConfirmationHike The hike pending delete confirmation, or null.
 */
data class HikeListUiState(
    val hikes: List<HikeListItem> = emptyList(),
    val sortOption: HikeSortOption = HikeSortOption.DATE,
    val searchQuery: String = "",
    val isLoading: Boolean = true,
    val isEmpty: Boolean = false,
    val deleteConfirmationHike: HikeListItem? = null
)

/**
 * ViewModel for the hike history list screen.
 *
 * Observes all saved routes from [RouteRepository] and transforms them
 * into display-ready [HikeListItem] instances. Supports sorting by date,
 * distance, elevation, or duration, and filtering by name search query.
 * Delete operations require explicit confirmation via a two-step flow.
 *
 * The combined state is exposed as a single [StateFlow] of [HikeListUiState],
 * which the composable collects. All database mutations are launched in
 * [viewModelScope] coroutines.
 *
 * @param routeRepository Provides reactive access to saved route entities.
 */
@HiltViewModel
class HikeListViewModel @Inject constructor(
    private val routeRepository: RouteRepository
) : ViewModel() {

    /** Current sort criterion, drives recomputation of the hike list. */
    private val _sortOption = MutableStateFlow(HikeSortOption.DATE)

    /** Current search query, drives filtering of the hike list. */
    private val _searchQuery = MutableStateFlow("")

    /** The hike currently awaiting delete confirmation, or null. */
    private val _deleteConfirmationHike = MutableStateFlow<HikeListItem?>(null)

    /**
     * Observable UI state combining routes, sort option, search query,
     * and delete confirmation into a single immutable snapshot.
     *
     * Uses [combine] to reactively recompute whenever any input changes:
     * the route list from the database, the sort option, or the search query.
     * The resulting list is filtered by name, then sorted according to the
     * selected criterion.
     */
    val uiState: StateFlow<HikeListUiState> = combine(
        routeRepository.observeAll(),
        _sortOption,
        _searchQuery,
        _deleteConfirmationHike
    ) { routes, sortOption, query, deleteHike ->
        val allItems = routes.map { entity -> entity.toListItem() }
        val filtered = filterByQuery(allItems, query)
        val sorted = sortItems(filtered, sortOption)

        HikeListUiState(
            hikes = sorted,
            sortOption = sortOption,
            searchQuery = query,
            isLoading = false,
            isEmpty = routes.isEmpty(),
            deleteConfirmationHike = deleteHike
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(STOP_TIMEOUT_MS),
        initialValue = HikeListUiState()
    )

    /**
     * The currently active sort option, exposed for UI controls.
     */
    val sortOption: StateFlow<HikeSortOption> = _sortOption.asStateFlow()

    /**
     * The current search query text, exposed for the search field.
     */
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    /**
     * Updates the sort criterion and triggers list recomputation.
     *
     * @param option The new sort criterion to apply.
     */
    fun setSortOption(option: HikeSortOption) {
        _sortOption.value = option
    }

    /**
     * Updates the search query and triggers list refiltering.
     *
     * The search is case-insensitive and matches against the hike name.
     * An empty query shows all hikes.
     *
     * @param query The new search text.
     */
    fun setSearchQuery(query: String) {
        _searchQuery.value = query
    }

    /**
     * Clears the search query, showing all hikes.
     */
    fun clearSearch() {
        _searchQuery.value = ""
    }

    /**
     * Requests deletion of a hike by showing the confirmation dialog.
     *
     * The hike is not deleted until [confirmDelete] is called. This
     * two-step flow prevents accidental data loss.
     *
     * @param hike The hike list item to potentially delete.
     */
    fun requestDelete(hike: HikeListItem) {
        _deleteConfirmationHike.value = hike
    }

    /**
     * Dismisses the delete confirmation dialog without deleting.
     */
    fun dismissDelete() {
        _deleteConfirmationHike.value = null
    }

    /**
     * Confirms and executes deletion of the pending hike.
     *
     * Deletes the saved route from the database via [RouteRepository]
     * and dismisses the confirmation dialog. If no hike is pending
     * confirmation, this is a no-op.
     */
    fun confirmDelete() {
        val hike = _deleteConfirmationHike.value ?: return
        _deleteConfirmationHike.value = null
        viewModelScope.launch {
            routeRepository.delete(hike.id)
        }
    }

    /**
     * Deletes a hike directly by ID, bypassing the confirmation dialog.
     *
     * Use this for programmatic deletion (e.g. swipe-to-delete with
     * its own undo mechanism). For user-initiated deletion via button,
     * prefer [requestDelete] / [confirmDelete] for safety.
     *
     * @param hikeId The UUID of the saved route to delete.
     */
    fun deleteHike(hikeId: String) {
        viewModelScope.launch {
            routeRepository.delete(hikeId)
        }
    }

    /**
     * Converts a [SavedRouteEntity] to a display-ready [HikeListItem].
     *
     * Pre-formats distance, elevation, and duration strings using
     * [HikeStatsFormatter] so the composable does not need to perform
     * formatting logic during recomposition.
     *
     * @return A [HikeListItem] with formatted statistics.
     */
    private fun SavedRouteEntity.toListItem(): HikeListItem {
        val durationSeconds = walkingTime + restingTime
        return HikeListItem(
            id = id,
            name = name,
            startTime = startTime,
            formattedDistance = HikeStatsFormatter.formatDistance(totalDistance),
            formattedElevationGain = HikeStatsFormatter.formatElevation(elevationGain),
            formattedDuration = HikeStatsFormatter.formatDuration(durationSeconds),
            totalDistance = totalDistance,
            elevationGain = elevationGain,
            durationSeconds = durationSeconds
        )
    }

    /**
     * Filters hike items by a case-insensitive name search query.
     *
     * Returns all items if the query is blank.
     *
     * @param items The full list of hike display items.
     * @param query The search text to match against hike names.
     * @return Filtered list containing only items whose name contains the query.
     */
    private fun filterByQuery(items: List<HikeListItem>, query: String): List<HikeListItem> {
        if (query.isBlank()) return items
        val lowerQuery = query.lowercase()
        return items.filter { it.name.lowercase().contains(lowerQuery) }
    }

    /**
     * Sorts hike items according to the specified criterion.
     *
     * All sort orders are descending (largest/newest first), matching
     * the typical user expectation for hike history screens.
     *
     * @param items The list of hike display items to sort.
     * @param option The sort criterion to apply.
     * @return A new list sorted by the given criterion.
     */
    private fun sortItems(items: List<HikeListItem>, option: HikeSortOption): List<HikeListItem> {
        return when (option) {
            HikeSortOption.DATE -> items.sortedByDescending { it.startTime }
            HikeSortOption.DISTANCE -> items.sortedByDescending { it.totalDistance }
            HikeSortOption.ELEVATION -> items.sortedByDescending { it.elevationGain }
            HikeSortOption.DURATION -> items.sortedByDescending { it.durationSeconds }
        }
    }

    companion object {
        /**
         * Timeout in milliseconds before the upstream flow collection stops
         * after the last subscriber disappears. A 5-second window survives
         * configuration changes (e.g. screen rotation) without restarting
         * the database query.
         */
        private const val STOP_TIMEOUT_MS = 5_000L
    }
}
