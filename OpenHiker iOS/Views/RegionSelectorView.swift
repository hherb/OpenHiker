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

#if os(iOS)
import SwiftUI
import MapKit
import CoreLocation

/// The main map view for selecting and downloading offline map regions on iOS.
///
/// Users interact with this view to:
/// 1. Browse an interactive MapKit map of the world
/// 2. Search for locations by name
/// 3. Draw a selection rectangle over the area they want to download
/// 4. Configure download options (zoom levels, region name)
/// 5. Initiate tile downloads from OpenTopoMap
///
/// The view persists the last-viewed map position via `@AppStorage` so users
/// return to their previous location on relaunch. Downloaded regions are automatically
/// transferred to the paired Apple Watch if connected.
struct RegionSelectorView: View {
    /// The current map camera position (region, center, and zoom).
    @State private var cameraPosition: MapCameraPosition = .automatic

    /// The rectangle drawn by the user during area selection (in screen coordinates).
    @State private var selectionRect: CGRect?

    /// Whether the user is currently in "select area" mode.
    @State private var isSelecting = false

    /// The map coordinate region derived from the user's selection.
    @State private var selectedRegion: MKCoordinateRegion?

    /// Whether the download configuration sheet is currently presented.
    @State private var showDownloadSheet = false

    /// The user-entered name for the region being downloaded.
    @State private var regionName = ""

    /// Whether the location search sheet is currently presented.
    @State private var showSearchSheet = false

    /// Whether a tile download is currently in progress.
    @State private var isDownloading = false

    /// The current download progress, updated during active downloads.
    @State private var downloadProgress: RegionDownloadProgress?

    /// Any error that occurred during the most recent download attempt.
    @State private var downloadError: Error?

    /// The minimum zoom level for tile downloads.
    @State private var minZoom: Int = 12

    /// The maximum zoom level for tile downloads.
    @State private var maxZoom: Int = 16

    /// iOS location manager for centering the map on the user's position.
    @StateObject private var locationManager = LocationManageriOS()

    /// Search completer for location name lookups.
    @StateObject private var searchCompleter = LocationSearchCompleter()

    // Persist the last viewed location
    @AppStorage("lastLatitude") private var lastLatitude: Double = 37.8651  // Yosemite default
    @AppStorage("lastLongitude") private var lastLongitude: Double = -119.5383
    @AppStorage("lastSpan") private var lastSpan: Double = 0.5

    /// The tile downloader actor used for downloading map tiles.
    private let tileDownloader = TileDownloader()

    /// Shared region storage for saving downloaded regions.
    @ObservedObject private var regionStorage = RegionStorage.shared

    /// Watch connectivity manager for auto-transferring downloaded regions.
    @EnvironmentObject private var watchConnectivity: WatchConnectivityManager

    // MARK: - Waypoint State

    /// All waypoints loaded from the local store, displayed as map annotations.
    @State private var waypoints: [Waypoint] = []

    /// Whether the add waypoint sheet is currently presented.
    @State private var showAddWaypointSheet = false

    /// The coordinate for a new waypoint (set by map tap/long-press).
    @State private var newWaypointCoordinate: CLLocationCoordinate2D?

    /// The waypoint selected for detail viewing.
    @State private var selectedWaypoint: Waypoint?

    /// Whether the waypoint detail view is presented.
    @State private var showWaypointDetail = false

    /// Whether an error alert is displayed for waypoint operations.
    @State private var showWaypointError = false

    /// The error message for the waypoint error alert.
    @State private var waypointErrorMessage = ""

    // MARK: - Map Style State

    /// The active map display style (Roads / Trails / Cycling).
    /// Defaults to "Trails" (OpenTopoMap) so hiking trails are visible.
    @AppStorage("preferredMapStyle") private var mapViewStyle: MapViewStyle = .hiking

    /// The tile server selected for the next download, synced from ``mapViewStyle``.
    @State private var selectedTileServer: TileDownloader.TileServer = .osmTopo

    /// Centre coordinate for the trail/cycling map overlay (kept in sync with ``cameraPosition``).
    @State private var trailMapCenter = CLLocationCoordinate2D(latitude: 37.8651, longitude: -119.5383)

    /// Span for the trail/cycling map overlay (kept in sync with ``cameraPosition``).
    @State private var trailMapSpan: Double = 0.5

