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

/// macOS list+detail view for reviewing saved hikes.
///
/// Uses a ``NavigationSplitView`` inner two-column layout:
/// - **List column**: Hike rows showing name, date, distance, and elevation
/// - **Detail column**: Full hike detail with map, stats, waypoints, and export
///
/// Hikes are loaded from ``RouteStore`` and sorted by date (newest first).
struct MacHikesView: View {
    /// All saved hikes loaded from the store.
    @State private var hikes: [SavedRoute] = []

    /// The currently selected hike ID.
    @State private var selectedHikeID: UUID?

    /// User preference for metric units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    /// Whether an error alert is shown.
    @State private var showError = false

    /// The error message for the alert.
    @State private var errorMessage = ""

    var body: some View {
        NavigationSplitView {
            hikeList
        } detail: {
            hikeDetail
        }
        .onAppear {
            loadHikes()
        }
    }

    // MARK: - Hike List

    /// The scrollable list of saved hikes.
    private var hikeList: some View {
        Group {
            if hikes.isEmpty {
                ContentUnavailableView(
                    "No Hikes",
                    systemImage: "figure.hiking",
                    description: Text("Hikes recorded on your Apple Watch will appear here after syncing via iCloud.")
                )
            } else {
                List(hikes, selection: $selectedHikeID) { hike in
                    hikeRow(hike)
                        .tag(hike.id)
                }
            }
        }
        .navigationTitle("Hikes")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    loadHikes()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh hike list")
            }
        }
    }

    /// A single row in the hike list.
    private func hikeRow(_ hike: SavedRoute) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hike.name)
                .font(.headline)

            HStack {
                Label(
                    HikeStatsFormatter.formatDistance(hike.totalDistance, useMetric: useMetricUnits),
                    systemImage: "ruler"
                )
                Spacer()
                Label(
                    HikeStatsFormatter.formatDuration(hike.duration),
                    systemImage: "clock"
                )
                Spacer()
                Label(
                    "+\(HikeStatsFormatter.formatElevation(hike.elevationGain, useMetric: useMetricUnits))",
                    systemImage: "arrow.up.right"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(hike.formattedDate)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Hike Detail

    /// The detail view for the selected hike, or a placeholder if nothing is selected.
    @ViewBuilder
    private var hikeDetail: some View {
        if let id = selectedHikeID, let hike = hikes.first(where: { $0.id == id }) {
            MacHikeDetailView(route: hike) {
                loadHikes()
            }
        } else {
            ContentUnavailableView(
                "Select a Hike",
                systemImage: "figure.hiking",
                description: Text("Choose a hike from the list to view its details.")
            )
        }
    }

    // MARK: - Data Loading

    /// Loads all hikes from the route store.
    private func loadHikes() {
        do {
            hikes = try RouteStore.shared.fetchAll()
        } catch {
            errorMessage = "Could not load hikes: \(error.localizedDescription)"
            showError = true
            print("Error loading hikes: \(error.localizedDescription)")
        }
    }
}
