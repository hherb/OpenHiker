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

/// macOS view for browsing and creating planned routes.
///
/// Displays planned routes in a list with name, distance, elevation, and duration.
/// Users can create new routes by selecting a downloaded region with routing data
/// and opening the interactive ``MacRoutePlanningView``.
///
/// Routes can also be imported from GPX files via the File > Import GPX menu command.
struct MacPlannedRoutesView: View {
    /// Reference to the shared planned route store for observation.
    @ObservedObject private var routeStore = PlannedRouteStore.shared

    /// Shared region storage to find regions with routing data.
    @ObservedObject private var regionStorage = RegionStorage.shared

    /// User preference for metric units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    /// The selected region for route planning.
    @State private var selectedPlanningRegion: Region?

    /// Whether the route planning sheet is shown.
    @State private var showRoutePlanning = false

    /// The number of routes imported in the last GPX import.
    @State private var importCount = 0

    /// Whether the import success alert is shown.
    @State private var showImportSuccess = false

    var body: some View {
        Group {
            if routeStore.routes.isEmpty {
                ContentUnavailableView(
                    "No Planned Routes",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text("Create a route below or import a GPX file via File > Import GPX.")
                )
            } else {
                List(routeStore.routes) { route in
                    routeRow(route)
                        .contextMenu {
                            Button("Send to iPhone via iCloud") {
                                Task {
                                    await CloudSyncManager.shared.performSync()
                                }
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                do {
                                    try PlannedRouteStore.shared.delete(id: route.id)
                                } catch {
                                    print("Error deleting route: \(error.localizedDescription)")
                                }
                            }
                        }
                }
            }
        }
        .navigationTitle("Planned Routes")
        .toolbar {
            ToolbarItemGroup {
                // Plan new route menu (only shows regions with routing data)
                Menu {
                    let routableRegions = regionStorage.regions.filter(\.hasRoutingData)
                    if routableRegions.isEmpty {
                        Text("Download a region with routing data first")
                    } else {
                        ForEach(routableRegions) { region in
                            Button(region.name) {
                                selectedPlanningRegion = region
                                showRoutePlanning = true
                            }
                        }
                    }
                } label: {
                    Label("Plan Route", systemImage: "plus")
                }
                .help("Plan a new route on a downloaded region")

                Button {
                    Task { @MainActor in
                        let count = await GPXImportHandler.presentImportPanel()
                        if count > 0 {
                            routeStore.loadAll()
                            importCount = count
                            showImportSuccess = true
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Import GPX file")

                Button {
                    routeStore.loadAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh route list")
            }
        }
        .sheet(isPresented: $showRoutePlanning) {
            if let region = selectedPlanningRegion {
                MacRoutePlanningView(region: region)
                    .frame(minWidth: 900, minHeight: 600)
            }
        }
        .alert("GPX Imported", isPresented: $showImportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(importCount) route(s) imported successfully.")
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
