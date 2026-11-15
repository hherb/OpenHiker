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

package com.openhiker.android.data.repository

import com.openhiker.android.data.sync.SyncStateStore
import com.openhiker.core.model.Coordinate
import com.openhiker.core.model.PlannedRoute
import com.openhiker.core.model.RoutingMode
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * Checks that [PlannedRouteRepository] reports failed writes and deletes to its caller instead of
 * pretending they succeeded (#68).
 */
class PlannedRouteRepositoryTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val repo by lazy {
        PlannedRouteRepository(folder.root, SyncStateStore(File(folder.root, "sync_state.json"), { 42L }))
    }

    /** Where the repository stores the file for route [id]. */
    private fun routeFile(id: String) = File(folder.root, "planned_routes/$id.json")

    private fun route(id: String) = PlannedRoute(
        id = id,
        name = "Test",
        mode = RoutingMode.HIKING,
        startCoordinate = Coordinate(47.0, 11.0),
        endCoordinate = Coordinate(47.1, 11.1),
        createdAt = "2026-11-15T00:00:00Z"
    )

    @Test
    fun `save writes the file and lists the route`() = runTest {
        repo.save(route("r1"))
        assertTrue(routeFile("r1").isFile)
        assertEquals(listOf("r1"), repo.routes.value.map { it.id })
    }

    @Test
    fun `a failed save throws and leaves the list unchanged`() = runTest {
        routeFile("r1").mkdirs() // a directory where the file should go makes the write fail
        val result = runCatching { repo.save(route("r1")) }
        assertTrue(result.isFailure)
        assertEquals(emptyList<PlannedRoute>(), repo.routes.value)
    }

    @Test
    fun `delete removes the file and the route`() = runTest {
        repo.save(route("r1"))
        repo.delete("r1")
        assertTrue(!routeFile("r1").exists())
        assertEquals(emptyList<PlannedRoute>(), repo.routes.value)
    }

    @Test
    fun `deleting a route with no file succeeds`() = runTest {
        repo.delete("missing")
        assertEquals(emptyList<PlannedRoute>(), repo.routes.value)
    }

    @Test
    fun `a failed delete throws and keeps the route listed`() = runTest {
        repo.save(route("r1"))
        // Swap the file for a non-empty directory, which File.delete() cannot remove.
        routeFile("r1").delete()
        File(routeFile("r1"), "child").apply { parentFile!!.mkdirs(); writeText("x") }
        val result = runCatching { repo.delete("r1") }
        assertTrue(result.isFailure)
        assertEquals(listOf("r1"), repo.routes.value.map { it.id })
    }
}