    var body: some View {
        NavigationStack {
            ZStack {
                // Map — conditionally rendered as Apple Maps or tile overlay
                if let tileTemplate = mapViewStyle.tileURLTemplate {
                    // Trail / Cycling overlay via MKMapView + MKTileOverlay
                    TrailMapView(
                        tileURLTemplate: tileTemplate,
                        center: $trailMapCenter,
                        span: $trailMapSpan,
                        waypoints: waypoints,
                        selectedRegion: selectedRegion,
                        trackCoordinates: locationManager.trackPoints.map(\.coordinate),
                        onRegionChange: { center, span in
                            // Keep cameraPosition in sync for finalizeSelection()
                            cameraPosition = .region(MKCoordinateRegion(
                                center: center,
                                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                            ))
                            saveLastLocation(coordinate: center, span: span)
                        },
                        onWaypointTapped: { waypoint in
                            selectedWaypoint = waypoint
                            showWaypointDetail = true
                        }
                    )
                } else {
                    // Apple Maps (standard road map)
                    Map(position: $cameraPosition) {
                        if let region = selectedRegion {
                            MapPolygon(coordinates: regionCorners(region))
                                .foregroundStyle(.blue.opacity(0.2))
                                .stroke(.blue, lineWidth: 2)
                        }

                        if locationManager.trackPoints.count >= 2 {
                            MapPolyline(coordinates: locationManager.trackPoints.map(\.coordinate))
                                .stroke(.orange, lineWidth: 4)
                        }

                        ForEach(waypoints) { waypoint in
                            Annotation(
                                waypoint.label.isEmpty ? waypoint.category.displayName : waypoint.label,
                                coordinate: waypoint.coordinate
                            ) {
                                Button {
                                    selectedWaypoint = waypoint
                                    showWaypointDetail = true
                                } label: {
                                    Image(systemName: waypoint.category.iconName)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(Color.orange)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                                }
                            }
                        }

                        UserAnnotation()
                    }
                    .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                    }
                    .onMapCameraChange { context in
                        saveLastLocation(
                            coordinate: context.region.center,
                            span: context.region.span.latitudeDelta
                        )
                        // Keep trail map state in sync for seamless switching
                        trailMapCenter = context.region.center
                        trailMapSpan = context.region.span.latitudeDelta
                    }
                }

                // Selection overlay - only blocks gestures during active selection
                if isSelecting {
                    SelectionOverlay(selectionRect: $selectionRect)
                }

                // Custom controls overlay
                VStack {
                    HStack {
                        Spacer()

                        VStack(spacing: 8) {
                            // Search location button
                            Button {
                                showSearchSheet = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.blue)
                                    .frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }

                            // Center on location button
                            Button {
                                centerOnUserLocation()
                            } label: {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.blue)
                                    .frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }

                            // Drop waypoint pin at map center
                            Button {
                                dropPinAtCenter()
                            } label: {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.orange)
                                    .frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }

                            // Track recording toggle
                            Button {
                                if locationManager.isTracking {
                                    locationManager.stopTracking()
                                } else {
                                    locationManager.requestLocationPermission()
                                    locationManager.startTracking()
                                }
                            } label: {
                                Image(systemName: locationManager.isTracking ? "record.circle.fill" : "record.circle")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(locationManager.isTracking ? .red : .blue)
                                    .frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.trailing, 8)
                        .padding(.top, 60) // Below navigation bar
                    }

                    Spacer()

                    if isDownloading, let progress = downloadProgress {
                        downloadProgressCard(progress)
                    } else if selectedRegion != nil {
                        selectedRegionInfo
                    } else {
                        instructionsCard
                    }
                }
                .padding()
            }
            .navigationTitle("Select Region")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                    Button(isSelecting ? "Done" : "Select Area") {
                        if isSelecting {
                            finalizeSelection()
                            // Show download sheet immediately if selection was successful
                            if selectedRegion != nil {
                                showDownloadSheet = true
                            }
                        }
                        isSelecting.toggle()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDownloading)
                }

                if selectedRegion != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear") {
                            selectedRegion = nil
                            selectionRect = nil
                        }
                    }
                }
            }
            .sheet(isPresented: $showDownloadSheet) {
                DownloadConfigSheet(
                    region: selectedRegion!,
                    regionName: $regionName,
                    minZoom: $minZoom,
                    maxZoom: $maxZoom,
                    selectedServer: $selectedTileServer,
                    onDownload: startDownload
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showAddWaypointSheet) {
                if let coord = newWaypointCoordinate {
                    AddWaypointView(
                        latitude: coord.latitude,
                        longitude: coord.longitude,
                        onSave: { waypoint in
                            waypoints.append(waypoint)
                        }
                    )
                }
            }
            .sheet(isPresented: $showWaypointDetail) {
                if let waypoint = selectedWaypoint {
                    NavigationStack {
                        WaypointDetailView(
                            waypoint: waypoint,
                            onUpdate: { updated in
                                if let index = waypoints.firstIndex(where: { $0.id == updated.id }) {
                                    waypoints[index] = updated
                                }
                            },
                            onDelete: { id in
                                waypoints.removeAll { $0.id == id }
                                showWaypointDetail = false
                            }
                        )
                    }
                }
            }
            .alert("Waypoint Error", isPresented: $showWaypointError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(waypointErrorMessage)
            }
            .sheet(isPresented: $showSearchSheet) {
                LocationSearchSheet(
                    searchCompleter: searchCompleter,
                    onSelectLocation: { coordinate in
                        showSearchSheet = false
                        saveLastLocation(coordinate: coordinate, span: 0.2)
                        trailMapCenter = coordinate
                        trailMapSpan = 0.2
                        withAnimation {
                            cameraPosition = .region(MKCoordinateRegion(
                                center: coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
                            ))
                        }
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            // Load the last viewed location
            let center = CLLocationCoordinate2D(latitude: lastLatitude, longitude: lastLongitude)
            cameraPosition = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: lastSpan, longitudeDelta: lastSpan)
            ))
            trailMapCenter = center
            trailMapSpan = lastSpan
            selectedTileServer = mapViewStyle.defaultDownloadServer
            loadWaypoints()
        }
        .onReceive(NotificationCenter.default.publisher(for: .waypointSyncReceived)) { _ in
            loadWaypoints()
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            // When location updates, center map if user requested it
            if locationManager.shouldCenterOnNextUpdate, let location = newLocation {
                locationManager.shouldCenterOnNextUpdate = false
                saveLastLocation(coordinate: location.coordinate, span: 0.1)
                trailMapCenter = location.coordinate
                trailMapSpan = 0.1
                withAnimation {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                    ))
                }
            }
        }
        .onChange(of: mapViewStyle) { _, newStyle in
            // Sync camera position when switching map styles
            selectedTileServer = newStyle.defaultDownloadServer
            if newStyle == .standard {
                // Switching TO Apple Maps — update cameraPosition from trail map state
                cameraPosition = .region(MKCoordinateRegion(
                    center: trailMapCenter,
                    span: MKCoordinateSpan(latitudeDelta: trailMapSpan, longitudeDelta: trailMapSpan)
                ))
            } else {
                // Switching FROM Apple Maps to trail/cycling overlay
                if let region = cameraPosition.region {
                    trailMapCenter = region.center
                    trailMapSpan = region.span.latitudeDelta
                }
            }
        }
    }

    /// An instructional card shown when no region is selected and no download is in progress.
    private var instructionsCard: some View {
        HStack {
            Image(systemName: "hand.draw")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading) {
                Text("Tap 'Select Area' to draw")
                    .font(.headline)
                Text("Draw a rectangle around the hiking area you want to download")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// A progress card shown during active tile downloads.
    ///
    /// Displays the current zoom level, downloaded/total tile count, a progress bar,
    /// and a completion checkmark when finished.
    ///
    /// - Parameter progress: The current ``RegionDownloadProgress``.
    /// - Returns: A styled progress card view.
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// An info card shown when a region has been selected but not yet downloaded.
    ///
    /// Displays the selected area size, estimated tile count, estimated download size,
    /// and a "Download" button to open the configuration sheet.
    private var selectedRegionInfo: some View {
        VStack(spacing: 12) {
            let boundingBox = BoundingBox(
                north: selectedRegion!.center.latitude + selectedRegion!.span.latitudeDelta / 2,
                south: selectedRegion!.center.latitude - selectedRegion!.span.latitudeDelta / 2,
                east: selectedRegion!.center.longitude + selectedRegion!.span.longitudeDelta / 2,
                west: selectedRegion!.center.longitude - selectedRegion!.span.longitudeDelta / 2
            )

            HStack {
                VStack(alignment: .leading) {
                    Text("Selected Area")
                        .font(.headline)

                    let area = boundingBox.areaKm2
                    Text("\(String(format: "%.1f", area)) km²")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let tileCount = boundingBox.estimateTileCount(zoomLevels: minZoom...maxZoom)
                    Text("~\(tileCount) tiles • ~\(estimatedSize(tileCount: tileCount))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button("Download") {
                    showDownloadSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Formats an estimated download size from a tile count.
    ///
    /// Uses an average tile size of 15 KB per tile for the estimate.
    ///
    /// - Parameter tileCount: The number of tiles.
    /// - Returns: A human-readable file size string (e.g., "12.3 MB").
    private func estimatedSize(tileCount: Int) -> String {
        let bytes = Int64(tileCount) * 15_000
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Calculates the four corner coordinates of a map region for polygon rendering.
    ///
    /// - Parameter region: The ``MKCoordinateRegion`` to convert.
    /// - Returns: An array of four ``CLLocationCoordinate2D`` values (NW, NE, SE, SW).
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

    /// Converts the user's screen-space selection into a map coordinate region.
    ///
    /// If the user drew a meaningful rectangle (width and height > 50pt), uses 50%
    /// of the visible map region. Otherwise, uses 60% of the visible region centered
    /// on the current map center.
    private func finalizeSelection() {
        // Use the visible region - if user drew a rectangle, scale it down
        // Otherwise use the center portion of the visible map
        guard let visibleRegion = cameraPosition.region else { return }

        let scaleFactor: Double
        if selectionRect != nil && selectionRect!.width > 50 && selectionRect!.height > 50 {
            // User drew a meaningful rectangle - use a smaller portion
            scaleFactor = 0.5
        } else {
            // No rectangle or too small - use center 60% of visible region
            scaleFactor = 0.6
        }

        selectedRegion = MKCoordinateRegion(
            center: visibleRegion.center,
            span: MKCoordinateSpan(
                latitudeDelta: visibleRegion.span.latitudeDelta * scaleFactor,
                longitudeDelta: visibleRegion.span.longitudeDelta * scaleFactor
            )
        )

        // Clear the selection rectangle
        selectionRect = nil
    }

    /// Initiates a tile download for the currently selected region.
    ///
    /// Creates a ``RegionSelectionRequest`` from the selected region, then uses the
    /// ``TileDownloader`` actor to download tiles. On completion, the region is saved
    /// to ``RegionStorage`` and automatically transferred to the paired Apple Watch.
    private func startDownload() {
        guard let region = selectedRegion else { return }

        let boundingBox = BoundingBox(
            north: region.center.latitude + region.span.latitudeDelta / 2,
            south: region.center.latitude - region.span.latitudeDelta / 2,
            east: region.center.longitude + region.span.longitudeDelta / 2,
            west: region.center.longitude - region.span.longitudeDelta / 2
        )

        let request = RegionSelectionRequest(
            name: regionName.isEmpty ? "Region \(Date().formatted(date: .abbreviated, time: .omitted))" : regionName,
            boundingBox: boundingBox,
            zoomLevels: minZoom...maxZoom
        )

        showDownloadSheet = false
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
                    // Save the region to storage
                    let region = regionStorage.createRegion(
                        from: request,
                        mbtilesURL: mbtilesURL,
                        tileCount: totalTiles,
                        hasRoutingData: routingDataBuilt
                    )
                    regionStorage.saveRegion(region)

                    // Transfer to watch if connected
                    if watchConnectivity.isPaired {
                        let metadata = regionStorage.metadata(for: region)
                        watchConnectivity.transferMBTilesFile(at: mbtilesURL, metadata: metadata)
                    }

                    isDownloading = false
                    downloadProgress = nil
                    print("Download complete: \(mbtilesURL.path)")
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    downloadError = error
                    print("Download failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Downloads OSM trail data, elevation data, and builds a routing graph for the region.
    ///
    /// This is called after tile download completes when `includeRoutingData` is enabled.
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
            // Step 1: Download and parse OSM trail data
            await MainActor.run {
                self.downloadProgress = RegionDownloadProgress(
                    regionId: regionId,
                    totalTiles: totalTiles,
                    downloadedTiles: totalTiles,
                    currentZoom: 0,
                    status: .downloadingTrailData
                )
            }

            let osmDownloader = OSMDataDownloader()
            let (nodes, ways) = try await osmDownloader.downloadAndParseTrailData(
                boundingBox: boundingBox
            ) { _, _ in }

            // Step 2: Build routing graph (elevation is fetched internally by the builder)
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
            let elevationManager = ElevationDataManager()
            try await graphBuilder.buildGraph(
                ways: ways,
                nodes: nodes,
                elevationManager: elevationManager,
                outputPath: routingDbURL.path,
                boundingBox: boundingBox
            ) { _, _ in }

            print("Routing graph built successfully: \(routingDbURL.path)")
            return true
        } catch {
            print("Routing graph build failed (non-fatal): \(error.localizedDescription)")
            // Clean up partial routing database if it exists
            try? FileManager.default.removeItem(at: routingDbURL)
            return false
        }
    }

    /// Centers the map on the user's current GPS location.
    ///
    /// If a location is already available, centers immediately. Otherwise, sets a
    /// flag so the map will center on the next location update from Core Location.
    private func centerOnUserLocation() {
        locationManager.shouldCenterOnNextUpdate = true
        locationManager.requestLocationPermission()

        // If we already have a location, center immediately
        if let location = locationManager.currentLocation {
            locationManager.shouldCenterOnNextUpdate = false
            saveLastLocation(coordinate: location.coordinate, span: 0.1)
            withAnimation {
                cameraPosition = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                ))
            }
        }
    }

    /// Persists the current map position to `@AppStorage` for restoration on next launch.
    ///
    /// - Parameters:
    ///   - coordinate: The map center coordinate to save.
    ///   - span: The map span (zoom level) to save.
    private func saveLastLocation(coordinate: CLLocationCoordinate2D, span: Double) {
        lastLatitude = coordinate.latitude
        lastLongitude = coordinate.longitude
        lastSpan = span
    }

    // MARK: - Waypoint Methods

    /// Loads all waypoints from ``WaypointStore`` for display on the map.
    ///
    /// Errors are logged but do not interrupt the map view — the user can still
    /// use all other features without waypoints.
    private func loadWaypoints() {
        do {
            waypoints = try WaypointStore.shared.fetchAll()
        } catch {
            waypointErrorMessage = "Could not load waypoints: \(error.localizedDescription)"
            showWaypointError = true
            print("Error loading waypoints: \(error.localizedDescription)")
        }
    }

    /// Opens the add waypoint sheet at the current visible map center.
    ///
    /// If the camera has a known region, uses its center. Otherwise falls back
    /// to the persisted last location from `@AppStorage`.
    private func dropPinAtCenter() {
        let coordinate: CLLocationCoordinate2D
        if let region = cameraPosition.region {
            coordinate = region.center
        } else {
            coordinate = CLLocationCoordinate2D(latitude: lastLatitude, longitude: lastLongitude)
        }
        newWaypointCoordinate = coordinate
        showAddWaypointSheet = true
    }
}

// MARK: - Location Search

/// Provides location search auto-completion using MapKit's ``MKLocalSearchCompleter``.
///
/// As the user types, this class queries Apple's search API and returns matching
/// place names and addresses. Selected completions can be resolved to geographic
/// coordinates via ``getCoordinate(for:)``.
class LocationSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    /// The current search query text.
    @Published var searchQuery = ""

    /// The list of search completions matching the current query.
    @Published var completions: [MKLocalSearchCompletion] = []

    /// Whether a search is currently in progress.
    @Published var isSearching = false

    /// The underlying MapKit search completer.
    private let completer = MKLocalSearchCompleter()

    /// Initializes the search completer and configures it for address and POI results.
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// Updates the search query and triggers auto-completion.
    ///
    /// - Parameter query: The search text entered by the user. An empty string clears results.
    func search(_ query: String) {
        searchQuery = query
        if query.isEmpty {
            completions = []
            isSearching = false
        } else {
            isSearching = true
            completer.queryFragment = query
        }
    }

    /// Called by MapKit when new search completions are available.
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
        isSearching = false
    }

    /// Called by MapKit when the search completer encounters an error.
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Search completer error: \(error.localizedDescription)")
        isSearching = false
    }

    /// Resolves a search completion to a geographic coordinate.
    ///
    /// Performs a ``MKLocalSearch`` using the completion and returns the coordinate
    /// of the first matching map item.
    ///
    /// - Parameter completion: The ``MKLocalSearchCompletion`` to resolve.
    /// - Returns: The coordinate of the first match, or `nil` if no results were found.
    func getCoordinate(for completion: MKLocalSearchCompletion) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            return response.mapItems.first?.placemark.coordinate
        } catch {
            print("Search error: \(error.localizedDescription)")
            return nil
        }
    }
}

