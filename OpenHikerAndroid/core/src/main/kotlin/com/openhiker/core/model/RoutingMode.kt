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
 * The activity mode used for route cost computation.
 *
 * Determines which cost constants (speed, climb penalty, surface multipliers)
 * are applied during A* pathfinding. Matches the iOS RoutingMode enum values
 * for cross-platform route compatibility.
 *
 * @property hiking Uses Naismith's rule: 1.33 m/s base, 7.92s penalty per metre climb.
 * @property cycling Steeper penalties: 4.17 m/s base, 12.0s penalty per metre climb.
 */
@Serializable
enum class RoutingMode {
    @SerialName("hiking")
    HIKING,

    @SerialName("cycling")
    CYCLING
}
