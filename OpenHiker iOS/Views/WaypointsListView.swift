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

/// A dedicated list view for browsing and managing all waypoints.
///
/// Available as a sidebar section on iPad (via ``SidebarSection/waypoints``) and also
/// usable standalone. Displays all waypoints from the ``WaypointStore`` grouped by
/// category, with navigation to ``WaypointDetailView`` for each entry.
///
/// ## Grouping
/// Waypoints are grouped by their ``WaypointCategory`` in the order defined
/// by the enum's `allCases`. Empty groups are hidden. This provides a natural
/// organization for users with many waypoints across multiple hikes.
///
/// ## Deletion
/// Swipe-to-delete is supported. The delete operation removes the waypoint from
/// the ``WaypointStore`` and refreshes the in-memory cache.
struct WaypointsListView: View {
    /// Reference to the shared waypoint store for observation.
    @ObservedObject private var waypointStore = WaypointStore.shared

    /// User preference for metric (true) or imperial (false) units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    /// Whether an error alert is displayed.
    @State private var showError = false

    /// The error message for the alert.
    @State private var errorMessage = ""

    var body: some View {
        Group {
            if waypointStore.waypoints.isEmpty {
                ContentUnavailableView(
                    "No Waypoints",
                    systemImage: "mappin.slash",
                    description: Text("Waypoints you add during hikes will appear here.")
                )
            } else {
                List {
                    ForEach(groupedCategories, id: \.category) { group in
                        Section {
                            ForEach(group.waypoints) { waypoint in
                                NavigationLink {
                                    WaypointDetailView(waypoint: waypoint)
                                } label: {
                                    waypointRow(waypoint)
                                }
                            }
                            .onDelete { offsets in
                                deleteWaypoints(at: offsets, in: group.waypoints)
                            }
                        } header: {
                            Label(group.category.displayName, systemImage: group.category.iconName)
                        }
                    }
                }
            }
        }
        .navigationTitle("Waypoints")
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Grouping

    /// A category group containing a category and its matching waypoints.
    private struct CategoryGroup {
        /// The waypoint category for this group.
        let category: WaypointCategory
        /// All waypoints in this category, sorted by timestamp descending.
        let waypoints: [Waypoint]
    }

    /// Waypoints grouped by category, with empty categories filtered out.
    private var groupedCategories: [CategoryGroup] {
        WaypointCategory.allCases.compactMap { category in
            let matching = waypointStore.waypoints.filter { $0.category == category }
            guard !matching.isEmpty else { return nil }
            return CategoryGroup(category: category, waypoints: matching)
        }
    }

    // MARK: - Row View

    /// A single waypoint row showing icon, label, note, and altitude.
    private func waypointRow(_ waypoint: Waypoint) -> some View {
        HStack(spacing: 8) {
            Image(systemName: waypoint.category.iconName)
                .foregroundStyle(Color(hex: waypoint.category.colorHex))
                .frame(width: 24)

            VStack(alignment: .leading) {
                Text(waypoint.label.isEmpty ? waypoint.category.displayName : waypoint.label)
                    .font(.subheadline)
                if !waypoint.note.isEmpty {
                    Text(waypoint.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let altitude = waypoint.altitude {
                Text(HikeStatsFormatter.formatElevation(altitude, useMetric: useMetricUnits))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if waypoint.hasPhoto {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Deletion

    /// Deletes waypoints at the given offsets within a category group.
    ///
    /// - Parameters:
    ///   - offsets: The index set of rows to delete.
    ///   - categoryWaypoints: The waypoints array for the category being deleted from.
    private func deleteWaypoints(at offsets: IndexSet, in categoryWaypoints: [Waypoint]) {
        for offset in offsets {
            let waypoint = categoryWaypoints[offset]
            do {
                try WaypointStore.shared.delete(id: waypoint.id)
            } catch {
                errorMessage = "Could not delete waypoint: \(error.localizedDescription)"
                showError = true
                print("Error deleting waypoint: \(error.localizedDescription)")
            }
        }
    }
}
