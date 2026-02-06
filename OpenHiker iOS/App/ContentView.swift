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
    @State private var regions: [Region] = []

    var body: some View {
        NavigationStack {
            Group {
                if regions.isEmpty {
                    ContentUnavailableView(
                        "No Regions Downloaded",
                        systemImage: "map",
                        description: Text("Select an area on the map to download offline tiles for your Apple Watch.")
                    )
                } else {
                    List {
                        ForEach(regions) { region in
                            RegionRowView(region: region)
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
            loadRegions()
        }
    }

    private func loadRegions() {
        // TODO: Load from persistent storage
    }

    private func deleteRegions(at offsets: IndexSet) {
        // TODO: Delete region files
        regions.remove(atOffsets: offsets)
    }
}

struct RegionRowView: View {
    let region: Region

    var body: some View {
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
        .padding(.vertical, 4)
    }
}

// MARK: - Watch Sync View

struct WatchSyncView: View {
    @EnvironmentObject var watchConnectivity: WatchConnectivityManager

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: watchConnectivity.isReachable ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                            .foregroundStyle(watchConnectivity.isReachable ? .green : .secondary)
                            .font(.title2)

                        VStack(alignment: .leading) {
                            Text(watchConnectivity.isPaired ? "Watch Paired" : "No Watch Paired")
                                .font(.headline)
                            Text(watchConnectivity.isReachable ? "Connected and reachable" : "Not reachable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Connection Status")
                }

                Section {
                    if watchConnectivity.pendingTransfers.isEmpty {
                        Text("No pending transfers")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(watchConnectivity.pendingTransfers, id: \.self) { transfer in
                            HStack {
                                ProgressView()
                                Text("Transferring...")
                                    .font(.caption)
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
}

#Preview {
    ContentView()
        .environmentObject(WatchConnectivityManager.shared)
}
