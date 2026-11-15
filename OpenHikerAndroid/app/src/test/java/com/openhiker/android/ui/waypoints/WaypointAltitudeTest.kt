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

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Unit tests for [waypointAltitude] (#65). */
class WaypointAltitudeTest {

    @Test
    fun `fix without altitude stores null, not 0 m`() {
        assertNull(waypointAltitude(hasAltitude = false, altitude = 0.0))
    }

    @Test
    fun `valid altitude is stored`() {
        assertEquals(1234.5, waypointAltitude(hasAltitude = true, altitude = 1234.5)!!, 0.0)
    }

    @Test
    fun `valid altitude below sea level is kept`() {
        assertEquals(-28.0, waypointAltitude(hasAltitude = true, altitude = -28.0)!!, 0.0)
    }

    @Test
    fun `valid altitude of exactly 0 m is kept`() {
        assertEquals(0.0, waypointAltitude(hasAltitude = true, altitude = 0.0)!!, 0.0)
    }
}
