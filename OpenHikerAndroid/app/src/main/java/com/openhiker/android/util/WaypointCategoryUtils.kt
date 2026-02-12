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

import android.util.Log
import androidx.compose.ui.graphics.Color
import com.openhiker.core.model.WaypointCategory

private const val TAG = "WaypointCategoryUtils"

/**
 * Resolves a category string (from the database) to a [WaypointCategory] enum value.
 *
 * Falls back to [WaypointCategory.CUSTOM] if the string does not match any known
 * category, and logs a warning so data corruption is not silently masked.
 *
 * @param categoryName The raw category name from the database.
 * @return The matching [WaypointCategory], or [WaypointCategory.CUSTOM] as fallback.
 */
fun resolveCategory(categoryName: String): WaypointCategory {
    return try {
        WaypointCategory.valueOf(categoryName)
    } catch (e: IllegalArgumentException) {
        Log.w(TAG, "Unknown waypoint category: '$categoryName', falling back to CUSTOM")
        WaypointCategory.CUSTOM
    }
}

/**
 * Parses the hex colour code from a [WaypointCategory] into a Compose [Color].
 *
 * Falls back to medium grey if the hex code is invalid, and logs a warning
 * so invalid colour data is not silently masked.
 *
 * @param category The waypoint category with a [WaypointCategory.colorHex] field.
 * @return The parsed [Color].
 */
fun parseCategoryColor(category: WaypointCategory): Color {
    return try {
        Color(android.graphics.Color.parseColor("#${category.colorHex}"))
    } catch (e: IllegalArgumentException) {
        Log.w(TAG, "Invalid colour hex for category ${category.name}: '${category.colorHex}'")
        Color.Gray
    }
}
