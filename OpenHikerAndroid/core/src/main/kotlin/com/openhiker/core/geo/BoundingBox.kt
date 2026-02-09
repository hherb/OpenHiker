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

package com.openhiker.core.geo

import com.openhiker.core.model.Coordinate
import kotlinx.serialization.Serializable
import kotlin.math.cos

/**
 * An axis-aligned geographic bounding box in WGS84 coordinates.
 *
 * Defines a rectangular region on the Earth's surface by its four edges.
 * Used to specify map region downloads, tile range calculations, and
 * spatial containment checks. The JSON format matches the iOS BoundingBox
 * struct for cross-platform region file compatibility.
 *
 * Note: Does not handle the antimeridian (180° longitude) crossing case.
 * All hiking regions are expected to be well within a single hemisphere.
 *
 * @property north Northern latitude boundary in degrees (-90 to +90).
 * @property south Southern latitude boundary in degrees (-90 to +90).
 * @property east Eastern longitude boundary in degrees (-180 to +180).
 * @property west Western longitude boundary in degrees (-180 to +180).
 */
@Serializable
data class BoundingBox(
    val north: Double,
    val south: Double,
    val east: Double,
    val west: Double
) {
    /** Geographic centre of the bounding box. */
    val center: Coordinate
        get() = Coordinate(
            latitude = (north + south) / 2.0,
            longitude = (east + west) / 2.0
        )

    /** Width of the bounding box in degrees of longitude. */
    val widthDegrees: Double get() = east - west

    /** Height of the bounding box in degrees of latitude. */
    val heightDegrees: Double get() = north - south

    /**
     * Approximate area of the bounding box in square kilometres.
     *
     * Uses a simplified flat-Earth approximation with latitude-corrected
     * longitude scaling. Accurate enough for hiking-scale regions (< 100km).
     *
     * Formula: width_km * height_km where
     *   height_km = heightDegrees * 111.32
     *   width_km = widthDegrees * 111.32 * cos(centerLatitude)
     */
    val areaKm2: Double
        get() {
            val latRadians = Math.toRadians(center.latitude)
            val heightKm = heightDegrees * DEGREES_TO_KM
            val widthKm = widthDegrees * DEGREES_TO_KM * cos(latRadians)
            return heightKm * widthKm
        }

    /**
     * Checks whether a coordinate falls within this bounding box.
     *
     * @param coordinate The geographic coordinate to test.
     * @return True if the coordinate is within the box (inclusive of edges).
     */
    fun contains(coordinate: Coordinate): Boolean =
        coordinate.latitude in south..north &&
            coordinate.longitude in west..east

    companion object {
        /** Approximate km per degree of latitude at the equator. */
        private const val DEGREES_TO_KM = 111.32

        /**
         * Creates a bounding box centred on a point with a given radius.
         *
         * Computes the lat/lon deltas for the given radius in metres,
         * accounting for longitude compression at the given latitude.
         *
         * @param center The centre coordinate.
         * @param radiusMetres The radius in metres from the centre to each edge.
         * @return A bounding box approximately [radiusMetres] in each direction.
         */
        fun fromCenter(center: Coordinate, radiusMetres: Double): BoundingBox {
            val latDelta = radiusMetres / (DEGREES_TO_KM * 1000.0)
            val lonDelta = radiusMetres /
                (DEGREES_TO_KM * 1000.0 * cos(Math.toRadians(center.latitude)))

            return BoundingBox(
                north = center.latitude + latDelta,
                south = center.latitude - latDelta,
                east = center.longitude + lonDelta,
                west = center.longitude - lonDelta
            )
        }
    }
}
