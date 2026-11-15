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

import com.openhiker.android.data.db.SyncStamp
import com.openhiker.android.data.db.routes.RouteDao
import com.openhiker.android.data.db.routes.SavedRouteEntity
import com.openhiker.android.data.db.waypoints.WaypointDao
import com.openhiker.android.data.db.waypoints.WaypointEntity
import com.openhiker.android.data.db.waypoints.WaypointSummary
import com.openhiker.android.data.sync.SyncStateStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * Checks that deleting a saved route or waypoint records a tombstone for cloud sync, so the
 * next sync publishes the deletion instead of downloading the entity again.
 */
class RepositoryDeleteTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val store by lazy { SyncStateStore(File(folder.root, "sync_state.json"), { 42L }) }

    private suspend fun pendingIds() = store.load().pendingTombstones.map { it.uuid }

    @Test
    fun `deleting a saved route records a tombstone`() = runTest {
        val dao = FakeRouteDao()
        RouteRepository(dao, store).delete("r1")
        assertEquals(listOf("r1"), dao.deleted)
        assertEquals(listOf("r1"), pendingIds())
    }

    @Test
    fun `deleting a waypoint records a tombstone`() = runTest {
        val dao = FakeWaypointDao()
        WaypointRepository(dao, store).delete("w1")
        assertEquals(listOf("w1"), dao.deleted)
        assertEquals(listOf("w1"), pendingIds())
    }

    @Test
    fun `the tombstone is recorded even if the row delete fails`() = runTest {
        val dao = FakeRouteDao(failDelete = true)
        runCatching { RouteRepository(dao, store).delete("r1") }
        assertEquals(listOf("r1"), pendingIds())
    }

    /** Route DAO that only supports [deleteById]. */
    private class FakeRouteDao(private val failDelete: Boolean = false) : RouteDao {
        val deleted = mutableListOf<String>()
        override suspend fun deleteById(id: String) {
            if (failDelete) error("disk full")
            deleted += id
        }
        override fun observeAll(): Flow<List<SavedRouteEntity>> = TODO()
        override suspend fun getById(id: String): SavedRouteEntity? = TODO()
        override suspend fun getByRegion(regionId: String): List<SavedRouteEntity> = TODO()
        override suspend fun insert(route: SavedRouteEntity) = TODO()
        override suspend fun update(route: SavedRouteEntity) = TODO()
        override suspend fun getSyncStamps(): List<SyncStamp> = TODO()
        override suspend fun count(): Int = TODO()
    }

    /** Waypoint DAO that only supports [deleteById]. */
    private class FakeWaypointDao : WaypointDao {
        val deleted = mutableListOf<String>()
        override suspend fun deleteById(id: String) {
            deleted += id
        }
        override fun observeAll(): Flow<List<WaypointSummary>> = TODO()
        override suspend fun getById(id: String): WaypointEntity? = TODO()
        override suspend fun getByHike(hikeId: String): List<WaypointSummary> = TODO()
        override suspend fun getByCategory(category: String): List<WaypointSummary> = TODO()
        override suspend fun insert(waypoint: WaypointEntity) = TODO()
        override suspend fun update(waypoint: WaypointEntity) = TODO()
        override suspend fun getSyncStamps(): List<SyncStamp> = TODO()
        override suspend fun count(): Int = TODO()
    }
}
