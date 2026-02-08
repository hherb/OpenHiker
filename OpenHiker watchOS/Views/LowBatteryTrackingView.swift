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

/// A minimal battery-saving view displayed when the watch battery drops to 5% during tracking.
///
/// This view replaces the full TabView (including the SpriteKit-based map) to dramatically
/// reduce power consumption while still recording the track. By eliminating all GPU-intensive
/// rendering and reducing UI updates to only essential metrics, battery life is extended as
/// long as possible so the hiker can complete their route.
///
/// ## Displayed Metrics
/// - **Distance**: Total km or mi walked/cycled so far
/// - **Heart Rate**: Current BPM from HealthKit (if available)
/// - **SpO2**: Blood oxygen saturation percentage (if available)
/// - **Battery Level**: Current percentage remaining
/// - **Elapsed Time**: Duration since tracking started
///
/// ## Layout
/// ```
/// ┌──────────────────────────┐
/// │   ⚠ LOW BATTERY (4%)    │
/// │                          │
/// │      12.4 km             │
/// │   walked so far          │
/// │                          │
/// │   ♥ 128 bpm   SpO2 96%  │
/// │                          │
/// │      02:45:30            │
/// │                          │
/// │     [Stop Hike]          │
/// └──────────────────────────┘
/// ```
///
/// ## Power Savings
/// - No SpriteKit scene rendering (eliminates GPU usage)
/// - No tile loading or map computation
/// - Static SwiftUI that only redraws on published state changes
/// - GPS continues in low-power mode for track recording
struct LowBatteryTrackingView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var batteryMonitor: BatteryMonitor

    /// User preference for metric (true) or imperial (false) units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    /// Whether the stop confirmation alert is displayed.
    @State private var showStopConfirmation = false

    /// Callback invoked when the user stops tracking from this view.
    let onStopTracking: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Low battery warning header
            batteryWarningHeader

            Spacer(minLength: 4)

            // Primary metric: distance
            distanceDisplay

            Spacer(minLength: 4)

            // Health vitals
            if healthKitManager.isAuthorized {
                vitalsSection
            }

            // Elapsed time
            timeDisplay

            Spacer(minLength: 4)

            // Stop button
            Button {
                showStopConfirmation = true
            } label: {
                Label("Stop Hike", systemImage: "stop.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black)
        .alert("Stop Hike?", isPresented: $showStopConfirmation) {
            Button("Stop & Save", role: .destructive) {
                onStopTracking()
            }
            Button("Continue", role: .cancel) {}
        } message: {
            Text("Your track will be saved.")
        }
    }

    // MARK: - Subviews

    /// The low-battery warning banner at the top of the view.
    ///
    /// Shows a yellow warning icon and the current battery percentage.
    private var batteryWarningHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "battery.25")
                .font(.caption)
                .foregroundStyle(.yellow)

            Text("LOW BATTERY")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.yellow)

            if let percentage = batteryMonitor.batteryPercentage {
                Text("(\(percentage)%)")
                    .font(.caption2)
                    .foregroundStyle(.yellow.opacity(0.8))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.yellow.opacity(0.15), in: Capsule())
    }

    /// The primary distance display — large, centered, easy to read at a glance.
    private var distanceDisplay: some View {
        VStack(spacing: 2) {
            Text(HikeStatsFormatter.formatDistance(
                locationManager.totalDistance,
                useMetric: useMetricUnits
            ))
            .font(.system(.title, design: .rounded))
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .monospacedDigit()

            Text("walked so far")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Heart rate and SpO2 display row.
    ///
    /// Only shown when HealthKit is authorized. Uses the same heart rate zone
    /// coloring as ``MinimalistNavigationView``.
    private var vitalsSection: some View {
        HStack(spacing: 16) {
            // Heart rate
            if let hr = healthKitManager.currentHeartRate {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(heartRateColor(hr))
                        .font(.caption)
                    Text(HikeStatsFormatter.formatHeartRate(hr))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }

            // SpO2
            if let spO2 = healthKitManager.currentSpO2 {
                HStack(spacing: 4) {
                    Image(systemName: "lungs.fill")
                        .foregroundStyle(.cyan)
                        .font(.caption)
                    Text(HikeStatsFormatter.formatSpO2(spO2))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
        }
    }

    /// The elapsed time display.
    private var timeDisplay: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(HikeStatsFormatter.formatDuration(
                locationManager.duration ?? 0
            ))
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .monospacedDigit()
        }
    }

    // MARK: - Helpers

    /// Returns a color for the heart rate value based on exercise intensity zone.
    ///
    /// - Parameter bpm: Heart rate in beats per minute.
    /// - Returns: Green (easy), yellow (moderate), or red (hard).
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
