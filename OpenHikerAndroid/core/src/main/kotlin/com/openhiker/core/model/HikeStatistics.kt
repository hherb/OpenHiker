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
 * Accumulated statistics for a completed hike.
 *
 * All distance values are in metres, all times in seconds, speeds in m/s.
 * Optional fields (heart rate, SpO2, calories) are null when the data
 * source is unavailable (e.g., no wearable connected).
 *
 * @property totalDistance Total distance walked in metres (Haversine sum).
 * @property elevationGain Cumulative uphill elevation change in metres.
 * @property elevationLoss Cumulative downhill elevation change in metres.
 * @property duration Total elapsed time in seconds (start to finish).
 * @property walkingTime Time spent moving (speed > resting threshold) in seconds.
 * @property restingTime Time spent stationary in seconds.
 * @property averageHeartRate Mean heart rate in BPM, or null if unavailable.
 * @property maxHeartRate Peak heart rate in BPM, or null if unavailable.
 * @property averageSpO2 Mean blood oxygen as fraction (0.0–1.0), or null.
 * @property estimatedCalories Estimated kilocalories burned, or null.
 * @property averageSpeed Mean moving speed in m/s.
 * @property maxSpeed Peak speed in m/s.
 */
@Serializable
data class HikeStatistics(
    val totalDistance: Double = 0.0,
    val elevationGain: Double = 0.0,
    val elevationLoss: Double = 0.0,
    val duration: Double = 0.0,
    val walkingTime: Double = 0.0,
    val restingTime: Double = 0.0,
    val averageHeartRate: Double? = null,
    val maxHeartRate: Double? = null,
    val averageSpO2: Double? = null,
    val estimatedCalories: Double? = null,
    val averageSpeed: Double = 0.0,
    val maxSpeed: Double = 0.0
)

/**
 * Configuration constants for hike statistics calculations.
 *
 * All thresholds and conversion factors are defined here to avoid
 * magic numbers throughout the codebase. Values match the iOS
 * HikeStatisticsConfig for consistent behaviour across platforms.
 */
object HikeStatisticsConfig {
    /** Speed below which the user is considered resting, in m/s (~1 km/h). */
    const val RESTING_SPEED_THRESHOLD = 0.3

    /** Base MET value for hiking (Compendium of Physical Activities). */
    const val BASE_HIKING_MET = 6.0

    /** Additional MET per 10% grade increase. */
    const val MET_PER_TEN_PERCENT_GRADE = 1.0

    /** Default body mass for calorie estimation (WHO reference), in kg. */
    const val DEFAULT_BODY_MASS_KG = 70.0

    /** Minimum rest duration to count as a rest period, in seconds. */
    const val MIN_REST_DURATION_SEC = 60.0

    /** Maximum age of SpO2 reading before it's considered stale, in seconds. */
    const val SPO2_MAX_AGE_SEC = 300.0

    /** Metres per statute mile. */
    const val METRES_PER_MILE = 1609.344

    /** Feet per metre. */
    const val FEET_PER_METRE = 3.28084

    /** km/h per m/s. */
    const val KMH_PER_MPS = 3.6

    /** mph per m/s. */
    const val MPH_PER_MPS = 2.23694

    /** Easy effort heart rate ceiling in BPM. */
    const val EASY_HEART_RATE_MAX = 120.0

    /** Moderate effort heart rate ceiling in BPM. */
    const val MODERATE_HEART_RATE_MAX = 150.0

    /** Metres per kilometre. */
    const val METRES_PER_KILOMETRE = 1000.0
}

/**
 * Pure functions for formatting hike statistics for display.
 *
 * All formatters accept raw metric values and return formatted strings.
 * The [useMetric] parameter controls metric vs. imperial output.
 */
object HikeStatsFormatter {

