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

package com.openhiker.core.navigation

/**
 * Threshold constants for route-following navigation guidance.
 *
 * All values must match the iOS RouteGuidanceConfig exactly to ensure
 * consistent navigation behaviour across platforms. The hysteresis
 * between off-route trigger (50m) and clear (30m) thresholds prevents
 * rapid on/off flapping when the user walks near the route boundary.
 */
object RouteGuidanceConfig {

    /** Distance in metres from the route to trigger an off-route warning. */
    const val OFF_ROUTE_THRESHOLD_METRES = 50.0

    /** Distance in metres to clear the off-route warning (must be < trigger). */
    const val OFF_ROUTE_CLEAR_THRESHOLD_METRES = 30.0

    /** Distance in metres from a turn to fire the "approaching turn" haptic. */
    const val APPROACHING_TURN_DISTANCE_METRES = 100.0

    /** Distance in metres from a turn to fire the "at turn" haptic and advance. */
    const val AT_TURN_DISTANCE_METRES = 30.0

    /** Distance in metres from the destination to trigger "arrived" notification. */
    const val ARRIVED_DISTANCE_METRES = 30.0
}
