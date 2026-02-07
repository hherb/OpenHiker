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
/// Presents an adaptive interface that switches layout based on horizontal size class:
/// - **iPhone** (compact width): ``TabView`` with six tabs (unchanged behaviour)
/// - **iPad** (regular width): ``NavigationSplitView`` with a persistent sidebar
///   and a detail column, following Apple's iPad navigation guidelines
///
/// Both layouts expose the same feature set:
/// - **Regions**: Select and download new map regions from OpenTopoMap
/// - **Downloaded**: View, manage, and transfer previously downloaded regions
/// - **Hikes**: Review saved hikes with track overlay, elevation profile, and stats
/// - **Routes**: Plan routes and manage planned routes for watch navigation
/// - **Waypoints**: Browse all waypoints across hikes (iPad sidebar only, embedded in Hikes on iPhone)
/// - **Community**: Browse and download shared routes from the OpenHikerRoutes repository
/// - **Watch**: Monitor Apple Watch connectivity and manage file transfers
struct ContentView: View {
    @EnvironmentObject var watchConnectivity: WatchConnectivityManager

    /// The horizontal size class used to switch between iPhone (compact) and iPad (regular) layouts.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The currently selected tab index (0 = Regions, 1 = Downloaded, 2 = Hikes, 3 = Routes, 4 = Community, 5 = Watch).
    @State private var selectedTab = 0

    /// The currently selected sidebar section on iPad.
    @State private var sidebarSelection: SidebarSection? = .regions

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }

    // MARK: - iPhone Layout (TabView)

    /// The standard iPhone tab-based layout (unchanged from before iPad support was added).
    private var iPhoneLayout: some View {
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

            PlannedRoutesListView(onNavigateToRegions: { selectedTab = 0 })
                .tabItem {
                    Label("Routes", systemImage: "arrow.triangle.turn.up.right.diamond")
                }
                .tag(3)

            CommunityBrowseView()
                .tabItem {
                    Label("Community", systemImage: "globe")
                }
                .tag(4)

            WatchSyncView()
                .tabItem {
                    Label("Watch", systemImage: "applewatch")
                }
                .tag(5)
        }
    }

    // MARK: - iPad Layout (NavigationSplitView)

    /// The iPad sidebar + detail layout using ``NavigationSplitView``.
    ///
    /// The sidebar lists all sections via ``SidebarView``. The detail column
    /// renders the appropriate view for the selected section, each wrapped in
    /// its own ``NavigationStack`` for independent navigation.
    private var iPadLayout: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
        } detail: {
            switch sidebarSelection {
            case .regions:
                NavigationStack {
                    RegionSelectorView()
                }
            case .downloaded:
                NavigationStack {
                    RegionsListView()
                }
            case .hikes:
                NavigationStack {
                    HikesListView()
                }
            case .routes:
                NavigationStack {
                    PlannedRoutesListView(onNavigateToRegions: { sidebarSelection = .regions })
                }
            case .waypoints:
                NavigationStack {
                    WaypointsListView()
                }
            case .community:
                NavigationStack {
                    CommunityBrowseView()
                }
            case .watch:
                NavigationStack {
                    WatchSyncView()
                }
            case nil:
                ContentUnavailableView(
                    "Select a Section",
                    systemImage: "sidebar.left",
                    description: Text("Choose a section from the sidebar.")
                )
            }
        }
    }
}

// MARK: - Planned Routes List View

/// Displays a list of all planned routes with options to plan new routes.
///
/// Each route shows its name, distance, estimated time, and creation date.
/// Tapping a route opens ``RouteDetailView`` for full details and watch transfer.
/// The "+" button opens a region picker so the user can choose a downloaded region
/// (with routing data) before entering ``RoutePlanningView``.
struct PlannedRoutesListView: View {
    @ObservedObject private var routeStore = PlannedRouteStore.shared
    @ObservedObject private var regionStorage = RegionStorage.shared
    @EnvironmentObject var watchConnectivity: WatchConnectivityManager

    /// Closure to navigate the user to the Regions tab for downloading a new region.
    var onNavigateToRegions: () -> Void = {}

    /// The selected region for route planning (needs routing data).
    /// Setting this non-nil triggers the route planning sheet via `.sheet(item:)`.
    @State private var selectedRegion: Region?

    /// Whether the region picker is displayed.
    @State private var showingRegionPicker = false

    /// Regions that have routing data available.
    private var routableRegions: [Region] {
        regionStorage.regions.filter { $0.hasRoutingData }
    }

    /// Regions that have been downloaded but lack routing data.
    private var nonRoutableRegions: [Region] {
        regionStorage.regions.filter { !$0.hasRoutingData }
    }

    var body: some View {
        NavigationStack {
            Group {
                if routeStore.routes.isEmpty {
                    ContentUnavailableView(
                        "No Planned Routes",
                        systemImage: "arrow.triangle.turn.up.right.diamond",
                        description: Text("Plan a route to get turn-by-turn navigation on your Apple Watch.")
                    )
                } else {
                    routesList
                }
            }
            .navigationTitle("Planned Routes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingRegionPicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                routeStore.loadAll()
            }
            .fullScreenCover(item: $selectedRegion) { region in
                RoutePlanningView(region: region)
            }
            .sheet(isPresented: $showingRegionPicker) {
                regionPickerSheet
            }
        }
    }

