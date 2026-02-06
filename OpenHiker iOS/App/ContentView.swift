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

/// The root content view of the iOS companion app.
///
/// Presents a tab-based interface with four main sections:
/// - **Regions**: Select and download new map regions from OpenTopoMap
/// - **Downloaded**: View, manage, and transfer previously downloaded regions
/// - **Hikes**: Review saved hikes with track overlay, elevation profile, and stats
/// - **Watch**: Monitor Apple Watch connectivity and manage file transfers
struct ContentView: View {
    @EnvironmentObject var watchConnectivity: WatchConnectivityManager

    /// The currently selected tab index (0 = Regions, 1 = Downloaded, 2 = Hikes, 3 = Watch).
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            RegionSelectorView()
                .tabItem {
                    Label("Regions", systemImage: "map")
                }
                .tag(0)

            RegionsListView()
                .tabItem {
                    Label("Downloaded", systemImage: "arrow.down.circle")
                }
                .tag(1)

            HikesListView()
                .tabItem {
                    Label("Hikes", systemImage: "figure.hiking")
                }
                .tag(2)

            WatchSyncView()
                .tabItem {
                    Label("Watch", systemImage: "applewatch")
                }
                .tag(3)
        }
    }
}

// MARK: - Downloaded Regions List

/// Displays a list of all downloaded offline map regions.
///
/// Each region row shows the region name, file size, tile count, zoom levels,
/// and area covered. Users can delete regions via swipe or edit mode, and
/// transfer individual regions to the Apple Watch.
struct RegionsListView: View {
    @ObservedObject private var storage = RegionStorage.shared
    @EnvironmentObject var watchConnectivity: WatchConnectivityManager

    var body: some View {
        NavigationStack {
            Group {
                if storage.regions.isEmpty {
                    ContentUnavailableView(
                        "No Regions Downloaded",
                        systemImage: "map",
                        description: Text("Select an area on the map to download offline tiles for your Apple Watch.")
                    )
                } else {
                    List {
                        ForEach(storage.regions) { region in
                            RegionRowView(region: region, onTransfer: {
                                transferToWatch(region)
                            })
                        }
                        .onDelete(perform: deleteRegions)
                    }
                }
            }
            .navigationTitle("Downloaded Regions")
            .toolbar {
                EditButton()
            }
        }
        .onAppear {
            storage.loadRegions()
        }
    }

    /// Deletes regions at the given index offsets from the list.
    ///
    /// - Parameter offsets: The index positions of the regions to delete.
    private func deleteRegions(at offsets: IndexSet) {
        storage.deleteRegions(at: offsets)
    }

    /// Initiates a WatchConnectivity file transfer for the specified region.
    ///
    /// Reads the MBTiles file from local storage and sends it along with
    /// region metadata to the paired Apple Watch.
    ///
    /// - Parameter region: The ``Region`` to transfer.
    private func transferToWatch(_ region: Region) {
        let mbtilesURL = storage.mbtilesURL(for: region)
        let metadata = storage.metadata(for: region)
        watchConnectivity.transferMBTilesFile(at: mbtilesURL, metadata: metadata)
    }
}

/// A single row in the downloaded regions list.
///
/// Shows region name, file size, tile count, zoom range, area covered, and a
/// transfer button (or transfer status icon if a transfer is in progress).
struct RegionRowView: View {
    /// The region displayed by this row.
    let region: Region

    /// Callback invoked when the user taps the transfer button.
    let onTransfer: () -> Void

    @EnvironmentObject var watchConnectivity: WatchConnectivityManager

    /// The current watch transfer status for this region, if any.
    private var transferStatus: WatchConnectivityManager.TransferStatus? {
        watchConnectivity.transferStatuses[region.id]
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(region.name)
                    .font(.headline)

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

            if let status = transferStatus {
                switch status {
                case .queued:
                    Image(systemName: "clock")
                        .foregroundStyle(.orange)
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            } else {
                Button {
                    onTransfer()
                } label: {
                    Image(systemName: "arrow.up.to.line")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Watch Sync View

/// Displays the Apple Watch connectivity status and transfer management interface.
///
/// Shows whether a watch is paired and reachable, provides a "Send All Regions" button,
/// and lists pending and completed file transfers with their status.
struct WatchSyncView: View {
    @EnvironmentObject var watchConnectivity: WatchConnectivityManager
    @ObservedObject private var storage = RegionStorage.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: statusIcon)
                            .foregroundStyle(statusColor)
                            .font(.title2)

                        VStack(alignment: .leading) {
                            Text(statusTitle)
                                .font(.headline)
                            Text(statusSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Connection Status")
                }

                if watchConnectivity.isPaired && watchConnectivity.isWatchAppInstalled && !storage.regions.isEmpty {
                    Section {
                        Button {
                            watchConnectivity.syncAllRegionsToWatch()
                        } label: {
                            Label("Send All Regions to Watch", systemImage: "arrow.up.circle.fill")
                        }
                    }
                }

                Section {
                    if watchConnectivity.pendingTransfers.isEmpty && watchConnectivity.transferStatuses.isEmpty {
                        Text("No pending transfers")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(watchConnectivity.pendingTransfers, id: \.self) { transfer in
                            HStack {
                                ProgressView()
                                Text("Transferring \(transfer.file.metadata?["name"] as? String ?? "file")...")
                                    .font(.caption)
                            }
                        }
                        ForEach(Array(watchConnectivity.transferStatuses), id: \.key) { regionId, status in
                            HStack {
                                switch status {
                                case .queued:
                                    Image(systemName: "clock")
                                        .foregroundStyle(.orange)
                                    Text("Queued")
                                        .font(.caption)
                                case .completed:
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Transfer complete")
                                        .font(.caption)
                                case .failed(let msg):
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                    Text("Failed: \(msg)")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Transfers")
                }
            }
            .navigationTitle("Apple Watch")
        }
    }

    /// SF Symbol name for the current watch connectivity state.
    private var statusIcon: String {
        if !watchConnectivity.isPaired { return "applewatch.slash" }
        if !watchConnectivity.isWatchAppInstalled { return "applewatch.slash" }
        if watchConnectivity.isReachable { return "applewatch.radiowaves.left.and.right" }
        return "applewatch"
    }

    /// Color representing the current connectivity state (green = connected, secondary = disconnected).
    private var statusColor: Color {
        if !watchConnectivity.isPaired || !watchConnectivity.isWatchAppInstalled { return .secondary }
        return .green
    }

    /// Human-readable title for the current watch state.
    private var statusTitle: String {
        if !watchConnectivity.isPaired { return "No Watch Paired" }
        if !watchConnectivity.isWatchAppInstalled { return "Watch App Not Installed" }
        return "Watch Ready"
    }

    /// Human-readable subtitle providing additional context about the watch state.
    private var statusSubtitle: String {
        if !watchConnectivity.isPaired { return "Pair an Apple Watch to sync maps" }
        if !watchConnectivity.isWatchAppInstalled { return "Install OpenHiker on your Apple Watch" }
        if watchConnectivity.isReachable { return "Watch app active" }
        return "Background transfers available"
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchConnectivityManager.shared)
}
