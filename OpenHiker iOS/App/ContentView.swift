import SwiftUI

struct ContentView: View {
    @EnvironmentObject var watchConnectivity: WatchConnectivityManager
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

            WatchSyncView()
                .tabItem {
                    Label("Watch", systemImage: "applewatch")
                }
                .tag(2)
        }
    }
}

// MARK: - Downloaded Regions List

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

    private func deleteRegions(at offsets: IndexSet) {
        storage.deleteRegions(at: offsets)
    }

    private func transferToWatch(_ region: Region) {
        let mbtilesURL = storage.mbtilesURL(for: region)
        let metadata = storage.metadata(for: region)
        watchConnectivity.transferMBTilesFile(at: mbtilesURL, metadata: metadata)
    }
}

struct RegionRowView: View {
    let region: Region
    let onTransfer: () -> Void
    @EnvironmentObject var watchConnectivity: WatchConnectivityManager

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

    private var statusIcon: String {
        if !watchConnectivity.isPaired { return "applewatch.slash" }
        if !watchConnectivity.isWatchAppInstalled { return "applewatch.slash" }
        if watchConnectivity.isReachable { return "applewatch.radiowaves.left.and.right" }
        return "applewatch"
    }

    private var statusColor: Color {
        if !watchConnectivity.isPaired || !watchConnectivity.isWatchAppInstalled { return .secondary }
        return .green
    }

    private var statusTitle: String {
        if !watchConnectivity.isPaired { return "No Watch Paired" }
        if !watchConnectivity.isWatchAppInstalled { return "Watch App Not Installed" }
        return "Watch Ready"
    }

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
