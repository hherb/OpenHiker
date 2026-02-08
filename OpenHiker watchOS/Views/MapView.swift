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
/// - Planned route polyline and navigation overlay for turn-by-turn guidance
/// - Region selection and loading from received MBTiles databases
///
/// The map is rendered using SpriteKit rather than SwiftUI for efficient tile
/// positioning and smooth scrolling on watchOS hardware.
struct MapView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var connectivityManager: WatchConnectivityReceiver
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var routeGuidance: RouteGuidance
    @EnvironmentObject var uvIndexManager: UVIndexManager
    @EnvironmentObject var batteryMonitor: BatteryMonitor

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

    /// Whether heading-up mode is active (map rotates so travel direction points up).
    @State private var isHeadingUp = true

    /// The SpriteKit scene displaying map tiles, or `nil` if no region is loaded.
    @State private var mapScene: MapScene?

    /// The region selected in the picker sheet (used for dismiss callback).
    @State private var pickedRegion: RegionMetadata?

    /// Whether the save hike sheet is currently displayed after stopping tracking.
    @State private var showingSaveHike = false

    /// Timer for periodic auto-save of track state during active recording.
    @State private var autoSaveTimer: Timer?


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

                // UV index overlay (WeatherKit-based)
                UVIndexOverlay()

                // Navigation overlay for route guidance
                NavigationOverlay(guidance: routeGuidance)

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
            refreshRouteLine()
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            updateUserPosition(newLocation)
        }
        .onChange(of: locationManager.heading) { _, newHeading in
            if let heading = newHeading {
                mapScene?.updateHeading(trueHeading: heading.trueHeading)
                // In heading-up mode, refresh overlays since the map rotation changed
                if isHeadingUp {
                    if locationManager.isTracking {
                        mapScene?.updateTrackTrail(trackPoints: locationManager.trackPoints)
                    }
                    refreshWaypointMarkers()
                    refreshRouteLine()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .waypointSyncReceived)) { _ in
            loadWaypoints()
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
                showError = true
            }
        }
        .sheet(isPresented: $showingSaveHike) {
            SaveHikeSheet(regionId: selectedRegion?.id) { saved in
                if saved {
                    print("Hike saved successfully")
                } else {
                    print("Hike discarded")
                }
                // Clear track data after save or discard
                locationManager.trackPoints.removeAll()
                TrackRecoveryManager.clearRecoveryState()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lowBatteryTriggered)) { _ in
            handleLowBattery()
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
            // Center on user / heading-up button
            Button {
                centerOnUser()
            } label: {
                Image(systemName: isCenteredOnUser && isHeadingUp ? "location.north.line.fill" : isCenteredOnUser ? "location.fill" : "location")
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

    /// A drag gesture that disables auto-centering and heading-up when the user pans the map.
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isCenteredOnUser = false
                isHeadingUp = false
                mapScene?.isHeadingUpMode = false
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
            let scene = mapRenderer.createScene(size: WKInterfaceDevice.current().screenBounds.size)
            scene.isHeadingUpMode = isHeadingUp
            mapScene = scene
            refreshWaypointMarkers()
        } catch {
            errorMessage = "Failed to load map region: \(error.localizedDescription)"
            showError = true
            print("Error loading region: \(error.localizedDescription)")
        }
    }

    /// Updates the position marker and track trail when the user's GPS location changes.
    ///
    /// Also feeds the new location to ``HealthKitManager`` for workout route recording
    /// and to ``UVIndexManager`` for UV index updates.
    ///
    /// - Parameter location: The new location, or `nil` if unavailable.
    private func updateUserPosition(_ location: CLLocation?) {
        guard let location = location else { return }

        // Center map on user if enabled (must happen before marker/overlay updates)
        if isCenteredOnUser {
            mapRenderer.setCenter(location.coordinate)
        }

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

        // Refresh overlays when centered (tiles already updated by setCenter)
        if isCenteredOnUser {
            refreshWaypointMarkers()
        }

        // Feed location to route guidance if active navigation
        if routeGuidance.isNavigating {
            routeGuidance.updateLocation(location)
            refreshRouteLine()
        }

        // Update UV index (rate-limited internally to once per 10 minutes)
        uvIndexManager.updateUVIndex(for: location)
    }

    /// Centers the map on the user's current GPS position and enables heading-up mode.
    ///
    /// If no location is available yet, requests a single location update.
    private func centerOnUser() {
        guard let location = locationManager.currentLocation else {
            locationManager.requestSingleLocation()
            return
        }

        isCenteredOnUser = true
        isHeadingUp = true
        mapScene?.isHeadingUpMode = true
        mapRenderer.setCenter(location.coordinate)

        // Apply current heading immediately
        if let heading = locationManager.heading {
            mapScene?.updateHeading(trueHeading: heading.trueHeading)
        }
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

    /// Updates the planned route polyline on the map from the active navigation route.
    ///
    /// Called after zoom/pan changes and location updates during active guidance.
    /// Clears the route line if navigation is not active.
    private func refreshRouteLine() {
        if let route = routeGuidance.activeRoute, routeGuidance.isNavigating {
            mapScene?.updateRouteLine(coordinates: route.coordinates)
        } else {
            mapScene?.clearRouteLine()
        }
    }

    /// Toggles hike track recording on or off.
    ///
    /// When starting, also begins a HealthKit workout session (if enabled in
    /// settings) for background runtime and vitals recording, starts battery
    /// monitoring, and schedules periodic auto-save of track state. When
    /// stopping, ends the workout, stops monitoring, and cleans up timers.
    /// Any HealthKit errors are surfaced via the error alert on this view.
    private func toggleTracking() {
        if locationManager.isTracking {
            locationManager.stopTracking()
            stopAutoSaveTimer()
            batteryMonitor.stopMonitoring()
            if healthKitManager.workoutActive {
                Task {
                    let workout = await healthKitManager.stopWorkout(
                        totalDistance: locationManager.totalDistance,
                        elevationGain: locationManager.elevationGain
                    )
                    if workout == nil, let error = healthKitManager.healthKitError {
                        await MainActor.run {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }
            }
            // Present save hike sheet if there are track points to save
            if !locationManager.trackPoints.isEmpty {
                showingSaveHike = true
            }
        } else {
            locationManager.startTracking()
            batteryMonitor.reset()
            batteryMonitor.startMonitoring()
            startAutoSaveTimer()
            if recordWorkouts {
                healthKitManager.startWorkout()
                // Check if startWorkout set an error (synchronous method)
                if let error = healthKitManager.healthKitError {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    /// Starts the periodic auto-save timer for track state recovery.
    ///
    /// Fires every ``TrackRecoveryManager/autoSaveIntervalSec`` (5 minutes) to
    /// save the current track points and statistics to disk.
    private func startAutoSaveTimer() {
        let locManager = locationManager
        let regionId = selectedRegion?.id
        autoSaveTimer = Timer.scheduledTimer(
            withTimeInterval: TrackRecoveryManager.autoSaveIntervalSec,
            repeats: true
        ) { _ in
            guard locManager.isTracking, !locManager.trackPoints.isEmpty else { return }
            TrackRecoveryManager.saveState(
                trackPoints: locManager.trackPoints,
                totalDistance: locManager.totalDistance,
                elevationGain: locManager.elevationGain,
                elevationLoss: locManager.elevationLoss,
                regionId: regionId
            )
        }
    }

    /// Stops and invalidates the auto-save timer.
    private func stopAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    /// Handles the low-battery event by saving track state and switching GPS to low power.
    ///
    /// Called when ``BatteryMonitor`` detects the battery has dropped to 5%.
    /// Performs an emergency save of the track data to both the recovery file
    /// and as a ``SavedRoute`` in the database, then switches GPS to low-power mode.
    /// The ``WatchContentView`` will detect ``batteryMonitor.isLowBatteryMode``
    /// and replace the entire UI with ``LowBatteryTrackingView``.
    private func handleLowBattery() {
        guard locationManager.isTracking, !locationManager.trackPoints.isEmpty else { return }

        // Save to recovery file
        TrackRecoveryManager.saveState(
            trackPoints: locationManager.trackPoints,
            totalDistance: locationManager.totalDistance,
            elevationGain: locationManager.elevationGain,
            elevationLoss: locationManager.elevationLoss,
            regionId: selectedRegion?.id
        )

        // Save as a route in case battery dies completely
        TrackRecoveryManager.emergencySaveAsRoute(
            trackPoints: locationManager.trackPoints,
            totalDistance: locationManager.totalDistance,
            elevationGain: locationManager.elevationGain,
            elevationLoss: locationManager.elevationLoss,
            regionId: selectedRegion?.id,
            averageHeartRate: healthKitManager.currentHeartRate,
            connectivityManager: connectivityManager
        )

        // Switch to low-power GPS to conserve remaining battery
        locationManager.switchToLowPowerMode()
        stopAutoSaveTimer()

        print("Low battery handled: track saved, GPS switched to low power")
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
        .environmentObject(RouteGuidance())
        .environmentObject(UVIndexManager())
        .environmentObject(BatteryMonitor())
}
