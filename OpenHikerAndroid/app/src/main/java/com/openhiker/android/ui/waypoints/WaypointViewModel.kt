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

package com.openhiker.android.ui.waypoints

import android.location.Location
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.openhiker.android.data.db.waypoints.WaypointEntity
import com.openhiker.android.data.db.waypoints.WaypointSummary
import com.openhiker.android.data.repository.WaypointRepository
import com.openhiker.android.service.location.LocationProvider
import com.openhiker.core.model.WaypointCategory
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.UUID
import javax.inject.Inject

/**
 * ViewModel for the waypoint management feature.
 *
 * Manages the state for three screens:
 * - **WaypointListScreen**: filtered list of all waypoints with multi-select category chips.
 * - **WaypointDetailScreen**: single waypoint with full photo data, edit, and delete actions.
 * - **AddWaypointScreen**: form to create a new waypoint with auto-filled GPS coordinates.
 *
 * All waypoint data is persisted through [WaypointRepository] (backed by Room).
 * Photo BLOBs are only loaded on demand via [loadWaypointDetail] to avoid
 * excessive memory usage in list queries.
 *
 * The current GPS location is exposed from [LocationProvider] so that the
 * AddWaypointScreen can auto-fill coordinates and the list screen can
 * display distance from the user's position.
 *
 * @param waypointRepository Repository providing CRUD access to waypoints.
 * @param locationProvider Provides the current GPS location as a [StateFlow].
 */
