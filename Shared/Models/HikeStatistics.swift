// Copyright (C) 2024-2026 Dr Horst Herb
//
// This file is part of OpenHiker.
//
// OpenHiker is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// OpenHiker is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with OpenHiker. If not, see <https://www.gnu.org/licenses/>.

import Foundation

/// A value type aggregating all statistics for a single hike.
///
/// This is a shared infrastructure type used by multiple subsystems:
/// - **Stats overlay** on the watch map (``HikeStatsOverlay``)
/// - **HealthKit** workout recording (``HealthKitManager``)
/// - **Saved routes** (Phase 3) for persistent hike records
/// - **Export** (Phase 6) for PDF/Markdown hike reports
///
/// All distance values are in meters, all time values are in seconds,
/// and all speed values are in meters per second. The UI layer is
/// responsible for locale-aware formatting (metric vs. imperial).
struct HikeStatistics: Codable, Sendable, Equatable {

    // MARK: - Distance & Elevation

    /// Total distance covered in meters, measured along the GPS track.
    let totalDistance: Double

    /// Total cumulative elevation gained in meters (only uphill segments).
    let elevationGain: Double

    /// Total cumulative elevation lost in meters (only downhill segments).
    let elevationLoss: Double

    // MARK: - Time

    /// Total elapsed time from hike start to finish, in seconds.
    let duration: TimeInterval

    /// Time spent actively moving (speed >= ``HikeStatisticsConfig/restingSpeedThreshold``), in seconds.
    let walkingTime: TimeInterval

    /// Time spent stationary or nearly stationary, in seconds.
    let restingTime: TimeInterval

    // MARK: - Heart Rate & SpO2 (optional, requires HealthKit)

    /// Average heart rate during the hike in beats per minute, or `nil` if HealthKit data is unavailable.
    let averageHeartRate: Double?

    /// Maximum heart rate recorded during the hike in beats per minute, or `nil` if unavailable.
    let maxHeartRate: Double?

    /// Average blood oxygen saturation percentage during the hike, or `nil` if unavailable.
    let averageSpO2: Double?

    // MARK: - Energy

    /// Estimated energy burned in kilocalories.
    ///
    /// Always has a value because ``CalorieEstimator`` falls back to
    /// ``HikeStatisticsConfig/defaultBodyMassKg`` when HealthKit body mass is unavailable.
    let estimatedCalories: Double?

    // MARK: - Speed

    /// Average speed in meters per second over the entire hike duration.
    let averageSpeed: Double

    /// Maximum instantaneous speed recorded in meters per second.
    let maxSpeed: Double
}

// MARK: - Configuration

/// Configuration constants for hike statistics calculations.
///
/// These constants control how statistics are computed from raw GPS and
/// HealthKit data. They are defined as static constants rather than
/// magic numbers to make the code self-documenting and easy to adjust.
enum HikeStatisticsConfig {

    /// Speed threshold in m/s below which the hiker is considered resting.
    ///
    /// 0.3 m/s is roughly 1 km/h — below normal walking pace, accounting
    /// for GPS drift when standing still.
    static let restingSpeedThreshold: Double = 0.3

    /// Base MET (Metabolic Equivalent of Task) value for moderate hiking.
    ///
    /// Source: Compendium of Physical Activities — "hiking, cross country" = 6.0 MET.
    static let baseHikingMET: Double = 6.0

    /// Additional MET per 10% average grade to account for steeper terrain.
    ///
    /// For every 10% of average grade (elevation gain / horizontal distance),
    /// add 1.0 MET to the base value.
    static let metPerTenPercentGrade: Double = 1.0

    /// Default body mass in kilograms, used when HealthKit body mass is unavailable.
    ///
    /// 70 kg is the WHO reference adult weight.
    static let defaultBodyMassKg: Double = 70.0

    /// Maximum age in seconds for a SpO2 reading to be considered "recent".
    ///
    /// Blood oxygen samples older than this threshold are hidden from the
    /// live stats overlay since they may no longer reflect current status.
    static let spO2MaxAgeSec: TimeInterval = 300.0

    // MARK: - Unit Conversion Constants

    /// Meters per mile (international mile).
    static let metersPerMile: Double = 1609.344

    /// Feet per meter (international foot).
    static let feetPerMeter: Double = 3.28084

    /// Conversion factor from m/s to km/h.
    static let kmhPerMps: Double = 3.6

    /// Conversion factor from m/s to mph.
    static let mphPerMps: Double = 2.23694
}

// MARK: - Formatting Helpers

/// Provides locale-aware formatting for hike statistics values.
///
/// All formatting respects the user's metric/imperial preference stored in
/// `@AppStorage("useMetricUnits")`. The formatters are designed for compact
/// display on Apple Watch screens.
enum HikeStatsFormatter {

