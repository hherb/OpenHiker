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
import MapKit
import CoreLocation

/// macOS view for selecting and downloading offline map regions.
///
/// Provides a full-width interactive map where users can:
/// 1. Browse the map and search for locations
/// 2. Click "Select Area" to capture the visible region
/// 3. Configure download options (zoom levels, tile server, region name)
/// 4. Download tiles into an MBTiles database with optional routing data
///
/// Uses the same ``TileDownloader`` and ``RegionStorage`` as the iOS version.
/// Downloaded regions sync to iPhone/Watch via iCloud.
struct MacRegionSelectorView: View {

    // MARK: - Layout Constants

    /// Minimum width of the map section in the split view.
    private static let mapSectionMinWidth: CGFloat = 500

    /// Width of the download configuration side panel.
    private static let downloadPanelWidth: CGFloat = 300

    /// Width of the search popover.
    private static let searchPopoverWidth: CGFloat = 320

    /// Height of the search popover.
    private static let searchPopoverHeight: CGFloat = 400

    /// Maximum width of the progress card overlay.
    private static let progressCardMaxWidth: CGFloat = 400

    /// Opacity of the selected region polygon fill.
    private static let selectionFillOpacity: Double = 0.15

    /// Fraction of the visible map area captured as the download region.
    private static let selectionScaleFactor: Double = 0.6

    /// Default span (in degrees) for the map after a search result selection.
    private static let searchResultSpan: Double = 0.2

    /// Average tile size in bytes, used for download size estimation.
    private static let averageTileSizeBytes: Int64 = 15_000

    /// Corner radius for card-style overlays.
    private static let cardCornerRadius: CGFloat = 12

    /// Maximum zoom level supported by tile servers.
    private static let absoluteMaxZoom: Int = 18

    /// Minimum zoom level for region downloads.
    private static let absoluteMinZoom: Int = 8

    // MARK: - Map State

    /// The current map camera position (region, center, zoom).
    @State private var cameraPosition: MapCameraPosition = .automatic

    /// The map coordinate region selected for download.
    @State private var selectedRegion: MKCoordinateRegion?

    // MARK: - Download State

    /// Whether the download config panel is shown.
    @State private var showDownloadConfig = false

    /// The user-entered name for the region.
    @State private var regionName = ""

    /// Whether a tile download is in progress.
    @State private var isDownloading = false

    /// Current download progress.
    @State private var downloadProgress: RegionDownloadProgress?

    /// Any error from the most recent download.
    @State private var downloadError: Error?

    /// Whether the error alert is shown.
    @State private var showError = false

    /// Minimum zoom level for downloads.
    @State private var minZoom: Int = 12

    /// Maximum zoom level for downloads.
    @State private var maxZoom: Int = 16

    /// The tile server for downloading.
    @State private var selectedTileServer: TileDownloader.TileServer = .osmTopo

    // MARK: - Search State

    /// Whether the search popover is shown.
    @State private var showSearch = false

    /// The search query text.
    @State private var searchText = ""

    /// Search results from MKLocalSearch.
    @State private var searchResults: [MKMapItem] = []

    /// Whether a search is in progress.
    @State private var isSearching = false

    // MARK: - Persisted State

    /// Last viewed latitude, restored on launch.
    @AppStorage("lastLatitude") private var lastLatitude: Double = 37.8651

    /// Last viewed longitude, restored on launch.
    @AppStorage("lastLongitude") private var lastLongitude: Double = -119.5383

    /// Last viewed span (zoom), restored on launch.
    @AppStorage("lastSpan") private var lastSpan: Double = 0.5

    // MARK: - Services

    /// The tile downloader actor for downloading map tiles.
    private let tileDownloader = TileDownloader()

    /// Shared region storage for managing downloaded regions.
    @ObservedObject private var regionStorage = RegionStorage.shared

    // MARK: - Body

