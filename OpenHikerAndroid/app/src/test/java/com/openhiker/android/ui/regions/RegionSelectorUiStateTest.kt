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

import com.openhiker.core.geo.BoundingBox
import com.openhiker.core.model.TileServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [RegionSelectorUiState] data class and its computed properties.
 *
 * These are pure data class tests that require no Android framework or mocking.
 */
class RegionSelectorUiStateTest {

    // ── Default state ─────────────────────────────────────────

    @Test
    fun `default state has null bounds`() {
        val state = RegionSelectorUiState()
        assertNull(state.selectedBounds)
    }

    @Test
    fun `default state has correct zoom range`() {
        val state = RegionSelectorUiState()
        assertEquals(RegionSelectorUiState.DEFAULT_MIN_ZOOM, state.minZoom)
        assertEquals(RegionSelectorUiState.DEFAULT_MAX_ZOOM, state.maxZoom)
    }

    @Test
    fun `default state uses OpenTopoMap server`() {
        val state = RegionSelectorUiState()
        assertEquals(TileServer.OPEN_TOPO_MAP, state.tileServer)
    }

    @Test
    fun `default state has zero tile count`() {
        val state = RegionSelectorUiState()
        assertEquals(0, state.estimatedTileCount)
    }

    @Test
    fun `default state has empty region name`() {
        val state = RegionSelectorUiState()
        assertEquals("", state.regionName)
    }

    @Test
    fun `default state does not show confirm dialog`() {
        val state = RegionSelectorUiState()
        assertFalse(state.showConfirmDialog)
    }

    // ── estimatedSizeFormatted ────────────────────────────────

    @Test
    fun `zero tiles formats as 0_0 MB`() {
        val state = RegionSelectorUiState(estimatedTileCount = 0)
        assertEquals("0.0 MB", state.estimatedSizeFormatted)
    }

    @Test
    fun `small tile count formats as MB`() {
        // 100 tiles * 30000 bytes = 3_000_000 bytes = ~2.9 MB
        val state = RegionSelectorUiState(estimatedTileCount = 100)
        assertTrue(
            "Expected MB range, got ${state.estimatedSizeFormatted}",
            state.estimatedSizeFormatted.endsWith("MB")
        )
    }

    @Test
    fun `typical region tile count formats as MB`() {
        // 1000 tiles * 30000 bytes = 30_000_000 bytes = ~28.6 MB
        val state = RegionSelectorUiState(estimatedTileCount = 1000)
        val formatted = state.estimatedSizeFormatted
        assertTrue("Expected MB format, got $formatted", formatted.endsWith("MB"))
    }

    @Test
    fun `large tile count formats as GB`() {
        // 50000 tiles * 30000 bytes = 1_500_000_000 bytes = ~1.4 GB
        val state = RegionSelectorUiState(estimatedTileCount = 50000)
        val formatted = state.estimatedSizeFormatted
        assertTrue("Expected GB format, got $formatted", formatted.endsWith("GB"))
    }

    // ── Copy mutations ────────────────────────────────────────

    @Test
    fun `copy with bounds preserves other fields`() {
        val original = RegionSelectorUiState(
            regionName = "Test",
            minZoom = 14,
            maxZoom = 18
        )
        val bbox = BoundingBox(north = 47.3, south = 47.2, east = 11.4, west = 11.3)
        val updated = original.copy(selectedBounds = bbox, estimatedTileCount = 500)

        assertEquals("Test", updated.regionName)
        assertEquals(14, updated.minZoom)
        assertEquals(18, updated.maxZoom)
        assertEquals(bbox, updated.selectedBounds)
        assertEquals(500, updated.estimatedTileCount)
    }

    @Test
    fun `copy with showConfirmDialog toggles correctly`() {
        val state = RegionSelectorUiState()
        val shown = state.copy(showConfirmDialog = true)
        assertTrue(shown.showConfirmDialog)
        val hidden = shown.copy(showConfirmDialog = false)
        assertFalse(hidden.showConfirmDialog)
    }
}
