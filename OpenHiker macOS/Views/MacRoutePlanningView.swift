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

/// macOS interactive route planning view.
///
/// Users click on the map to place start (green), end (red), and via-points (blue).
/// The ``RoutingEngine`` computes the optimal hiking or cycling path and displays
/// it as a polyline with distance, elevation, and turn-by-turn instructions.
///
/// ## Interaction Model
/// 1. First click → place start pin (green)
/// 2. Second click → place end pin (red), auto-compute route
/// 3. Subsequent clicks → add via-points (blue), re-compute
/// 4. Click existing pin → remove it
/// 5. Save → store to ``PlannedRouteStore``, sync to iPhone via iCloud
struct MacRoutePlanningView: View {
    @Environment(\.dismiss) private var dismiss

    /// The region whose routing database and tiles to use.
    let region: Region

    // MARK: - Route State

    /// Hiking or cycling mode.
    @State private var routingMode: RoutingMode = .hiking

    /// Start coordinate set by the user's first click.
    @State private var startCoordinate: CLLocationCoordinate2D?

    /// End coordinate set by the user's second click.
    @State private var endCoordinate: CLLocationCoordinate2D?

    /// Ordered via-points added after start and end.
    @State private var viaPoints: [CLLocationCoordinate2D] = []

    /// The computed route result from the routing engine.
    @State private var computedRoute: ComputedRoute?

    /// Turn-by-turn instructions for the computed route.
    @State private var turnInstructions: [TurnInstruction] = []

    /// Whether the routing engine is computing.
    @State private var isComputing = false

    /// Error message for the alert.
    @State private var errorMessage: String?

    /// Whether the error alert is shown.
    @State private var showError = false

    /// User-provided name for the route.
    @State private var routeName = ""

    /// Whether the save success alert is shown.
    @State private var showSaveSuccess = false

    /// Whether directions are expanded.
    @State private var showDirections = false

    /// Map camera position for the planning map.
    @State private var cameraPosition: MapCameraPosition = .automatic

    // MARK: - Body

    var body: some View {
        HSplitView {
            mapView
                .frame(minWidth: 400)

            sidePanel
                .frame(width: 320)
        }
        .navigationTitle("Plan Route — \(region.name)")
        .toolbar {
            ToolbarItemGroup {
                Picker("Mode", selection: $routingMode) {
                    Label("Hiking", systemImage: "figure.hiking").tag(RoutingMode.hiking)
                    Label("Cycling", systemImage: "bicycle").tag(RoutingMode.cycling)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                if computedRoute != nil {
                    Button("Save Route") {
                        saveRoute()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Clear All") {
                    clearAll()
                }
                .disabled(startCoordinate == nil)
            }
        }
        .onAppear {
            let center = region.boundingBox.center
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                span: MKCoordinateSpan(
                    latitudeDelta: region.boundingBox.north - region.boundingBox.south,
                    longitudeDelta: region.boundingBox.east - region.boundingBox.west
                )
            ))
        }
        .onChange(of: routingMode) { _, _ in
            computeRoute()
        }
        .alert("Route Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .alert("Route Saved", isPresented: $showSaveSuccess) {
            Button("OK", role: .cancel) {}
            Button("Sync to iPhone") {
                Task {
                    await CloudSyncManager.shared.performSync()
                }
            }
        } message: {
            Text("Your route has been saved. Sync to iPhone to transfer it to your Apple Watch.")
        }
    }

    // MARK: - Map View

    /// The interactive map with pin annotations and route polyline.
    private var mapView: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                // Start pin
                if let start = startCoordinate {
                    Annotation("Start", coordinate: start) {
                        pinView(color: .green, icon: "flag.fill")
                            .onTapGesture { removeStart() }
                    }
                }

                // End pin
                if let end = endCoordinate {
                    Annotation("End", coordinate: end) {
                        pinView(color: .red, icon: "mappin")
                            .onTapGesture { removeEnd() }
                    }
                }

                // Via-points
                ForEach(Array(viaPoints.enumerated()), id: \.offset) { index, point in
                    Annotation("Via \(index + 1)", coordinate: point) {
                        pinView(color: .blue, icon: "circle.fill")
                            .onTapGesture { removeViaPoint(at: index) }
                    }
                }

