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

package com.openhiker.android.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class FileNameUtilsTest {

    @Test
    fun `safe name is kept as is`() {
        assertEquals("Mt Kosciuszko_2026-01.v2", sanitizeFileName("Mt Kosciuszko_2026-01.v2"))
    }

    @Test
    fun `path separators are replaced`() {
        val result = sanitizeFileName("../etc/passwd")
        assertFalse(result.contains('/'))
        assertEquals(".._etc_passwd", result)
    }

    @Test
    fun `characters reserved on common file systems are replaced`() {
        assertEquals("a_b_c_d_e_f_g_h_i", sanitizeFileName("a\\b:c*d?e\"f<g>h|i"))
    }

    @Test
    fun `non-ASCII characters are replaced`() {
        assertEquals("Z_rich H_tte", sanitizeFileName("Zürich Hütte"))
    }

    @Test
    fun `surrounding whitespace is trimmed`() {
        assertEquals("Ridge walk", sanitizeFileName("  Ridge walk  "))
    }

    @Test
    fun `empty or blank name falls back to the default`() {
        assertEquals("openhiker_route", sanitizeFileName(""))
        assertEquals("openhiker_route", sanitizeFileName("   "))
    }

    @Test
    fun `custom default is used when given`() {
        assertEquals("hike", sanitizeFileName("", defaultName = "hike"))
    }
}
