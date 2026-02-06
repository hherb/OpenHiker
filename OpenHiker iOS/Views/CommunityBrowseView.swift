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
import CoreLocation
import MapKit

/// Displays a browsable, filterable list of community-shared routes from the OpenHikerRoutes repository.
///
/// The view fetches `index.json` from GitHub on appear and presents routes in a searchable list.
/// Users can filter by activity type and proximity to their current location. Tapping a route
/// navigates to ``CommunityRouteDetailView`` for full details and offline download.
///
/// ## Data Flow
/// 1. On appear, ``GitHubRouteService/fetchIndex(forceRefresh:)`` loads the master index
/// 2. The index is filtered client-side by activity type and geographic proximity
/// 3. Tapping a route fetches the full `route.json` via ``GitHubRouteService/fetchRoute(at:)``
struct CommunityBrowseView: View {
    /// All route entries from the index.
    @State private var allRoutes: [RouteIndexEntry] = []

    /// Routes after applying filters.
    @State private var filteredRoutes: [RouteIndexEntry] = []

    /// The selected activity type filter (nil = all types).
    @State private var selectedActivityType: ActivityType?

    /// Search text for filtering by route name.
    @State private var searchText = ""

    /// Whether the initial index load is in progress.
    @State private var isLoading = true

    /// Error message if the index fetch fails.
    @State private var errorMessage: String?

    /// Whether the error alert is displayed.
    @State private var showError = false

    /// The user's current location for proximity filtering.
    @State private var userLocation: CLLocationCoordinate2D?

    /// Whether to filter by proximity to the user's location.
    @State private var filterByProximity = false

    /// Search radius in kilometers for proximity filtering.
    private static let searchRadiusKm: Double = 100

    /// User preference for metric (true) or imperial (false) units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    /// Location manager for getting the user's current position.
    private let locationManager = CLLocationManager()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading community routes...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("Could Not Load Routes", systemImage: "wifi.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { loadIndex(forceRefresh: true) }
                            .buttonStyle(.bordered)
                    }
                } else if filteredRoutes.isEmpty && !allRoutes.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if allRoutes.isEmpty {
                    ContentUnavailableView(
                        "No Community Routes Yet",
                        systemImage: "globe",
                        description: Text("Be the first to share a route! Open a saved hike and tap \"Share to Community\".")
                    )
                } else {
                    routeList
                }
            }
            .navigationTitle("Community")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Activity Type") {
                            Button {
                                selectedActivityType = nil
                                applyFilters()
                            } label: {
                                Label("All Activities", systemImage: selectedActivityType == nil ? "checkmark" : "")
                            }

                            ForEach(ActivityType.allCases, id: \.self) { type in
                                Button {
                                    selectedActivityType = type
                                    applyFilters()
                                } label: {
                                    Label(
                                        type.displayName,
                                        systemImage: selectedActivityType == type ? "checkmark" : type.iconName
                                    )
                                }
                            }
                        }

                        Section("Location") {
                            Toggle("Near Me", isOn: Binding(
                                get: { filterByProximity },
                                set: { newValue in
                                    filterByProximity = newValue
                                    if newValue { requestLocation() }
                                    applyFilters()
                                }
                            ))
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        loadIndex(forceRefresh: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .searchable(text: $searchText, prompt: "Search routes")
            .onChange(of: searchText) {
                applyFilters()
            }
            .onAppear {
                loadIndex()
            }
        }
    }

    // MARK: - Route List

    /// The scrollable list of community routes with summary rows.
    private var routeList: some View {
        List {
            ForEach(filteredRoutes) { entry in
                NavigationLink(destination: CommunityRouteDetailView(entry: entry)) {
                    CommunityRouteRow(entry: entry, useMetric: useMetricUnits)
                }
            }
        }
    }

    // MARK: - Data Loading

    /// Fetches the community route index from GitHub.
    ///
    /// - Parameter forceRefresh: If `true`, bypasses the cache.
    private func loadIndex(forceRefresh: Bool = false) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let index = try await GitHubRouteService.shared.fetchIndex(forceRefresh: forceRefresh)
                await MainActor.run {
                    allRoutes = index.routes
                    applyFilters()
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    // MARK: - Filtering

    /// Applies all active filters (activity type, proximity, search text) to the route list.
    private func applyFilters() {
        Task {
            let filtered = await GitHubRouteService.shared.filterRoutes(
                allRoutes,
                activityType: selectedActivityType,
                nearLatitude: filterByProximity ? userLocation?.latitude : nil,
                nearLongitude: filterByProximity ? userLocation?.longitude : nil,
                radiusKm: Self.searchRadiusKm
            )

            await MainActor.run {
                if searchText.isEmpty {
                    filteredRoutes = filtered
                } else {
                    filteredRoutes = filtered.filter { entry in
                        entry.name.localizedCaseInsensitiveContains(searchText) ||
                        entry.region.area.localizedCaseInsensitiveContains(searchText) ||
                        entry.author.localizedCaseInsensitiveContains(searchText)
                    }
                }
            }
        }
    }

    // MARK: - Location

    /// Requests the user's current location for proximity filtering.
    private func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
        if let location = locationManager.location {
            userLocation = location.coordinate
        }
    }
}

// MARK: - Route Row

/// A single row in the community route list showing summary information.
///
/// Displays the route name, activity type icon, author, region, and key statistics.
struct CommunityRouteRow: View {
    /// The route index entry to display.
    let entry: RouteIndexEntry

    /// Whether to use metric units.
    let useMetric: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: entry.activityType.iconName)
                    .foregroundStyle(.blue)
                    .frame(width: 20)

                Text(entry.name)
                    .font(.headline)
                    .lineLimit(1)
            }

            Text("by \(entry.author) | \(entry.region.area), \(entry.region.country)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 12) {
                Label(
                    HikeStatsFormatter.formatDistance(entry.stats.distanceMeters, useMetric: useMetric),
                    systemImage: "figure.walk"
                )

                Label(
                    "+\(HikeStatsFormatter.formatElevation(entry.stats.elevationGainMeters, useMetric: useMetric))",
                    systemImage: "arrow.up.right"
                )

                if entry.photoCount > 0 {
                    Label("\(entry.photoCount)", systemImage: "photo")
                }

                if entry.waypointCount > 0 {
                    Label("\(entry.waypointCount)", systemImage: "mappin")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
