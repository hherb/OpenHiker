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
import Combine

// MARK: - Navigation View

/// The main iPhone navigation screen providing turn-by-turn guidance and route recording.
///
/// Presents a full-screen MapKit map with:
/// - Offline OpenTopoMap tile overlay (loaded from downloaded MBTiles regions)
/// - Route polyline overlay for the active planned route
/// - Live GPS position tracking with compass heading
/// - Turn-by-turn instruction overlay (``iOSNavigationOverlay``)
/// - Hike statistics bar with optional watch health data (``iOSHikeStatsBar``)
///
/// ## Modes
/// 1. **Route Navigation**: User selects a planned route and receives turn-by-turn guidance
/// 2. **Free Recording**: User records a track without a pre-planned route
///
/// Both modes track distance, elevation, and duration. When a paired Apple Watch
/// is running a workout, heart rate, SpO2, and UV index are relayed and displayed.
struct iOSNavigationView: View {
    @EnvironmentObject var locationManager: iOSLocationManager
    @EnvironmentObject var routeGuidance: iOSRouteGuidance
    @EnvironmentObject var healthRelay: WatchHealthRelay
    @EnvironmentObject var watchConnectivity: WatchConnectivityManager

    @ObservedObject private var routeStore = PlannedRouteStore.shared
    @ObservedObject private var regionStorage = RegionStorage.shared

    /// The active map display style (Roads / Trails / Cycling).
    /// Defaults to "Roads" (Apple Maps) unless the user is within a downloaded topo region.
    @AppStorage("navigationMapStyle") private var mapViewStyle: MapViewStyle = .standard

    /// Whether the initial map style has been auto-selected based on user location.
    @State private var hasAutoSelectedStyle = false

    /// Whether the route picker sheet is showing.
    @State private var showingRoutePicker = false

    /// Whether the save confirmation alert is showing after stopping tracking.
    @State private var showingSaveConfirmation = false

    /// Whether the GPS mode picker is showing.
    @State private var showingGPSModePicker = false

    /// Whether the map orientation is heads-up (follow heading) or north-up.
    @State private var isHeadingUp = true

    /// Whether a save error alert is showing.
    @State private var showingSaveError = false

    /// The error message for the save error alert.
    @State private var saveErrorMessage = ""

    /// The selected route for navigation (triggers route picker dismissal).
    @State private var selectedRoute: PlannedRoute?

    /// The currently visible map region, captured from `NavigationMapView`.
    @State private var visibleMapRegion: MKCoordinateRegion?

    /// Whether the download config sheet is showing.
    @State private var showingDownloadSheet = false

    /// Region name for download configuration.
    @State private var downloadRegionName = ""

    /// Minimum zoom level for download.
    @State private var downloadMinZoom: Int = 12

    /// Maximum zoom level for download.
    @State private var downloadMaxZoom: Int = 16

    /// Tile server for download, derived from current map style.
    @State private var downloadTileServer: TileDownloader.TileServer = .osmTopo

    /// Whether a tile download is currently in progress.
    @State private var isDownloadingRegion = false

    /// Current download progress.
    @State private var downloadProgress: RegionDownloadProgress?

    /// Any download error to display.
    @State private var downloadError: Error?

    /// Whether the download error alert is showing.
    @State private var showingDownloadError = false

    /// The tile downloader actor for downloading map regions.
    private let tileDownloader = TileDownloader()

    /// Shared elevation data manager for routing graph construction.
    /// Its memory cache is cleared after building the routing graph.
    private let sharedElevationManager = ElevationDataManager()

    /// Active download task, kept for cancellation support.
    @State private var downloadTask: Task<Void, Never>?

    /// Subject for communicating recenter requests to the map view.
    private let recenterSubject = PassthroughSubject<Void, Never>()

