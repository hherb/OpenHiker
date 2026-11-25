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
import com.openhiker.android.data.repository.PlannedRouteRepository
import com.openhiker.android.data.repository.SkippedRouteFile
import com.openhiker.core.model.PlannedRoute
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Backs the Routes tab's list of saved planned routes (#102), the Android counterpart of Apple's
 * `PlannedRoutesListView`.
 *
 * The routes and the unreadable files come straight from [PlannedRouteRepository], so a save,
 * rename or delete elsewhere shows here at once.
 *
 * @param repository Source of the planned routes.
 */
@HiltViewModel
class PlannedRouteListViewModel @Inject constructor(
    private val repository: PlannedRouteRepository
) : ViewModel() {

    /** The readable routes, newest first after a [refresh]. */
    val routes: StateFlow<List<PlannedRoute>> = repository.routes

    /** Route files the last [refresh] could not read. */
    val unreadableFiles: StateFlow<List<SkippedRouteFile>> = repository.skippedFiles

    private val _loadError = MutableStateFlow<String?>(null)

    /** Why the route folder could not be read, or null. The list is then not complete. */
    val loadError: StateFlow<String?> = _loadError.asStateFlow()

    /** Reads every route file again; called whenever the list appears. */
    fun refresh() {
        viewModelScope.launch {
            _loadError.value = try {
                repository.loadAll()
                null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "Cannot read the planned routes", e)
                "Cannot read the planned routes: ${e.message}"
            }
        }
    }

    private companion object {
        const val TAG = "PlannedRouteListVM"
    }
}
