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

/// macOS view for browsing all waypoints in a native Table.
///
/// Uses the macOS-native ``Table`` view with sortable columns for a spreadsheet-like
/// experience that leverages the larger screen. Waypoints can be sorted by category,
/// label, date, or altitude.
struct MacWaypointsView: View {
    /// Reference to the shared waypoint store for observation.
    @ObservedObject private var waypointStore = WaypointStore.shared

    /// User preference for metric units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    /// The currently selected waypoint IDs.
    @State private var selection = Set<UUID>()

    /// Sort order for the table.
    @State private var sortOrder = [KeyPathComparator(\Waypoint.timestamp, order: .reverse)]

    var body: some View {
        Group {
            if waypointStore.waypoints.isEmpty {
                ContentUnavailableView(
                    "No Waypoints",
                    systemImage: "mappin.slash",
                    description: Text("Waypoints will appear here after syncing from your iOS device via iCloud.")
                )
            } else {
                Table(sortedWaypoints, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Category", value: \.category.rawValue) { wp in
                        Label(wp.category.displayName, systemImage: wp.category.iconName)
                    }
                    .width(min: 80, ideal: 110)

                    TableColumn("Label", value: \.label) { wp in
                        Text(wp.label.isEmpty ? "-" : wp.label)
                    }
                    .width(min: 100, ideal: 150)

                    TableColumn("Coordinate") { wp in
                        Text(wp.formattedCoordinate)
                            .font(.system(.body, design: .monospaced))
                    }
                    .width(min: 150, ideal: 170)

                    TableColumn("Altitude") { wp in
                        if let altitude = wp.altitude {
                            Text(HikeStatsFormatter.formatElevation(altitude, useMetric: useMetricUnits))
                        } else {
                            Text("-")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("Date", value: \.timestamp) { wp in
                        Text(wp.timestamp, style: .date)
                    }
                    .width(min: 100, ideal: 120)

                    TableColumn("Note", value: \.note) { wp in
                        Text(wp.note)
                            .lineLimit(1)
                    }

                    TableColumn("Photo") { wp in
                        if wp.hasPhoto {
                            Image(systemName: "photo")
                                .foregroundStyle(.blue)
                        }
                    }
                    .width(min: 40, ideal: 50)
                }
            }
        }
        .navigationTitle("Waypoints (\(waypointStore.waypoints.count))")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    deleteSelected()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selection.isEmpty)
                .help("Delete selected waypoints")
            }
        }
    }

    /// Waypoints sorted by the current table sort order.
    private var sortedWaypoints: [Waypoint] {
        waypointStore.waypoints.sorted(using: sortOrder)
    }

    /// Deletes the currently selected waypoints.
    private func deleteSelected() {
        for id in selection {
            do {
                try WaypointStore.shared.delete(id: id)
            } catch {
                print("Error deleting waypoint \(id): \(error.localizedDescription)")
            }
        }
        selection.removeAll()
    }
}
