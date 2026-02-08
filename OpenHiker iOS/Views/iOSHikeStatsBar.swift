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

import SwiftUI

/// A translucent bottom bar displaying live hike statistics and watch health data.
///
/// Shows two rows of badges during active tracking:
/// - **Row 1 (Hike Stats)**: Distance, Duration, Elevation gain
/// - **Row 2 (Watch Health)**: Heart rate, SpO2, UV index (only when a paired watch
///   is sending data via ``WatchHealthRelay``)
///
/// The health data row is hidden when no watch is connected or no health data
/// is being received. Each badge displays a compact icon + value using the
/// ``HikeStatsFormatter`` utility.
struct iOSHikeStatsBar: View {
    @ObservedObject var locationManager: iOSLocationManager
    @ObservedObject var healthRelay: WatchHealthRelay
    @ObservedObject var watchConnectivity: WatchConnectivityManager

    /// User preference for metric (true) or imperial (false) units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    var body: some View {
        if locationManager.isTracking {
            VStack(spacing: 6) {
                // Row 1: Hike statistics
                hikeStatsRow

                // Row 2: Watch health data (conditional)
                if healthRelay.isReceivingData {
                    healthDataRow
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Hike Stats Row

    /// Distance, duration, and elevation gain badges.
    private var hikeStatsRow: some View {
        HStack(spacing: 12) {
            statBadge(
                icon: "figure.walk",
                value: HikeStatsFormatter.formatDistance(
                    locationManager.totalDistance,
                    useMetric: useMetricUnits
                ),
                iconColor: .blue
            )

            statBadge(
                icon: "clock",
                value: HikeStatsFormatter.formatDuration(
                    locationManager.duration ?? 0
                ),
                iconColor: .orange
            )

            statBadge(
                icon: "arrow.up.right",
                value: HikeStatsFormatter.formatElevation(
                    locationManager.elevationGain,
                    useMetric: useMetricUnits
                ),
                iconColor: .green
            )
        }
    }

    // MARK: - Watch Health Data Row

    /// Heart rate, SpO2, and UV index badges from the paired Apple Watch.
    private var healthDataRow: some View {
        HStack(spacing: 12) {
            // Heart rate
            if let hr = healthRelay.heartRate {
                statBadge(
                    icon: "heart.fill",
                    value: HikeStatsFormatter.formatHeartRate(hr),
                    iconColor: heartRateColor(hr)
                )
            }

            // SpO2
            if let spo2 = healthRelay.spO2 {
                statBadge(
                    icon: "lungs.fill",
                    value: HikeStatsFormatter.formatSpO2(spo2),
                    iconColor: .cyan
                )
            }

            // UV Index
            if let uv = healthRelay.uvIndex {
                statBadge(
                    icon: "sun.max.fill",
                    value: "UV \(uv)",
                    iconColor: healthRelay.uvCategory?.displayColor ?? .yellow
                )
            }

            // Watch connection indicator
            if watchConnectivity.isPaired {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Badge View

    /// Creates a compact capsule badge displaying an SF Symbol icon and a text value.
    ///
    /// - Parameters:
    ///   - icon: The SF Symbol name for the icon.
    ///   - value: The formatted text value to display.
    ///   - iconColor: The color for the icon.
    /// - Returns: A styled capsule view with the icon and value.
    private func statBadge(icon: String, value: String, iconColor: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Heart Rate Color

    /// Returns a color based on heart rate zone thresholds.
    ///
    /// - Green: < 120 bpm (easy)
    /// - Yellow: 120-150 bpm (moderate)
    /// - Red: > 150 bpm (hard)
    ///
    /// - Parameter bpm: Heart rate in beats per minute.
    /// - Returns: The appropriate zone color.
    private func heartRateColor(_ bpm: Double) -> Color {
        if bpm < HikeStatisticsConfig.easyHeartRateMax {
            return .green
        } else if bpm < HikeStatisticsConfig.moderateHeartRateMax {
            return .yellow
        } else {
            return .red
        }
    }
}
