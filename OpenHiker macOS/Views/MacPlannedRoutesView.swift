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

/// macOS view for browsing planned routes.
///
/// Displays planned routes in a list with name, distance, elevation, and duration.
/// Route planning is only available on iOS (where the MapKit interactive view is
/// used); this view is read-only for reviewing routes synced via iCloud.
struct MacPlannedRoutesView: View {
    /// Reference to the shared planned route store for observation.
    @ObservedObject private var routeStore = PlannedRouteStore.shared

    /// User preference for metric units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    var body: some View {
        Group {
            if routeStore.routes.isEmpty {
                ContentUnavailableView(
                    "No Planned Routes",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text("Plan routes in the iOS app and they will sync here via iCloud.")
                )
            } else {
                List(routeStore.routes) { route in
                    routeRow(route)
                }
            }
        }
        .navigationTitle("Planned Routes")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    routeStore.loadAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh route list")
            }
        }
    }

    /// A single row in the planned routes list.
    private func routeRow(_ route: PlannedRoute) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(route.name)
                    .font(.headline)
                Spacer()
                Image(systemName: route.mode == .hiking ? "figure.hiking" : "bicycle")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label(
                    HikeStatsFormatter.formatDistance(route.totalDistance, useMetric: useMetricUnits),
                    systemImage: "ruler"
                )
                Spacer()
                Label(route.formattedDuration, systemImage: "clock")
                Spacer()
                Label(
                    "+\(HikeStatsFormatter.formatElevation(route.elevationGain, useMetric: useMetricUnits))",
                    systemImage: "arrow.up.right"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(route.formattedDate)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
