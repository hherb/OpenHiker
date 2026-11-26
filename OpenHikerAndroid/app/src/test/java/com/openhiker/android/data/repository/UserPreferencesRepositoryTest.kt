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

import androidx.datastore.core.handlers.ReplaceFileCorruptionHandler
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
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
 * Unit tests for the pure data classes and enums in UserPreferencesRepository.
 *
 * Covers [GpsAccuracyMode], [UnitSystem], and [UserPreferences] default values, the read-error
 * operators, and the repository on a real DataStore file, all on the JVM.
 */
class UserPreferencesRepositoryTest {

    @get:Rule
    val folder = TemporaryFolder()

    /**
     * Runs [block] on a repository over a DataStore on [file], with the app's corruption
     * handler, and closes the DataStore afterwards.
     */
    private fun withRepository(file: File, block: suspend (UserPreferencesRepository) -> Unit) {
        val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        try {
            val dataStore = PreferenceDataStoreFactory.create(
                corruptionHandler = ReplaceFileCorruptionHandler(
                    UserPreferencesRepository::resetAfterCorruption
                ),
                scope = scope,
                produceFile = { file }
            )
            runBlocking { block(UserPreferencesRepository(dataStore)) }
        } finally {
            scope.cancel()
        }
    }

    // ── Damaged preferences file (#115) ───────────────────────────

    @Test
    fun `a damaged file reads as the defaults with the reset notice, until dismissed`() {
        val file = File(folder.root, "user_preferences.preferences_pb")
        file.writeBytes(byteArrayOf(0x7f, 0x00, 0x13, 0x42))

        withRepository(file) { repo ->
            assertEquals(UserPreferences(settingsWereReset = true), repo.preferencesFlow.first())

            repo.setSyncEnabled(true)
            repo.dismissSettingsResetNotice()

            assertEquals(UserPreferences(syncEnabled = true), repo.preferencesFlow.first())
        }
    }

    @Test
    fun `a readable file has no reset notice`() {
        withRepository(File(folder.root, "user_preferences.preferences_pb")) { repo ->
            repo.setUnitSystem(UnitSystem.IMPERIAL)
            assertEquals(
                UserPreferences(unitSystem = UnitSystem.IMPERIAL), repo.preferencesFlow.first()
            )
        }
    }

    // ── retryOnReadError (#115) ───────────────────────────────────

    @Test
    fun `the retry delay doubles from one second up to a minute`() {
        assertEquals(
            listOf(1_000L, 2_000L, 4_000L, 32_000L, 60_000L, 60_000L, 60_000L),
            listOf(0L, 1L, 2L, 5L, 6L, 7L, Long.MAX_VALUE).map(::preferencesRetryDelayMs)
        )
    }

    @Test
    fun `a read failure is retried until the preferences can be read`() = runTest {
        var reads = 0
        val waits = mutableListOf<Long>()
        val prefs = UserPreferences(syncEnabled = true)
        val emitted = flow {
            if (++reads < 3) throw IOException("disk error")
            emit(prefs)
        }.retryOnReadError(delayMs = { attempt -> 10L.also { waits.add(attempt) } }).toList()

        // No defaults in between: the collector only sees the stored values.
        assertEquals(listOf(prefs), emitted)
        assertEquals(listOf(0L, 1L), waits)
    }

    @Test(expected = IllegalStateException::class)
    fun `retryOnReadError does not retry an error other than a read failure`() = runTest {
        flow<UserPreferences> { throw IllegalStateException("bug") }
            .retryOnReadError(delayMs = { 10L }).toList()
    }

    // ── orDefaultsOnReadError (#112) ──────────────────────────────

    @Test
    fun `a read failure emits the defaults with the error, then reads again`() = runTest {
        var reads = 0
        val prefs = UserPreferences(syncEnabled = true)
        val emitted = flow {
            if (++reads == 1) throw IOException("disk error")
            emit(prefs)
        }.orDefaultsOnReadError { 10L }.toList()
        assertEquals(listOf(UserPreferences(readError = "disk error"), prefs), emitted)
    }

    @Test
    fun `readable preferences pass through unchanged`() = runTest {
        val prefs = UserPreferences(syncEnabled = true)
        assertEquals(listOf(prefs), flowOf(prefs).orDefaultsOnReadError().toList())
    }

    @Test(expected = IllegalStateException::class)
    fun `an error other than a read failure still propagates`() = runTest {
        flow<UserPreferences> { throw IllegalStateException("bug") }
            .orDefaultsOnReadError().toList()
    }

    // ── GpsAccuracyMode.fromId ────────────────────────────────────

    @Test
    fun `GpsAccuracyMode fromId returns HIGH for valid id high`() {
        val mode = GpsAccuracyMode.fromId("high")
        assertEquals(GpsAccuracyMode.HIGH, mode)
    }

    @Test
    fun `GpsAccuracyMode fromId returns BALANCED for valid id balanced`() {
        val mode = GpsAccuracyMode.fromId("balanced")
        assertEquals(GpsAccuracyMode.BALANCED, mode)
    }

    @Test
    fun `GpsAccuracyMode fromId returns LOW_POWER for valid id low_power`() {
        val mode = GpsAccuracyMode.fromId("low_power")
        assertEquals(GpsAccuracyMode.LOW_POWER, mode)
    }

    @Test
    fun `GpsAccuracyMode fromId defaults to HIGH for unknown id`() {
        val mode = GpsAccuracyMode.fromId("unknown_mode")
        assertEquals(GpsAccuracyMode.HIGH, mode)
    }

