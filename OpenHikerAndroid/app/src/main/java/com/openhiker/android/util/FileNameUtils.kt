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

/**
 * Sanitizes a string for use as a file name.
 *
 * Replaces characters that are invalid in file names with underscores,
 * trims whitespace, and falls back to [defaultName] if the result is empty.
 *
 * @param name The raw name to sanitize.
 * @param defaultName Fallback name if sanitization produces an empty string.
 * @return A file-system-safe name string.
 */
fun sanitizeFileName(name: String, defaultName: String = "openhiker_route"): String {
    val sanitized = name.replace(Regex("[^a-zA-Z0-9._\\- ]"), "_").trim()
    return sanitized.ifBlank { defaultName }
}
