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
 * Direction of a turn in a navigation instruction.
 *
 * Each direction has a human-readable verb for display in the navigation
 * UI and a Material icon name for rendering the turn arrow.
 * Serial names match the iOS TurnDirection raw values.
 *
 * @property verb Human-readable description (e.g., "Turn left").
 * @property iconName Material Design icon name for the turn arrow.
 */
@Serializable
enum class TurnDirection(
    val verb: String,
    val iconName: String
) {
    @SerialName("start")
    START("Start", "play_arrow"),

    @SerialName("straight")
    STRAIGHT("Continue straight", "arrow_upward"),

    @SerialName("slightLeft")
    SLIGHT_LEFT("Bear left", "turn_slight_left"),

    @SerialName("left")
    LEFT("Turn left", "turn_left"),

    @SerialName("sharpLeft")
    SHARP_LEFT("Sharp left", "turn_sharp_left"),

    @SerialName("slightRight")
    SLIGHT_RIGHT("Bear right", "turn_slight_right"),

    @SerialName("right")
    RIGHT("Turn right", "turn_right"),

    @SerialName("sharpRight")
    SHARP_RIGHT("Sharp right", "turn_sharp_right"),

    @SerialName("uTurn")
    U_TURN("U-turn", "u_turn_right"),

    @SerialName("arrive")
    ARRIVE("Arrive", "flag")
}
