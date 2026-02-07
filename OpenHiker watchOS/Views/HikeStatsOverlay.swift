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

/// A translucent overlay displaying live hike statistics on the watch map.
///
/// This view shows real-time metrics during an active hike:
/// - **Distance** walked (km or mi, locale-aware)
/// - **Elevation gain** (m or ft)
/// - **Elapsed time** (HH:MM:SS)
/// - **Heart rate** (BPM, when HealthKit is authorized and data available)
/// - **SpO2** (%, when a recent reading exists)
///
/// The overlay uses compact capsule badges with `.ultraThinMaterial` backgrounds
/// to avoid obscuring the map. It auto-hides after ``autoHideDelaySec`` seconds
/// of inactivity and reappears on tap or new location updates.
///
/// ## Visibility Rules
/// - Only visible when `locationManager.isTracking == true`
/// - Heart rate row only appears when `healthKitManager.isAuthorized` and data exists
/// - SpO2 only appears when a reading less than 5 minutes old exists
struct HikeStatsOverlay: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var uvIndexManager: UVIndexManager

    /// User preference for metric (true) or imperial (false) units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    /// Whether the overlay is currently visible (controlled by auto-hide timer).
    @State private var isVisible = true

    /// Timer that fires to hide the overlay after a period of inactivity.
    @State private var hideTimer: Timer?

    /// Number of seconds before the overlay auto-hides after the last interaction.
    private static let autoHideDelaySec: TimeInterval = 5.0

    var body: some View {
        if locationManager.isTracking && isVisible {
            VStack(alignment: .leading, spacing: 4) {
                // Row 1: Distance and time
                HStack(spacing: 6) {
                    statBadge(
                        icon: "figure.walk",
                        value: HikeStatsFormatter.formatDistance(
                            locationManager.totalDistance,
                            useMetric: useMetricUnits
                        )
                    )

                    statBadge(
                        icon: "clock",
                        value: HikeStatsFormatter.formatDuration(
                            locationManager.duration ?? 0
                        )
                    )
                }

                // Row 2: Elevation gain
                HStack(spacing: 6) {
                    statBadge(
                        icon: "arrow.up.right",
                        value: HikeStatsFormatter.formatElevation(
                            locationManager.elevationGain,
                            useMetric: useMetricUnits
                        )
                    )

                    // Heart rate (only when authorized and data available)
                    if healthKitManager.isAuthorized,
                       let hr = healthKitManager.currentHeartRate {
                        statBadge(
                            icon: "heart.fill",
                            value: HikeStatsFormatter.formatHeartRate(hr),
                            iconColor: .red
                        )
                    }
                }

                // Row 3: SpO2 and UV index
                HStack(spacing: 6) {
                    if healthKitManager.isAuthorized,
                       let spO2 = healthKitManager.currentSpO2 {
                        statBadge(
                            icon: "lungs.fill",
                            value: HikeStatsFormatter.formatSpO2(spO2),
                            iconColor: .cyan
                        )
                    }

                    // UV index (when available)
                    if let uvIndex = uvIndexManager.currentUVIndex,
                       let category = uvIndexManager.currentCategory {
                        statBadge(
                            icon: "sun.max.fill",
                            value: "UV \(uvIndex)",
                            iconColor: uvColorForCategory(category)
                        )
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 24)
            .onTapGesture {
                resetAutoHideTimer()
            }
            .onChange(of: locationManager.currentLocation) { _, _ in
                showAndResetTimer()
            }
            .onAppear {
                resetAutoHideTimer()
            }
            .onDisappear {
                hideTimer?.invalidate()
                hideTimer = nil
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: isVisible)
        } else if locationManager.isTracking && !isVisible {
            // Invisible tap target to bring the overlay back
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    showAndResetTimer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Subviews

    /// Creates a compact capsule badge displaying an SF Symbol icon and a text value.
    ///
    /// - Parameters:
    ///   - icon: The SF Symbol name for the icon.
    ///   - value: The formatted text value to display.
    ///   - iconColor: The color for the icon (defaults to white).
    /// - Returns: A styled capsule view with the icon and value.
    private func statBadge(icon: String, value: String, iconColor: Color = .white) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(iconColor)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// Returns the SwiftUI color for a UV category following the WHO color scheme.
    ///
    /// - Parameter category: The UV exposure category.
    /// - Returns: The corresponding SwiftUI ``Color``.
    private func uvColorForCategory(_ category: UVCategory) -> Color {
        switch category {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .veryHigh: return .red
        case .extreme: return .purple
        }
    }

    // MARK: - Auto-Hide Timer

    /// Makes the overlay visible and resets the auto-hide countdown.
    private func showAndResetTimer() {
        isVisible = true
        resetAutoHideTimer()
    }

    /// Resets the auto-hide timer. After ``autoHideDelaySec`` seconds the overlay fades out.
    private func resetAutoHideTimer() {
        hideTimer?.invalidate()
        isVisible = true
        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.autoHideDelaySec, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation {
                    isVisible = false
                }
            }
        }
    }
}
