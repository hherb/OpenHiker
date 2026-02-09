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

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the pure data classes and enums in UserPreferencesRepository.
 *
 * Covers [GpsAccuracyMode], [UnitSystem], and [UserPreferences] default values
 * without requiring any Android context or DataStore dependencies. These are
 * pure JVM tests that validate enum lookup logic and data class defaults.
 */
class UserPreferencesRepositoryTest {

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
