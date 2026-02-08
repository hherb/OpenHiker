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

/// A heads-up navigation overlay displayed on the iPhone map during active guidance.
///
/// Shows the upcoming turn direction (as an SF Symbol arrow), distance to the next turn,
/// the instruction text (e.g., "Turn left onto Blue Ridge Trail"), and remaining distance
/// with progress. Turns red and shows a warning when the user goes off-route.
///
/// ## Layout
/// ```
/// ┌────────────────────────────────────────┐
/// │  ↰  In 120m                            │
/// │     Turn left onto Blue Ridge Trail    │
/// ├────────────────────────────────────────┤
/// │  ████████████░░░░  2.4 km remaining    │
/// └────────────────────────────────────────┘
/// ```
struct iOSNavigationOverlay: View {
    @ObservedObject var guidance: iOSRouteGuidance

    /// User preference for metric (true) or imperial (false) units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    var body: some View {
        if guidance.isNavigating {
            VStack(spacing: 0) {
                // Instruction card
                instructionCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Progress bar
                progressBar
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            }
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Instruction Card

    /// The main card showing the upcoming turn direction and instruction text.
    private var instructionCard: some View {
        HStack(spacing: 16) {
            // Turn direction icon
            if let instruction = guidance.currentInstruction {
                Image(systemName: instruction.direction.sfSymbolName)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(guidance.isOffRoute ? .red : .purple)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(guidance.isOffRoute
                                  ? Color.red.opacity(0.15)
                                  : Color.purple.opacity(0.15))
                    )
            }

            // Instruction text
            VStack(alignment: .leading, spacing: 4) {
                if guidance.isOffRoute {
                    offRouteContent
                } else {
                    onRouteContent
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// Text content when on-route: distance to next turn and instruction.
    private var onRouteContent: some View {
        Group {
            if let distance = guidance.distanceToNextTurn {
                Text("In \(HikeStatsFormatter.formatDistance(distance, useMetric: useMetricUnits))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let instruction = guidance.currentInstruction {
                Text(instruction.description)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// Text content when off-route: warning and return-to-trail message.
    private var offRouteContent: some View {
        Group {
            Text("OFF ROUTE")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.red)

            Text("Return to the trail")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Progress Bar

    /// Bottom bar with a progress indicator and remaining distance.
    private var progressBar: some View {
        VStack(spacing: 4) {
            // Progress track
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 6)

                    Capsule()
                        .fill(.purple)
                        .frame(width: max(6, geometry.size.width * guidance.progress), height: 6)
                }
            }
            .frame(height: 6)

            // Distance and percentage
            HStack {
                Text("\(HikeStatsFormatter.formatDistance(guidance.remainingDistance, useMetric: useMetricUnits)) remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(guidance.progress * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
    }

}
