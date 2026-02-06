import SwiftUI
import SpriteKit
import CoreLocation
import WatchKit

/// SwiftUI wrapper for the SpriteKit map scene
struct MapView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var connectivityManager: WatchConnectivityReceiver

    @StateObject private var mapRenderer = MapRenderer()
    @State private var showingRegionPicker = false
    @State private var selectedRegion: RegionMetadata?
    @State private var isCenteredOnUser = true
    @State private var mapScene: MapScene?
    @State private var pickedRegion: RegionMetadata?

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
        }
        .onChange(of: mapRenderer.currentZoom) { _, _ in
            mapScene?.updateVisibleTiles()
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            updateUserPosition(newLocation)
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
    }

    // MARK: - Subviews

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

    private var bottomControls: some View {
        HStack(spacing: 16) {
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

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isCenteredOnUser = false
                // Pan the map
                // This would require implementing pan logic in MapRenderer
            }
    }

    // MARK: - Actions

    private func loadSavedRegion() {
        // Try to load the most recently used region
        let regions = connectivityManager.loadAllRegionMetadata()
        if let lastRegion = regions.first {
            loadRegion(lastRegion)
        }
    }

    private func loadRegion(_ region: RegionMetadata) {
        do {
            try mapRenderer.loadRegion(region)
            selectedRegion = region
            // Create the scene once after loading; SpriteView will reuse it
            mapScene = mapRenderer.createScene(size: WKInterfaceDevice.current().screenBounds.size)
        } catch {
            print("Error loading region: \(error.localizedDescription)")
        }
    }

    private func updateUserPosition(_ location: CLLocation?) {
        guard let location = location else { return }

        // Update position marker on map
        mapScene?.updatePositionMarker(coordinate: location.coordinate)

        // Center map on user if enabled
        if isCenteredOnUser {
            mapRenderer.setCenter(location.coordinate)
        }
    }

    private func centerOnUser() {
        guard let location = locationManager.currentLocation else {
            locationManager.requestSingleLocation()
            return
        }

        isCenteredOnUser = true
        mapRenderer.setCenter(location.coordinate)
    }

    private func toggleTracking() {
        if locationManager.isTracking {
            locationManager.stopTracking()
        } else {
            locationManager.startTracking()
        }
    }
}

// MARK: - Region Picker Sheet

struct RegionPickerSheet: View {
    let regions: [RegionMetadata]
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
}
