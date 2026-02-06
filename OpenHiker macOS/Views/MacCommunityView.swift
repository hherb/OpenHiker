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

/// macOS view for browsing the community route repository.
///
/// Provides a searchable list of shared routes from the OpenHikerRoutes GitHub
/// repository. Each route shows its name, country, activity type, distance, and
/// elevation. Selecting a route shows its full details.
///
/// Uses the same ``GitHubRouteService`` as the iOS app for data fetching.
struct MacCommunityView: View {
    /// Routes loaded from the community repository.
    @State private var routes: [RouteIndexEntry] = []

    /// Whether the route list is currently loading.
    @State private var isLoading = false

    /// Search text for filtering routes by name or country.
    @State private var searchText = ""

    /// Error message if loading fails.
    @State private var errorMessage: String?

    /// The selected route entry ID.
    @State private var selectedRouteID: UUID?

    /// Filtered routes based on search text.
    private var filteredRoutes: [RouteIndexEntry] {
        if searchText.isEmpty {
            return routes
        }
        let query = searchText.lowercased()
        return routes.filter { entry in
            entry.name.lowercased().contains(query) ||
            entry.country.lowercased().contains(query) ||
            entry.area.lowercased().contains(query)
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading community routes...")
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Could Not Load Routes",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if routes.isEmpty {
                ContentUnavailableView(
                    "No Community Routes",
                    systemImage: "person.3",
                    description: Text("Community routes will appear here once the repository has content.")
                )
            } else {
                List(filteredRoutes, selection: $selectedRouteID) { entry in
                    routeRow(entry)
                        .tag(entry.id)
                }
                .searchable(text: $searchText, prompt: "Search routes by name or country")
            }
        }
        .navigationTitle("Community Routes (\(filteredRoutes.count))")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await loadRoutes() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh community routes")
            }
        }
        .task {
            if routes.isEmpty {
                await loadRoutes()
            }
        }
    }

    /// A single row in the community routes list.
    private func routeRow(_ entry: RouteIndexEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.name)
                    .font(.headline)
                Spacer()
                Text(entry.country)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label(
                    HikeStatsFormatter.formatDistance(entry.distance, useMetric: true),
                    systemImage: "ruler"
                )
                Spacer()
                Label(
                    "+\(HikeStatsFormatter.formatElevation(entry.elevationGain, useMetric: true))",
                    systemImage: "arrow.up.right"
                )
                Spacer()
                Label(entry.activityType.displayName, systemImage: entry.activityType.iconName)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// Loads the community route index from the GitHub repository.
    private func loadRoutes() async {
        isLoading = true
        errorMessage = nil

        do {
            let index = try await GitHubRouteService.shared.fetchRouteIndex()
            routes = index.routes
        } catch {
            errorMessage = error.localizedDescription
            print("Error loading community routes: \(error.localizedDescription)")
        }

        isLoading = false
    }
}
