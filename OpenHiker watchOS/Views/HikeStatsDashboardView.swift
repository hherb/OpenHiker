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

/// A dedicated full-screen dashboard displaying live hike health and distance statistics.
///
/// This view is placed as the first tab (index 0) in the vertical page ``TabView``,
/// directly above the map tab. The user swipes down from the map to access it.
///
/// ## Displayed Metrics
/// - **Heart Rate**: Current BPM from HealthKit (red heart icon)
/// - **SpO2**: Blood oxygen saturation percentage (cyan lungs icon)
/// - **Distance**: Total distance walked in km or mi
/// - **Elevation**: Cumulative gain in m or ft
/// - **Duration**: Elapsed tracking time as HH:MM:SS
/// - **Speed**: Current average speed in km/h or mph
/// - **UV Index**: Current UV exposure level with WHO color coding
///
/// ## States
/// - **Tracking Active**: Shows all live metrics with auto-updating values
/// - **Not Tracking**: Shows a prompt to start tracking with current UV/health readings
struct HikeStatsDashboardView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var uvIndexManager: UVIndexManager

    /// User preference for metric (true) or imperial (false) units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Title
                Text("Hike Stats")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                if locationManager.isTracking {
                    trackingStatsContent
                } else {
                    notTrackingContent
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Tracking Active Content

    /// The full stats layout shown during an active hike.
    private var trackingStatsContent: some View {
        VStack(spacing: 6) {
            // Health vitals section
            if healthKitManager.isAuthorized {
                healthVitalsSection
            }

            // Distance and elevation
            statRow(
                icon: "figure.walk",
                iconColor: .green,
                label: "Distance",
                value: HikeStatsFormatter.formatDistance(
                    locationManager.totalDistance,
                    useMetric: useMetricUnits
                )
            )

            statRow(
                icon: "arrow.up.right",
                iconColor: .orange,
                label: "Elevation",
                value: HikeStatsFormatter.formatElevation(
                    locationManager.elevationGain,
                    useMetric: useMetricUnits
                )
            )

            // Time and speed
            statRow(
                icon: "clock",
                iconColor: .blue,
                label: "Duration",
                value: HikeStatsFormatter.formatDuration(
                    locationManager.duration ?? 0
                )
            )

            if let duration = locationManager.duration, duration > 0 {
                let speed = locationManager.totalDistance / duration
                statRow(
                    icon: "speedometer",
                    iconColor: .mint,
                    label: "Avg Speed",
                    value: HikeStatsFormatter.formatSpeed(speed, useMetric: useMetricUnits)
                )
            }

            // UV Index
            uvIndexSection
        }
    }

    /// Heart rate and SpO2 rows, shown only when HealthKit is authorized.
    private var healthVitalsSection: some View {
        VStack(spacing: 6) {
            if let hr = healthKitManager.currentHeartRate {
                statRow(
                    icon: "heart.fill",
                    iconColor: .red,
                    label: "Heart Rate",
                    value: HikeStatsFormatter.formatHeartRate(hr)
                )
            }

            if let spO2 = healthKitManager.currentSpO2 {
                statRow(
                    icon: "lungs.fill",
                    iconColor: .cyan,
                    label: "SpO2",
                    value: HikeStatsFormatter.formatSpO2(spO2)
                )
            }

            if healthKitManager.currentHeartRate == nil
                && healthKitManager.currentSpO2 == nil {
                HStack(spacing: 6) {
                    Image(systemName: "heart.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Waiting for health data...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Not Tracking Content

    /// The content shown when no hike is actively being tracked.
    private var notTrackingContent: some View {
        VStack(spacing: 12) {
            // HealthKit authorization prompt
            if !healthKitManager.isAuthorized {
                healthKitAuthPrompt
            } else {
                // Show available health data even when not tracking
                healthVitalsSection
            }

            // UV Index (available regardless of tracking state)
            uvIndexSection

            // Prompt to start tracking
            VStack(spacing: 8) {
                Image(systemName: "figure.hiking")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text("Start a hike to see distance, elevation, and speed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)
        }
    }

    /// A prompt shown when HealthKit is not yet authorized.
    private var healthKitAuthPrompt: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "heart.text.square")
                    .font(.body)
                    .foregroundStyle(.red)
                Text("HealthKit Not Authorized")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Authorize in Settings for heart rate and SpO2")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - UV Index Section

    /// UV index display with category color and protection advice.
    private var uvIndexSection: some View {
        Group {
            if uvIndexManager.isReadingCurrent,
               let uvIndex = uvIndexManager.currentUVIndex,
               let category = uvIndexManager.currentCategory {
                VStack(spacing: 4) {
                    statRow(
                        icon: "sun.max.fill",
                        iconColor: category.displayColor,
                        label: "UV Index",
                        value: "\(uvIndex) - \(category.rawValue)"
                    )

                    Text(category.protectionAdvice)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 28)
                }
            }
        }
    }

    // MARK: - Subviews

    /// A single stat row with an icon, label, and formatted value.
    ///
    /// - Parameters:
    ///   - icon: The SF Symbol name for the row icon.
    ///   - iconColor: The color for the icon.
    ///   - label: A short description of the metric (e.g. "Heart Rate").
    ///   - value: The formatted metric value (e.g. "142 bpm").
    /// - Returns: A styled row view.
    private func statRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    HikeStatsDashboardView()
        .environmentObject(LocationManager())
        .environmentObject(HealthKitManager())
        .environmentObject(UVIndexManager())
}
