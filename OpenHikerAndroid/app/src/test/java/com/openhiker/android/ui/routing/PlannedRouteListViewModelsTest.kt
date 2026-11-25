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

import androidx.lifecycle.SavedStateHandle
import com.openhiker.android.data.repository.PlannedRouteRepository
import com.openhiker.android.data.repository.SkippedRouteFile
import com.openhiker.android.data.sync.SyncStateStore
import com.openhiker.core.model.Coordinate
import com.openhiker.core.model.PlannedRoute
import com.openhiker.core.model.RoutingMode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * Tests the planned-route list (#102) and deleting a route from its detail screen, loaded or
 * not. A real [PlannedRouteRepository] on a temporary folder does the file work; the tests
 * wait on the published state because the repository reads on the IO dispatcher.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class PlannedRouteListViewModelsTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val store by lazy { SyncStateStore(File(folder.root, "sync_state.json"), { 42L }) }

    private val repo by lazy { PlannedRouteRepository(folder.root, store) }

    private fun routeFile(id: String) = File(folder.root, "planned_routes/$id.json")

    private fun route(id: String, createdAt: String) = PlannedRoute(
        id = id,
        name = "Route $id",
        mode = RoutingMode.HIKING,
        startCoordinate = Coordinate(47.0, 11.0),
        endCoordinate = Coordinate(47.1, 11.1),
        createdAt = createdAt
    )

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `refresh lists the routes newest first and the unreadable files`() = runTest {
        repo.save(route("old", "2026-01-01T00:00:00Z"))
        repo.save(route("new", "2026-06-01T00:00:00Z"))
        routeFile("broken").writeText("{ not json")
        // A fresh repository, as after an app start, knows nothing until refresh reads the disk.
        val viewModel = PlannedRouteListViewModel(PlannedRouteRepository(folder.root, store))

        viewModel.refresh()

        val unreadable = viewModel.unreadableFiles.first { it.isNotEmpty() }
        assertEquals(listOf("broken.json"), unreadable.map { it.fileName })
        assertEquals(listOf("new", "old"), viewModel.routes.value.map { it.id })
        assertEquals(null, viewModel.loadError.value)
    }

    @Test
    fun `refresh reports a folder that cannot be read`() = runTest {
        // A file where the directory should be makes the folder unreadable.
        File(folder.root, "planned_routes").writeText("")
        val viewModel = PlannedRouteListViewModel(repo)

        viewModel.refresh()

        val error = viewModel.loadError.first { it != null }
        assertTrue(error!!.startsWith("Cannot read the planned routes"))
    }

    @Test
    fun `detail deletes a route whose file cannot be read`() = runTest {
        routeFile("r1").parentFile!!.mkdirs()
        routeFile("r1").writeText("{ not json")
        val viewModel = RouteDetailViewModel(repo, SavedStateHandle(mapOf("routeId" to "r1")))
        viewModel.uiState.first { !it.isLoading }
        assertTrue(viewModel.uiState.value.errorMessage != null)

        viewModel.deleteRoute()

        viewModel.uiState.first { it.isDeleted || it.actionErrorMessage != null }
        assertTrue(viewModel.uiState.value.isDeleted)
        assertFalse(routeFile("r1").exists())
        // Only the broken local copy goes (#77): a good copy in the sync folder must come back.
        assertEquals(emptyList<String>(), store.load().pendingTombstones.map { it.uuid })
    }

    @Test
    fun `detail deletes a loaded route everywhere`() = runTest {
        repo.save(route("r1", "2026-01-01T00:00:00Z"))
        val viewModel = RouteDetailViewModel(repo, SavedStateHandle(mapOf("routeId" to "r1")))
        viewModel.uiState.first { !it.isLoading }

        viewModel.deleteRoute()

        viewModel.uiState.first { it.isDeleted || it.actionErrorMessage != null }
        assertTrue(viewModel.uiState.value.isDeleted)
        assertFalse(routeFile("r1").exists())
        // Recorded for sync, so the next sync deletes the route from the sync folder too.
        assertEquals(listOf("r1"), store.load().pendingTombstones.map { it.uuid })
    }

    @Test
    fun `refresh clears the folder error once the folder can be read again`() = runTest {
        val dir = File(folder.root, "planned_routes")
        dir.writeText("")
        val viewModel = PlannedRouteListViewModel(repo)
        viewModel.refresh()
        viewModel.loadError.first { it != null }

        dir.delete()
        repo.save(route("r1", "2026-01-01T00:00:00Z"))
        viewModel.refresh()

        viewModel.loadError.first { it == null }
        assertEquals(listOf("r1"), viewModel.routes.value.map { it.id })
    }

    @Test
    fun `empty state shows only when nothing was read and nothing failed`() {
        val skipped = listOf(SkippedRouteFile("broken.json", "bad JSON"))
        val routes = listOf(route("r1", "2026-01-01T00:00:00Z"))
        assertTrue(showsEmptyState(emptyList(), emptyList(), null))
        assertFalse(showsEmptyState(emptyList(), emptyList(), "Cannot read"))
        assertFalse(showsEmptyState(emptyList(), skipped, null))
        assertFalse(showsEmptyState(routes, emptyList(), null))
    }
}
