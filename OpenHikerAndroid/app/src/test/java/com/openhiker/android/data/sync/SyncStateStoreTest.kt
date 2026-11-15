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

package com.openhiker.android.data.sync

import com.openhiker.core.formats.SyncManifest
import com.openhiker.core.formats.Tombstone
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/** Unit tests for [SyncStateStore]. */
class SyncStateStoreTest {

    @get:Rule
    val folder = TemporaryFolder()

    private var now = 1_000_000_000_000L
    private val file: File get() = File(folder.root, "sync_state.json")
    private fun store() = SyncStateStore(file, { now }, logError = { _, _ -> })

    @Test
    fun `missing file loads a fresh state`() = runTest {
        assertEquals(SyncState(), store().load())
    }

    @Test
    fun `recorded deletions persist across instances`() = runTest {
        store().recordDeletion("a")
        now += 5
        store().recordDeletion("b")
        assertEquals(
            listOf(Tombstone("a", now - 5), Tombstone("b", now)),
            store().load().pendingTombstones
        )
    }

    @Test
    fun `recording the same uuid again keeps one tombstone with the new time`() = runTest {
        val store = store()
        store.recordDeletion("a")
        now += 10
        store.recordDeletion("a")
        assertEquals(listOf(Tombstone("a", now)), store.load().pendingTombstones)
    }

    @Test
    fun `recording drops expired pending tombstones`() = runTest {
        val store = store()
        store.recordDeletion("old")
        now += SyncManifest.TOMBSTONE_EXPIRY_MILLIS + 1
        store.recordDeletion("new")
        assertEquals(listOf(Tombstone("new", now)), store.load().pendingTombstones)
    }

    @Test
    fun `completeSync clears published tombstones and sets the time`() = runTest {
        val store = store()
        store.recordDeletion("a")
        store.recordDeletion("b")
        store.completeSync(publishedUuids = setOf("a"), lastSyncTimestamp = 42L)
        assertEquals(
            SyncState(lastSyncTimestamp = 42L, pendingTombstones = listOf(Tombstone("b", now))),
            store.load()
        )
    }

    @Test
    fun `completeSync with a null time keeps the previous time`() = runTest {
        val store = store()
        store.completeSync(emptySet(), lastSyncTimestamp = 42L)
        store.completeSync(emptySet(), lastSyncTimestamp = null)
        assertEquals(42L, store.load().lastSyncTimestamp)
    }

    @Test
    fun `corrupt file is moved aside and deleting still works`() = runTest {
        file.writeText("{garbage")
        val store = store()
        assertEquals(SyncState(), store.load())
        assertEquals("{garbage", File(folder.root, "sync_state.json.corrupt").readText())
        store.recordDeletion("a")
        assertEquals(listOf(Tombstone("a", now)), store().load().pendingTombstones)
    }
}
