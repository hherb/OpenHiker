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

import com.openhiker.core.compression.TrackPoint
import com.openhiker.core.geo.Haversine
import com.openhiker.core.model.Coordinate
import com.openhiker.core.model.ElevationPoint

/**
 * Generates elevation profiles from coordinate lists using HGT grid data.
 *
 * An elevation profile pairs each point along a route with its cumulative
 * distance from the start and its elevation. The resulting list of
 * [ElevationPoint] values can be plotted as an elevation chart.
 *
 * Also computes cumulative elevation gain and loss with a configurable
 * noise filter threshold to suppress GPS and data noise.
 *
 * Pure functions only — no state, no side effects.
 */
object ElevationProfile {

    /**
     * Minimum elevation change in metres to count as gain or loss.
     *
     * Changes smaller than this threshold are considered noise and
     * are ignored in gain/loss accumulation. This matches the iOS
     * implementation's noise filter.
     */
    const val NOISE_FILTER_METRES = 3.0

    /**
     * Generates an elevation profile from a coordinate list.
     *
     * For each coordinate, looks up the elevation from the provided grid
     * lookup function. Computes cumulative Haversine distance between
     * consecutive points. Points where the elevation lookup returns null
     * are skipped.
     *
     * @param coordinates Ordered list of route coordinates.
     * @param elevationLookup Function that returns the elevation in metres
     *        for a given latitude and longitude, or null if unavailable.
     * @return List of [ElevationPoint] with cumulative distance and elevation.
     */
    fun generate(
        coordinates: List<Coordinate>,
        elevationLookup: (latitude: Double, longitude: Double) -> Double?
    ): List<ElevationPoint> {
        if (coordinates.isEmpty()) return emptyList()

        val profile = mutableListOf<ElevationPoint>()
        var cumulativeDistance = 0.0

        for (i in coordinates.indices) {
            if (i > 0) {
                cumulativeDistance += Haversine.distance(coordinates[i - 1], coordinates[i])
            }

            val elevation = elevationLookup(
                coordinates[i].latitude,
                coordinates[i].longitude
            )

            if (elevation != null) {
                profile.add(ElevationPoint(cumulativeDistance, elevation))
            }
        }

        return profile
    }

    /**
     * Computes cumulative elevation gain and loss from an elevation profile.
     *
     * Applies a noise filter: only elevation changes exceeding
     * [NOISE_FILTER_METRES] are counted. This prevents GPS altitude
     * noise from inflating the gain/loss totals.
     *
     * @param profile Ordered list of elevation points.
     * @param noiseThreshold Minimum change in metres to count (default: [NOISE_FILTER_METRES]).
     * @return A pair of (elevationGain, elevationLoss), both in metres (positive values).
     */
    fun computeGainLoss(
        profile: List<ElevationPoint>,
        noiseThreshold: Double = NOISE_FILTER_METRES
    ): ElevationGainLoss {
        val totals = profile.fold(ElevationAccumulator()) { acc, point ->
            acc.add(point.elevation, noiseThreshold)
        }
        return ElevationGainLoss(totals.gain, totals.loss)
    }

    /**
     * Builds an elevation profile from recorded GPS track points.
     *
     * Each point keeps its recorded altitude and gets the cumulative
     * Haversine distance from the first point, ready for an elevation chart.
     *
     * @param trackPoints Recorded track points in time order.
     * @return One [ElevationPoint] per track point, ordered by distance.
     */
    fun fromTrackPoints(trackPoints: List<TrackPoint>): List<ElevationPoint> {
        var cumulativeDistance = 0.0
        return trackPoints.mapIndexed { i, point ->
            if (i > 0) {
                val prev = trackPoints[i - 1]
                cumulativeDistance += Haversine.distance(
                    prev.latitude, prev.longitude,
                    point.latitude, point.longitude
                )
            }
            ElevationPoint(distance = cumulativeDistance, elevation = point.altitude)
        }
    }

    /**
     * Computes the elevation at a specific distance along the profile.
     *
     * Linearly interpolates between the two nearest profile points.
     * Returns null if the profile is empty or the distance is out of range.
     *
     * @param profile Ordered elevation profile.
     * @param distance Distance from route start in metres.
     * @return Interpolated elevation in metres, or null.
     */
    fun elevationAtDistance(
        profile: List<ElevationPoint>,
        distance: Double
    ): Double? {
        if (profile.isEmpty()) return null
        if (distance <= profile.first().distance) return profile.first().elevation
        if (distance >= profile.last().distance) return profile.last().elevation

        // Binary search for the segment containing the distance
        var low = 0
        var high = profile.size - 1
        while (low < high - 1) {
            val mid = (low + high) / 2
            if (profile[mid].distance <= distance) {
                low = mid
            } else {
                high = mid
            }
        }

        val p0 = profile[low]
        val p1 = profile[high]
        val segmentLength = p1.distance - p0.distance
        if (segmentLength <= 0) return p0.elevation

        val fraction = (distance - p0.distance) / segmentLength
        return p0.elevation + (p1.elevation - p0.elevation) * fraction
    }
}

/**
 * Cumulative elevation gain and loss along a profile.
 *
 * @property gain Total uphill elevation change in metres (positive).
 * @property loss Total downhill elevation change in metres (positive).
 */
data class ElevationGainLoss(
    val gain: Double,
    val loss: Double
)

/**
 * Running elevation gain and loss, fed one altitude sample at a time.
 *
 * Used both for whole profiles ([ElevationProfile.computeGainLoss]) and for
 * live hike recording, so both apply the same noise filter. The first sample
 * only sets the reference. After that, a sample counts only once it differs
 * from the last counted sample by at least the noise threshold, so slow drift
 * still adds up once it crosses the threshold.
 *
 * @property gain Total uphill change counted so far, in metres (positive).
 * @property loss Total downhill change counted so far, in metres (positive).
 * @property lastSignificantElevation The last sample that was counted (or the
 *           first sample), or null before any sample.
 */
data class ElevationAccumulator(
    val gain: Double = 0.0,
    val loss: Double = 0.0,
    val lastSignificantElevation: Double? = null
) {
    /**
     * Returns the totals after one more altitude sample.
     *
     * @param altitude The new altitude in metres.
     * @param noiseThreshold Minimum change in metres to count
     *        (default: [ElevationProfile.NOISE_FILTER_METRES]).
     * @return Updated totals; this instance is unchanged.
     */
    fun add(
        altitude: Double,
        noiseThreshold: Double = ElevationProfile.NOISE_FILTER_METRES
    ): ElevationAccumulator {
        val last = lastSignificantElevation ?: return copy(lastSignificantElevation = altitude)
        val delta = altitude - last
        return when {
            kotlin.math.abs(delta) < noiseThreshold -> this
            delta > 0 -> copy(gain = gain + delta, lastSignificantElevation = altitude)
            else -> copy(loss = loss - delta, lastSignificantElevation = altitude)
        }
    }
}
