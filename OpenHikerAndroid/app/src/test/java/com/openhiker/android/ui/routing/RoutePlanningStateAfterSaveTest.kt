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

import com.openhiker.core.routing.ComputedRoute
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Tests [stateAfterSave]: "Navigate" opens the saved copy by [RoutePlanningUiState.savedRouteId],
 * so it must be set only for the route on screen and only when the save worked (#102).
 */
class RoutePlanningStateAfterSaveTest {

    private fun computed() = ComputedRoute(
        nodes = emptyList(),
        edges = emptyList(),
        totalDistance = 1000.0,
        totalCost = 1000.0,
        estimatedDuration = 600.0,
        elevationGain = 10.0,
        elevationLoss = 10.0,
        coordinates = emptyList()
    )

    @Test
    fun `a save of the route on screen sets its id and closes the dialog`() {
        val route = computed()
        val current = RoutePlanningUiState(computedRoute = route, isSaveDialogVisible = true)

        val next = stateAfterSave(current, route, "id1", null)

        assertEquals("id1", next.savedRouteId)
        assertFalse(next.isSaveDialogVisible)
        assertNull(next.errorMessage)
    }

    @Test
    fun `a failed save sets no id and shows the error`() {
        val route = computed()
        val current = RoutePlanningUiState(computedRoute = route)

        val next = stateAfterSave(current, route, "id1", "Failed to save route: disk full")

        assertNull(next.savedRouteId)
        assertEquals("Failed to save route: disk full", next.errorMessage)
    }

    @Test
    fun `a route computed during the save is not marked saved, even with equal contents`() {
        val saved = computed()
        val current = RoutePlanningUiState(computedRoute = computed())

        assertNull(stateAfterSave(current, saved, "id1", null).savedRouteId)
    }

    @Test
    fun `a save of an older route keeps the id the current route already has`() {
        val current = RoutePlanningUiState(computedRoute = computed(), savedRouteId = "id0")

        assertEquals("id0", stateAfterSave(current, computed(), "id1", null).savedRouteId)
    }
}