    /// Formats a distance in meters as a human-readable string.
    ///
    /// - Parameters:
    ///   - meters: The distance in meters.
    ///   - useMetric: If `true`, formats as km; if `false`, formats as mi.
    /// - Returns: A formatted string like "3.2 km" or "2.0 mi".
    static func formatDistance(_ meters: Double, useMetric: Bool) -> String {
        if useMetric {
            let km = meters / 1000.0
            return String(format: "%.1f km", km)
        } else {
            let miles = meters / HikeStatisticsConfig.metersPerMile
            return String(format: "%.1f mi", miles)
        }
    }

    /// Formats an elevation value in meters as a human-readable string.
    ///
    /// - Parameters:
    ///   - meters: The elevation in meters.
    ///   - useMetric: If `true`, formats as m; if `false`, formats as ft.
    /// - Returns: A formatted string like "450 m" or "1476 ft".
    static func formatElevation(_ meters: Double, useMetric: Bool) -> String {
        if useMetric {
            return String(format: "%.0f m", meters)
        } else {
            let feet = meters * HikeStatisticsConfig.feetPerMeter
            return String(format: "%.0f ft", feet)
        }
    }

    /// Formats a time interval as HH:MM:SS.
    ///
    /// - Parameter interval: The time interval in seconds.
    /// - Returns: A formatted string like "02:15:30" or "00:45:12".
    static func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// Formats a speed in m/s as a human-readable string.
    ///
    /// - Parameters:
    ///   - metersPerSecond: The speed in meters per second.
    ///   - useMetric: If `true`, formats as km/h; if `false`, formats as mph.
    /// - Returns: A formatted string like "4.5 km/h" or "2.8 mph".
    static func formatSpeed(_ metersPerSecond: Double, useMetric: Bool) -> String {
        if useMetric {
            let kmh = metersPerSecond * HikeStatisticsConfig.kmhPerMps
            return String(format: "%.1f km/h", kmh)
        } else {
            let mph = metersPerSecond * HikeStatisticsConfig.mphPerMps
            return String(format: "%.1f mph", mph)
        }
    }

    /// Formats a heart rate value as a BPM string.
    ///
    /// - Parameter bpm: Heart rate in beats per minute.
    /// - Returns: A formatted string like "142 bpm".
    static func formatHeartRate(_ bpm: Double) -> String {
        return String(format: "%.0f bpm", bpm)
    }

    /// Formats a blood oxygen saturation value as a percentage string.
    ///
    /// - Parameter fraction: SpO2 as a fraction (0.0 to 1.0).
    /// - Returns: A formatted string like "97%".
    static func formatSpO2(_ fraction: Double) -> String {
        return String(format: "%.0f%%", fraction * 100)
    }

    /// Formats a calorie count as a human-readable string.
    ///
    /// - Parameter kcal: Energy in kilocalories.
    /// - Returns: A formatted string like "523 kcal".
    static func formatCalories(_ kcal: Double) -> String {
        return String(format: "%.0f kcal", kcal)
    }
}

// MARK: - Calorie Estimation

/// Pure-function calorie estimator using MET-based calculation.
///
/// This uses the standard MET formula from exercise physiology:
/// `calories = MET * bodyMassKg * durationHours`
///
/// The base MET for hiking (6.0) is adjusted upward for steeper terrain
/// using the average grade derived from elevation gain and horizontal distance.
enum CalorieEstimator {

    /// Estimates calories burned during a hike.
    ///
    /// - Parameters:
    ///   - distanceMeters: Total horizontal distance in meters.
    ///   - elevationGainMeters: Total cumulative elevation gain in meters.
    ///   - durationSeconds: Total hike duration in seconds.
    ///   - bodyMassKg: Hiker's body mass in kilograms. Uses ``HikeStatisticsConfig/defaultBodyMassKg``
    ///     (70 kg) if `nil`.
    /// - Returns: Estimated energy burned in kilocalories.
    static func estimateCalories(
        distanceMeters: Double,
        elevationGainMeters: Double,
        durationSeconds: TimeInterval,
        bodyMassKg: Double?
    ) -> Double {
        let mass = bodyMassKg ?? HikeStatisticsConfig.defaultBodyMassKg
        let durationHours = durationSeconds / 3600.0

        // Calculate average grade as a percentage
        var met = HikeStatisticsConfig.baseHikingMET
        if distanceMeters > 0 {
            let gradePercent = (elevationGainMeters / distanceMeters) * 100.0
            let gradeTens = gradePercent / 10.0
            met += gradeTens * HikeStatisticsConfig.metPerTenPercentGrade
        }

        return met * mass * durationHours
    }
}
