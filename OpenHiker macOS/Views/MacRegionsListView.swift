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

/// macOS view for managing downloaded offline map regions.
///
/// Displays all downloaded regions in a list with name, file size, tile count,
/// zoom levels, area covered, and routing data status. Users can delete regions
/// and trigger iCloud sync to push data to the iPhone (which relays to the watch).
struct MacRegionsListView: View {
    /// Shared region storage singleton.
    @ObservedObject private var storage = RegionStorage.shared

    /// User preference for metric units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    /// Currently selected region for detail view.
    @State private var selectedRegion: Region?

    /// Region to send via MultipeerConnectivity (triggers the send sheet).
    @State private var regionToSend: Region?

    /// Region selected for route planning (triggers the planning sheet).
    @State private var regionForPlanning: Region?

    /// Whether the "no routing data" alert is shown.
    @State private var showNoRoutingAlert = false

    /// Region currently being renamed (triggers the rename alert).
    @State private var regionToRename: Region?

    /// Text field binding for the rename alert.
    @State private var renameText = ""

    /// Whether the rename alert is displayed.
    @State private var showRenameAlert = false

    var body: some View {
        Group {
            if storage.regions.isEmpty {
                ContentUnavailableView(
                    "No Regions Downloaded",
                    systemImage: "map",
                    description: Text("Use the Regions tab to select and download an area for offline use.")
                )
            } else {
                List(selection: $selectedRegion) {
                    ForEach(storage.regions) { region in
                        regionRow(region)
                            .tag(region)
                            .onTapGesture(count: 2) {
                                if region.hasRoutingData {
                                    regionForPlanning = region
                                } else {
                                    showNoRoutingAlert = true
                                }
                            }
                            .contextMenu {
                                Button {
                                    regionToRename = region
                                    renameText = region.name
                                    showRenameAlert = true
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                if region.hasRoutingData {
                                    Button {
                                        regionForPlanning = region
                                    } label: {
                                        Label("Plan Route", systemImage: "arrow.triangle.turn.up.right.diamond")
                                    }
                                }
                                Button("Send to iPhone") {
                                    regionToSend = region
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    storage.deleteRegion(region)
                                }
                            }
                    }
                    .onDelete(perform: deleteRegions)
                }
            }
        }
        .navigationTitle("Downloaded Regions")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    storage.loadRegions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh region list")
            }
        }
        .onAppear {
            storage.loadRegions()
        }
        .alert("No Routing Data", isPresented: $showNoRoutingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Re-download this region with routing enabled to plan routes on it.")
        }
        .sheet(item: $regionForPlanning) { region in
            MacRoutePlanningView(region: region, onDismiss: {
                regionForPlanning = nil
            })
            .frame(minWidth: 800, minHeight: 600)
        }
        .sheet(item: $regionToSend) { region in
            MacPeerSendView(region: region)
        }
        .alert("Rename Region", isPresented: $showRenameAlert) {
            TextField("Region name", text: $renameText)
            Button("Cancel", role: .cancel) {
                regionToRename = nil
            }
            Button("Rename") {
                if let region = regionToRename,
                   !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    storage.renameRegion(region, to: renameText.trimmingCharacters(in: .whitespaces))
                }
                regionToRename = nil
            }
        } message: {
            Text("Enter a new name for this region.")
        }
    }

    /// A single row in the downloaded regions list.
    private func regionRow(_ region: Region) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(region.name)
                    .font(.headline)
                Spacer()
                if region.hasRoutingData {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                        .help("Routing data available")
                }
            }

            HStack {
                Label(region.fileSizeFormatted, systemImage: "externaldrive")
                Spacer()
                Label("\(region.tileCount) tiles", systemImage: "square.grid.3x3")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("Zoom \(region.zoomLevels.lowerBound)-\(region.zoomLevels.upperBound) • \(String(format: "%.1f", region.areaCoveredKm2)) km²")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    /// Deletes regions at the given index offsets.
    private func deleteRegions(at offsets: IndexSet) {
        storage.deleteRegions(at: offsets)
    }
}
