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

/**
 * Utility functions for formatting values into human-readable strings.
 *
 * All functions are pure (no side effects) and safe for use on any thread.
 */
object FormatUtils {

    /** Bytes per kilobyte (base-1024). */
    private const val BYTES_PER_KB = 1024.0

    /** Bytes per megabyte (base-1024). */
    private const val BYTES_PER_MB = BYTES_PER_KB * 1024.0

    /** Bytes per gigabyte (base-1024). */
    private const val BYTES_PER_GB = BYTES_PER_MB * 1024.0

    /**
     * Formats a byte count as a human-readable size string.
     *
     * Uses binary (base-1024) units: B, KB, MB, GB.
     * Results are formatted to one decimal place for KB and above.
     *
     * Examples:
     * - `formatBytes(0)` returns `"0 B"`
     * - `formatBytes(512)` returns `"512 B"`
     * - `formatBytes(1536)` returns `"1.5 KB"`
     * - `formatBytes(15_728_640)` returns `"15.0 MB"`
     * - `formatBytes(1_610_612_736)` returns `"1.5 GB"`
     *
     * @param bytes The size in bytes. Should be non-negative.
     * @return Formatted string like "15.2 MB" or "1.3 GB".
     */
    fun formatBytes(bytes: Long): String {
        val gb = bytes / BYTES_PER_GB
        val mb = bytes / BYTES_PER_MB
        val kb = bytes / BYTES_PER_KB
        return when {
            gb >= 1.0 -> "%.1f GB".format(gb)
            mb >= 1.0 -> "%.1f MB".format(mb)
            kb >= 1.0 -> "%.1f KB".format(kb)
            else -> "$bytes B"
        }
    }
}