    /// User preference for metric or imperial units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    var body: some View {
        NavigationStack {
            ZStack {
                // Map layer
                NavigationMapView(
                    locationManager: locationManager,
                    routeGuidance: routeGuidance,
                    regionStorage: regionStorage,
                    mapStyle: mapViewStyle,
                    isHeadingUp: $isHeadingUp,
                    recenterPublisher: recenterSubject.eraseToAnyPublisher(),
                    visibleRegion: $visibleMapRegion
                )
                .ignoresSafeArea(edges: .top)

                // Overlays
                VStack(spacing: 0) {
                    // Turn-by-turn instruction overlay (top)
                    iOSNavigationOverlay(guidance: routeGuidance)

                    Spacer()

                    // Stats bar (bottom)
                    iOSHikeStatsBar(
                        locationManager: locationManager,
                        healthRelay: healthRelay,
                        watchConnectivity: watchConnectivity
                    )
                }

                // Download progress overlay (shown during active download)
                if isDownloadingRegion, let progress = downloadProgress {
                    VStack {
                        VStack(spacing: 4) {
                            HStack(spacing: 8) {
                                ProgressView(value: progress.progress)
                                    .frame(width: 120)
                                Text("\(Int(progress.progress * 100))%")
                                    .font(.caption.monospacedDigit())
                                Button {
                                    downloadTask?.cancel()
                                    downloadTask = nil
                                    isDownloadingRegion = false
                                    downloadProgress = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(progress.status.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 60)
                        Spacer()
                    }
                }

                // Floating action buttons
                VStack {
                    Spacer()

                    HStack {
                        Spacer()

                        VStack(spacing: 12) {
                            // Download visible region button (hidden during navigation/tracking/download)
                            if !locationManager.isTracking && !routeGuidance.isNavigating && !isDownloadingRegion {
                                mapButton(icon: "arrow.down.circle", color: .green) {
                                    prepareDownload()
                                }
                            }

                            // Compass toggle: heads-up (follow heading) vs north-up
                            mapButton(
                                icon: isHeadingUp ? "location.north.line.fill" : "location.north.line",
                                color: isHeadingUp ? .orange : .secondary
                            ) {
                                isHeadingUp.toggle()
                            }

                            // Recenter button
                            mapButton(icon: "location.fill", color: .blue) {
                                recenterSubject.send()
                            }

                            // GPS mode button
                            mapButton(icon: gpsModeSFSymbol, color: .secondary) {
                                showingGPSModePicker = true
                            }
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 120)
                    }
                }
            }
            .navigationTitle("Navigate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if locationManager.isTracking || routeGuidance.isNavigating {
                        stopButton
                    } else {
                        routePickerButton
                    }
                }

                ToolbarItem(placement: .principal) {
                    Picker("Map Style", selection: $mapViewStyle) {
                        ForEach(MapViewStyle.allCases, id: \.self) { style in
                            Text(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !locationManager.isTracking && !routeGuidance.isNavigating {
                        startTrackingButton
                    }
                }
            }
            .sheet(isPresented: $showingRoutePicker) {
                routePickerSheet
            }
            .confirmationDialog("GPS Accuracy", isPresented: $showingGPSModePicker) {
                ForEach(iOSLocationManager.GPSMode.allCases, id: \.rawValue) { mode in
                    Button(mode.description) {
                        locationManager.gpsMode = mode
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Save Track?", isPresented: $showingSaveConfirmation) {
                Button("Save") {
                    saveCurrentTrack()
                }
                Button("Discard", role: .destructive) {
                    discardTrack()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                let distance = HikeStatsFormatter.formatDistance(
                    locationManager.totalDistance, useMetric: useMetricUnits
                )
                let duration = HikeStatsFormatter.formatDuration(
                    locationManager.duration ?? 0
                )
                Text("You recorded \(distance) in \(duration). Save this hike?")
            }
            .alert("Save Failed", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
            .sheet(isPresented: $showingDownloadSheet) {
                DownloadConfigSheet(
                    region: visibleMapRegion ?? MKCoordinateRegion(),
                    regionName: $downloadRegionName,
                    minZoom: $downloadMinZoom,
                    maxZoom: $downloadMaxZoom,
                    selectedServer: $downloadTileServer,
                    onDownload: startMapDownload
                )
                .presentationDetents([.medium, .large])
            }
            .alert("Download Failed", isPresented: $showingDownloadError) {
                Button("OK", role: .cancel) { downloadError = nil }
            } message: {
                Text(downloadError?.localizedDescription ?? "Unknown error occurred.")
            }
            .onAppear {
                locationManager.requestPermission()
                locationManager.startLocationUpdates()
                routeStore.loadAll()
                autoSelectMapStyleIfNeeded()
            }
            .onDisappear {
                if !locationManager.isTracking {
                    locationManager.stopLocationUpdates()
                }
            }
            .onChange(of: locationManager.currentLocation) { _, newLocation in
                guard let location = newLocation else { return }
                routeGuidance.updateLocation(location)
                autoSelectMapStyleIfNeeded()
            }
        }
    }

    // MARK: - Toolbar Buttons

    /// Button to open the route picker for navigating a planned route.
    private var routePickerButton: some View {
        Button {
            showingRoutePicker = true
        } label: {
            Label("Routes", systemImage: "arrow.triangle.turn.up.right.diamond")
        }
    }

    /// Button to start free-form track recording without a planned route.
    private var startTrackingButton: some View {
        Button {
            locationManager.startTracking()
        } label: {
            Label("Record", systemImage: "record.circle")
        }
        .tint(.red)
    }

    /// Button to stop navigation or track recording.
    private var stopButton: some View {
        Button(role: .destructive) {
            if routeGuidance.isNavigating {
                routeGuidance.stop()
            }
            if locationManager.isTracking {
                locationManager.stopTracking()
                if locationManager.trackPoints.count >= 2 {
                    showingSaveConfirmation = true
                }
            }
        } label: {
            Label("Stop", systemImage: "stop.circle.fill")
        }
        .tint(.red)
    }

    // MARK: - Map Buttons

    /// Creates a floating circular map button.
    ///
    /// - Parameters:
    ///   - icon: SF Symbol name.
    ///   - color: Foreground color.
    ///   - action: Button action closure.
    /// - Returns: A styled circular button view.
    private func mapButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(radius: 2)
        }
    }

    /// SF Symbol name for the current GPS mode.
    private var gpsModeSFSymbol: String {
        switch locationManager.gpsMode {
        case .highAccuracy: return "antenna.radiowaves.left.and.right"
        case .balanced: return "antenna.radiowaves.left.and.right"
        case .lowPower: return "bolt.shield"
        }
    }

    // MARK: - Route Picker Sheet

    /// A sheet for selecting a planned route to navigate.
    private var routePickerSheet: some View {
        NavigationStack {
            Group {
                if routeStore.routes.isEmpty {
                    ContentUnavailableView(
                        "No Planned Routes",
                        systemImage: "arrow.triangle.turn.up.right.diamond",
                        description: Text("Plan a route in the Routes tab to get turn-by-turn navigation.")
                    )
                } else {
                    List(routeStore.routes) { route in
                        Button {
                            startNavigation(route: route)
                            showingRoutePicker = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(route.name)
                                    .font(.headline)
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
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Select Route")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingRoutePicker = false }
                }
            }
        }
    }

    // MARK: - Actions

    /// Starts navigation along the given planned route.
    ///
    /// Begins GPS tracking and activates route guidance simultaneously.
    ///
    /// - Parameter route: The ``PlannedRoute`` to navigate.
    private func startNavigation(route: PlannedRoute) {
        locationManager.startTracking()
        routeGuidance.start(route: route)
    }

    /// Saves the current track as a ``SavedRoute`` and stores it.
    private func saveCurrentTrack() {
        let trackPoints = locationManager.trackPoints
        guard trackPoints.count >= 2,
              let startTime = trackPoints.first?.timestamp,
              let endTime = trackPoints.last?.timestamp else {
            return
        }

        let compressedTrack = TrackCompression.encode(trackPoints)
        let (walkingTime, restingTime) = calculateWalkingRestingTime(trackPoints: trackPoints)

        let savedRoute = SavedRoute(
            name: routeGuidance.activeRoute?.name ?? "Hike \(Date().formatted(date: .abbreviated, time: .shortened))",
            startLatitude: trackPoints[0].coordinate.latitude,
            startLongitude: trackPoints[0].coordinate.longitude,
            endLatitude: trackPoints[trackPoints.count - 1].coordinate.latitude,
            endLongitude: trackPoints[trackPoints.count - 1].coordinate.longitude,
            startTime: startTime,
            endTime: endTime,
            totalDistance: locationManager.totalDistance,
            elevationGain: locationManager.elevationGain,
            elevationLoss: locationManager.elevationLoss,
            walkingTime: walkingTime,
            restingTime: restingTime,
            averageHeartRate: healthRelay.averageHeartRate,
            trackData: compressedTrack
        )

        do {
            try RouteStore.shared.insert(savedRoute)
            print("Saved navigation track: \(savedRoute.name)")
        } catch {
            print("Error saving track: \(error.localizedDescription)")
            saveErrorMessage = "Could not save your hike: \(error.localizedDescription)"
            showingSaveError = true
        }
    }

    /// Discards the current recorded track without saving.
    private func discardTrack() {
        locationManager.trackPoints.removeAll()
        print("Discarded navigation track")
    }

    // MARK: - Map Region Download

    /// Prepares and shows the download config sheet for the currently visible map region.
    ///
    /// Sets default values for region name, zoom levels, and tile server based on the
    /// current map style. The tile server defaults to the one matching the active map style.
    private func prepareDownload() {
        guard visibleMapRegion != nil else { return }
        downloadRegionName = ""
        downloadMinZoom = 12
        downloadMaxZoom = 16
        downloadTileServer = mapViewStyle.defaultDownloadServer
        showingDownloadSheet = true
    }

    /// Downloads the currently visible map region with tiles and routing data.
    ///
    /// Creates a ``RegionSelectionRequest`` from the visible map region and the
    /// download configuration, then delegates to ``TileDownloader`` for tile download.
    /// After tiles are downloaded, builds a routing graph (OSM trail data + elevation)
    /// using the same process as ``RegionSelectorView``. On success, the region is saved
    /// to ``RegionStorage`` and auto-transferred to the paired Apple Watch if connected.
    /// The map style is switched to "Trails" so the downloaded offline tiles are used.
    private func startMapDownload() {
        guard let region = visibleMapRegion else { return }

        let boundingBox = BoundingBox(
            north: region.center.latitude + region.span.latitudeDelta / 2,
            south: region.center.latitude - region.span.latitudeDelta / 2,
            east: region.center.longitude + region.span.longitudeDelta / 2,
            west: region.center.longitude - region.span.longitudeDelta / 2
        )

        let request = RegionSelectionRequest(
            name: downloadRegionName.isEmpty
                ? "Region \(Date().formatted(date: .abbreviated, time: .omitted))"
                : downloadRegionName,
            boundingBox: boundingBox,
            zoomLevels: downloadMinZoom...downloadMaxZoom
        )

        showingDownloadSheet = false
        isDownloadingRegion = true

        downloadTask = Task {
            do {
                var totalTiles = 0
                let mbtilesURL = try await tileDownloader.downloadRegion(
                    request, server: downloadTileServer
                ) { progress in
                    totalTiles = progress.totalTiles
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }

                // Build routing graph if requested (default: true)
                var routingDataBuilt = false
                if request.includeRoutingData {
                    routingDataBuilt = await buildRoutingGraph(
                        boundingBox: boundingBox,
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

                    // Transfer to watch if connected
                    if watchConnectivity.isPaired {
                        let metadata = regionStorage.metadata(for: savedRegion)
                        watchConnectivity.transferMBTilesFile(at: mbtilesURL, metadata: metadata)
                    }

                    // Switch to Trails style so downloaded offline tiles are used
                    if mapViewStyle == .standard {
                        mapViewStyle = .hiking
                    }

                    isDownloadingRegion = false
                    downloadProgress = nil
                    downloadTask = nil
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        isDownloadingRegion = false
                        downloadProgress = nil
                        downloadError = error
                        showingDownloadError = true
                        downloadTask = nil
                    }
                }
            }
        }
    }

    /// Downloads OSM trail data, elevation data, and builds a routing graph for the region.
    ///
    /// Called after tile download completes when `includeRoutingData` is enabled.
    /// If the routing build fails, the error is logged but the download is not considered
    /// failed — the user still gets their map tiles, just without route planning.
    ///
    /// - Parameters:
    ///   - boundingBox: The geographic area for trail data and routing.
    ///   - mbtilesURL: The downloaded MBTiles file URL (used to derive the region UUID).
    ///   - totalTiles: Total tile count for progress reporting.
    /// - Returns: `true` if the routing graph was built successfully, `false` otherwise.
    private func buildRoutingGraph(
        boundingBox: BoundingBox,
        mbtilesURL: URL,
        totalTiles: Int
    ) async -> Bool {
        let regionIdString = mbtilesURL.deletingPathExtension().lastPathComponent
        let regionId = UUID(uuidString: regionIdString) ?? UUID()
        let routingDbURL = regionStorage.routingDbURL(
            for: Region(
                id: regionId,
                name: "",
                boundingBox: boundingBox,
                zoomLevels: 0...0,
                tileCount: 0,
                fileSizeBytes: 0
            )
        )

        do {
            // Step 1: Download and parse OSM trail data.
            await MainActor.run {
                self.downloadProgress = RegionDownloadProgress(
                    regionId: regionId,
                    totalTiles: totalTiles,
                    downloadedTiles: totalTiles,
                    currentZoom: 0,
                    status: .downloadingTrailData
                )
            }

            let nodes: [Int64: PBFParser.OSMNode]
            let ways: [PBFParser.OSMWay]
            do {
                let osmDownloader = OSMDataDownloader()
                (nodes, ways) = try await osmDownloader.downloadAndParseTrailData(
                    boundingBox: boundingBox
                ) { _, _ in }
            }

            // Step 2: Build routing graph (elevation is fetched internally by the builder).
            await MainActor.run {
                self.downloadProgress = RegionDownloadProgress(
                    regionId: regionId,
                    totalTiles: totalTiles,
                    downloadedTiles: totalTiles,
                    currentZoom: 0,
                    status: .buildingRoutingGraph
                )
            }

            let graphBuilder = RoutingGraphBuilder()
            try await graphBuilder.buildGraph(
                ways: ways,
                nodes: nodes,
                elevationManager: sharedElevationManager,
                outputPath: routingDbURL.path,
                boundingBox: boundingBox
            ) { _, _ in }

            // Release elevation tile memory cache now that graph is built
            await sharedElevationManager.clearMemoryCache()

            print("Routing graph built successfully: \(routingDbURL.path)")
            return true
        } catch {
            print("Routing graph build failed (non-fatal): \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: routingDbURL)
            return false
        }
    }

    // MARK: - Map Style Auto-Selection

    /// Checks if the user's current location is within any downloaded region.
    ///
    /// If so, defaults to the "Trails" map style so offline topo tiles are shown.
    /// Otherwise keeps the current style (defaults to "Roads" / Apple Maps).
    /// Only runs once per view appearance to avoid overriding manual user choice.
    private func autoSelectMapStyleIfNeeded() {
        guard !hasAutoSelectedStyle else { return }
        hasAutoSelectedStyle = true

        guard let location = locationManager.currentLocation else {
            // Re-check when location becomes available
            hasAutoSelectedStyle = false
            return
        }

        let isWithinRegion = regionStorage.regions.contains { region in
            region.boundingBox.contains(location.coordinate)
        }

        if isWithinRegion && mapViewStyle == .standard {
            mapViewStyle = .hiking
        }
    }

    // MARK: - Track Statistics

    /// Calculates walking and resting time from recorded track points.
    ///
    /// A point-to-point speed below ``HikeStatisticsConfig/restingSpeedThreshold``
    /// counts as resting; otherwise it counts as walking.
    ///
    /// - Parameter trackPoints: The recorded GPS locations.
    /// - Returns: A tuple of (walkingTime, restingTime) in seconds.
    private func calculateWalkingRestingTime(trackPoints: [CLLocation]) -> (TimeInterval, TimeInterval) {
        guard trackPoints.count > 1 else { return (0, 0) }

        var walking: TimeInterval = 0
        var resting: TimeInterval = 0

        for i in 1..<trackPoints.count {
            let distance = trackPoints[i].distance(from: trackPoints[i - 1])
            let timeDelta = trackPoints[i].timestamp.timeIntervalSince(trackPoints[i - 1].timestamp)

            guard timeDelta > 0 else { continue }

            let speed = distance / timeDelta
            if speed >= HikeStatisticsConfig.restingSpeedThreshold {
                walking += timeDelta
            } else {
                resting += timeDelta
            }
        }

        return (walking, resting)
    }
}

// MARK: - MBTiles Tile Overlay

/// A MapKit tile overlay that reads tiles from a local MBTiles SQLite database.
///
/// Used to render offline OpenTopoMap tiles on the iPhone navigation map.
/// The overlay loads tile data from ``TileStore`` instances opened for each
/// downloaded region.
final class NavigationTileOverlay: MKTileOverlay {

    /// The tile stores for all available downloaded regions.
    private let tileStores: [TileStore]

    /// Creates a tile overlay from the downloaded regions.
    ///
    /// - Parameter regions: The downloaded regions with their MBTiles files.
    init(regions: [Region]) {
        var stores: [TileStore] = []
        let storage = RegionStorage.shared

        for region in regions {
            let url = storage.mbtilesURL(for: region)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            let store = TileStore(path: url.path)
            do {
                try store.open()
                stores.append(store)
            } catch {
                print("Failed to open TileStore for region \(region.name): \(error.localizedDescription)")
            }
        }

        self.tileStores = stores
        super.init(urlTemplate: nil)
        self.canReplaceMapContent = true
        self.minimumZ = 1
        self.maximumZ = 17
    }

    deinit {
        for store in tileStores {
            store.close()
        }
    }

    /// Loads tile data from the local MBTiles database.
    ///
    /// Searches all open tile stores for a matching tile and returns the first
    /// result found. If no tile is available, returns an error.
    ///
    /// MapKit provides tile coordinates in standard XYZ (slippy map) convention.
    /// ``TileStore/getTile(_:)`` handles the TMS y-flip internally, so we pass
    /// the XYZ coordinates through unchanged.
    override func loadTile(
        at path: MKTileOverlayPath,
        result: @escaping (Data?, Error?) -> Void
    ) {
        // Pass XYZ coordinates directly — TileStore.getTile() handles TMS conversion
        let coordinate = TileCoordinate(x: path.x, y: path.y, z: path.z)

        for store in tileStores {
            if let data = try? store.getTile(coordinate) {
                result(data, nil)
                return
            }
        }

        // No tile found — return error so MapKit falls back to default tiles
        result(nil, TileStoreError.tileNotFound)
    }
}

// MARK: - Navigation Map View (UIKit Bridge)

/// A `UIViewRepresentable` wrapping `MKMapView` for the navigation map.
///
/// Provides tile overlay rendering (Apple Maps, OpenTopoMap, or CyclOSM),
/// offline MBTiles overlay from downloaded regions, route polyline,
/// user location tracking, and recorded track visualization.
struct NavigationMapView: UIViewRepresentable {
    @ObservedObject var locationManager: iOSLocationManager
    @ObservedObject var routeGuidance: iOSRouteGuidance
    @ObservedObject var regionStorage: RegionStorage

    /// The current map display style (Roads / Trails / Cycling).
    let mapStyle: MapViewStyle

    /// Whether the map should follow the user's heading (heads-up) or stay north-up.
    @Binding var isHeadingUp: Bool

    /// Publisher that emits when the user taps the recenter button.
    let recenterPublisher: AnyPublisher<Void, Never>

    /// The currently visible map region, updated when the user pans or zooms.
    @Binding var visibleRegion: MKCoordinateRegion?

    /// Creates and configures the MKMapView.
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = isHeadingUp ? .followWithHeading : .follow
        // Show MapKit compass only in heads-up mode (it indicates current heading)
        mapView.showsCompass = isHeadingUp
        mapView.showsScale = true

        // Add tile overlays based on current style
        applyMapStyle(to: mapView, coordinator: context.coordinator)

        // Subscribe to recenter requests
        context.coordinator.recenterCancellable = recenterPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak mapView] in
                guard let mapView = mapView else { return }
                let mode: MKUserTrackingMode = self.isHeadingUp ? .followWithHeading : .follow
                mapView.setUserTrackingMode(mode, animated: true)
            }

        return mapView
    }

    /// Updates the map overlays and tracking mode when state changes.
    func updateUIView(_ mapView: MKMapView, context: Context) {
        updateMapStyleIfNeeded(on: mapView, coordinator: context.coordinator)
        updateRouteOverlay(on: mapView, coordinator: context.coordinator)
        updateTrackOverlay(on: mapView, coordinator: context.coordinator)
        updateOfflineTileOverlay(on: mapView, coordinator: context.coordinator)

        // Sync heading mode and compass visibility with toggle state
        let desiredMode: MKUserTrackingMode = isHeadingUp ? .followWithHeading : .follow
        if mapView.userTrackingMode != desiredMode {
            mapView.setUserTrackingMode(desiredMode, animated: true)
        }
        mapView.showsCompass = isHeadingUp
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Map Style Management

    /// Applies the current map style by adding the appropriate tile overlays.
    ///
    /// - For "Roads": no tile overlay (Apple Maps default)
    /// - For "Trails"/"Cycling": adds an online tile overlay, plus offline tiles on top
    private func applyMapStyle(to mapView: MKMapView, coordinator: Coordinator) {
        coordinator.lastMapStyle = mapStyle

        if let tileTemplate = mapStyle.tileURLTemplate {
            // Online tile overlay (OpenTopoMap or CyclOSM)
            let onlineOverlay = MKTileOverlay(urlTemplate: tileTemplate)
            onlineOverlay.canReplaceMapContent = true
            onlineOverlay.minimumZ = 1
            onlineOverlay.maximumZ = 18
            onlineOverlay.tileSize = CGSize(width: 256, height: 256)
            mapView.addOverlay(onlineOverlay, level: .aboveLabels)
            coordinator.onlineTileOverlay = onlineOverlay
        }

        // Add offline MBTiles overlay on top for downloaded regions
        addOfflineTileOverlay(to: mapView, coordinator: coordinator)
    }

    /// Detects map style changes and swaps overlays accordingly.
    private func updateMapStyleIfNeeded(on mapView: MKMapView, coordinator: Coordinator) {
        guard mapStyle != coordinator.lastMapStyle else { return }

        // Remove existing tile overlays
        if let onlineOverlay = coordinator.onlineTileOverlay {
            mapView.removeOverlay(onlineOverlay)
            coordinator.onlineTileOverlay = nil
        }
        if let offlineOverlay = coordinator.offlineTileOverlay {
            mapView.removeOverlay(offlineOverlay)
            coordinator.offlineTileOverlay = nil
        }

        // Apply new style
        applyMapStyle(to: mapView, coordinator: coordinator)
    }

    // MARK: - Offline Tile Overlay

    /// Adds the offline MBTiles tile overlay from downloaded regions.
    ///
    /// Only added when map style is "Trails" or "Cycling" — offline tiles are layered
    /// on top of the online overlay to provide seamless coverage in areas with downloads.
    /// In "Roads" mode, Apple Maps is used without any tile overlay.
    private func addOfflineTileOverlay(to mapView: MKMapView, coordinator: Coordinator) {
        // Only overlay offline tiles when using a tile-based style
        guard mapStyle.tileURLTemplate != nil else { return }

        let regions = regionStorage.regions
        guard !regions.isEmpty else { return }

        let overlay = NavigationTileOverlay(regions: regions)
        overlay.canReplaceMapContent = false
        mapView.addOverlay(overlay, level: .aboveLabels)
        coordinator.offlineTileOverlay = overlay
    }

    /// Refreshes the offline tile overlay when downloaded regions change.
    private func updateOfflineTileOverlay(on mapView: MKMapView, coordinator: Coordinator) {
        let currentCount = regionStorage.regions.count
        guard currentCount != coordinator.lastRegionCount else { return }
        coordinator.lastRegionCount = currentCount

        // Remove existing offline overlay
        if let existing = coordinator.offlineTileOverlay {
            mapView.removeOverlay(existing)
            coordinator.offlineTileOverlay = nil
        }

        // Add updated offline overlay
        addOfflineTileOverlay(to: mapView, coordinator: coordinator)
    }

    /// Updates the route polyline overlay for the active planned route.
    private func updateRouteOverlay(on mapView: MKMapView, coordinator: Coordinator) {
        // Remove existing route overlay
        if let existing = coordinator.routeOverlay {
            mapView.removeOverlay(existing)
            coordinator.routeOverlay = nil
        }

        // Add new route overlay if navigating
        guard let route = routeGuidance.activeRoute, !route.coordinates.isEmpty else { return }

        var coordinates = route.coordinates
        let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
        coordinator.routeOverlay = polyline
        mapView.addOverlay(polyline, level: .aboveRoads)
    }

    /// Updates the recorded track overlay.
    private func updateTrackOverlay(on mapView: MKMapView, coordinator: Coordinator) {
        // Remove existing track overlay
        if let existing = coordinator.trackOverlay {
            mapView.removeOverlay(existing)
            coordinator.trackOverlay = nil
        }

        // Add track overlay if recording
        guard locationManager.isTracking, locationManager.trackPoints.count >= 2 else { return }

        var coords = locationManager.trackPoints.map { $0.coordinate }
        let polyline = MKPolyline(coordinates: &coords, count: coords.count)
        coordinator.trackOverlay = polyline
        mapView.addOverlay(polyline, level: .aboveRoads)
    }

    // MARK: - Coordinator

    /// MapKit delegate coordinator for rendering overlays.
    final class Coordinator: NSObject, MKMapViewDelegate {
        let parent: NavigationMapView

        /// The current route polyline overlay.
        var routeOverlay: MKPolyline?

        /// The current recorded track polyline overlay.
        var trackOverlay: MKPolyline?

        /// The online tile overlay (OpenTopoMap or CyclOSM), or `nil` for Apple Maps.
        var onlineTileOverlay: MKTileOverlay?

        /// The offline MBTiles tile overlay from downloaded regions.
        var offlineTileOverlay: NavigationTileOverlay?

        /// The last applied map style, used to detect style changes.
        var lastMapStyle: MapViewStyle = .standard

        /// Tracks the last known region count to detect changes.
        var lastRegionCount: Int = 0

        /// Subscription for recenter requests.
        var recenterCancellable: AnyCancellable?

        init(parent: NavigationMapView) {
            self.parent = parent
        }

        /// Captures the visible map region when the user finishes panning or zooming.
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.visibleRegion = mapView.region
        }

        /// Provides renderers for map overlays.
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(overlay: tileOverlay)
            }

            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)

                if polyline === routeOverlay {
                    // Planned route: purple with some transparency
                    renderer.strokeColor = UIColor.systemPurple.withAlphaComponent(0.8)
                    renderer.lineWidth = 5
                } else if polyline === trackOverlay {
                    // Recorded track: blue
                    renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.9)
                    renderer.lineWidth = 4
                } else {
                    renderer.strokeColor = UIColor.systemBlue
                    renderer.lineWidth = 3
                }

                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
