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

// MARK: - Navigation Overlay

/// A heads-up navigation overlay displayed on the watch map during active guidance.
///
/// Shows the upcoming turn direction (as an SF Symbol arrow), distance to the next turn,
/// the instruction text (e.g., "Turn left onto Blue Ridge Trail"), and remaining distance.
/// Turns red and pulses when the user goes off-route.
///
/// Positioned at the top of the ``MapView`` using a ZStack overlay. The overlay auto-hides
/// when navigation is not active (``RouteGuidance/isNavigating`` is false).
///
/// ## Layout
/// ```
/// ┌──────────────────────────────┐
/// │  ↰  In 120m, turn left      │  ← Instruction bar
/// │     onto Blue Ridge Trail    │
/// ├──────────────────────────────┤
/// │         [Map View]           │
/// ├──────────────────────────────┤
/// │  2.4 km remaining            │  ← Progress bar
/// └──────────────────────────────┘
/// ```
struct NavigationOverlay: View {
    @ObservedObject var guidance: RouteGuidance

    var body: some View {
        if guidance.isNavigating {
            VStack(spacing: 0) {
                // Top instruction bar
                instructionBar
                    .background(instructionBarBackground)

                Spacer()

                // Bottom progress bar
                progressBar
                    .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Instruction Bar

    /// The top bar showing the upcoming turn direction and instruction text.
    private var instructionBar: some View {
        HStack(spacing: 8) {
            // Turn direction icon (SF Symbols already indicate direction)
            if let instruction = guidance.currentInstruction {
                Image(systemName: instruction.direction.sfSymbolName)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(guidance.isOffRoute ? .red : .white)
            }

            // Instruction text
            VStack(alignment: .leading, spacing: 2) {
                if guidance.isOffRoute {
                    offRouteText
                } else {
                    instructionText
                }
            }
            .lineLimit(2)
            .minimumScaleFactor(0.7)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    /// Text displayed when navigation is on-route.
    private var instructionText: some View {
        Group {
            if let distance = guidance.distanceToNextTurn {
                Text("In \(formatShortDistance(distance))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            if let instruction = guidance.currentInstruction {
                Text(instruction.description)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            }
        }
    }

    /// Text displayed when the user is off-route.
    private var offRouteText: some View {
        Group {
            Text("OFF ROUTE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.red)

            Text("Return to trail")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    /// Background color for the instruction bar: purple (normal) or red (off-route).
    private var instructionBarBackground: some View {
        Group {
            if guidance.isOffRoute {
                Color.red.opacity(0.85)
            } else {
                Color.purple.opacity(0.85)
            }
        }
    }

    // MARK: - Progress Bar

    /// The bottom bar showing remaining distance and progress.
    private var progressBar: some View {
        VStack(spacing: 2) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(height: 4)

                    // Progress fill
                    Capsule()
                        .fill(.purple)
                        .frame(width: max(4, geometry.size.width * guidance.progress), height: 4)
                }
            }
            .frame(height: 4)

            // Remaining distance text
            HStack {
                Text(formatShortDistance(guidance.remainingDistance))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("remaining")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(Int(guidance.progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    /// Metres-per-kilometre constant for compact distance formatting.
    private static let metresPerKilometre: Double = 1000.0

    /// Formats a distance for compact display on the watch.
    ///
    /// Under 1 km: shows metres (e.g., "120m").
    /// Over 1 km: shows kilometres with one decimal (e.g., "2.4km").
    ///
    /// - Parameter metres: Distance in metres.
    /// - Returns: A compact formatted string.
    private func formatShortDistance(_ metres: Double) -> String {
        if metres < Self.metresPerKilometre {
            return "\(Int(metres))m"
        } else {
            return String(format: "%.1fkm", metres / Self.metresPerKilometre)
        }
    }
}
