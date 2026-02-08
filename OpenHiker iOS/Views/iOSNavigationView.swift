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

    /// Whether the route picker sheet is showing.
    @State private var showingRoutePicker = false

    /// Whether the save confirmation alert is showing after stopping tracking.
    @State private var showingSaveConfirmation = false

    /// Whether the GPS mode picker is showing.
    @State private var showingGPSModePicker = false

    /// Whether a save error alert is showing.
    @State private var showingSaveError = false

    /// The error message for the save error alert.
    @State private var saveErrorMessage = ""

    /// The selected route for navigation (triggers route picker dismissal).
    @State private var selectedRoute: PlannedRoute?

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
                    recenterPublisher: recenterSubject.eraseToAnyPublisher()
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

                // Floating action buttons
                VStack {
                    Spacer()

                    HStack {
                        Spacer()

                        VStack(spacing: 12) {
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
            .onAppear {
                locationManager.requestPermission()
                locationManager.startLocationUpdates()
                routeStore.loadAll()
            }
            .onDisappear {
                if !locationManager.isTracking {
                    locationManager.stopLocationUpdates()
                }
            }
            .onChange(of: locationManager.currentLocation) { _, newLocation in
                guard let location = newLocation else { return }
                routeGuidance.updateLocation(location)
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
private final class NavigationTileOverlay: MKTileOverlay {

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
    override func loadTile(
        at path: MKTileOverlayPath,
        result: @escaping (Data?, Error?) -> Void
    ) {
        // MBTiles uses TMS y-coordinate (inverted)
        let tmsY = (1 << path.z) - 1 - path.y
        let coordinate = TileCoordinate(x: path.x, y: tmsY, z: path.z)

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
/// Provides offline tile overlay, route polyline, user location tracking,
/// and recorded track visualization.
struct NavigationMapView: UIViewRepresentable {
    @ObservedObject var locationManager: iOSLocationManager
    @ObservedObject var routeGuidance: iOSRouteGuidance
    @ObservedObject var regionStorage: RegionStorage

    /// Publisher that emits when the user taps the recenter button.
    let recenterPublisher: AnyPublisher<Void, Never>

    /// Creates and configures the MKMapView.
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .followWithHeading
        mapView.showsCompass = true
        mapView.showsScale = true

        // Add offline tile overlay
        addTileOverlay(to: mapView)

        // Subscribe to recenter requests
        context.coordinator.recenterCancellable = recenterPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak mapView] in
                mapView?.setUserTrackingMode(.followWithHeading, animated: true)
            }

        return mapView
    }

    /// Updates the map overlays when state changes.
    func updateUIView(_ mapView: MKMapView, context: Context) {
        updateRouteOverlay(on: mapView, coordinator: context.coordinator)
        updateTrackOverlay(on: mapView, coordinator: context.coordinator)
        updateTileOverlay(on: mapView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Overlay Management

    /// Adds the offline tile overlay to the map.
    private func addTileOverlay(to mapView: MKMapView) {
        let regions = regionStorage.regions
        guard !regions.isEmpty else { return }

        let overlay = NavigationTileOverlay(regions: regions)
        mapView.addOverlay(overlay, level: .aboveLabels)
    }

    /// Refreshes the tile overlay when regions change.
    private func updateTileOverlay(on mapView: MKMapView, coordinator: Coordinator) {
        let currentCount = regionStorage.regions.count
        guard currentCount != coordinator.lastRegionCount else { return }
        coordinator.lastRegionCount = currentCount

        // Remove existing tile overlays
        for overlay in mapView.overlays where overlay is NavigationTileOverlay {
            mapView.removeOverlay(overlay)
        }

        // Add updated tile overlay
        addTileOverlay(to: mapView)
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

        /// Tracks the last known region count to detect changes.
        var lastRegionCount: Int = 0

        /// Subscription for recenter requests.
        var recenterCancellable: AnyCancellable?

        init(parent: NavigationMapView) {
            self.parent = parent
        }

        /// Provides renderers for map overlays.
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? NavigationTileOverlay {
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
