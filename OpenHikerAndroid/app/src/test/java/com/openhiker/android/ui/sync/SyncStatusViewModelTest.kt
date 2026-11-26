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

package com.openhiker.android.ui.sync

import com.openhiker.android.data.repository.PlannedRouteRepository
import com.openhiker.android.data.repository.UserPreferences
import com.openhiker.android.data.repository.orDefaultsOnReadError
import com.openhiker.android.data.sync.SyncStateStore
import com.openhiker.android.testutil.ViewModelScopes
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
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
import java.io.IOException
import java.util.Collections

/**
 * Tests the banner's "Delete unreadable route files" flow (#77, #104, #105, #107) and that a
 * banner action's failure line is not hidden by another action's run, only by Dismiss (#110).
 * A real [PlannedRouteRepository] and [SyncStateStore] on a temporary folder do the file work;
 * the sync itself is a fake, so each test decides when it ends and whether it fails.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SyncStatusViewModelTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val store by lazy { SyncStateStore(File(folder.root, "sync_state.json"), { 42L }) }

    private val repo by lazy { PlannedRouteRepository(folder.root, store) }

    private val prefs =
        MutableStateFlow(UserPreferences(syncEnabled = true, syncFolderUri = FOLDER))

    /** The preferences the ViewModel reads; [prefs] unless a test replaces it. */
    private var preferences: Flow<UserPreferences> = prefs

    /** Serialises the fake syncs, as `CloudDriveSyncEngine`'s mutex does. */
    private val syncLock = Mutex()

    /** Folder URIs the fake sync was asked to sync, in call order; written from IO threads too. */
    private val syncedFolders: MutableList<String> = Collections.synchronizedList(mutableListOf())

    /** What the fake sync does after recording its call; succeeds by default. */
    private var syncAction: suspend () -> Unit = {}

    private val scopes = ViewModelScopes()

    /** A ViewModel on the real store and repository, with the fake sync. */
    private fun viewModel() = scopes.track(SyncStatusViewModel(
        isSyncing = MutableStateFlow(false),
        runSync = { folderUri ->
            syncLock.withLock {
                syncedFolders.add(folderUri)
                syncAction()
            }
        },
        syncStateStore = store,
        preferences = preferences,
        plannedRouteRepository = repo
    ))

    /** The planned-route file [name] in the temporary folder. */
    private fun routeFile(name: String) = File(folder.root, "planned_routes/$name")

    /** An unparseable route file, which the delete can remove. */
    private fun brokenFile(name: String) = routeFile(name).apply {
        parentFile!!.mkdirs()
        writeText("{ not json")
    }

    /** A non-empty directory named like a route file: unreadable, and it cannot be deleted. */
    private fun stuckFile(name: String) = routeFile(name).apply {
        mkdirs()
        File(this, "x").writeText("x")
    }

    /** The delete's failure line among [messages], or null. */
    private fun deleteLine(messages: List<String>) =
        messages.singleOrNull { it.startsWith("Cannot delete the unreadable route files: ") }

    /**
     * Waits until the startup scan has listed [count] unreadable files, as the user can only
     * tap Delete after that; a later scan result would otherwise race the delete's own.
     */
    private suspend fun awaitStartupScan(viewModel: SyncStatusViewModel, count: Int = 1) {
        viewModel.bannerState.first { it.unreadableRouteFiles.size == count }
    }

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @After
    fun tearDown() {
        scopes.cancelAndJoinAll()
        Dispatchers.resetMain()
    }

    @Test
    fun `a delete with sync on deletes the files and syncs the folder`() = runTest {
        brokenFile("bad.json")
        val synced = CompletableDeferred<Unit>()
        syncAction = { synced.complete(Unit) }
        val viewModel = viewModel()
        awaitStartupScan(viewModel)

        viewModel.deleteUnreadableRouteFiles(listOf("bad.json"))

        synced.await()
        assertFalse(routeFile("bad.json").exists())
        assertEquals(listOf(FOLDER), syncedFolders)
        // Waiting for the emptied file list proves the banner ran after the delete.
        val banner = viewModel.bannerState.first { it.unreadableRouteFiles.isEmpty() }
        assertEquals(emptyList<String>(), banner.messages)
    }

    @Test
    fun `a delete failure shows during the follow-up sync and after it fails too`() = runTest {
        stuckFile("stuck.json")
        val syncStarted = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        syncAction = {
            syncStarted.complete(Unit)
            release.await()
            throw IOException("offline")
        }
        val viewModel = viewModel()
        awaitStartupScan(viewModel)

        viewModel.deleteUnreadableRouteFiles(listOf("stuck.json"))

        syncStarted.await()
        // Before #110 the follow-up sync cleared the delete failure until it ended.
        val during = viewModel.bannerState.first { deleteLine(it.messages) != null }.messages
        assertTrue(deleteLine(during)!!.contains("stuck.json"))
        release.complete(Unit)
        val after = viewModel.bannerState.first { it.messages.size == 2 }.messages
        assertTrue(deleteLine(after) != null)
        assertTrue(after.contains("Sync failed: offline"))

        viewModel.dismiss()

        viewModel.bannerState.first { it.messages.isEmpty() }
    }

    @Test
    fun `a Retry failure during the delete flow is not replaced when the flow ends`() = runTest {
        stuckFile("stuck.json")
        val syncStarted = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        // The delete's follow-up sync waits, then succeeds; the Retry's sync fails at once.
        syncAction = {
            if (syncedFolders.size == 1) {
                syncStarted.complete(Unit)
                release.await()
            } else {
                throw IOException("offline")
            }
        }
        val viewModel = viewModel()
        awaitStartupScan(viewModel)
        viewModel.deleteUnreadableRouteFiles(listOf("stuck.json"))
        syncStarted.await()

        viewModel.retry()
        release.complete(Unit)

        val messages = viewModel.bannerState.first { it.messages.size == 2 }.messages
        assertEquals(2, syncedFolders.size)
        assertTrue(deleteLine(messages) != null)
        assertTrue(messages.contains("Sync failed: offline"))
    }

    @Test
    fun `a Retry that succeeds after a failed follow-up sync clears the sync failure line`() =
        runTest {
            stuckFile("stuck.json")
            val syncStarted = CompletableDeferred<Unit>()
            val release = CompletableDeferred<Unit>()
            // The delete's follow-up sync waits, then fails; the Retry's sync succeeds.
            syncAction = {
                if (syncedFolders.size == 1) {
                    syncStarted.complete(Unit)
                    release.await()
                    throw IOException("offline")
                }
            }
            val viewModel = viewModel()
            awaitStartupScan(viewModel)
            viewModel.deleteUnreadableRouteFiles(listOf("stuck.json"))
            syncStarted.await()

            // The Retry waits on the lock behind the follow-up sync, which fails meanwhile.
            viewModel.retry()
            release.complete(Unit)

            // Before #113 the follow-up's "Sync failed" line stayed after the Retry succeeded.
            val messages = viewModel.bannerState
                .first { syncedFolders.size == 2 && it.messages.size == 1 }.messages
            assertTrue(deleteLine(messages) != null)
        }

    @Test
    fun `preferences that cannot be read show in the banner and turn sync off`() = runTest {
        brokenFile("bad.json")
        preferences = flow<UserPreferences> { throw IOException("disk error") }
            .orDefaultsOnReadError()
        val viewModel = viewModel()
        awaitStartupScan(viewModel)

        // Before #112 these read the preferences outside any error handling and crashed.
        viewModel.retry()
        viewModel.deleteUnreadableRouteFiles(listOf("bad.json"))

        val banner = viewModel.bannerState.first { it.unreadableRouteFiles.isEmpty() }
        assertEquals(listOf("$PREFERENCES_READ_FAILED: disk error"), banner.messages)
        assertFalse(banner.canRetry)
        assertEquals(emptyList<String>(), syncedFolders)
    }

    @Test
    fun `with sync off a full delete clears the stored errors and does not sync`() = runTest {
        brokenFile("bad.json")
        store.recordOutcome(listOf("Planned routes: cannot read local file bad.json"))
        prefs.value = UserPreferences(syncEnabled = false, syncFolderUri = FOLDER)
        val viewModel = viewModel()
        awaitStartupScan(viewModel)

        viewModel.deleteUnreadableRouteFiles(listOf("bad.json"))

        store.state.first { it?.lastErrors?.isEmpty() == true }
        assertFalse(routeFile("bad.json").exists())
        assertEquals(emptyList<String>(), syncedFolders)
        viewModel.bannerState.first { it.messages.isEmpty() }
    }

    @Test
    fun `with sync off a partial delete keeps the stored errors`() = runTest {
        brokenFile("bad.json")
        stuckFile("stuck.json")
        val stored = listOf("Planned routes: cannot read local file stuck.json")
        store.recordOutcome(stored)
        prefs.value = UserPreferences(syncEnabled = false, syncFolderUri = FOLDER)
        val viewModel = viewModel()

        // The startup scan lists both files; the banner offers to delete them.
        awaitStartupScan(viewModel, count = 2)
        val before = viewModel.bannerState.value
        assertEquals(setOf("bad.json", "stuck.json"), before.unreadableRouteFiles.toSet())

        viewModel.deleteUnreadableRouteFiles(listOf("bad.json", "stuck.json"))

        val banner = viewModel.bannerState.first { deleteLine(it.messages) != null }
        val messages = banner.messages
        assertEquals(listOf("stuck.json"), banner.unreadableRouteFiles)
        assertEquals(listOf(SYNC_FAILED_HEADING) + stored, messages.take(2))
        assertEquals(stored, store.state.value?.lastErrors)
        assertFalse(routeFile("bad.json").exists())
        assertEquals(emptyList<String>(), syncedFolders)
    }

    @Test
    fun `a successful Retry clears the sync failure line and keeps the delete failure`() =
        runTest {
            stuckFile("stuck.json")
            syncAction = { throw IOException("offline") }
            val viewModel = viewModel()
            awaitStartupScan(viewModel)
            viewModel.deleteUnreadableRouteFiles(listOf("stuck.json"))
            viewModel.bannerState.first { it.messages.contains("Sync failed: offline") }

            syncAction = {}
            viewModel.retry()

            val messages = viewModel.bannerState.first { it.messages.size == 1 }.messages
            assertTrue(deleteLine(messages) != null)
        }

    @Test
    fun `a failure that arrives after Dismiss still shows`() = runTest {
        stuckFile("stuck.json")
        val syncStarted = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        syncAction = {
            syncStarted.complete(Unit)
            release.await()
            throw IOException("offline")
        }
        val viewModel = viewModel()
        awaitStartupScan(viewModel)
        viewModel.deleteUnreadableRouteFiles(listOf("stuck.json"))
        syncStarted.await()
        viewModel.bannerState.first { deleteLine(it.messages) != null }

        viewModel.dismiss()
        viewModel.bannerState.first { it.messages.isEmpty() }
        release.complete(Unit)

        val messages = viewModel.bannerState.first { it.messages.isNotEmpty() }.messages
        assertEquals(listOf("Sync failed: offline"), messages)
    }

    @Test
    fun `with sync off a planned-route folder that cannot be read shows in the banner`() =
        runTest {
            // A file where the directory should be makes the folder unreadable.
            File(folder.root, "planned_routes").writeText("")
            prefs.value = UserPreferences(syncEnabled = false, syncFolderUri = null)
            val viewModel = viewModel()

            val messages = viewModel.bannerState.first { it.messages.isNotEmpty() }.messages
            assertEquals(1, messages.size)
            assertTrue(messages.single().startsWith("Cannot read the planned routes: "))
        }

    private companion object {
        const val FOLDER = "content://sync-folder"
    }
}