/// A modal sheet displaying location search results with auto-completion.
///
/// Users type a place name or address, and matching results appear in a list.
/// Tapping a result resolves it to a coordinate and calls the `onSelectLocation` callback.
struct LocationSearchSheet: View {
    /// The search completer providing auto-complete results.
    @ObservedObject var searchCompleter: LocationSearchCompleter

    /// Callback invoked when the user selects a location from the search results.
    let onSelectLocation: (CLLocationCoordinate2D) -> Void

    /// The current search text bound to the search bar.
    @State private var searchText = ""

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search results
                if searchCompleter.completions.isEmpty && !searchText.isEmpty && !searchCompleter.isSearching {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(searchCompleter.completions, id: \.self) { completion in
                        Button {
                            Task {
                                if let coordinate = await searchCompleter.getCoordinate(for: completion) {
                                    onSelectLocation(coordinate)
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .foregroundStyle(.primary)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search Location")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search for a place")
            .onChange(of: searchText) { _, newValue in
                searchCompleter.search(newValue)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Location Manager for iOS

/// A simple Core Location manager for the iOS companion app.
///
/// Provides current location, authorization handling, and basic track recording
/// for the map view. This is separate from the watchOS ``LocationManager`` because
/// the iOS app has different requirements (e.g., `showsBackgroundLocationIndicator`).
class LocationManageriOS: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// The underlying Core Location manager.
    private let manager = CLLocationManager()

    /// The most recent location update from Core Location.
    @Published var currentLocation: CLLocation?

    /// The current location authorization status.
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Whether track recording is currently active.
    @Published var isTracking = false

    /// Recorded GPS points during an active tracking session.
    @Published var trackPoints: [CLLocation] = []

    /// Flag indicating the map should center on the next location update.
    var shouldCenterOnNextUpdate = false

    /// Initializes the location manager with high-accuracy settings optimized for hiking.
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.showsBackgroundLocationIndicator = true
        manager.activityType = .fitness
        authorizationStatus = manager.authorizationStatus
    }

    /// Requests location permission and starts location updates if already authorized.
    ///
    /// If authorization has not been determined, requests "when in use" permission.
    /// If already authorized, immediately starts updating location.
    func requestLocationPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    /// Starts recording a GPS track.
    ///
    /// Clears any previous track points and begins appending new locations as they arrive.
    func startTracking() {
        trackPoints.removeAll()
        isTracking = true
        manager.startUpdatingLocation()
    }

    /// Stops recording the GPS track.
    ///
    /// Location updates continue (for map centering) but points are no longer recorded.
    func stopTracking() {
        isTracking = false
    }

    /// Called by Core Location when new locations are available.
    ///
    /// Updates ``currentLocation`` and appends to ``trackPoints`` if tracking is active,
    /// applying a minimum distance filter of 5 meters between points.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location

        if isTracking {
            if let lastPoint = trackPoints.last {
                let distance = location.distance(from: lastPoint)
                if distance >= 5 {
                    trackPoints.append(location)
                }
            } else {
                trackPoints.append(location)
            }
        }
    }

    /// Called by Core Location when a location update fails.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    /// Called when the user changes location authorization.
    ///
    /// Automatically starts location updates when permission is granted.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}

// MARK: - Selection Overlay

/// A transparent overlay that captures drag gestures for drawing selection rectangles.
///
/// When the user drags on this overlay, a blue-outlined rectangle is drawn from the
/// drag start point to the current touch position. The resulting rectangle is stored
/// in the ``selectionRect`` binding for use by ``RegionSelectorView``.
struct SelectionOverlay: View {
    /// Binding to the selection rectangle (in screen coordinates).
    @Binding var selectionRect: CGRect?

    /// The starting point of the current drag gesture.
    @State private var dragStart: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent overlay
                Color.black.opacity(0.3)
                    .allowsHitTesting(true)

                // Selection rectangle
                if let rect = selectionRect {
                    Rectangle()
                        .stroke(Color.blue, lineWidth: 3)
                        .background(Color.blue.opacity(0.1))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStart == nil {
                            dragStart = value.startLocation
                        }

                        if let start = dragStart {
                            let minX = min(start.x, value.location.x)
                            let minY = min(start.y, value.location.y)
                            let maxX = max(start.x, value.location.x)
                            let maxY = max(start.y, value.location.y)

                            selectionRect = CGRect(
                                x: minX,
                                y: minY,
                                width: maxX - minX,
                                height: maxY - minY
                            )
                        }
                    }
                    .onEnded { _ in
                        dragStart = nil
                    }
            )
        }
    }
}

// MARK: - Download Configuration Sheet

/// A modal sheet for configuring download options before starting a tile download.
///
/// Allows the user to:
/// - Name the region
/// - Toggle contour line inclusion
/// - Adjust minimum and maximum zoom levels via steppers
/// - See estimated tile count and download size
/// - Initiate the download
struct DownloadConfigSheet: View {
    /// The map region to download tiles for.
    let region: MKCoordinateRegion

