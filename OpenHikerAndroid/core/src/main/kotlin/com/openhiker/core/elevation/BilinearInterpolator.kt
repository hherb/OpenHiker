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

package com.openhiker.core.elevation

import kotlin.math.floor

/**
 * Bilinear interpolation for sub-cell elevation lookups in HGT grids.
 *
 * Given a latitude and longitude that falls between grid cells, this
 * interpolator computes a weighted average of the four surrounding cells
 * to produce a smooth elevation estimate.
 *
 * Handles void cells by falling back to the nearest non-void neighbour
 * among the four surrounding cells. Returns null only if all four cells
 * are void.
 *
 * Pure functions only — no state, no side effects.
 */
object BilinearInterpolator {

    /**
     * Looks up the interpolated elevation at a geographic coordinate.
     *
     * Computes the fractional row and column within the grid, then
     * performs bilinear interpolation between the four surrounding cells.
     *
     * The HGT grid has row 0 at the **north** edge (highest latitude)
     * and column 0 at the **west** edge (lowest longitude). The grid
     * covers from [southwestLatitude, southwestLatitude + 1] in latitude
     * and [southwestLongitude, southwestLongitude + 1] in longitude.
     *
     * @param grid The parsed HGT elevation grid.
     * @param latitude WGS84 latitude in degrees.
     * @param longitude WGS84 longitude in degrees.
     * @return Interpolated elevation in metres, or null if all surrounding
     *         cells are void (no data).
     */
    fun interpolate(grid: HgtGrid, latitude: Double, longitude: Double): Double? {
        // Fractional position within the tile (0.0 = SW corner, 1.0 = NE corner)
        val latFraction = latitude - grid.southwestLatitude
        val lonFraction = longitude - grid.southwestLongitude

        // Clamp to valid range [0, 1]
        val clampedLat = latFraction.coerceIn(0.0, 1.0)
        val clampedLon = lonFraction.coerceIn(0.0, 1.0)

        // Convert to grid coordinates. Row 0 = north, so invert latitude.
        // samples - 1 intervals across the 1-degree tile
        val intervals = grid.samples - 1
        val rowExact = (1.0 - clampedLat) * intervals
        val colExact = clampedLon * intervals

        // Integer row/col of the north-west corner of the surrounding cell
        val row0 = floor(rowExact).toInt().coerceIn(0, intervals - 1)
        val col0 = floor(colExact).toInt().coerceIn(0, intervals - 1)
        val row1 = row0 + 1
        val col1 = col0 + 1

        // Fractional position within the cell
        val rowFrac = rowExact - row0
        val colFrac = colExact - col0

        // Read the four surrounding elevations
        val nw = grid.elevationAt(row0, col0)?.toDouble()
        val ne = grid.elevationAt(row0, col1)?.toDouble()
        val sw = grid.elevationAt(row1, col0)?.toDouble()
        val se = grid.elevationAt(row1, col1)?.toDouble()

        return bilinear(nw, ne, sw, se, rowFrac, colFrac)
    }

    /**
     * Performs bilinear interpolation between four corner values.
     *
     * If any corner is null (void), falls back to the nearest non-void
     * value among the four corners. Returns null only if all four are void.
     *
     * @param nw North-west corner value, or null if void.
     * @param ne North-east corner value, or null if void.
     * @param sw South-west corner value, or null if void.
     * @param se South-east corner value, or null if void.
     * @param rowFrac Fractional row position within the cell (0 = north, 1 = south).
     * @param colFrac Fractional column position within the cell (0 = west, 1 = east).
     * @return Interpolated value, or null if all corners are void.
     */
    internal fun bilinear(
        nw: Double?,
        ne: Double?,
        sw: Double?,
        se: Double?,
        rowFrac: Double,
        colFrac: Double
    ): Double? {
        val corners = listOfNotNull(nw, ne, sw, se)
        if (corners.isEmpty()) return null

        // If all four are valid, perform standard bilinear interpolation
        if (nw != null && ne != null && sw != null && se != null) {
            val top = nw + (ne - nw) * colFrac
            val bottom = sw + (se - sw) * colFrac
            return top + (bottom - top) * rowFrac
        }

        // Partial data: use inverse-distance weighting among available corners.
        // Each corner's weight is based on its proximity to (rowFrac, colFrac).
        val weights = mutableListOf<Pair<Double, Double>>() // (value, weight)
        val epsilon = 1e-10

        if (nw != null) {
            val dist = distance(0.0, 0.0, rowFrac, colFrac)
            weights.add(nw to 1.0 / (dist + epsilon))
        }
        if (ne != null) {
            val dist = distance(0.0, 1.0, rowFrac, colFrac)
            weights.add(ne to 1.0 / (dist + epsilon))
        }
        if (sw != null) {
            val dist = distance(1.0, 0.0, rowFrac, colFrac)
            weights.add(sw to 1.0 / (dist + epsilon))
        }
        if (se != null) {
            val dist = distance(1.0, 1.0, rowFrac, colFrac)
            weights.add(se to 1.0 / (dist + epsilon))
        }

        val totalWeight = weights.sumOf { it.second }
        return weights.sumOf { it.first * it.second } / totalWeight
    }

    /**
     * Euclidean distance between two points in grid-cell coordinates.
     *
     * @param r1 Row of point 1.
     * @param c1 Column of point 1.
     * @param r2 Row of point 2.
     * @param c2 Column of point 2.
     * @return Euclidean distance.
     */
    private fun distance(r1: Double, c1: Double, r2: Double, c2: Double): Double {
        val dr = r2 - r1
        val dc = c2 - c1
        return kotlin.math.sqrt(dr * dr + dc * dc)
    }
}
