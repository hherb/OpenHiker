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
import SpriteKit
import CoreLocation
import WatchKit

/// The main map view for the watchOS app, wrapping a SpriteKit-based tile map.
///
/// This view manages:
/// - Displaying offline map tiles via ``MapScene`` (SpriteKit)
/// - Digital Crown zoom control (bound to ``MapRenderer/currentZoom``)
/// - GPS position marker and compass heading indicator
/// - Track trail rendering during active hike recording
/// - Region selection and loading from received MBTiles databases
///
/// The map is rendered using SpriteKit rather than SwiftUI for efficient tile
/// positioning and smooth scrolling on watchOS hardware.
struct MapView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var connectivityManager: WatchConnectivityReceiver
    @EnvironmentObject var healthKitManager: HealthKitManager

    /// Whether to record hikes as workouts in Apple Health.
    @AppStorage("recordWorkouts") private var recordWorkouts = true

    /// The map renderer that manages tile loading and coordinate calculations.
    @StateObject private var mapRenderer = MapRenderer()

    /// Whether the region picker sheet is currently displayed.
    @State private var showingRegionPicker = false

    /// Whether the add waypoint sheet is currently displayed.
    @State private var showingAddWaypoint = false

    /// All waypoints loaded from the local store, displayed as map markers.
    @State private var waypoints: [Waypoint] = []

    /// Whether an error alert is displayed.
    @State private var showError = false

    /// The error message for the alert.
    @State private var errorMessage = ""

    /// The currently loaded region's metadata, or `nil` if no region is loaded.
    @State private var selectedRegion: RegionMetadata?

    /// Whether the map should auto-center on the user's GPS position.
    @State private var isCenteredOnUser = true

    /// The SpriteKit scene displaying map tiles, or `nil` if no region is loaded.
    @State private var mapScene: MapScene?

    /// The region selected in the picker sheet (used for dismiss callback).
    @State private var pickedRegion: RegionMetadata?

    /// Whether to show an error alert for HealthKit or tracking failures.
    @State private var showingError = false

    /// The error message to display in the alert.
    @State private var errorMessage = ""

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Map Scene
                if let scene = mapScene {
                    SpriteView(scene: scene)
                        .ignoresSafeArea()
                        .gesture(dragGesture)
                        .focusable()
                        .digitalCrownRotation(
                            detent: $mapRenderer.currentZoom,
                            from: mapRenderer.minZoom,
                            through: mapRenderer.maxZoom,
                            by: 1,
                            sensitivity: .medium
                        ) { _ in
                            // Crown rotation handled by binding
                        }
                } else {
                    noMapView
                }

                // Hike stats overlay (distance, elevation, time, vitals)
                HikeStatsOverlay()

                // Overlays
                VStack {
                    // Top bar with info
                    if selectedRegion != nil {
                        topInfoBar
                    }

                    Spacer()

                    // Bottom controls
                    if selectedRegion != nil {
                        bottomControls
                    }
                }
            }
        }
        .onAppear {
            loadSavedRegion()
            loadWaypoints()
            locationManager.startLocationUpdates()
        }
        .onChange(of: mapRenderer.currentZoom) { _, _ in
            mapScene?.updateVisibleTiles()
            refreshWaypointMarkers()
            if locationManager.isTracking {
                mapScene?.updateTrackTrail(trackPoints: locationManager.trackPoints)
            }
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            updateUserPosition(newLocation)
        }
        .onChange(of: locationManager.heading) { _, newHeading in
            if let heading = newHeading {
                mapScene?.updateHeading(trueHeading: heading.trueHeading)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingAddWaypoint) {
            AddWaypointSheet(onSave: { waypoint in
                waypoints.append(waypoint)
                refreshWaypointMarkers()
            })
        }
        .sheet(isPresented: $showingRegionPicker, onDismiss: {
            if let region = pickedRegion {
                loadRegion(region)
                pickedRegion = nil
            }
        }) {
            RegionPickerSheet(
                regions: connectivityManager.availableRegions,
                selectedRegion: $pickedRegion
            )
        }
        .onChange(of: healthKitManager.healthKitError?.localizedDescription) { _, newValue in
            if let message = newValue {
                errorMessage = message
                showingError = true
            }
        }
        .alert("Tracking Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Subviews

    /// A placeholder view shown when no map region is loaded.
    ///
    /// Displays contextual messages based on the current state:
    /// - A progress indicator if a file transfer is in progress
    /// - A "Select Region" button if local regions are available
    /// - An instruction to download from iPhone otherwise
    private var noMapView: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("No Map Loaded")
                .font(.headline)

            if connectivityManager.isReceivingFile {
                ProgressView("Receiving map...")
                    .font(.caption)
            } else if !connectivityManager.availableRegions.isEmpty {
                let localRegions = connectivityManager.loadAllRegionMetadata()
                if !localRegions.isEmpty {
                    Button("Select Region") {
                        showingRegionPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Maps transferring from iPhone...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("Download a region on your iPhone to get started")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    /// The top overlay bar showing the current zoom level and GPS tracking status.
    private var topInfoBar: some View {
        HStack {
            // Zoom level
            Text("z\(mapRenderer.currentZoom)")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            // GPS status
            Image(systemName: locationManager.isTracking ? "location.fill" : "location")
                .foregroundStyle(locationManager.isTracking ? .green : .secondary)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    /// The bottom control bar with center-on-user, pin, tracking toggle, and region picker buttons.
    private var bottomControls: some View {
        HStack(spacing: 12) {
            // Center on user button
            Button {
                centerOnUser()
            } label: {
                Image(systemName: isCenteredOnUser ? "location.fill" : "location")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isCenteredOnUser ? .blue : .primary)

            Spacer()

            // Drop waypoint pin button
            Button {
                showingAddWaypoint = true
            } label: {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)

            Spacer()

            // Start/Stop tracking
            Button {
                toggleTracking()
            } label: {
                Image(systemName: locationManager.isTracking ? "stop.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(locationManager.isTracking ? .red : .green)
            }
            .buttonStyle(.plain)

            Spacer()

            // Region picker
            Button {
                showingRegionPicker = true
            } label: {
                Image(systemName: "map")
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Gestures

    /// A drag gesture that disables auto-centering when the user pans the map.
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isCenteredOnUser = false
                // Pan the map
                // This would require implementing pan logic in MapRenderer
            }
    }

    // MARK: - Actions

    /// Attempts to load the most recently used map region from local storage.
    private func loadSavedRegion() {
        // Try to load the most recently used region
        let regions = connectivityManager.loadAllRegionMetadata()
        if let lastRegion = regions.first {
            loadRegion(lastRegion)
        }
    }

    /// Loads a map region by opening its MBTiles database and creating the SpriteKit scene.
    ///
    /// - Parameter region: The ``RegionMetadata`` of the region to load.
    private func loadRegion(_ region: RegionMetadata) {
        do {
            try mapRenderer.loadRegion(region)
            selectedRegion = region
            // Create the scene once after loading; SpriteView will reuse it
            mapScene = mapRenderer.createScene(size: WKInterfaceDevice.current().screenBounds.size)
            refreshWaypointMarkers()
        } catch {
            errorMessage = "Failed to load map region: \(error.localizedDescription)"
            showError = true
            print("Error loading region: \(error.localizedDescription)")
        }
    }

    /// Updates the position marker and track trail when the user's GPS location changes.
    ///
    /// Also feeds the new location to ``HealthKitManager`` for workout route recording.
    ///
    /// - Parameter location: The new location, or `nil` if unavailable.
    private func updateUserPosition(_ location: CLLocation?) {
        guard let location = location else { return }

        // Update position marker on map
        mapScene?.updatePositionMarker(coordinate: location.coordinate)

        // Update track trail if recording
        if locationManager.isTracking {
            mapScene?.updateTrackTrail(trackPoints: locationManager.trackPoints)

            // Feed location to HealthKit route builder if workout is active
            if healthKitManager.workoutActive {
                healthKitManager.addRoutePoints([location])
            }
        }

        // Center map on user if enabled
        if isCenteredOnUser {
            mapRenderer.setCenter(location.coordinate)
            refreshWaypointMarkers()
        }
    }

    /// Centers the map on the user's current GPS position.
    ///
    /// If no location is available yet, requests a single location update.
    private func centerOnUser() {
        guard let location = locationManager.currentLocation else {
            locationManager.requestSingleLocation()
            return
        }

        isCenteredOnUser = true
        mapRenderer.setCenter(location.coordinate)
    }

    /// Loads all waypoints from the local ``WaypointStore`` and updates the map markers.
    ///
    /// Called on appear and after new waypoints are synced from the iPhone.
    private func loadWaypoints() {
        do {
            waypoints = try WaypointStore.shared.fetchAll()
            refreshWaypointMarkers()
        } catch {
            errorMessage = "Could not load waypoints: \(error.localizedDescription)"
            showError = true
            print("Error loading waypoints: \(error.localizedDescription)")
        }
    }

    /// Tells the ``MapScene`` to refresh waypoint marker positions.
    ///
    /// Called after zoom/pan changes and when waypoints are added or removed.
    private func refreshWaypointMarkers() {
        mapScene?.updateWaypointMarkers(waypoints: waypoints)
    }

    /// Toggles hike track recording on or off.
    ///
    /// When starting, also begins a HealthKit workout session (if enabled in
    /// settings) for background runtime and vitals recording. When stopping,
    /// ends the workout and saves it to Apple Health with distance and elevation data.
    /// Any HealthKit errors are surfaced via the error alert on this view.
    private func toggleTracking() {
        if locationManager.isTracking {
            locationManager.stopTracking()
            if healthKitManager.workoutActive {
                Task {
                    let workout = await healthKitManager.stopWorkout(
                        totalDistance: locationManager.totalDistance,
                        elevationGain: locationManager.elevationGain
                    )
                    if workout == nil, let error = healthKitManager.healthKitError {
                        await MainActor.run {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }
                }
            }
        } else {
            locationManager.startTracking()
            if recordWorkouts {
                healthKitManager.startWorkout()
                // Check if startWorkout set an error (synchronous method)
                if let error = healthKitManager.healthKitError {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}

// MARK: - Region Picker Sheet

/// A modal sheet for selecting which offline map region to display.
///
/// Presents a list of all available ``RegionMetadata`` objects. Tapping a region
/// sets the binding and dismisses the sheet, triggering the parent view to load it.
struct RegionPickerSheet: View {
    /// The list of available regions to choose from.
    let regions: [RegionMetadata]

    /// Binding to the selected region (set when the user taps a row).
    @Binding var selectedRegion: RegionMetadata?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(regions) { region in
                Button {
                    selectedRegion = region
                    dismiss()
                } label: {
                    VStack(alignment: .leading) {
                        Text(region.name)
                            .font(.headline)
                        Text("\(region.tileCount) tiles")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Select Region")
        }
    }
}


#Preview {
    MapView()
        .environmentObject(LocationManager())
        .environmentObject(WatchConnectivityReceiver.shared)
        .environmentObject(HealthKitManager())
}
