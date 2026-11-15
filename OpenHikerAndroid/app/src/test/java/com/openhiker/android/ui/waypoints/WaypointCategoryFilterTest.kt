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

package com.openhiker.android.ui.waypoints

import com.openhiker.android.data.db.waypoints.WaypointSummary
import com.openhiker.core.model.WaypointCategory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/** Unit tests for [toggledCategories] and [filterByCategories] (#30 item 8). */
class WaypointCategoryFilterTest {

    private fun waypoint(id: String, category: String) = WaypointSummary(
        id = id,
        latitude = 47.0,
        longitude = 11.0,
        altitude = null,
        timestamp = "2026-01-01T00:00:00Z",
        label = id,
        category = category,
        note = "",
        hasPhoto = false,
        hikeId = null,
        modifiedAt = null
    )

    private val waypoints = listOf(
        waypoint("view", WaypointCategory.VIEWPOINT.name),
        waypoint("water", WaypointCategory.WATER_SOURCE.name),
        waypoint("camp", "campsite"),
        waypoint("unknown", "not_a_category")
    )

    // ─── toggledCategories ─────────────────────────────────────────────

    @Test
    fun `toggle adds an unselected category`() {
        assertEquals(
            setOf(WaypointCategory.VIEWPOINT, WaypointCategory.CAMPSITE),
            toggledCategories(setOf(WaypointCategory.VIEWPOINT), WaypointCategory.CAMPSITE)
        )
    }

    @Test
    fun `toggle removes a selected category`() {
        assertEquals(
            setOf(WaypointCategory.CAMPSITE),
            toggledCategories(
                setOf(WaypointCategory.VIEWPOINT, WaypointCategory.CAMPSITE),
                WaypointCategory.VIEWPOINT
            )
        )
    }

    @Test
    fun `toggling twice restores the original selection`() {
        val start = setOf(WaypointCategory.WATER_SOURCE)
        val once = toggledCategories(start, WaypointCategory.VIEWPOINT)
        assertEquals(start, toggledCategories(once, WaypointCategory.VIEWPOINT))
    }

    // ─── filterByCategories ────────────────────────────────────────────

    @Test
    fun `empty selection returns all waypoints unchanged`() {
        assertSame(waypoints, filterByCategories(waypoints, emptySet()))
    }

    @Test
    fun `single category keeps only matching waypoints`() {
        val result = filterByCategories(waypoints, setOf(WaypointCategory.WATER_SOURCE))
        assertEquals(listOf("water"), result.map { it.id })
    }

    @Test
    fun `several categories keep waypoints matching any of them in original order`() {
        val result = filterByCategories(
            waypoints,
            setOf(WaypointCategory.CAMPSITE, WaypointCategory.VIEWPOINT)
        )
        assertEquals(listOf("view", "camp"), result.map { it.id })
    }

    @Test
    fun `stored category matches the enum name ignoring case`() {
        val result = filterByCategories(waypoints, setOf(WaypointCategory.CAMPSITE))
        assertEquals(listOf("camp"), result.map { it.id })
    }

    @Test
    fun `unknown stored category matches no filter`() {
        val result = filterByCategories(waypoints, WaypointCategory.entries.toSet())
        assertEquals(listOf("view", "water", "camp"), result.map { it.id })
    }
}