@HiltViewModel
class WaypointViewModel @Inject constructor(
    private val waypointRepository: WaypointRepository,
    private val locationProvider: LocationProvider
) : ViewModel() {

    // ── Category filter state ───────────────────────────────────────

    private val _selectedCategories = MutableStateFlow<Set<WaypointCategory>>(emptySet())

    /**
     * Currently selected category filters for the list screen.
     *
     * When empty, all waypoints are shown (no filter applied).
     * When one or more categories are selected, only matching waypoints appear.
     */
    val selectedCategories: StateFlow<Set<WaypointCategory>> = _selectedCategories.asStateFlow()

    // ── Filtered waypoint list ──────────────────────────────────────

    /**
     * All waypoints filtered by the currently selected categories.
     *
     * This is a combined flow that reacts to both changes in the underlying
     * waypoint data (from the database) and changes in the selected category
     * filters. When no categories are selected, all waypoints are returned.
     *
     * Waypoints are emitted as [WaypointSummary] (without photo BLOBs)
     * to keep memory usage low in list views.
     */
    val filteredWaypoints: StateFlow<List<WaypointSummary>> = combine(
        waypointRepository.observeAll(),
        _selectedCategories
    ) { allWaypoints, categories ->
        if (categories.isEmpty()) {
            allWaypoints
        } else {
            val categoryNames = categories.map { it.name }
            allWaypoints.filter { waypoint ->
                categoryNames.any { name ->
                    name.equals(waypoint.category, ignoreCase = true)
                }
            }
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(STOP_TIMEOUT_MS), emptyList())

    // ── Detail screen state ─────────────────────────────────────────

    private val _detailWaypoint = MutableStateFlow<WaypointEntity?>(null)

    /**
     * The currently loaded waypoint for the detail screen, including full photo data.
     *
     * Set by [loadWaypointDetail] and cleared by [clearWaypointDetail].
     * Returns null when no waypoint is loaded or the ID was not found.
     */
    val detailWaypoint: StateFlow<WaypointEntity?> = _detailWaypoint.asStateFlow()

    private val _detailLoading = MutableStateFlow(false)

    /**
     * Whether the detail waypoint is currently being loaded from the database.
     *
     * True while [loadWaypointDetail] is fetching photo BLOBs from Room.
     */
    val detailLoading: StateFlow<Boolean> = _detailLoading.asStateFlow()

    // ── Error state ─────────────────────────────────────────────────

    private val _errorMessage = MutableStateFlow<String?>(null)

    /**
     * User-facing error message, or null when there is no error.
     *
     * Set when a save or delete operation fails. The UI should display
     * this in a snackbar and call [clearError] after showing it.
     */
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    // ── Location ────────────────────────────────────────────────────

    /**
     * The current GPS location from [LocationProvider].
     *
     * Used by the list screen to compute distance from each waypoint,
     * and by the add screen to auto-fill latitude/longitude fields.
     * Returns null if location permission is not granted or GPS is unavailable.
     */
    val currentLocation: StateFlow<Location?> = locationProvider.location

    // ── Category filter actions ─────────────────────────────────────

    /**
     * Toggles a category in the multi-select filter.
     *
     * If the category is already selected, it is removed (deselected).
     * If it is not selected, it is added. The filtered waypoint list
     * updates automatically via the combined flow.
     *
     * @param category The [WaypointCategory] to toggle.
     */
    fun toggleCategory(category: WaypointCategory) {
        _selectedCategories.value = _selectedCategories.value.let { current ->
            if (current.contains(category)) {
                current - category
            } else {
                current + category
            }
        }
    }

    /**
     * Clears all selected category filters, showing all waypoints.
     */
    fun clearCategoryFilter() {
        _selectedCategories.value = emptySet()
    }

    // ── Detail screen actions ───────────────────────────────────────

    /**
     * Loads a single waypoint with full photo data for the detail screen.
     *
     * This fetches the complete [WaypointEntity] including photo and thumbnail
     * BLOBs from the database. The result is exposed via [detailWaypoint].
     * While loading, [detailLoading] is true.
     *
     * If the waypoint is not found (deleted or invalid ID), [detailWaypoint]
     * will be null and an error message is set.
     *
     * @param waypointId The UUID of the waypoint to load.
     */
    fun loadWaypointDetail(waypointId: String) {
        viewModelScope.launch {
            _detailLoading.value = true
            try {
                val entity = waypointRepository.getById(waypointId)
                _detailWaypoint.value = entity
                if (entity == null) {
                    _errorMessage.value = "Waypoint not found"
                    Log.w(TAG, "Waypoint not found: $waypointId")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load waypoint detail: $waypointId", e)
                _errorMessage.value = "Failed to load waypoint: ${e.localizedMessage}"
                _detailWaypoint.value = null
            } finally {
                _detailLoading.value = false
            }
        }
    }

    /**
     * Clears the detail waypoint state.
     *
     * Call this when navigating away from the detail screen to free
     * any photo BLOB memory held by [detailWaypoint].
     */
    fun clearWaypointDetail() {
        _detailWaypoint.value = null
    }

    // ── Save waypoint ───────────────────────────────────────────────

    /**
     * Saves a new waypoint to the database.
     *
     * Creates a [WaypointEntity] from the provided form fields and persists it
     * via [WaypointRepository]. The waypoint receives a new UUID and the current
     * timestamp. On success, [onSuccess] is called (typically to navigate back).
     * On failure, an error message is set in [errorMessage].
     *
     * @param label The user-entered name/label for the waypoint.
     * @param category The selected [WaypointCategory].
     * @param latitude The GPS latitude in decimal degrees.
     * @param longitude The GPS longitude in decimal degrees.
     * @param altitude Optional altitude in metres, or null if unavailable.
     * @param note Optional text note attached to the waypoint.
     * @param photo Optional full-resolution photo as JPEG bytes.
     * @param thumbnail Optional thumbnail (100x100) as JPEG bytes.
     * @param hikeId Optional UUID of the associated hike/saved route.
     * @param onSuccess Callback invoked after the waypoint is saved successfully.
     */
    fun saveWaypoint(
        label: String,
        category: WaypointCategory,
        latitude: Double,
        longitude: Double,
        altitude: Double?,
        note: String,
        photo: ByteArray? = null,
        thumbnail: ByteArray? = null,
        hikeId: String? = null,
        onSuccess: () -> Unit = {}
    ) {
        viewModelScope.launch {
            try {
                val now = Instant.now().toString()
                val entity = WaypointEntity(
                    id = UUID.randomUUID().toString(),
                    latitude = latitude,
                    longitude = longitude,
                    altitude = altitude,
                    timestamp = now,
                    label = label,
                    category = category.name,
                    note = note,
                    hasPhoto = photo != null,
                    hikeId = hikeId,
                    photo = photo,
                    thumbnail = thumbnail,
                    modifiedAt = now
                )
                waypointRepository.save(entity)
                Log.d(TAG, "Waypoint saved: ${entity.id} (${entity.label})")
                onSuccess()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to save waypoint", e)
                _errorMessage.value = "Failed to save waypoint: ${e.localizedMessage}"
            }
        }
    }

    // ── Update waypoint ─────────────────────────────────────────────

    /**
     * Updates an existing waypoint's editable fields and saves to the database.
     *
     * Only the label, category, and note fields can be edited. The waypoint's
     * coordinates, photos, and associations remain unchanged. The [modifiedAt]
     * timestamp is updated to the current time.
     *
     * On success, the [detailWaypoint] is refreshed with the updated data.
     * On failure, an error message is set in [errorMessage].
     *
     * @param waypointId The UUID of the waypoint to update.
     * @param label The new label/name.
     * @param category The new category.
     * @param note The new note text.
     * @param onSuccess Callback invoked after the waypoint is updated successfully.
     */
    fun updateWaypoint(
        waypointId: String,
        label: String,
        category: WaypointCategory,
        note: String,
        onSuccess: () -> Unit = {}
    ) {
        viewModelScope.launch {
            try {
                val existing = waypointRepository.getById(waypointId)
                if (existing == null) {
                    _errorMessage.value = "Waypoint not found"
                    Log.w(TAG, "Cannot update: waypoint not found: $waypointId")
                    return@launch
                }
                val updated = existing.copy(
                    label = label,
                    category = category.name,
                    note = note,
                    modifiedAt = Instant.now().toString()
                )
                waypointRepository.save(updated)
                _detailWaypoint.value = updated
                Log.d(TAG, "Waypoint updated: $waypointId")
                onSuccess()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update waypoint: $waypointId", e)
                _errorMessage.value = "Failed to update waypoint: ${e.localizedMessage}"
            }
        }
    }

    // ── Delete waypoint ─────────────────────────────────────────────

    /**
     * Deletes a waypoint from the database.
     *
     * Permanently removes the waypoint and its photo data. On success,
     * [onSuccess] is called (typically to navigate back from the detail screen).
     * On failure, an error message is set in [errorMessage].
     *
     * @param waypointId The UUID of the waypoint to delete.
     * @param onSuccess Callback invoked after deletion succeeds.
     */
    fun deleteWaypoint(waypointId: String, onSuccess: () -> Unit = {}) {
        viewModelScope.launch {
            try {
                waypointRepository.delete(waypointId)
                Log.d(TAG, "Waypoint deleted: $waypointId")
                onSuccess()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete waypoint: $waypointId", e)
                _errorMessage.value = "Failed to delete waypoint: ${e.localizedMessage}"
            }
        }
    }

    // ── Error handling ──────────────────────────────────────────────

    /**
     * Clears the current error message.
     *
     * Call this after the UI has displayed the error (e.g., after a snackbar
     * is dismissed) to reset the error state.
     */
    fun clearError() {
        _errorMessage.value = null
    }

    companion object {
        private const val TAG = "WaypointViewModel"

        /**
         * Timeout in milliseconds before the [filteredWaypoints] flow stops
         * collecting when there are no subscribers. Set to 5 seconds to
         * survive brief configuration changes (screen rotation) without
         * restarting the database query.
         */
        private const val STOP_TIMEOUT_MS = 5_000L
    }
}
