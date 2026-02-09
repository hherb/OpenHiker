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
import com.openhiker.core.model.RegionMetadata
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [RegionDisplayItem] data class.
 *
 * Verifies that display items correctly carry enriched region data.
 */
class RegionDisplayItemTest {

    private val testBBox = BoundingBox(
        north = 47.30, south = 47.20, east = 11.45, west = 11.35
    )

    private val testMetadata = RegionMetadata(
        id = "test-region-1",
        name = "Innsbruck",
        boundingBox = testBBox,
        minZoom = 12,
        maxZoom = 16,
        tileCount = 1500
    )

    // ── Construction ──────────────────────────────────────────

    @Test
    fun `display item carries correct metadata`() {
        val item = RegionDisplayItem(
            metadata = testMetadata,
            fileSizeBytes = 15_000_000L,
            fileSizeFormatted = "14.3 MB",
            areaKm2 = 85.5
        )
        assertEquals("test-region-1", item.metadata.id)
        assertEquals("Innsbruck", item.metadata.name)
        assertEquals(1500, item.metadata.tileCount)
    }

    @Test
    fun `display item carries correct file size`() {
        val item = RegionDisplayItem(
            metadata = testMetadata,
            fileSizeBytes = 15_000_000L,
            fileSizeFormatted = "14.3 MB",
            areaKm2 = 85.5
        )
        assertEquals(15_000_000L, item.fileSizeBytes)
        assertEquals("14.3 MB", item.fileSizeFormatted)
    }

    @Test
    fun `display item carries correct area`() {
        val item = RegionDisplayItem(
            metadata = testMetadata,
            fileSizeBytes = 0L,
            fileSizeFormatted = "0 B",
            areaKm2 = 123.4
        )
        assertEquals(123.4, item.areaKm2, 0.001)
    }

    // ── Area from bounding box ────────────────────────────────

    @Test
    fun `area from bounding box is positive`() {
        val area = testBBox.areaKm2
        assertTrue("Area should be positive, got $area", area > 0.0)
    }

    // ── Equality ──────────────────────────────────────────────

    @Test
    fun `display items with same fields are equal`() {
        val item1 = RegionDisplayItem(
            metadata = testMetadata,
            fileSizeBytes = 1000L,
            fileSizeFormatted = "1.0 KB",
            areaKm2 = 10.0
        )
        val item2 = RegionDisplayItem(
            metadata = testMetadata,
            fileSizeBytes = 1000L,
            fileSizeFormatted = "1.0 KB",
            areaKm2 = 10.0
        )
        assertEquals(item1, item2)
    }
}