    /// The list of saved planned routes.
    private var routesList: some View {
        List {
            ForEach(routeStore.routes) { route in
                NavigationLink(destination: RouteDetailView(route: route)) {
                    plannedRouteRow(route)
                }
            }
            .onDelete(perform: deleteRoutes)
        }
    }

    /// A single row in the planned routes list.
    ///
    /// - Parameter route: The planned route to display.
    /// - Returns: A view for the list row.
    private func plannedRouteRow(_ route: PlannedRoute) -> some View {
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
                    HikeStatsFormatter.formatDistance(route.totalDistance, useMetric: true),
                    systemImage: "ruler"
                )
                Spacer()
                Label(route.formattedDuration, systemImage: "clock")
                Spacer()
                Label(
                    "+\(HikeStatsFormatter.formatElevation(route.elevationGain, useMetric: true))",
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

    /// A sheet for picking which downloaded region to plan a route in.
    ///
    /// Handles three cases:
    /// - **No regions at all**: guides the user to download a region first.
    /// - **Regions without routing data**: shows them as disabled with an explanation.
    /// - **Routable regions**: lists them for selection, opening ``RoutePlanningView``.
    private var regionPickerSheet: some View {
        NavigationStack {
            Group {
                if regionStorage.regions.isEmpty {
                    ContentUnavailableView {
                        Label("No Regions Downloaded", systemImage: "map")
                    } description: {
                        Text("Download a map region with routing data enabled before planning a route.")
                    } actions: {
                        Button {
                            showingRegionPicker = false
                            onNavigateToRegions()
                        } label: {
                            Label("Go to Regions", systemImage: "map.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if !routableRegions.isEmpty {
                            Section {
                                ForEach(routableRegions) { region in
                                    Button {
                                        let picked = region
                                        showingRegionPicker = false
                                        // Delay presenting the route planning sheet until the
                                        // region picker sheet has finished dismissing.
                                        // Setting selectedRegion triggers .sheet(item:).
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            selectedRegion = picked
                                        }
                                    } label: {
                                        regionRow(region, enabled: true)
                                    }
                                }
                            } header: {
                                Text("Ready for Route Planning")
                            }
                        }

                        if !nonRoutableRegions.isEmpty {
                            Section {
                                ForEach(nonRoutableRegions) { region in
                                    regionRow(region, enabled: false)
                                }
                            } header: {
                                Text("No Routing Data")
                            } footer: {
                                Text("Re-download these regions with routing enabled to plan routes on them.")
                            }
                        }

                        Section {
                            Button {
                                showingRegionPicker = false
                                onNavigateToRegions()
                            } label: {
                                Label("Download New Region", systemImage: "square.and.arrow.down")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Region")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingRegionPicker = false }
                }
            }
        }
    }

    /// A row displaying region info in the picker sheet.
    ///
    /// - Parameters:
    ///   - region: The region to display.
    ///   - enabled: Whether the region is selectable (has routing data).
    /// - Returns: A styled row view.
    private func regionRow(_ region: Region, enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(region.name)
                    .font(.headline)
                Spacer()
                if enabled {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            HStack {
                Label("\(region.tileCount) tiles", systemImage: "square.grid.3x3")
                Spacer()
                Label(
                    String(format: "%.1f km²", region.areaCoveredKm2),
                    systemImage: "map"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("Zoom \(region.zoomLevels.lowerBound)-\(region.zoomLevels.upperBound)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .opacity(enabled ? 1.0 : 0.5)
    }

    /// Deletes planned routes at the given index offsets.
    ///
    /// Logs and surfaces errors to the user if deletion fails.
    ///
    /// - Parameter offsets: The index positions of the routes to delete.
    private func deleteRoutes(at offsets: IndexSet) {
        for index in offsets {
            let route = routeStore.routes[index]
            do {
                try PlannedRouteStore.shared.delete(id: route.id)
            } catch {
                print("Failed to delete planned route \(route.id): \(error.localizedDescription)")
            }
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

    /// Whether the peer receive sheet is showing.
    @State private var showingPeerReceive = false

    /// Region to send via peer-to-peer transfer (triggers the send sheet).
    @State private var regionToSend: Region?

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
                            .contextMenu {
                                Button {
                                    regionToSend = region
                                } label: {
                                    Label("Share with nearby device", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                        .onDelete(perform: deleteRegions)
                    }
                }
            }
            .navigationTitle("Downloaded Regions")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingPeerReceive = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("Receive from nearby device")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
        .onAppear {
            storage.loadRegions()
        }
        .sheet(isPresented: $showingPeerReceive) {
            PeerReceiveView()
        }
        .sheet(item: $regionToSend) { region in
            PeerSendView(region: region)
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
