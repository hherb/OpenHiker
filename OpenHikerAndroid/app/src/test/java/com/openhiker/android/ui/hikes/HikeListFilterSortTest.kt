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

package com.openhiker.android.ui.hikes

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class HikeListFilterSortTest {

    private fun item(
        id: String,
        name: String = id,
        startTime: String = "2026-01-01T00:00:00Z",
        distance: Double = 0.0,
        gain: Double = 0.0,
        duration: Double = 0.0
    ) = HikeListItem(
        id = id,
        name = name,
        startTime = startTime,
        formattedDistance = "",
        formattedElevationGain = "",
        formattedDuration = "",
        totalDistance = distance,
        elevationGain = gain,
        durationSeconds = duration
    )

    private val items = listOf(
        item("a", name = "Morning Ridge", startTime = "2026-03-01T08:00:00Z", distance = 5_000.0, gain = 300.0, duration = 7_200.0),
        item("b", name = "Lake loop", startTime = "2026-05-10T09:30:00Z", distance = 12_000.0, gain = 100.0, duration = 3_600.0),
        item("c", name = "ridge traverse", startTime = "2025-12-24T07:15:00Z", distance = 8_000.0, gain = 900.0, duration = 10_800.0)
    )

    // ── filterByQuery ────────────────────────────────────────────────

    @Test
    fun `blank query returns all items unchanged`() {
        assertSame(items, filterByQuery(items, ""))
        assertSame(items, filterByQuery(items, "   "))
    }

    @Test
    fun `query matches name case-insensitively`() {
        assertEquals(listOf("a", "c"), filterByQuery(items, "RIDGE").map { it.id })
    }

    @Test
    fun `query matches a substring in the middle of the name`() {
        assertEquals(listOf("b"), filterByQuery(items, "e lo").map { it.id })
    }

    @Test
    fun `query with no match returns empty list`() {
        assertTrue(filterByQuery(items, "glacier").isEmpty())
    }

    // ── sortItems ────────────────────────────────────────────────────

    @Test
    fun `date sort puts newest first`() {
        assertEquals(listOf("b", "a", "c"), sortItems(items, HikeSortOption.DATE).map { it.id })
    }

    @Test
    fun `date sort compares instants, not strings`() {
        // As strings, "08:30+02:00" > "07:00Z" and "00Z" > "00.5Z"; as instants both are older.
        val mixed = listOf(
            item("offset", startTime = "2026-03-01T08:30:00+02:00"), // 06:30 UTC
            item("utc", startTime = "2026-03-01T07:00:00Z"),
            item("whole", startTime = "2026-03-01T09:00:00Z"),
            item("fraction", startTime = "2026-03-01T09:00:00.5Z")
        )
        assertEquals(
            listOf("fraction", "whole", "utc", "offset"),
            sortItems(mixed, HikeSortOption.DATE).map { it.id }
        )
    }

    @Test
    fun `date sort puts unparseable start times last`() {
        val mixed = listOf(item("bad", startTime = "not a date"), item("ok", startTime = "2020-01-01T00:00:00Z"))
        assertEquals(listOf("ok", "bad"), sortItems(mixed, HikeSortOption.DATE).map { it.id })
    }

    @Test
    fun `parseStartTime reads Z and offset timestamps and rejects other text`() {
        assertEquals(Instant.parse("2026-03-01T06:30:00Z"), parseStartTime("2026-03-01T08:30:00+02:00"))
        assertEquals(Instant.parse("2026-03-01T09:00:00.5Z"), parseStartTime("2026-03-01T09:00:00.5Z"))
        assertNull(parseStartTime("2026-03-01"))
        assertNull(parseStartTime(""))
    }

    @Test
    fun `distance sort puts longest first`() {
        assertEquals(listOf("b", "c", "a"), sortItems(items, HikeSortOption.DISTANCE).map { it.id })
    }

    @Test
    fun `elevation sort puts biggest gain first`() {
        assertEquals(listOf("c", "a", "b"), sortItems(items, HikeSortOption.ELEVATION).map { it.id })
    }

    @Test
    fun `duration sort puts longest first`() {
        assertEquals(listOf("c", "a", "b"), sortItems(items, HikeSortOption.DURATION).map { it.id })
    }

    @Test
    fun `sort keeps the original order for ties`() {
        val tied = listOf(item("x", distance = 1.0), item("y", distance = 1.0))
        assertEquals(listOf("x", "y"), sortItems(tied, HikeSortOption.DISTANCE).map { it.id })
    }

    @Test
    fun `sorting an empty list returns an empty list`() {
        assertTrue(sortItems(emptyList(), HikeSortOption.DATE).isEmpty())
    }
}
