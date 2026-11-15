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

package com.openhiker.android.service.export

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Unit tests for [calculateAverageSpeed] (#30 item 7). */
class AverageSpeedTest {

    @Test
    fun `divides distance by duration`() {
        assertEquals(1.25, calculateAverageSpeed(4_500.0, 3_600.0)!!, 1e-9)
    }

    @Test
    fun `zero distance gives zero speed`() {
        assertEquals(0.0, calculateAverageSpeed(0.0, 600.0)!!, 0.0)
    }

    @Test
    fun `zero duration returns null instead of dividing by zero`() {
        assertNull(calculateAverageSpeed(1_000.0, 0.0))
    }

    @Test
    fun `negative duration returns null`() {
        assertNull(calculateAverageSpeed(1_000.0, -5.0))
    }

    @Test
    fun `NaN duration returns null`() {
        assertNull(calculateAverageSpeed(1_000.0, Double.NaN))
    }
}
