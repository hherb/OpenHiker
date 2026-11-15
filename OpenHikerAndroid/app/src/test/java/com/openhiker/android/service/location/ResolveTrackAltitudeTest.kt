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
package com.openhiker.android.service.location

import com.openhiker.core.compression.TrackPoint
import org.junit.Assert.assertEquals
import org.junit.Test

class ResolveTrackAltitudeTest {

    private fun point(altitude: Double, t: Double) = TrackPoint(47.0, 11.0, altitude, t)

    @Test
    fun `fix with altitude is stored as is`() {
        val recorded = mutableListOf(point(500.0, 1.0))
        assertEquals(510.0, resolveTrackAltitude(recorded, 510.0, 500.0), 0.0)
        assertEquals(listOf(point(500.0, 1.0)), recorded)
    }

    @Test
    fun `fix without altitude reuses the last known one`() {
        val recorded = mutableListOf(point(500.0, 1.0))
        assertEquals(500.0, resolveTrackAltitude(recorded, null, 500.0), 0.0)
    }

    @Test
    fun `no altitude yet stores the placeholder`() {
        assertEquals(0.0, resolveTrackAltitude(mutableListOf(), null, null), 0.0)
    }

    @Test
    fun `first altitude backfills the leading points`() {
        val recorded = mutableListOf(point(0.0, 1.0), point(0.0, 2.0))
        assertEquals(820.0, resolveTrackAltitude(recorded, 820.0, null), 0.0)
        assertEquals(listOf(point(820.0, 1.0), point(820.0, 2.0)), recorded)
    }

    @Test
    fun `later altitudes do not rewrite earlier points`() {
        val recorded = mutableListOf(point(820.0, 1.0), point(830.0, 2.0))
        resolveTrackAltitude(recorded, 900.0, 830.0)
        assertEquals(listOf(point(820.0, 1.0), point(830.0, 2.0)), recorded)
    }
}
