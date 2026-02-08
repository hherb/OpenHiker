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

/// Displays a searchable list of all saved hiking routes on the iOS app.
///
/// Each row shows the hike name, date, distance, duration, and elevation gain.
/// Tapping a row navigates to ``HikeDetailView`` for full review. Swipe-to-delete
/// removes routes from the ``RouteStore`` with confirmation.
///
/// The list is sorted by date (newest first) and can be filtered using the search bar.
struct HikesListView: View {
    /// All saved routes loaded from the ``RouteStore``.
    @State private var routes: [SavedRoute] = []

    /// The current search query text.
    @State private var searchText = ""

    /// Whether an error alert is displayed.
    @State private var showError = false

    /// The error message for the alert.
    @State private var errorMessage = ""

    /// Whether a delete confirmation dialog is displayed.
    @State private var showDeleteConfirmation = false

    /// The route pending deletion (set before showing confirmation dialog).
    @State private var routeToDelete: SavedRoute?

    /// Route currently being renamed (triggers the rename alert).
    @State private var routeToRename: SavedRoute?

    /// Text field binding for the rename alert.
    @State private var renameText = ""

    /// Whether the rename alert is displayed.
    @State private var showRenameAlert = false

    /// User preference for metric (true) or imperial (false) units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    /// Routes filtered by the search text, matching against the route name.
    private var filteredRoutes: [SavedRoute] {
        if searchText.isEmpty {
            return routes
        }
        return routes.filter { route in
            route.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if routes.isEmpty {
                    ContentUnavailableView(
                        "No Hikes Saved",
                        systemImage: "figure.hiking",
                        description: Text("Complete a hike on your Apple Watch and save it to see it here.")
                    )
                } else if filteredRoutes.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(filteredRoutes) { route in
                            NavigationLink(destination: HikeDetailView(route: route, onUpdate: {
                                loadRoutes()
                            })) {
                                HikeRowView(route: route, useMetric: useMetricUnits)
                            }
                            .contextMenu {
                                Button {
                                    routeToRename = route
                                    renameText = route.name
                                    showRenameAlert = true
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    routeToDelete = route
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete(perform: confirmDelete)
                    }
                    .searchable(text: $searchText, prompt: "Search hikes")
                }
            }
            .navigationTitle("Hikes")
            .toolbar {
                if !routes.isEmpty {
                    EditButton()
                }
            }
            .onAppear {
                loadRoutes()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .confirmationDialog(
                "Delete Hike",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let route = routeToDelete {
                        deleteRoute(route)
                    }
                }
                Button("Cancel", role: .cancel) {
                    routeToDelete = nil
                }
            } message: {
                if let route = routeToDelete {
                    Text("Are you sure you want to delete \"\(route.name)\"? This cannot be undone.")
                }
            }
            .alert("Rename Hike", isPresented: $showRenameAlert) {
                TextField("Hike name", text: $renameText)
                Button("Cancel", role: .cancel) {
                    routeToRename = nil
                }
                Button("Rename") {
                    if var route = routeToRename,
                       !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                        route.name = renameText.trimmingCharacters(in: .whitespaces)
                        route.modifiedAt = Date()
                        do {
                            try RouteStore.shared.update(route)
                            loadRoutes()
                        } catch {
                            errorMessage = "Could not rename hike: \(error.localizedDescription)"
                            showError = true
                        }
                    }
                    routeToRename = nil
                }
            } message: {
                Text("Enter a new name for this hike.")
            }
        }
    }

    // MARK: - Data Loading

    /// Loads all saved routes from the ``RouteStore``.
    private func loadRoutes() {
        do {
            routes = try RouteStore.shared.fetchAll()
        } catch {
            errorMessage = "Could not load hikes: \(error.localizedDescription)"
            showError = true
            print("Error loading routes: \(error.localizedDescription)")
        }
    }

    // MARK: - Deletion

    /// Presents a confirmation dialog before deleting a route.
    ///
    /// - Parameter offsets: The index positions of the routes to delete.
    private func confirmDelete(at offsets: IndexSet) {
        guard let index = offsets.first else { return }
        routeToDelete = filteredRoutes[index]
        showDeleteConfirmation = true
    }

    /// Deletes a route from the ``RouteStore`` and refreshes the list.
    ///
    /// - Parameter route: The ``SavedRoute`` to delete.
    private func deleteRoute(_ route: SavedRoute) {
        do {
            try RouteStore.shared.delete(id: route.id)
            loadRoutes()
        } catch {
            errorMessage = "Could not delete hike: \(error.localizedDescription)"
            showError = true
            print("Error deleting route: \(error.localizedDescription)")
        }
        routeToDelete = nil
    }
}

// MARK: - Hike Row View

/// A single row in the hikes list showing summary information.
///
/// Displays: name, date with start time, distance, duration, and elevation gain.
struct HikeRowView: View {
    /// The route to display.
    let route: SavedRoute

    /// Whether to use metric units.
    let useMetric: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(route.name)
                .font(.headline)
                .lineLimit(1)

            Text("\(route.formattedDate) at \(route.formattedStartTime)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Label(
                    HikeStatsFormatter.formatDistance(route.totalDistance, useMetric: useMetric),
                    systemImage: "figure.walk"
                )

                Label(
                    HikeStatsFormatter.formatDuration(route.duration),
                    systemImage: "clock"
                )

                Label(
                    "+\(HikeStatsFormatter.formatElevation(route.elevationGain, useMetric: useMetric))",
                    systemImage: "arrow.up.right"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
