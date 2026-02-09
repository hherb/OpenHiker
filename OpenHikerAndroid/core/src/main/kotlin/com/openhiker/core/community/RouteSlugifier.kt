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

package com.openhiker.core.community

/**
 * Pure functions for generating URL-safe slugs from route names.
 *
 * Used to create filesystem-friendly directory names for community
 * route uploads to the GitHub repository. The slug format matches
 * the iOS implementation for consistent cross-platform paths.
 */
object RouteSlugifier {

    /**
     * Converts a human-readable route name to a URL-safe slug.
     *
     * Transformations applied (in order):
     * 1. Convert to lowercase
     * 2. Replace spaces and underscores with hyphens
     * 3. Remove all characters except letters, digits, and hyphens
     * 4. Collapse consecutive hyphens into a single hyphen
     * 5. Trim leading/trailing hyphens
     * 6. Truncate to [maxLength] characters
     * 7. Fall back to "unnamed-route" if the result is empty
     *
     * @param name The human-readable route name.
     * @param maxLength Maximum slug length (default 80).
     * @return A URL-safe slug string.
     */
    fun slugify(name: String, maxLength: Int = MAX_SLUG_LENGTH): String {
        val slug = name
            .lowercase()
            .replace(Regex("[\\s_]+"), "-")
            .replace(Regex("[^a-z0-9-]"), "")
            .replace(Regex("-+"), "-")
            .trim('-')
            .take(maxLength)
            .trimEnd('-')

        return slug.ifEmpty { DEFAULT_SLUG }
    }

    /** Maximum length for generated slugs. */
    private const val MAX_SLUG_LENGTH = 80

    /** Fallback slug when the input produces an empty result. */
    private const val DEFAULT_SLUG = "unnamed-route"
}
