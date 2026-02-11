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
import os

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

    /// A lightweight SpriteKit scene for mapless trail display, shown when recording
    /// without a loaded map region. Displays the GPS trail on a black background.
    @State private var trackOnlyScene: TrackOnlyScene?

    /// Index into ``TrackOnlyScene/viewRadii`` controlling the visible radius
    /// via Digital Crown when using the track-only scene.
    @State private var viewRadiusIndex: Int = 2

    /// Stable UUID for the current recording session, used for periodic phone sync.
    @State private var liveRouteId: UUID?

    /// The region selected in the picker sheet (used for dismiss callback).
    @State private var pickedRegion: RegionMetadata?

    /// Whether the save hike sheet is currently displayed after stopping tracking.
    @State private var showingSaveHike = false

    /// Timer that auto-recenters the map on the user after a pan gesture during tracking.
    ///
    /// When the user pans the map while tracking or navigating, this timer fires after
    /// ``autoRecenterDelaySec`` seconds to re-enable auto-centering, so the map doesn't
    /// stay panned away from the user's position indefinitely.
    @State private var autoRecenterTimer: Timer?

    /// Seconds before the map auto-recenters after a pan gesture during tracking.
    private static let autoRecenterDelaySec: TimeInterval = 10.0

    /// Timer for periodic auto-save of track state during active recording.
    ///
    /// Stored as a reference rather than `@State` to avoid SwiftUI lifecycle issues.
    /// The timer is invalidated in `stopAutoSaveTimer()`, `onDisappear`, and when
    /// the view transitions to ``LowBatteryTrackingView``.
    @State private var autoSaveTimer: Timer?

    /// Logger for map view events related to battery and recovery.
    private static let logger = Logger(
        subsystem: "com.openhiker.watchos",
        category: "MapView"
    )

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Map Scene
                if let scene = mapScene {
                    SpriteView(scene: scene)
                        .ignoresSafeArea()
                        .gesture(dragGesture)
                        .allowsHitTesting(true)
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
                } else if let trackScene = trackOnlyScene {
                    SpriteView(scene: trackScene)
                        .ignoresSafeArea()
                        .allowsHitTesting(true)
                        .focusable()
                        .digitalCrownRotation(
                            detent: $viewRadiusIndex,
                            from: 0,
                            through: TrackOnlyScene.viewRadii.count - 1,
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
                    .allowsHitTesting(false)

                // UV index overlay (WeatherKit-based)
                UVIndexOverlay()
                    .allowsHitTesting(false)

                // Navigation overlay for route guidance
                NavigationOverlay(guidance: routeGuidance)

                // Overlays
                VStack {
                    // Top bar with info
                    topInfoBar

                    Spacer()

                    // Bottom controls — always visible so recording works without a loaded map
                    bottomControls
                }
            }
        }
        .onAppear {
            loadSavedRegion()
            loadWaypoints()
            locationManager.startLocationUpdates()
            configureLowBatteryCallback()
        }
        .onDisappear {
            stopAutoSaveTimer()
            autoRecenterTimer?.invalidate()
            autoRecenterTimer = nil
        }
        .onChange(of: mapRenderer.currentZoom) { _, _ in
            mapScene?.updateVisibleTiles()
            refreshWaypointMarkers()
            if locationManager.isTracking {
                mapScene?.updateTrackTrail(trackPoints: locationManager.trackPoints)
            }
            refreshRouteLine()
            refreshTrailOverlays()
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            updateUserPosition(newLocation)
        }
        .onChange(of: locationManager.heading) { _, newHeading in
            if let heading = newHeading {
                mapScene?.updateHeading(trueHeading: heading.trueHeading)
                trackOnlyScene?.updateHeading(trueHeading: heading.trueHeading)
                // In heading-up mode, refresh overlays since the map rotation changed
                if isHeadingUp {
                    if locationManager.isTracking {
                        mapScene?.updateTrackTrail(trackPoints: locationManager.trackPoints)
                        trackOnlyScene?.updateTrackTrail(trackPoints: locationManager.trackPoints)
                    }
                    refreshWaypointMarkers()
                    refreshRouteLine()
                    refreshTrailOverlays()
                }
            }
        }
        .onChange(of: viewRadiusIndex) { _, newIndex in
            let clampedIndex = max(0, min(newIndex, TrackOnlyScene.viewRadii.count - 1))
            trackOnlyScene?.setViewRadius(TrackOnlyScene.viewRadii[clampedIndex])
            // Re-render trail at new zoom level
            if locationManager.isTracking {
                trackOnlyScene?.updateTrackTrail(trackPoints: locationManager.trackPoints)
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
                // Clear track data after save or discard
                locationManager.trackPoints.removeAll()
                TrackRecoveryManager.clearRecoveryState()
            }
        }
        // Low-battery handling is done via batteryMonitor.onLowBatteryTriggered callback
        // (set in configureLowBatteryCallback) instead of .onReceive, to avoid the race
        // condition where the view may be removed before the notification handler fires.
    }

    // MARK: - Subviews

    /// A placeholder view shown when no map region is loaded.
    ///
    /// Displays contextual messages based on the current state:
    /// - A progress indicator if a file transfer is in progress
    /// - A "Select Region" button if local regions are available
    /// - An instruction to download from iPhone otherwise
    ///
    /// Also shows the current tracking status if recording is active without a map,
    /// so the user knows their trail is being recorded.
    private var noMapView: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("No Map Loaded")
                .font(.headline)

            if locationManager.isTracking {
                Label("Recording trail...", systemImage: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

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

            // On-demand tile request when phone is reachable
            if connectivityManager.isTileRequestPending {
                ProgressView("Requesting map...")
                    .font(.caption)
            } else if let location = locationManager.currentLocation,
                      !connectivityManager.isReceivingFile {
                Button("Request Map from iPhone") {
                    connectivityManager.requestTilesFromPhone(
                        coordinate: location.coordinate
                    )
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .tint(.blue)
            }
        }
        .padding()
    }

    /// The top overlay bar showing the current zoom level and GPS tracking status.
    ///
    /// Zoom level is only shown when a map region is loaded. The GPS status
    /// indicator is always visible.
    private var topInfoBar: some View {
        HStack {
            // Zoom level (tile map) or radius (track-only scene)
            if selectedRegion != nil {
                Text("z\(mapRenderer.currentZoom)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
            } else if trackOnlyScene != nil {
                let radiusIndex = max(0, min(viewRadiusIndex, TrackOnlyScene.viewRadii.count - 1))
                let radius = TrackOnlyScene.viewRadii[radiusIndex]
                Text(radius >= 1000 ? String(format: "%.1f km", radius / 1000.0) : "\(Int(radius))m")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            Spacer()

            // GPS status
            Image(systemName: locationManager.isTracking ? "location.fill" : "location")
                .foregroundStyle(locationManager.isTracking ? .green : .secondary)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .allowsHitTesting(false)
    }

    /// The bottom control bar with center-on-user, pin, tracking toggle, and region picker buttons.
    ///
    /// Recording and waypoint buttons are always visible so that trail recording
    /// works even when no map region is loaded. The center-on-user button is only
    /// shown when a map scene is available.
    private var bottomControls: some View {
        HStack(spacing: 12) {
            // Center on user / heading-up button (useful when a map or track-only scene is loaded)
            if selectedRegion != nil || trackOnlyScene != nil {
                Button {
                    centerOnUser()
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    Image(systemName: isCenteredOnUser && isHeadingUp ? "location.north.line.fill" : isCenteredOnUser ? "location.fill" : "location")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isCenteredOnUser ? .blue : .primary)

                Spacer()
            }

            // Drop waypoint pin button
            Button {
                WKInterfaceDevice.current().play(.click)
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
                WKInterfaceDevice.current().play(.click)
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
                WKInterfaceDevice.current().play(.click)
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
    ///
    /// Uses a minimum drag distance of 8 points to avoid intercepting tap gestures
    /// intended for the overlay buttons. During active tracking or navigation,
    /// schedules an auto-recenter timer so the map returns to following the user
    /// after ``autoRecenterDelaySec`` seconds of inactivity.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                isCenteredOnUser = false
                isHeadingUp = false
                mapScene?.isHeadingUpMode = false
                trackOnlyScene?.isHeadingUpMode = false
                // Pan the map
                // This would require implementing pan logic in MapRenderer
            }
            .onEnded { _ in
                scheduleAutoRecenter()
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
            // Dismiss track-only scene now that a tile map is available
            trackOnlyScene = nil
            refreshWaypointMarkers()
            refreshTrailOverlays()
            // If actively recording, render existing track on the new map scene
            if locationManager.isTracking {
                scene.updateTrackTrail(trackPoints: locationManager.trackPoints)
            }
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

        // Update track-only scene (mapless trail display)
        if let trackScene = trackOnlyScene {
            trackScene.updateCenter(location.coordinate)
            trackScene.updatePositionMarker(coordinate: location.coordinate)
            if locationManager.isTracking {
                trackScene.updateTrackTrail(trackPoints: locationManager.trackPoints)
            }
        }

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
            refreshTrailOverlays()
        }

        // Feed location to route guidance if active navigation
        if routeGuidance.isNavigating {
            routeGuidance.updateLocation(location)
            refreshRouteLine()
        }

        // Update UV index (rate-limited internally to once per 10 minutes)
        uvIndexManager.updateUVIndex(for: location)
    }

    /// Schedules auto-recentering on the user's position after a pan gesture.
    ///
    /// Only activates during active tracking or navigation so that casual map
    /// browsing is not interrupted. Cancels any previous pending recenter.
    private func scheduleAutoRecenter() {
        autoRecenterTimer?.invalidate()
        autoRecenterTimer = nil

        guard locationManager.isTracking || routeGuidance.isNavigating else { return }

        autoRecenterTimer = Timer.scheduledTimer(
            withTimeInterval: Self.autoRecenterDelaySec,
            repeats: false
        ) { _ in
            DispatchQueue.main.async {
                centerOnUser()
            }
        }
    }

    /// Centers the map on the user's current GPS position and enables heading-up mode.
    ///
    /// If no location is available yet, requests a single location update.
    private func centerOnUser() {
        autoRecenterTimer?.invalidate()
        autoRecenterTimer = nil

        guard let location = locationManager.currentLocation else {
            locationManager.requestSingleLocation()
            return
        }

        isCenteredOnUser = true
        isHeadingUp = true
        mapScene?.isHeadingUpMode = true
        trackOnlyScene?.isHeadingUpMode = true
        mapRenderer.setCenter(location.coordinate)

        // Apply current heading immediately
        if let heading = locationManager.heading {
            mapScene?.updateHeading(trueHeading: heading.trueHeading)
            trackOnlyScene?.updateHeading(trueHeading: heading.trueHeading)
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

    /// Updates trail overlay polylines based on the current map viewport.
    ///
    /// Queries the routing database for trail edges visible on screen and
    /// renders them as colored polylines grouped by highway type. Uses
    /// internal caching to avoid redundant database queries when the
    /// viewport hasn't changed significantly.
    private func refreshTrailOverlays() {
        guard let scene = mapScene, selectedRegion?.hasRoutingData == true else { return }

        let bbox = mapRenderer.viewportBoundingBox(sceneSize: scene.size, isHeadingUp: isHeadingUp)

        if let bbox = bbox, scene.shouldRequeryTrails(currentBbox: bbox, currentZoom: mapRenderer.currentZoom) {
            // Viewport changed significantly — re-query database
            let edges = mapRenderer.getTrailEdgesInViewport(sceneSize: scene.size, isHeadingUp: isHeadingUp)
            scene.recordTrailQuery(bbox: bbox, zoom: mapRenderer.currentZoom)
            scene.updateTrailOverlays(edges: edges)
        } else {
            // Viewport similar — just re-project cached edges (coordinates changed due to pan)
            scene.updateTrailOverlays(edges: nil)
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
            liveRouteId = nil
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
            // Dismiss track-only scene after save sheet is presented
            trackOnlyScene = nil
        } else {
            locationManager.startTracking()
            liveRouteId = UUID()
            batteryMonitor.reset()
            batteryMonitor.startMonitoring()
            startAutoSaveTimer()
            // Create track-only scene for mapless trail display when no map is loaded
            if mapScene == nil {
                let scene = TrackOnlyScene(size: WKInterfaceDevice.current().screenBounds.size)
                scene.isHeadingUpMode = isHeadingUp
                scene.setViewRadius(TrackOnlyScene.viewRadii[viewRadiusIndex])
                trackOnlyScene = scene
            }
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
    /// save the current track points and statistics to disk. The file I/O is
    /// dispatched to a background queue to avoid blocking the main thread and
    /// causing button unresponsiveness during active recording.
    private func startAutoSaveTimer() {
        // Defensive: invalidate any existing timer before creating a new one
        stopAutoSaveTimer()

        let locManager = locationManager
        let regionId = selectedRegion?.id
        let connManager = connectivityManager
        let currentLiveRouteId = liveRouteId
        autoSaveTimer = Timer.scheduledTimer(
            withTimeInterval: TrackRecoveryManager.autoSaveIntervalSec,
            repeats: true
        ) { _ in
            guard locManager.isTracking, !locManager.trackPoints.isEmpty else { return }
            // Snapshot the data on the main thread, then save on a background queue
            let points = locManager.trackPoints
            let distance = locManager.totalDistance
            let gain = locManager.elevationGain
            let loss = locManager.elevationLoss
            DispatchQueue.global(qos: .utility).async {
                TrackRecoveryManager.saveState(
                    trackPoints: points,
                    totalDistance: distance,
                    elevationGain: gain,
                    elevationLoss: loss,
                    regionId: regionId
                )

                // Sync partial route to phone if reachable
                guard let routeId = currentLiveRouteId, !points.isEmpty else { return }
                MapView.syncPartialRouteToPhone(
                    connManager: connManager,
                    routeId: routeId,
                    trackPoints: points,
                    distance: distance,
                    elevationGain: gain,
                    elevationLoss: loss,
                    regionId: regionId
                )
            }
        }
    }

    /// Creates a partial ``SavedRoute`` from in-progress recording data and sends it
    /// to the phone via live sync.
    ///
    /// Called from the auto-save timer every 5 minutes during active recording.
    /// The route uses the stable ``liveRouteId`` so the phone can upsert
    /// (replace the same route on each sync rather than creating duplicates).
    ///
    /// - Parameters:
    ///   - connManager: The ``WatchConnectivityReceiver`` to send through.
    ///   - routeId: The stable UUID for this recording session.
    ///   - trackPoints: The current array of recorded GPS points.
    ///   - distance: Total distance in meters.
    ///   - elevationGain: Total elevation gain in meters.
    ///   - elevationLoss: Total elevation loss in meters.
    ///   - regionId: The current region ID, if any.
    private static func syncPartialRouteToPhone(
        connManager: WatchConnectivityReceiver,
        routeId: UUID,
        trackPoints: [CLLocation],
        distance: CLLocationDistance,
        elevationGain: Double,
        elevationLoss: Double,
        regionId: UUID?
    ) {
        guard let firstPoint = trackPoints.first,
              let lastPoint = trackPoints.last else { return }

        let compressedData = TrackCompression.encode(trackPoints)
        let (walkingTime, restingTime) = LocationManager.computeWalkingAndRestingTime(from: trackPoints)

        let route = SavedRoute(
            id: routeId,
            name: "Recording — \(Self.liveSyncDateFormatter.string(from: firstPoint.timestamp))",
            startLatitude: firstPoint.coordinate.latitude,
            startLongitude: firstPoint.coordinate.longitude,
            endLatitude: lastPoint.coordinate.latitude,
            endLongitude: lastPoint.coordinate.longitude,
            startTime: firstPoint.timestamp,
            endTime: lastPoint.timestamp,
            totalDistance: distance,
            elevationGain: elevationGain,
            elevationLoss: elevationLoss,
            walkingTime: walkingTime,
            restingTime: restingTime,
            comment: "In-progress recording",
            regionId: regionId,
            trackData: compressedData
        )

        connManager.syncLiveRoute(route)
    }

    /// Date formatter for live sync route names.
    private static let liveSyncDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Stops and invalidates the auto-save timer.
    private func stopAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    /// Configures the ``BatteryMonitor/onLowBatteryTriggered`` callback for emergency saves.
    ///
    /// Uses a direct callback instead of NotificationCenter to avoid the race condition
    /// where SwiftUI may remove this view (swapping to ``LowBatteryTrackingView``) before
    /// a `.onReceive` handler fires. The callback is invoked synchronously by
    /// ``BatteryMonitor/checkBatteryLevel()`` before the `@Published` property change
    /// triggers a view swap.
    private func configureLowBatteryCallback() {
        batteryMonitor.onLowBatteryTriggered = { [locationManager, healthKitManager, connectivityManager] in
            handleLowBattery(
                locationManager: locationManager,
                healthKitManager: healthKitManager,
                connectivityManager: connectivityManager
            )
        }
    }

    /// Handles the low-battery event by saving track state and switching GPS to low power.
    ///
    /// Called via ``BatteryMonitor/onLowBatteryTriggered`` when battery drops to 5%.
    /// Saves the track as an emergency ``SavedRoute`` in the database and also writes
    /// recovery files (marked with `routeAlreadySaved = true` to prevent duplicate
    /// creation on next launch). Then switches GPS to low-power mode.
    private func handleLowBattery(
        locationManager: LocationManager,
        healthKitManager: HealthKitManager,
        connectivityManager: WatchConnectivityReceiver
    ) {
        guard locationManager.isTracking, !locationManager.trackPoints.isEmpty else { return }

        let regionId = selectedRegion?.id

        // Save as a route in case battery dies completely.
        // Note: currentHeartRate is the latest reading, not a true average. Passed as nil
        // since we cannot compute a reliable average from HealthKit at this point.
        let routeSaved = TrackRecoveryManager.emergencySaveAsRoute(
            trackPoints: locationManager.trackPoints,
            totalDistance: locationManager.totalDistance,
            elevationGain: locationManager.elevationGain,
            elevationLoss: locationManager.elevationLoss,
            regionId: regionId,
            averageHeartRate: nil,
            connectivityManager: connectivityManager
        )

        // Save recovery file with routeAlreadySaved flag so recovery on next launch
        // does not create a duplicate route
        TrackRecoveryManager.saveState(
            trackPoints: locationManager.trackPoints,
            totalDistance: locationManager.totalDistance,
            elevationGain: locationManager.elevationGain,
            elevationLoss: locationManager.elevationLoss,
            regionId: regionId,
            routeAlreadySaved: routeSaved
        )

        // Switch to low-power GPS to conserve remaining battery
        locationManager.switchToLowPowerMode()
        stopAutoSaveTimer()

        if routeSaved {
            Self.logger.info("Low battery handled: emergency route saved, GPS switched to low power")
        } else {
            Self.logger.error("Low battery: emergency route save FAILED, recovery file written as fallback")
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
        .environmentObject(RouteGuidance())
        .environmentObject(UVIndexManager())
        .environmentObject(BatteryMonitor())
}
