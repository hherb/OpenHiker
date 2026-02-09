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

package com.openhiker.core.util

import org.junit.Assert.assertEquals
import org.junit.Test

/** Unit tests for [FormatUtils] byte formatting. */
class FormatUtilsTest {

    // ── Zero and small values ─────────────────────────────────

    @Test
    fun `zero bytes formats as 0 B`() {
        assertEquals("0 B", FormatUtils.formatBytes(0L))
    }

    @Test
    fun `single byte formats as 1 B`() {
        assertEquals("1 B", FormatUtils.formatBytes(1L))
    }

    @Test
    fun `bytes below 1 KB show unit B`() {
        assertEquals("512 B", FormatUtils.formatBytes(512L))
        assertEquals("1023 B", FormatUtils.formatBytes(1023L))
    }

    // ── Kilobyte range ────────────────────────────────────────

    @Test
    fun `exactly 1 KB formats as 1_0 KB`() {
        assertEquals("1.0 KB", FormatUtils.formatBytes(1024L))
    }

    @Test
    fun `fractional kilobytes format with one decimal`() {
        assertEquals("1.5 KB", FormatUtils.formatBytes(1536L))
    }

    @Test
    fun `upper kilobyte range just below 1 MB`() {
        // 1023 KB = 1_047_552 bytes
        assertEquals("1023.0 KB", FormatUtils.formatBytes(1_047_552L))
    }

    // ── Megabyte range ────────────────────────────────────────

    @Test
    fun `exactly 1 MB formats as 1_0 MB`() {
        assertEquals("1.0 MB", FormatUtils.formatBytes(1_048_576L))
    }

    @Test
    fun `fractional megabytes format correctly`() {
        // 15 MB = 15_728_640 bytes
        assertEquals("15.0 MB", FormatUtils.formatBytes(15_728_640L))
    }

    @Test
    fun `typical mbtiles size formats correctly`() {
        // ~250 MB
        assertEquals("250.0 MB", FormatUtils.formatBytes(262_144_000L))
    }

    // ── Gigabyte range ────────────────────────────────────────

    @Test
    fun `exactly 1 GB formats as 1_0 GB`() {
        assertEquals("1.0 GB", FormatUtils.formatBytes(1_073_741_824L))
    }

    @Test
    fun `fractional gigabytes format correctly`() {
        assertEquals("1.5 GB", FormatUtils.formatBytes(1_610_612_736L))
    }

    @Test
    fun `large gigabyte values format correctly`() {
        // ~10 GB
        assertEquals("10.0 GB", FormatUtils.formatBytes(10_737_418_240L))
    }
}