    var body: some View {
        HSplitView {
            mapSection
                .frame(minWidth: Self.mapSectionMinWidth)

            if showDownloadConfig, selectedRegion != nil {
                downloadConfigPanel
                    .frame(width: Self.downloadPanelWidth)
            }
        }
        .navigationTitle("Select Region")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showSearch.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Search for a location (⌘F)")
                .keyboardShortcut("f", modifiers: .command)
                .popover(isPresented: $showSearch) {
                    searchPopover
                        .frame(width: Self.searchPopoverWidth, height: Self.searchPopoverHeight)
                }

                Button(selectedRegion != nil ? "Clear Selection" : "Select Visible Area") {
                    if selectedRegion != nil {
                        selectedRegion = nil
                        showDownloadConfig = false
                    } else {
                        captureVisibleRegion()
                    }
                }
                .disabled(isDownloading)

                if selectedRegion != nil && !showDownloadConfig {
                    Button("Download...") {
                        showDownloadConfig = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear {
            let center = CLLocationCoordinate2D(latitude: lastLatitude, longitude: lastLongitude)
            cameraPosition = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: lastSpan, longitudeDelta: lastSpan)
            ))
        }
        .alert("Download Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloadError?.localizedDescription ?? "Unknown error")
        }
    }

    // MARK: - Map Section

    /// The main map view with selection overlay and progress indicator.
    private var mapSection: some View {
        ZStack {
            Map(position: $cameraPosition) {
                if let region = selectedRegion {
                    MapPolygon(coordinates: regionCorners(region))
                        .foregroundStyle(.blue.opacity(Self.selectionFillOpacity))
                        .stroke(.blue, lineWidth: 2)
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange { context in
                lastLatitude = context.region.center.latitude
                lastLongitude = context.region.center.longitude
                lastSpan = context.region.span.latitudeDelta
            }

            VStack {
                Spacer()

                if isDownloading, let progress = downloadProgress {
                    downloadProgressCard(progress)
                        .frame(maxWidth: Self.progressCardMaxWidth)
                        .padding()
                } else if selectedRegion == nil {
                    instructionsCard
                        .padding()
                }
            }
        }
    }

    /// Instructions shown when no region is selected.
    private var instructionsCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.dashed")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Navigate to your hiking area")
                    .font(.headline)
                Text("Then click \"Select Visible Area\" in the toolbar to capture the region for download.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Self.cardCornerRadius))
    }

    /// Download progress indicator overlay.
    private func downloadProgressCard(_ progress: RegionDownloadProgress) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downloading...")
                        .font(.headline)
                    Text(progress.status.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Zoom level \(progress.currentZoom) • \(progress.downloadedTiles)/\(progress.totalTiles) tiles")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if progress.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.green)
                } else {
                    ProgressView()
                }
            }
            ProgressView(value: progress.progress)
                .tint(.blue)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Self.cardCornerRadius))
    }

    // MARK: - Download Config Panel

    /// Side panel for configuring download options.
    private var downloadConfigPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Download Options")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Region name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Region Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g., Yosemite Valley", text: $regionName)
                        .textFieldStyle(.roundedBorder)
                }

                // Map source
                VStack(alignment: .leading, spacing: 4) {
                    Text("Map Source")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $selectedTileServer) {
                        Text("OpenTopoMap (Hiking)").tag(TileDownloader.TileServer.osmTopo)
                        Text("CyclOSM (Cycling)").tag(TileDownloader.TileServer.cyclosm)
                        Text("OpenStreetMap").tag(TileDownloader.TileServer.osmStandard)
                    }
                    .labelsHidden()
                }

                // Zoom levels
                VStack(alignment: .leading, spacing: 4) {
                    Text("Zoom Levels")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper("Min: \(minZoom)", value: $minZoom, in: Self.absoluteMinZoom...maxZoom)
                    Stepper("Max: \(maxZoom)", value: $maxZoom, in: minZoom...Self.absoluteMaxZoom)
                }

                // Estimates
                if let region = selectedRegion {
                    let bb = boundingBox(from: region)
                    let tiles = bb.estimateTileCount(zoomLevels: minZoom...maxZoom)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Estimate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Label("~\(tiles) tiles", systemImage: "square.grid.3x3")
                            Spacer()
                            Text("~\(ByteCountFormatter.string(fromByteCount: Int64(tiles) * Self.averageTileSizeBytes, countStyle: .file))")
                        }
                        .font(.caption)

                        Text("\(String(format: "%.1f", bb.areaKm2)) km²")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Download button
                Button {
                    startDownload()
                } label: {
                    HStack {
                        Spacer()
                        Label("Download Region", systemImage: "arrow.down.circle")
                            .font(.headline)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isDownloading)

                // Cancel button
                Button("Cancel") {
                    showDownloadConfig = false
                    selectedRegion = nil
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }

    // MARK: - Search Popover

    /// Location search popover with auto-complete.
    private var searchPopover: some View {
        VStack(spacing: 0) {
            TextField("Search for a place...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()
                .onSubmit {
                    performSearch()
                }

            if isSearching {
                ProgressView()
                    .padding()
            }

            List(searchResults, id: \.self) { item in
                Button {
                    if let location = item.placemark.location {
                        showSearch = false
                        searchText = ""
                        searchResults = []
                        withAnimation {
                            cameraPosition = .region(MKCoordinateRegion(
                                center: location.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: Self.searchResultSpan, longitudeDelta: Self.searchResultSpan)
                            ))
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? "Unknown")
                            .foregroundStyle(.primary)
                        if let address = item.placemark.title {
                            Text(address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    /// Captures the currently visible map region as the selection.
    private func captureVisibleRegion() {
        guard let visibleRegion = cameraPosition.region else { return }

        // Use 60% of the visible area as the selection
        let scaleFactor = Self.selectionScaleFactor
        selectedRegion = MKCoordinateRegion(
            center: visibleRegion.center,
            span: MKCoordinateSpan(
                latitudeDelta: visibleRegion.span.latitudeDelta * scaleFactor,
                longitudeDelta: visibleRegion.span.longitudeDelta * scaleFactor
            )
        )
        showDownloadConfig = true
    }

    /// Initiates a tile download for the selected region.
    private func startDownload() {
        guard let region = selectedRegion else { return }

        let bb = boundingBox(from: region)
        let request = RegionSelectionRequest(
            name: regionName.isEmpty ? "Region \(Date().formatted(date: .abbreviated, time: .omitted))" : regionName,
            boundingBox: bb,
            zoomLevels: minZoom...maxZoom
        )

        showDownloadConfig = false
        isDownloading = true
        selectedRegion = nil

        Task {
            do {
                var totalTiles = 0
                let mbtilesURL = try await tileDownloader.downloadRegion(request, server: selectedTileServer) { progress in
                    totalTiles = progress.totalTiles
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }

                // Build routing graph
                var routingDataBuilt = false
                if request.includeRoutingData {
                    routingDataBuilt = await buildRoutingGraph(
                        boundingBox: bb,
                        mbtilesURL: mbtilesURL,
                        totalTiles: totalTiles
                    )
                }

                await MainActor.run {
                    let savedRegion = regionStorage.createRegion(
                        from: request,
                        mbtilesURL: mbtilesURL,
                        tileCount: totalTiles,
                        hasRoutingData: routingDataBuilt
                    )
                    regionStorage.saveRegion(savedRegion)

                    // Trigger iCloud sync so iPhone can forward to watch
                    Task {
                        await CloudSyncManager.shared.performSync()
                    }

                    isDownloading = false
                    downloadProgress = nil
                    regionName = ""
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    downloadError = error
                    showError = true
                }
            }
        }
    }

    /// Builds a routing graph from OSM trail data for the downloaded region.
    ///
    /// Non-fatal — if this fails, the region is still usable for map viewing,
    /// just without route planning capability.
    private func buildRoutingGraph(
        boundingBox: BoundingBox,
        mbtilesURL: URL,
        totalTiles: Int
    ) async -> Bool {
        let regionIdString = mbtilesURL.deletingPathExtension().lastPathComponent
        let regionId = UUID(uuidString: regionIdString) ?? UUID()
        let routingDbURL = regionStorage.routingDbURL(
            for: Region(
                id: regionId, name: "", boundingBox: boundingBox,
                zoomLevels: 0...0, tileCount: 0, fileSizeBytes: 0
            )
        )

        do {
            await MainActor.run {
                self.downloadProgress = RegionDownloadProgress(
                    regionId: regionId, totalTiles: totalTiles,
                    downloadedTiles: totalTiles, currentZoom: 0,
                    status: .downloadingTrailData
                )
            }

            let osmDownloader = OSMDataDownloader()
            let (nodes, ways) = try await osmDownloader.downloadAndParseTrailData(
                boundingBox: boundingBox
            ) { _, _ in }

            await MainActor.run {
                self.downloadProgress = RegionDownloadProgress(
                    regionId: regionId, totalTiles: totalTiles,
                    downloadedTiles: totalTiles, currentZoom: 0,
                    status: .buildingRoutingGraph
                )
            }

            let graphBuilder = RoutingGraphBuilder()
            let elevationManager = ElevationDataManager()
            try await graphBuilder.buildGraph(
                ways: ways, nodes: nodes, elevationManager: elevationManager,
                outputPath: routingDbURL.path, boundingBox: boundingBox
            ) { _, _ in }

            return true
        } catch {
            print("Routing graph build failed (non-fatal): \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: routingDbURL)
            return false
        }
    }

    /// Performs a location search using MKLocalSearch.
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        isSearching = true

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText

        let search = MKLocalSearch(request: request)
        search.start { response, error in
            isSearching = false
            if let response = response {
                searchResults = response.mapItems
            }
        }
    }

    // MARK: - Helpers

    /// Converts a map region to a ``BoundingBox``.
    private func boundingBox(from region: MKCoordinateRegion) -> BoundingBox {
        BoundingBox(
            north: region.center.latitude + region.span.latitudeDelta / 2,
            south: region.center.latitude - region.span.latitudeDelta / 2,
            east: region.center.longitude + region.span.longitudeDelta / 2,
            west: region.center.longitude - region.span.longitudeDelta / 2
        )
    }

    /// Calculates the four corner coordinates of a region for polygon rendering.
    private func regionCorners(_ region: MKCoordinateRegion) -> [CLLocationCoordinate2D] {
        let latDelta = region.span.latitudeDelta / 2
        let lonDelta = region.span.longitudeDelta / 2
        let center = region.center
        return [
            CLLocationCoordinate2D(latitude: center.latitude + latDelta, longitude: center.longitude - lonDelta),
            CLLocationCoordinate2D(latitude: center.latitude + latDelta, longitude: center.longitude + lonDelta),
            CLLocationCoordinate2D(latitude: center.latitude - latDelta, longitude: center.longitude + lonDelta),
            CLLocationCoordinate2D(latitude: center.latitude - latDelta, longitude: center.longitude - lonDelta),
        ]
    }
}
