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

// MARK: - Minimalist Navigation View

/// A battery-saving navigation view that displays turn-by-turn guidance without map rendering.
///
/// Replaces the SpriteKit-based ``MapView`` during active navigation to dramatically reduce
/// power consumption. Instead of rendering tiles at 60 FPS, this view uses static SwiftUI
/// that only redraws when ``RouteGuidance`` publishes state changes (every few seconds
/// on GPS updates). Estimated battery improvement: 50-75% longer runtime.
///
/// ## Displayed Information
/// - Large turn direction icon (SF Symbol from ``TurnDirection/sfSymbolName``)
/// - Instruction text (e.g., "Turn left onto Blue Ridge Trail")
/// - Distance countdown to next turn
/// - Heart rate and SpO2 (when a HealthKit workout is active)
/// - Route progress bar and remaining distance
/// - "Show Map" button to switch to the full map tab
///
/// ## Layout
/// ```
/// ┌──────────────────────────────┐
/// │         ↰ (large icon)       │
/// │       Turn left              │
/// │   onto Blue Ridge Trail      │
/// │         120m                 │
/// ├──────────────────────────────┤
/// │   ♥ 132 bpm     SpO2 97%    │
/// ├──────────────────────────────┤
/// │   ━━━━━━━━━━━━━━━━░░░░  64% │
/// │     2.4 km remaining         │
/// │       [Show Map]             │
/// └──────────────────────────────┘
/// ```
///
/// When no route is active, displays a placeholder prompting the user to select a route.
struct MinimalistNavigationView: View {
    @EnvironmentObject var routeGuidance: RouteGuidance
    @EnvironmentObject var healthKitManager: HealthKitManager

    /// Whether to use metric units (km, m) or imperial (mi, ft).
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    /// Binding to the parent TabView's selected tab, allowing navigation to the map.
    @Binding var selectedTab: Int

    var body: some View {
        if routeGuidance.isNavigating {
            activeNavigationView
        } else {
            noRouteView
        }
    }

    // MARK: - Active Navigation

    /// The main navigation display shown during active route guidance.
    private var activeNavigationView: some View {
        VStack(spacing: 0) {
            if routeGuidance.isOffRoute {
                offRouteView
            } else {
                turnGuidanceView
            }

            if healthKitManager.workoutActive {
                vitalsBar
            }

            progressSection
        }
        .background(Color.black)
    }

    // MARK: - Turn Guidance

    /// The primary turn direction display: large icon, instruction text, and distance countdown.
    private var turnGuidanceView: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 4)

            // Turn direction icon
            if let instruction = routeGuidance.currentInstruction {
                Image(systemName: instruction.direction.sfSymbolName)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.purple)

                // Instruction text
                Text(instruction.description)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
            }

            // Distance to next turn (large countdown)
            if let distance = routeGuidance.distanceToNextTurn {
                Text(formatDistance(distance))
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }

            Spacer(minLength: 4)
        }
    }

    // MARK: - Off-Route Warning

    /// Full-screen red warning displayed when the user strays from the route.
    private var offRouteView: some View {
        VStack(spacing: 8) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)

            Text("OFF ROUTE")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text("Return to trail")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.85))
    }

    // MARK: - Health Vitals

    /// A compact bar showing heart rate and SpO2 from the active HealthKit workout.
    ///
    /// Heart rate icon color indicates zone:
    /// - Green: < 120 bpm (easy)
    /// - Yellow: 120-150 bpm (moderate)
    /// - Red: > 150 bpm (hard)
    ///
    /// These values are already being collected by ``HealthKitManager`` during the
    /// workout session — displaying them here costs zero additional sensor power.
    private var vitalsBar: some View {
        HStack(spacing: 12) {
            // Heart rate
            if let hr = healthKitManager.currentHeartRate {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(heartRateColor(hr))
                        .font(.caption2)
                    Text("\(Int(hr))")
                        .font(.caption2)
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
                        .font(.caption2)
                    Text("\(Int(spO2 * 100))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Progress Section

    /// The bottom section showing route progress, remaining distance, and a map button.
    private var progressSection: some View {
        VStack(spacing: 4) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(height: 4)
                    Capsule()
                        .fill(.purple)
                        .frame(width: max(4, geometry.size.width * routeGuidance.progress), height: 4)
                }
            }
            .frame(height: 4)

            // Remaining distance + percentage
            HStack {
                Text(formatDistance(routeGuidance.remainingDistance))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("remaining")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(Int(routeGuidance.progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Show Map button
            Button {
                selectedTab = 1
            } label: {
                Label("Show Map", systemImage: "map")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .tint(.purple)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
    }

    // MARK: - No Active Route

    /// Placeholder displayed when no route navigation is active.
    private var noRouteView: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.turn.up.right.diamond")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Active Route")
                .font(.headline)
            Text("Select a route from the Routes tab to start navigation")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Helpers

    /// Metres-per-kilometre constant for distance formatting.
    private static let metresPerKilometre: Double = 1000.0

    /// Metres-per-mile constant for imperial distance formatting.
    private static let metresPerMile: Double = 1609.344

    /// Feet-per-metre constant for imperial distance formatting.
    private static let feetPerMetre: Double = 3.28084

    /// Formats a distance for display, respecting the user's unit preference.
    ///
    /// - Metric: "120m" or "2.4km"
    /// - Imperial: "394ft" or "1.5mi"
    ///
    /// - Parameter metres: Distance in metres.
    /// - Returns: A compact formatted string with unit suffix.
    private func formatDistance(_ metres: Double) -> String {
        if useMetricUnits {
            if metres < Self.metresPerKilometre {
                return "\(Int(metres))m"
            } else {
                return String(format: "%.1fkm", metres / Self.metresPerKilometre)
            }
        } else {
            let feet = metres * Self.feetPerMetre
            if metres < Self.metresPerMile {
                return "\(Int(feet))ft"
            } else {
                return String(format: "%.1fmi", metres / Self.metresPerMile)
            }
        }
    }

    /// Returns a color for the heart rate value based on exercise intensity zone.
    ///
    /// - Parameter bpm: Heart rate in beats per minute.
    /// - Returns: Green (< 120), yellow (120-150), or red (> 150).
    private func heartRateColor(_ bpm: Double) -> Color {
        if bpm < 120 {
            return .green
        } else if bpm < 150 {
            return .yellow
        } else {
            return .red
        }
    }
}
