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
import MapKit

// MARK: - Route Detail View

/// Read-only view of a saved planned route.
///
/// Shows the route polyline on a MapKit map, statistics summary (distance, time,
/// elevation), and a scrollable list of turn-by-turn directions. Provides a
/// "Send to Watch" button to transfer the route for active guidance.
struct RouteDetailView: View {
    @EnvironmentObject var watchConnectivity: WatchConnectivityManager

    /// The planned route to display.
    let route: PlannedRoute

    /// Whether the "sent to watch" confirmation is shown.
    @State private var showSentConfirmation = false

    /// Error message from failed transfers.
    @State private var errorMessage: String?

    /// Whether the error alert is displayed.
    @State private var showError = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Map with route polyline
                mapSection

                // Statistics
                statsSection

                // Send to Watch button
                sendToWatchButton

                // Turn-by-turn directions
                directionsSection
            }
            .padding()
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sent to Watch", isPresented: $showSentConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The route has been queued for transfer to your Apple Watch.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An error occurred.")
        }
    }

    // MARK: - Map Section

    /// The map showing the route polyline and start/end markers.
    private var mapSection: some View {
        Map {
            // Route polyline
            if route.coordinates.count >= 2 {
                MapPolyline(coordinates: route.coordinates)
                    .stroke(.purple, lineWidth: 4)
            }

            // Start marker
            Annotation("Start", coordinate: route.startCoordinate) {
                Circle()
                    .fill(.green)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }

            // End marker
            Annotation("End", coordinate: route.endCoordinate) {
                Circle()
                    .fill(.red)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }

            // Via-point markers
            ForEach(Array(route.viaPoints.enumerated()), id: \.offset) { index, via in
                Annotation("Via \(index + 1)", coordinate: via) {
                    Circle()
                        .fill(.blue)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Stats Section

    /// Route statistics grid showing distance, time, and elevation.
    private var statsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Route Details")
                    .font(.headline)
                Spacer()
                Text(route.mode == .hiking ? "Hiking" : "Cycling")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(route.mode == .hiking ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                    )
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                DetailStatItem(
                    icon: "ruler",
                    label: "Distance",
                    value: HikeStatsFormatter.formatDistance(route.totalDistance, useMetric: true)
                )
                DetailStatItem(
                    icon: "clock",
                    label: "Est. Time",
                    value: route.formattedDuration
                )
                DetailStatItem(
                    icon: "arrow.up.right",
                    label: "Gain",
                    value: "+\(HikeStatsFormatter.formatElevation(route.elevationGain, useMetric: true))"
                )
                DetailStatItem(
                    icon: "arrow.down.right",
                    label: "Loss",
                    value: "-\(HikeStatsFormatter.formatElevation(route.elevationLoss, useMetric: true))"
                )
                DetailStatItem(
                    icon: "calendar",
                    label: "Created",
                    value: route.formattedDate
                )
                DetailStatItem(
                    icon: "point.bottomleft.forward.to.point.topright.scurvepath",
                    label: "Turns",
                    value: "\(route.turnInstructions.count)"
                )
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    // MARK: - Send to Watch

    /// Button to transfer the planned route to the Apple Watch.
    private var sendToWatchButton: some View {
        Button {
            sendToWatch()
        } label: {
            Label("Send to Watch", systemImage: "applewatch.radiowaves.left.and.right")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(.purple)
    }

    // MARK: - Directions Section

    /// Scrollable list of turn-by-turn directions.
    private var directionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Directions")
                .font(.headline)

            ForEach(Array(route.turnInstructions.enumerated()), id: \.offset) { index, instruction in
                HStack(alignment: .top, spacing: 12) {
                    // Step number
                    Text("\(index + 1)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.purple.opacity(0.15)))

                    // Direction icon
                    Image(systemName: instruction.direction.sfSymbolName)
                        .font(.body)
                        .foregroundStyle(.purple)
                        .frame(width: 24)

                    // Instruction text
                    VStack(alignment: .leading, spacing: 2) {
                        Text(instruction.description)
                            .font(.subheadline)
                        if instruction.distanceFromPrevious > 0 {
                            Text("In \(HikeStatsFormatter.formatDistance(instruction.distanceFromPrevious, useMetric: true))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 4)

                if index < route.turnInstructions.count - 1 {
                    Divider()
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    // MARK: - Actions

    /// Transfers the planned route JSON file to the Apple Watch.
    private func sendToWatch() {
        guard let fileURL = PlannedRouteStore.shared.fileURL(for: route.id) else {
            errorMessage = "Route file not found. Try saving the route again."
            showError = true
            return
        }

        watchConnectivity.sendPlannedRouteToWatch(fileURL: fileURL, route: route)
        showSentConfirmation = true
    }
}

// MARK: - Detail Stat Item

/// A stat item with icon, label, and value for the route detail view.
private struct DetailStatItem: View {
    /// SF Symbol name for the stat icon.
    let icon: String
    /// Label text (e.g., "Distance").
    let label: String
    /// Value text (e.g., "12.4 km").
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.purple)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