    @Test
    fun `GpsAccuracyMode fromId defaults to HIGH for empty string`() {
        val mode = GpsAccuracyMode.fromId("")
        assertEquals(GpsAccuracyMode.HIGH, mode)
    }

    // ── GpsAccuracyMode enum properties ───────────────────────────

    @Test
    fun `GpsAccuracyMode HIGH has correct intervalMs`() {
        assertEquals(2000L, GpsAccuracyMode.HIGH.intervalMs)
    }

    @Test
    fun `GpsAccuracyMode HIGH has correct minDisplacementMetres`() {
        assertEquals(5f, GpsAccuracyMode.HIGH.minDisplacementMetres)
    }

    @Test
    fun `GpsAccuracyMode BALANCED has correct intervalMs`() {
        assertEquals(5000L, GpsAccuracyMode.BALANCED.intervalMs)
    }

    @Test
    fun `GpsAccuracyMode BALANCED has correct minDisplacementMetres`() {
        assertEquals(10f, GpsAccuracyMode.BALANCED.minDisplacementMetres)
    }

    @Test
    fun `GpsAccuracyMode LOW_POWER has correct intervalMs`() {
        assertEquals(10000L, GpsAccuracyMode.LOW_POWER.intervalMs)
    }

    @Test
    fun `GpsAccuracyMode LOW_POWER has correct minDisplacementMetres`() {
        assertEquals(50f, GpsAccuracyMode.LOW_POWER.minDisplacementMetres)
    }

    @Test
    fun `GpsAccuracyMode HIGH has correct displayName`() {
        assertEquals("High Accuracy", GpsAccuracyMode.HIGH.displayName)
    }

    @Test
    fun `GpsAccuracyMode BALANCED has correct displayName`() {
        assertEquals("Balanced", GpsAccuracyMode.BALANCED.displayName)
    }

    @Test
    fun `GpsAccuracyMode LOW_POWER has correct displayName`() {
        assertEquals("Low Power", GpsAccuracyMode.LOW_POWER.displayName)
    }

    // ── UnitSystem.fromId ─────────────────────────────────────────

    @Test
    fun `UnitSystem fromId returns METRIC for valid id metric`() {
        val unit = UnitSystem.fromId("metric")
        assertEquals(UnitSystem.METRIC, unit)
    }

    @Test
    fun `UnitSystem fromId returns IMPERIAL for valid id imperial`() {
        val unit = UnitSystem.fromId("imperial")
        assertEquals(UnitSystem.IMPERIAL, unit)
    }

    @Test
    fun `UnitSystem fromId defaults to METRIC for unknown id`() {
        val unit = UnitSystem.fromId("unknown_system")
        assertEquals(UnitSystem.METRIC, unit)
    }

    @Test
    fun `UnitSystem fromId defaults to METRIC for empty string`() {
        val unit = UnitSystem.fromId("")
        assertEquals(UnitSystem.METRIC, unit)
    }

    @Test
    fun `UnitSystem METRIC has correct displayName`() {
        assertEquals("Metric (km, m)", UnitSystem.METRIC.displayName)
    }

    @Test
    fun `UnitSystem IMPERIAL has correct displayName`() {
        assertEquals("Imperial (mi, ft)", UnitSystem.IMPERIAL.displayName)
    }

    // ── UserPreferences default values ────────────────────────────

    @Test
    fun `UserPreferences default tile server is opentopomap`() {
        val prefs = UserPreferences()
        assertEquals("opentopomap", prefs.defaultTileServerId)
        assertEquals(UserPreferences.DEFAULT_TILE_SERVER_ID, prefs.defaultTileServerId)
    }

    @Test
    fun `UserPreferences default GPS mode is HIGH`() {
        val prefs = UserPreferences()
        assertEquals(GpsAccuracyMode.HIGH, prefs.gpsAccuracyMode)
    }

    @Test
    fun `UserPreferences default unit system is METRIC`() {
        val prefs = UserPreferences()
        assertEquals(UnitSystem.METRIC, prefs.unitSystem)
    }

    @Test
    fun `UserPreferences default haptic feedback is enabled`() {
        val prefs = UserPreferences()
        assertTrue(prefs.hapticFeedbackEnabled)
    }

    @Test
    fun `UserPreferences default audio cues is disabled`() {
        val prefs = UserPreferences()
        assertFalse(prefs.audioCuesEnabled)
    }

    @Test
    fun `UserPreferences default min zoom matches constant`() {
        val prefs = UserPreferences()
        assertEquals(12, prefs.defaultMinZoom)
        assertEquals(UserPreferences.DEFAULT_MIN_ZOOM, prefs.defaultMinZoom)
    }

    @Test
    fun `UserPreferences default max zoom matches constant`() {
        val prefs = UserPreferences()
        assertEquals(16, prefs.defaultMaxZoom)
        assertEquals(UserPreferences.DEFAULT_MAX_ZOOM, prefs.defaultMaxZoom)
    }

    @Test
    fun `UserPreferences default concurrent downloads matches constant`() {
        val prefs = UserPreferences()
        assertEquals(6, prefs.concurrentDownloadLimit)
        assertEquals(UserPreferences.DEFAULT_CONCURRENT_DOWNLOADS, prefs.concurrentDownloadLimit)
    }

    @Test
    fun `UserPreferences default sync is disabled`() {
        val prefs = UserPreferences()
        assertFalse(prefs.syncEnabled)
    }

    @Test
    fun `UserPreferences default sync folder URI is null`() {
        val prefs = UserPreferences()
        assertNull(prefs.syncFolderUri)
    }

    @Test
    fun `UserPreferences default keep screen on is enabled`() {
        val prefs = UserPreferences()
        assertTrue(prefs.keepScreenOnDuringNavigation)
    }
}
