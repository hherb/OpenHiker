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

import com.openhiker.core.model.RoutingMode
import kotlinx.serialization.Serializable

/**
 * The index of all community-shared routes in the OpenHikerRoutes repository.
 *
 * Fetched from `index.json` in the repository root. Cached with a 300-second
 * TTL to reduce GitHub API calls. The format matches the iOS RouteIndex
 * struct for cross-platform compatibility.
 *
 * @property updatedAt ISO-8601 timestamp of last index regeneration.
 * @property routeCount Total number of routes in the repository.
 * @property routes List of route entries, sorted newest first.
 */
@Serializable
data class RouteIndex(
    val updatedAt: String,
    val routeCount: Int,
    val routes: List<RouteIndexEntry>
)

/**
 * A summary entry for one community route in the index.
 *
 * Contains enough metadata for browsing and filtering without
 * fetching the full route JSON. The [path] field gives the
 * repository-relative directory for fetching the full route.
 *
 * @property id UUID string matching the full SharedRoute.id.
 * @property name Route name for display.
 * @property activityType Hiking or cycling, for filtering.
 * @property author Display name of the route creator.
 * @property summary First 200 characters of the description.
 * @property createdAt ISO-8601 creation timestamp for sorting.
 * @property region Country and area for geographic filtering.
 * @property stats Distance, elevation, and duration for display.
 * @property boundingBox Geographic extent for spatial search.
 * @property path Repository-relative path (e.g., "routes/US/mount-tamalpais").
 * @property photoCount Number of photos attached to the route.
 * @property waypointCount Number of waypoints on the route.
 */
@Serializable
data class RouteIndexEntry(
    val id: String,
    val name: String,
    val activityType: RoutingMode,
    val author: String,
    val summary: String,
    val createdAt: String,
    val region: RouteRegion,
    val stats: RouteStats,
    val boundingBox: SharedBoundingBox,
    val path: String,
    val photoCount: Int = 0,
    val waypointCount: Int = 0
)
