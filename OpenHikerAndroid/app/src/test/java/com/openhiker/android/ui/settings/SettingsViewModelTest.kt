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

package com.openhiker.android.ui.settings

import com.openhiker.android.data.repository.GpsAccuracyMode
import com.openhiker.android.data.repository.UnitSystem
import com.openhiker.android.data.repository.UserPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * Unit tests for [SettingsViewModel] pure logic and [SettingsUiState] defaults.
 *
 * Tests the static [SettingsViewModel.directorySize] helper and the default
 * values of [SettingsUiState]. Uses [TemporaryFolder] for filesystem tests
 * so no Android context is required.
 */
class SettingsViewModelTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    // ── SettingsUiState default values ────────────────────────────

    @Test
    fun `default SettingsUiState has default UserPreferences`() {
        val state = SettingsUiState()
        assertEquals(UserPreferences(), state.preferences)
    }

    @Test
    fun `default SettingsUiState is not syncing`() {
        val state = SettingsUiState()
        assertFalse(state.isSyncing)
    }

    @Test
    fun `default SettingsUiState has null last sync result`() {
        val state = SettingsUiState()
        assertNull(state.lastSyncResult)
    }

    @Test
    fun `default SettingsUiState has zero elevation cache size`() {
        val state = SettingsUiState()
        assertEquals(0L, state.elevationCacheSizeBytes)
    }

    @Test
    fun `default SettingsUiState has zero OSM cache size`() {
        val state = SettingsUiState()
        assertEquals(0L, state.osmCacheSizeBytes)
    }

    @Test
    fun `default SettingsUiState has zero total region size`() {
        val state = SettingsUiState()
        assertEquals(0L, state.totalRegionSizeBytes)
    }

    @Test
    fun `default SettingsUiState has null error`() {
        val state = SettingsUiState()
        assertNull(state.error)
    }

    @Test
    fun `default SettingsUiState has Not configured sync folder display name`() {
        val state = SettingsUiState()
        assertEquals("Not configured", state.syncFolderDisplayName)
    }

    @Test
    fun `default SettingsUiState preferences has correct GPS mode`() {
        val state = SettingsUiState()
        assertEquals(GpsAccuracyMode.HIGH, state.preferences.gpsAccuracyMode)
    }

    @Test
    fun `default SettingsUiState preferences has correct unit system`() {
        val state = SettingsUiState()
        assertEquals(UnitSystem.METRIC, state.preferences.unitSystem)
    }

    // ── directorySize ─────────────────────────────────────────────

    @Test
    fun `directorySize returns 0 for non-existent directory`() {
        val nonExistent = File(tempFolder.root, "does_not_exist")
        val size = SettingsViewModel.directorySize(nonExistent)
        assertEquals(0L, size)
    }

    @Test
    fun `directorySize returns 0 for empty directory`() {
        val emptyDir = tempFolder.newFolder("empty")
        val size = SettingsViewModel.directorySize(emptyDir)
        assertEquals(0L, size)
    }

    @Test
    fun `directorySize returns correct size for single file`() {
        val dir = tempFolder.newFolder("single")
        val file = File(dir, "test.bin")
        file.writeBytes(ByteArray(1024))

        val size = SettingsViewModel.directorySize(dir)
        assertEquals(1024L, size)
    }

    @Test
    fun `directorySize sums multiple files`() {
        val dir = tempFolder.newFolder("multi")
        File(dir, "file1.bin").writeBytes(ByteArray(500))
        File(dir, "file2.bin").writeBytes(ByteArray(300))
        File(dir, "file3.bin").writeBytes(ByteArray(200))

        val size = SettingsViewModel.directorySize(dir)
        assertEquals(1000L, size)
    }

    @Test
    fun `directorySize includes files in subdirectories`() {
        val dir = tempFolder.newFolder("nested")
        File(dir, "top.bin").writeBytes(ByteArray(100))

        val subDir = File(dir, "sub")
        subDir.mkdir()
        File(subDir, "nested.bin").writeBytes(ByteArray(200))

        val deepDir = File(subDir, "deep")
        deepDir.mkdir()
        File(deepDir, "deep.bin").writeBytes(ByteArray(300))

        val size = SettingsViewModel.directorySize(dir)
        assertEquals(600L, size)
    }

    @Test
    fun `directorySize returns 0 when path is a file not a directory`() {
        val file = tempFolder.newFile("not_a_dir.txt")
        file.writeBytes(ByteArray(512))

        val size = SettingsViewModel.directorySize(file)
        assertEquals(0L, size)
    }
}