    /// Binding to the user-entered region name.
    @Binding var regionName: String

    /// Binding to the minimum zoom level.
    @Binding var minZoom: Int

    /// Binding to the maximum zoom level.
    @Binding var maxZoom: Int

    /// Binding to the tile server used for downloading.
    @Binding var selectedServer: TileDownloader.TileServer

    /// Callback invoked when the user taps "Download Region".
    let onDownload: () -> Void

    /// Whether to include contour lines in the download (currently informational only).
    @State private var includeContours = true

    /// The bounding box derived from the selected map region.
    private var boundingBox: BoundingBox {
        BoundingBox(
            north: region.center.latitude + region.span.latitudeDelta / 2,
            south: region.center.latitude - region.span.latitudeDelta / 2,
            east: region.center.longitude + region.span.longitudeDelta / 2,
            west: region.center.longitude - region.span.longitudeDelta / 2
        )
    }

    /// The estimated total number of tiles for the current zoom range.
    private var estimatedTiles: Int {
        boundingBox.estimateTileCount(zoomLevels: minZoom...maxZoom)
    }

    /// A human-readable description of the selected tile server.
    private var serverDescription: String {
        switch selectedServer {
        case .osmTopo:
            return "Topographic maps with hiking trails, contour lines, and elevation data."
        case .cyclosm:
            return "Cycling-focused maps with bike routes, lanes, and infrastructure."
        case .osmStandard:
            return "Standard road maps from OpenStreetMap. No hiking or cycling trails."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Region Name", text: $regionName)
                } header: {
                    Text("Name")
                }

                Section {
                    Picker("Map Source", selection: $selectedServer) {
                        Text("OpenTopoMap (Hiking)").tag(TileDownloader.TileServer.osmTopo)
                        Text("CyclOSM (Cycling)").tag(TileDownloader.TileServer.cyclosm)
                        Text("OpenStreetMap").tag(TileDownloader.TileServer.osmStandard)
                    }
                } header: {
                    Text("Map Source")
                } footer: {
                    Text(serverDescription)
                }

                Section {
                    Toggle("Include Contour Lines", isOn: $includeContours)

                    Stepper("Min Zoom: \(minZoom)", value: $minZoom, in: 8...maxZoom)
                    Stepper("Max Zoom: \(maxZoom)", value: $maxZoom, in: minZoom...18)

                    HStack {
                        Text("~\(estimatedTiles) tiles")
                        Spacer()
                        Text("~\(ByteCountFormatter.string(fromByteCount: Int64(estimatedTiles) * 15_000, countStyle: .file))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Options")
                } footer: {
                    Text("Higher zoom levels provide more detail but require more storage. Level 16 shows individual trails.")
                }

                Section {
                    Button(action: onDownload) {
                        HStack {
                            Spacer()
                            Label("Download Region", systemImage: "arrow.down.circle")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Download Options")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    RegionSelectorView()
}
#endif
