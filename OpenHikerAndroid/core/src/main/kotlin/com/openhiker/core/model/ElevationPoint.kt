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

import kotlinx.serialization.Serializable

/**
 * A single point on an elevation profile chart.
 *
 * Pairs a cumulative distance from the route start with the elevation
 * at that point. Used to render elevation profile charts in the UI
 * for both planned and recorded routes.
 *
 * @property distance Cumulative distance from route start in metres.
 * @property elevation Elevation above sea level in metres.
 */
@Serializable
data class ElevationPoint(
    val distance: Double,
    val elevation: Double
)
