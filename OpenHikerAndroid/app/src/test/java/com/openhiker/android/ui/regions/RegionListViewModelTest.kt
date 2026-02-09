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

package com.openhiker.android.ui.regions

import com.openhiker.android.testutil.FakeRegionDataSource
import com.openhiker.core.geo.BoundingBox
import com.openhiker.core.model.RegionMetadata
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Unit tests for [RegionListViewModel].
 *
 * Uses [FakeRegionDataSource] to avoid Android Context dependencies and
 * a [TemporaryFolder] for any filesystem operations needed by the fake.
 * [UnconfinedTestDispatcher] replaces Dispatchers.Main so that
 * viewModelScope coroutines and stateIn flows execute eagerly.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RegionListViewModelTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private val testDispatcher = UnconfinedTestDispatcher()

    private lateinit var fakeDataSource: FakeRegionDataSource
    private lateinit var viewModel: RegionListViewModel

    private val testBBox = BoundingBox(
        north = 47.30, south = 47.20, east = 11.45, west = 11.35
    )

    private val regionA = RegionMetadata(
        id = "region-a",
        name = "Innsbruck",
        boundingBox = testBBox,
        minZoom = 12,
        maxZoom = 16,
        tileCount = 1500
    )

    private val regionB = RegionMetadata(
        id = "region-b",
        name = "Salzburg",
        boundingBox = BoundingBox(
            north = 47.85, south = 47.75, east = 13.10, west = 13.00
        ),
        minZoom = 10,
        maxZoom = 15,
        tileCount = 3200
    )

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        fakeDataSource = FakeRegionDataSource(tempFolder.root)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    /**
     * Creates the ViewModel after the fake data source is configured.
     *
     * Passes the [testDispatcher] as both the Main dispatcher (via
     * [Dispatchers.setMain]) and the IO dispatcher so all coroutine
     * work runs on the test scheduler.
     *
     * Must be called explicitly in each test so that regions can be
     * pre-populated before the ViewModel's init block runs.
     */
    private fun createViewModel(): RegionListViewModel {
        return RegionListViewModel(fakeDataSource, testDispatcher)
    }

    // ── Initial state ──────────────────────────────────────────

    @Test
    fun `initial state has empty display items`() = runTest(testDispatcher) {
        viewModel = createViewModel()
        advanceUntilIdle()

        assertTrue(viewModel.displayItems.value.isEmpty())
    }

    @Test
    fun `initial state has zero total storage`() = runTest(testDispatcher) {
        viewModel = createViewModel()
        advanceUntilIdle()

        assertEquals(0L, viewModel.totalStorageBytesFlow.value)
    }

    @Test
    fun `initial state has no rename dialog`() = runTest(testDispatcher) {
        viewModel = createViewModel()
        advanceUntilIdle()

        assertNull(viewModel.renameDialogRegion.value)
    }

    @Test
    fun `initial state has no delete dialog`() = runTest(testDispatcher) {
        viewModel = createViewModel()
        advanceUntilIdle()

        assertNull(viewModel.deleteDialogRegion.value)
    }

    // ── Display items react to region changes ──────────────────

    @Test
    fun `display items reflect pre-populated regions`() = runTest(testDispatcher) {
        fakeDataSource.setRegions(listOf(regionA, regionB))
        viewModel = createViewModel()
        advanceUntilIdle()

        val items = viewModel.displayItems.value
        assertEquals(2, items.size)
        assertEquals("Innsbruck", items.first { it.metadata.id == "region-a" }.metadata.name)
        assertEquals("Salzburg", items.first { it.metadata.id == "region-b" }.metadata.name)
    }

    @Test
    fun `display items update when regions are added`() = runTest(testDispatcher) {
        viewModel = createViewModel()
        advanceUntilIdle()
        assertTrue(viewModel.displayItems.value.isEmpty())

        fakeDataSource.setRegions(listOf(regionA))
        advanceUntilIdle()

        assertEquals(1, viewModel.displayItems.value.size)
        assertEquals("region-a", viewModel.displayItems.value[0].metadata.id)
    }

    @Test
    fun `display item file size matches fake file on disk`() = runTest(testDispatcher) {
        fakeDataSource.setRegions(listOf(regionA))
        fakeDataSource.createMbtilesFile("region-a", 5_000_000L)
        viewModel = createViewModel()
        advanceUntilIdle()

        val item = viewModel.displayItems.value.first()
        assertEquals(5_000_000L, item.fileSizeBytes)
        assertEquals("4.8 MB", item.fileSizeFormatted)
    }

    @Test
    fun `display item file size is zero when no file exists`() = runTest(testDispatcher) {
        fakeDataSource.setRegions(listOf(regionA))
        // No file created on disk
        viewModel = createViewModel()
        advanceUntilIdle()

        val item = viewModel.displayItems.value.first()
        assertEquals(0L, item.fileSizeBytes)
        assertEquals("0 B", item.fileSizeFormatted)
    }

    @Test
    fun `display item area comes from bounding box`() = runTest(testDispatcher) {
        fakeDataSource.setRegions(listOf(regionA))
        viewModel = createViewModel()
        advanceUntilIdle()

        val item = viewModel.displayItems.value.first()
        assertEquals(testBBox.areaKm2, item.areaKm2, 0.001)
    }

    // ── Total storage computation ──────────────────────────────

    @Test
    fun `total storage sums mbtiles and routing files`() = runTest(testDispatcher) {
        fakeDataSource.setRegions(listOf(regionA))
        fakeDataSource.createMbtilesFile("region-a", 3_000_000L)
        fakeDataSource.createRoutingFile("region-a", 1_000_000L)
        viewModel = createViewModel()
        advanceUntilIdle()

        assertEquals(4_000_000L, viewModel.totalStorageBytesFlow.value)
    }

    @Test
    fun `total storage sums across multiple regions`() = runTest(testDispatcher) {
        fakeDataSource.setRegions(listOf(regionA, regionB))
        fakeDataSource.createMbtilesFile("region-a", 2_000_000L)
        fakeDataSource.createMbtilesFile("region-b", 3_000_000L)
        viewModel = createViewModel()
        advanceUntilIdle()

        assertEquals(5_000_000L, viewModel.totalStorageBytesFlow.value)
    }

    @Test
    fun `total storage is zero when no files exist`() = runTest(testDispatcher) {
        fakeDataSource.setRegions(listOf(regionA))
        viewModel = createViewModel()
        advanceUntilIdle()

        assertEquals(0L, viewModel.totalStorageBytesFlow.value)
    }

    // ── Rename dialog state ────────────────────────────────────

    @Test
    fun `showRenameDialog sets the rename dialog region`() = runTest(testDispatcher) {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.showRenameDialog(regionA)

        assertEquals(regionA, viewModel.renameDialogRegion.value)
    }

    @Test
    fun `dismissRenameDialog clears the rename dialog region`() = runTest(testDispatcher) {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.showRenameDialog(regionA)
        viewModel.dismissRenameDialog()

        assertNull(viewModel.renameDialogRegion.value)
    }

    // ── Delete dialog state ────────────────────────────────────

    @Test
    fun `showDeleteDialog sets the delete dialog region`() = runTest(testDispatcher) {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.showDeleteDialog(regionB)

        assertEquals(regionB, viewModel.deleteDialogRegion.value)
    }

    @Test
    fun `dismissDeleteDialog clears the delete dialog region`() = runTest(testDispatcher) {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.showDeleteDialog(regionB)
        viewModel.dismissDeleteDialog()

        assertNull(viewModel.deleteDialogRegion.value)
    }

    // ── Rename operation ───────────────────────────────────────

    @Test
    fun `renameRegion updates region name in repository`() = runTest(testDispatcher) {
        fakeDataSource.setRegions(listOf(regionA))
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.showRenameDialog(regionA)
        viewModel.renameRegion("region-a", "Innsbruck North")
        advanceUntilIdle()

        val updatedRegion = fakeDataSource.regions.value.first()
        assertEquals("Innsbruck North", updatedRegion.name)
    }

    @Test
    fun `renameRegion dismisses the rename dialog`() = runTest(testDispatcher) {
        fakeDataSource.setRegions(listOf(regionA))
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.showRenameDialog(regionA)
        viewModel.renameRegion("region-a", "New Name")
        advanceUntilIdle()

        assertNull(viewModel.renameDialogRegion.value)
    }

    @Test
    fun `renameRegion updates display items`() = runTest(testDispatcher) {
        fakeDataSource.setRegions(listOf(regionA))
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.renameRegion("region-a", "Updated Name")
        advanceUntilIdle()

        val displayItem = viewModel.displayItems.value.first()
        assertEquals("Updated Name", displayItem.metadata.name)
    }

    // ── Delete operation ───────────────────────────────────────

    @Test
    fun `deleteRegion removes region from repository`() = runTest(testDispatcher) {
        fakeDataSource.setRegions(listOf(regionA, regionB))
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.deleteRegion("region-a")
        advanceUntilIdle()

        val remaining = fakeDataSource.regions.value
        assertEquals(1, remaining.size)
        assertEquals("region-b", remaining[0].id)
    }

    @Test
    fun `deleteRegion dismisses the delete dialog`() = runTest(testDispatcher) {
        fakeDataSource.setRegions(listOf(regionA))
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.showDeleteDialog(regionA)
        viewModel.deleteRegion("region-a")
        advanceUntilIdle()

        assertNull(viewModel.deleteDialogRegion.value)
    }

    @Test
    fun `deleteRegion removes files from disk`() = runTest(testDispatcher) {
        fakeDataSource.setRegions(listOf(regionA))
        fakeDataSource.createMbtilesFile("region-a", 1000L)
        fakeDataSource.createRoutingFile("region-a", 500L)
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.deleteRegion("region-a")
        advanceUntilIdle()

        val mbtilesFile = java.io.File(fakeDataSource.mbtilesPath("region-a"))
        val routingFile = java.io.File(fakeDataSource.routingDbPath("region-a"))
        assertTrue("MBTiles file should be deleted", !mbtilesFile.exists())
        assertTrue("Routing file should be deleted", !routingFile.exists())
    }

    @Test
    fun `deleteRegion updates display items`() = runTest(testDispatcher) {
        fakeDataSource.setRegions(listOf(regionA, regionB))
        viewModel = createViewModel()
        advanceUntilIdle()
        assertEquals(2, viewModel.displayItems.value.size)

        viewModel.deleteRegion("region-a")
        advanceUntilIdle()

        assertEquals(1, viewModel.displayItems.value.size)
        assertEquals("region-b", viewModel.displayItems.value[0].metadata.id)
    }

    @Test
    fun `deleteRegion updates total storage`() = runTest(testDispatcher) {
        fakeDataSource.setRegions(listOf(regionA, regionB))
        fakeDataSource.createMbtilesFile("region-a", 2_000_000L)
        fakeDataSource.createMbtilesFile("region-b", 3_000_000L)
        viewModel = createViewModel()
        advanceUntilIdle()
        assertEquals(5_000_000L, viewModel.totalStorageBytesFlow.value)

        viewModel.deleteRegion("region-a")
        advanceUntilIdle()

        assertEquals(3_000_000L, viewModel.totalStorageBytesFlow.value)
    }
}