                // Route polyline
                if let route = computedRoute, route.coordinates.count >= 2 {
                    MapPolyline(coordinates: route.coordinates)
                        .stroke(.purple, lineWidth: 4)
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onTapGesture { screenPoint in
                if let coordinate = proxy.convert(screenPoint, from: .local) {
                    handleMapClick(coordinate)
                }
            }
        }
    }

    /// A colored pin marker for map annotations.
    private func pinView(color: Color, icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2)
    }

    // MARK: - Side Panel

    /// The side panel with instructions, stats, and directions.
    private var sidePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Instructions
                instructionSection

                // Stats
                if let route = computedRoute {
                    statsSection(route)
                }

                if isComputing {
                    HStack {
                        ProgressView()
                        Text("Computing route...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }

                // Directions
                if !turnInstructions.isEmpty {
                    directionsSection
                }

                // Route name + save
                if computedRoute != nil {
                    saveSection
                }
            }
            .padding()
        }
    }

    /// Current instruction text based on pin placement state.
    private var instructionSection: some View {
        HStack(spacing: 12) {
            Image(systemName: instructionIcon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(instructionTitle)
                    .font(.headline)
                Text(instructionSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Route statistics display.
    private func statsSection(_ route: ComputedRoute) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Route Statistics")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                statItem(icon: "ruler", label: "Distance",
                         value: HikeStatsFormatter.formatDistance(route.totalDistance, useMetric: true))
                Spacer()
                statItem(icon: "clock", label: "Duration",
                         value: formatDuration(route.estimatedDuration))
            }

            HStack {
                statItem(icon: "arrow.up.right", label: "Gain",
                         value: "+\(HikeStatsFormatter.formatElevation(route.elevationGain, useMetric: true))")
                Spacer()
                statItem(icon: "arrow.down.right", label: "Loss",
                         value: "-\(HikeStatsFormatter.formatElevation(route.elevationLoss, useMetric: true))")
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    /// A single stat item.
    private func statItem(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
    }

    /// Turn-by-turn directions section.
    private var directionsSection: some View {
        DisclosureGroup("Directions (\(turnInstructions.count) steps)", isExpanded: $showDirections) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(turnInstructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: instruction.direction.sfSymbolName)
                            .frame(width: 20)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(instruction.description)
                                .font(.caption)
                            if instruction.distanceFromPrevious > 0 {
                                Text(HikeStatsFormatter.formatDistance(instruction.distanceFromPrevious, useMetric: true))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    /// Route save section with name field.
    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save Route")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Route name", text: $routeName)
                .textFieldStyle(.roundedBorder)

            Button {
                saveRoute()
            } label: {
                HStack {
                    Spacer()
                    Label("Save & Sync", systemImage: "square.and.arrow.down")
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Instruction State

    private var instructionIcon: String {
        if startCoordinate == nil { return "1.circle" }
        if endCoordinate == nil { return "2.circle" }
        return "checkmark.circle"
    }

    private var instructionTitle: String {
        if startCoordinate == nil { return "Set Start Point" }
        if endCoordinate == nil { return "Set Destination" }
        return "Route Ready"
    }

    private var instructionSubtitle: String {
        if startCoordinate == nil { return "Click the map to place the start pin" }
        if endCoordinate == nil { return "Click to set your destination" }
        return "Click to add via-points, or save your route"
    }

    // MARK: - Actions

    /// Handles a click on the map to place pins.
    private func handleMapClick(_ coordinate: CLLocationCoordinate2D) {
        if startCoordinate == nil {
            startCoordinate = coordinate
        } else if endCoordinate == nil {
            endCoordinate = coordinate
            computeRoute()
        } else {
            viaPoints.append(coordinate)
            computeRoute()
        }
    }

    /// Removes the start pin and clears the route.
    private func removeStart() {
        startCoordinate = nil
        computedRoute = nil
        turnInstructions = []
    }

    /// Removes the end pin and clears the route.
    private func removeEnd() {
        endCoordinate = nil
        computedRoute = nil
        turnInstructions = []
    }

    /// Removes a via-point and recomputes the route.
    private func removeViaPoint(at index: Int) {
        viaPoints.remove(at: index)
        computeRoute()
    }

    /// Clears all pins and the computed route.
    private func clearAll() {
        startCoordinate = nil
        endCoordinate = nil
        viaPoints.removeAll()
        computedRoute = nil
        turnInstructions = []
        routeName = ""
    }

    /// Computes the route using the routing engine.
    private func computeRoute() {
        guard let start = startCoordinate, let end = endCoordinate else { return }

        isComputing = true
        computedRoute = nil
        turnInstructions = []

        Task {
            do {
                let routingDbPath = RegionStorage.shared.routingDbURL(for: region).path

                let engine = RoutingEngine()
                try engine.open(databasePath: routingDbPath)

                let route = try engine.findRoute(
                    from: start,
                    to: end,
                    viaPoints: viaPoints,
                    mode: routingMode
                )

                let instructions = TurnInstructionGenerator.generate(from: route)

                await MainActor.run {
                    self.computedRoute = route
                    self.turnInstructions = instructions
                    self.isComputing = false
                }
            } catch {
                await MainActor.run {
                    self.isComputing = false
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }

    /// Saves the planned route and triggers iCloud sync.
    private func saveRoute() {
        guard let route = computedRoute else { return }

        let name = routeName.isEmpty ? "Route \(Date().formatted(date: .abbreviated, time: .omitted))" : routeName
        let planned = PlannedRoute.from(
            computedRoute: route,
            name: name,
            mode: routingMode,
            regionId: region.id
        )

        do {
            try PlannedRouteStore.shared.save(planned)
            showSaveSuccess = true
        } catch {
            errorMessage = "Failed to save route: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Formats a duration in seconds to a human-readable string.
    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
