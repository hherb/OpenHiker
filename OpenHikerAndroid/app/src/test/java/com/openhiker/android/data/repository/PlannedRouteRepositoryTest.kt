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
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException

/**
 * Checks that [PlannedRouteRepository] reports failed writes, deletes (#68) and reads (#74) to its
 * caller instead of pretending they succeeded or that the route does not exist.
 */
class PlannedRouteRepositoryTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val store by lazy { SyncStateStore(File(folder.root, "sync_state.json"), { 42L }) }

    private val repo by lazy { PlannedRouteRepository(folder.root, store) }

    private suspend fun pendingIds() = store.load().pendingTombstones.map { it.uuid }

    /** Where the repository stores the file for route [id]. */
    private fun routeFile(id: String) = File(folder.root, "planned_routes/$id.json")

    private fun route(id: String, name: String = "Test") = PlannedRoute(
        id = id,
        name = name,
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
    fun `saving an existing route replaces it`() = runTest {
        repo.save(route("r1", name = "v1"))
        repo.save(route("r1", name = "v2"))
        assertEquals(listOf("v2"), repo.routes.value.map { it.name })
        assertEquals("v2", repo.getById("r1")?.name)
    }

    @Test
    fun `a failed save throws and leaves the list unchanged`() = runTest {
        routeFile("r1").mkdirs() // a directory where the file should go makes the write fail
        val result = runCatching { repo.save(route("r1")) }
        assertTrue(result.exceptionOrNull() is IOException)
        assertEquals(emptyList<PlannedRoute>(), repo.routes.value)
    }

    @Test
    fun `a failed save over an existing route keeps the saved copy`() = runTest {
        repo.save(route("r1", name = "v1"))
        // A directory where the temp file goes makes the next write fail.
        File(routeFile("r1").path + ".tmp").mkdirs()
        val result = runCatching { repo.save(route("r1", name = "v2")) }
        assertTrue(result.exceptionOrNull() is IOException)
        assertEquals("v1", repo.getById("r1")?.name)
        assertEquals(listOf("v1"), repo.routes.value.map { it.name })
    }

    @Test
    fun `delete removes the file and the route`() = runTest {
        repo.save(route("r1"))
        repo.delete("r1")
        assertFalse(routeFile("r1").exists())
        assertEquals(emptyList<PlannedRoute>(), repo.routes.value)
        assertEquals(listOf("r1"), pendingIds())
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
        assertTrue(result.exceptionOrNull() is IOException)
        assertEquals(listOf("r1"), repo.routes.value.map { it.id })
        // Tombstone first, so the next sync still deletes the route.
        assertEquals(listOf("r1"), pendingIds())
    }

    @Test
    fun `getById returns null for a missing route`() = runTest {
        assertNull(repo.getById("missing"))
    }

    @Test
    fun `getById throws for a corrupt route file`() = runTest {
        routeFile("r1").apply { parentFile!!.mkdirs(); writeText("{not json") }
        val result = runCatching { repo.getById("r1") }
        assertTrue(result.exceptionOrNull() is IOException)
    }

    @Test
    fun `loadAll lists readable routes and names the skipped files`() = runTest {
        repo.save(route("r1"))
        routeFile("bad").writeText("{not json")
        val skipped = repo.loadAll()
        assertEquals(1, skipped.size)
        assertTrue(skipped[0], skipped[0].startsWith("bad.json: "))
        assertEquals(listOf("r1"), repo.routes.value.map { it.id })
    }

    @Test
    fun `loadAll throws and keeps the list when the directory is unusable`() = runTest {
        repo.save(route("r1"))
        // A regular file where the directory should be cannot be listed or created.
        File(folder.root, "planned_routes").deleteRecursively()
        File(folder.root, "planned_routes").writeText("x")
        val result = runCatching { repo.loadAll() }
        assertTrue(result.exceptionOrNull() is IOException)
        assertEquals(listOf("r1"), repo.routes.value.map { it.id })
    }
}
