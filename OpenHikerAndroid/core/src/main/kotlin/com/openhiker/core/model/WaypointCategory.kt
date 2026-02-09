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

package com.openhiker.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Categories for waypoints (points of interest) on a hike.
 *
 * Each category has a display name, a Material icon name (for Android),
 * and a colour hex code. The serial names match the iOS WaypointCategory
 * raw values for cross-platform JSON compatibility.
 *
 * @property displayName Human-readable label shown in the UI.
 * @property iconName Material Design icon name for Android rendering.
 * @property colorHex Six-character hex colour code (no '#' prefix).
 */
@Serializable
enum class WaypointCategory(
    val displayName: String,
    val iconName: String,
    val colorHex: String
) {
    @SerialName("trailMarker")
    TRAIL_MARKER("Trail Marker", "signpost", "8B4513"),

    @SerialName("viewpoint")
    VIEWPOINT("Viewpoint", "visibility", "4169E1"),

    @SerialName("waterSource")
    WATER_SOURCE("Water Source", "water_drop", "1E90FF"),

    @SerialName("campsite")
    CAMPSITE("Campsite", "camping", "228B22"),

    @SerialName("danger")
    DANGER("Danger", "warning", "FF4500"),

    @SerialName("food")
    FOOD("Food", "restaurant", "FF8C00"),

    @SerialName("shelter")
    SHELTER("Shelter", "house", "708090"),

    @SerialName("parking")
    PARKING("Parking", "local_parking", "4682B4"),

    @SerialName("custom")
    CUSTOM("Custom", "location_on", "9370DB")
}
