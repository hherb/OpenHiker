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
 * A geographic coordinate in WGS84 (latitude/longitude).
 *
 * Platform-agnostic replacement for Apple's CLLocationCoordinate2D.
 * Serializes to JSON as {"latitude": ..., "longitude": ...} which is
 * byte-compatible with the iOS app's CLLocationCoordinate2D Codable output.
 *
 * @property latitude Degrees north of the equator (-90 to +90).
 * @property longitude Degrees east of the prime meridian (-180 to +180).
 */
@Serializable
data class Coordinate(
    val latitude: Double,
    val longitude: Double
) {
    companion object {
        /** The null island coordinate (0, 0). Useful as a default/sentinel. */
        val ZERO = Coordinate(0.0, 0.0)
    }

    /**
     * Formats the coordinate as a human-readable string with 5 decimal places.
     *
     * 5 decimal places gives ~1.1 meter precision, which is sufficient
     * for hiking GPS accuracy.
     *
     * @return A string like "47.26543, 11.39354".
     */
    fun formatted(): String = "%.5f, %.5f".format(latitude, longitude)
}
