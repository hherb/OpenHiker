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

package com.openhiker.core.model

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Unit tests for [WaypointCategory.rawValue] and [WaypointCategory.fromStored]. */
class WaypointCategoryTest {

    @Test
    fun `rawValue equals the serialised name for every category`() {
        for (category in WaypointCategory.entries) {
            assertEquals("\"${category.rawValue}\"", Json.encodeToString(category))
        }
    }

    @Test
    fun `fromStored reads the raw value`() {
        assertEquals(WaypointCategory.WATER_SOURCE, WaypointCategory.fromStored("waterSource"))
        assertEquals(WaypointCategory.CAMPSITE, WaypointCategory.fromStored("campsite"))
    }

    @Test
    fun `fromStored reads the legacy enum name`() {
        assertEquals(WaypointCategory.TRAIL_MARKER, WaypointCategory.fromStored("TRAIL_MARKER"))
    }

    @Test
    fun `fromStored returns null for unknown or differently cased strings`() {
        assertNull(WaypointCategory.fromStored("not_a_category"))
        assertNull(WaypointCategory.fromStored("WaterSource"))
        assertNull(WaypointCategory.fromStored(""))
    }
}