    /**
     * Formats a distance value for display.
     *
     * @param metres Distance in metres.
     * @param useMetric True for km, false for miles.
     * @return Formatted string like "3.2 km" or "2.0 mi".
     */
    fun formatDistance(metres: Double, useMetric: Boolean = true): String {
        return if (useMetric) {
            "%.1f km".format(metres / HikeStatisticsConfig.METRES_PER_KILOMETRE)
        } else {
            "%.1f mi".format(metres / HikeStatisticsConfig.METRES_PER_MILE)
        }
    }

    /**
     * Formats an elevation value for display.
     *
     * @param metres Elevation in metres.
     * @param useMetric True for metres, false for feet.
     * @return Formatted string like "450 m" or "1476 ft".
     */
    fun formatElevation(metres: Double, useMetric: Boolean = true): String {
        return if (useMetric) {
            "%.0f m".format(metres)
        } else {
            "%.0f ft".format(metres * HikeStatisticsConfig.FEET_PER_METRE)
        }
    }

    /**
     * Formats a duration as HH:MM:SS.
     *
     * @param seconds Duration in seconds.
     * @return Formatted string like "02:34:15".
     */
    fun formatDuration(seconds: Double): String {
        val totalSeconds = seconds.toLong()
        val hours = totalSeconds / 3600
        val minutes = (totalSeconds % 3600) / 60
        val secs = totalSeconds % 60
        return "%02d:%02d:%02d".format(hours, minutes, secs)
    }

    /**
     * Formats a speed value for display.
     *
     * @param metersPerSecond Speed in m/s.
     * @param useMetric True for km/h, false for mph.
     * @return Formatted string like "4.5 km/h" or "2.8 mph".
     */
    fun formatSpeed(metersPerSecond: Double, useMetric: Boolean = true): String {
        return if (useMetric) {
            "%.1f km/h".format(metersPerSecond * HikeStatisticsConfig.KMH_PER_MPS)
        } else {
            "%.1f mph".format(metersPerSecond * HikeStatisticsConfig.MPH_PER_MPS)
        }
    }

    /**
     * Formats a heart rate value.
     *
     * @param bpm Heart rate in beats per minute.
     * @return Formatted string like "142 bpm".
     */
    fun formatHeartRate(bpm: Double): String = "%.0f bpm".format(bpm)

    /**
     * Formats a blood oxygen saturation value.
     *
     * @param fraction SpO2 as a fraction (0.0–1.0).
     * @return Formatted string like "97%".
     */
    fun formatSpO2(fraction: Double): String = "%.0f%%".format(fraction * 100.0)

    /**
     * Formats a calorie count.
     *
     * @param kcal Kilocalories burned.
     * @return Formatted string like "523 kcal".
     */
    fun formatCalories(kcal: Double): String = "%.0f kcal".format(kcal)
}

/**
 * Pure function for estimating calories burned during a hike.
 *
 * Uses the MET (Metabolic Equivalent of Task) method with grade adjustment.
 * Formula: MET * bodyMass * durationHours, where MET increases with steeper grades.
 */
object CalorieEstimator {

    /**
     * Estimates calories burned during a hike.
     *
     * @param distanceMetres Total distance walked in metres.
     * @param elevationGainMetres Total elevation gained in metres.
     * @param durationSeconds Total duration in seconds.
     * @param bodyMassKg Body mass in kilograms (defaults to 70 kg WHO reference).
     * @return Estimated kilocalories burned.
     */
    fun estimate(
        distanceMetres: Double,
        elevationGainMetres: Double,
        durationSeconds: Double,
        bodyMassKg: Double = HikeStatisticsConfig.DEFAULT_BODY_MASS_KG
    ): Double {
        if (durationSeconds <= 0.0 || distanceMetres <= 0.0) return 0.0

        val gradePercent = if (distanceMetres > 0) {
            (elevationGainMetres / distanceMetres) * 100.0
        } else {
            0.0
        }

        val met = HikeStatisticsConfig.BASE_HIKING_MET +
            (gradePercent / 10.0) * HikeStatisticsConfig.MET_PER_TEN_PERCENT_GRADE
        val durationHours = durationSeconds / 3600.0

        return met * bodyMassKg * durationHours
    }
}
