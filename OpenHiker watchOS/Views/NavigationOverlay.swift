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
/// │ ↰ 120m Turn left onto trail  │  ← Thin instruction strip
/// ├──────────────────────────────┤
/// │                              │
/// │         [Map View]           │
/// │                              │
/// ├──────────────────────────────┤
/// │ ━━━━━━━━━  2.4km rem.  62%  │  ← Thin progress bar
/// └──────────────────────────────┘
/// ```
struct NavigationOverlay: View {
    @ObservedObject var guidance: RouteGuidance

    var body: some View {
        if guidance.isNavigating {
            VStack(spacing: 0) {
                // Compact instruction strip pinned to top
                instructionBar
                    .background(instructionBarBackground)

                Spacer()

                // Thin progress bar pinned to bottom (above toolbar)
                progressBar
                    .background(.ultraThinMaterial)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Instruction Bar

    /// Compact top strip showing turn direction and instruction in a single line.
    private var instructionBar: some View {
        HStack(spacing: 4) {
            // Turn direction icon
            if let instruction = guidance.currentInstruction {
                Image(systemName: instruction.direction.sfSymbolName)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(guidance.isOffRoute ? .white : .white)
            }

            // Instruction text — single line, compact
            if guidance.isOffRoute {
                offRouteText
            } else {
                instructionText
            }

            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    /// Single-line text displayed when navigation is on-route.
    private var instructionText: some View {
        HStack(spacing: 4) {
            if let distance = guidance.distanceToNextTurn {
                Text(formatShortDistance(distance))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            if let instruction = guidance.currentInstruction {
                Text(instruction.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
            }
        }
    }

    /// Single-line compact text displayed when the user is off-route.
    private var offRouteText: some View {
        HStack(spacing: 4) {
            Text("OFF ROUTE")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
            Text("Return to trail")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    /// Background color for the instruction bar: red (off-route) or purple (normal), semi-transparent.
    private var instructionBarBackground: some View {
        Group {
            if guidance.isOffRoute {
                Color.red.opacity(0.7)
            } else {
                Color.purple.opacity(0.7)
            }
        }
    }

    // MARK: - Progress Bar

    /// Thin bottom bar showing remaining distance and progress.
    private var progressBar: some View {
        VStack(spacing: 1) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(height: 3)
                    Capsule()
                        .fill(.purple)
                        .frame(width: max(3, geometry.size.width * guidance.progress), height: 3)
                }
            }
            .frame(height: 3)

            // Remaining distance — single compact line
            HStack {
                Text("\(formatShortDistance(guidance.remainingDistance)) remaining")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(guidance.progress * 100))%")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
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
