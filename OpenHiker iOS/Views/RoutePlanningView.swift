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

// MARK: - Route Planning View

/// Interactive route planning view for the iPhone.
///
/// Users tap on the map to place start (green), end (red), and optional via-points (blue).
/// The routing engine computes the optimal hiking or cycling path and displays it as a
/// polyline with statistics. Pins can be long-pressed to drag, and tapped to remove.
///
/// ## Interaction Model
/// 1. First tap → place start pin (green)
/// 2. Second tap → place end pin (red), auto-compute route
/// 3. Subsequent taps → add via-points (blue), re-compute route
/// 4. Mode toggle → switch hiking/cycling, re-compute
/// 5. Save → store to PlannedRouteStore, option to transfer to watch
struct RoutePlanningView: View {
    @EnvironmentObject var watchConnectivity: WatchConnectivityManager
    @Environment(\.dismiss) private var dismiss

    /// The region whose routing database to use.
    let region: Region?

    /// The routing mode: hiking or cycling.
    @State private var routingMode: RoutingMode = .hiking

    /// The start coordinate set by the user's first tap.
    @State private var startCoordinate: CLLocationCoordinate2D?

    /// The end coordinate set by the user's second tap.
    @State private var endCoordinate: CLLocationCoordinate2D?

    /// Ordered via-points added by the user after start and end.
    @State private var viaPoints: [CLLocationCoordinate2D] = []

    /// The computed route result from the routing engine.
    @State private var computedRoute: ComputedRoute?

    /// The generated turn instructions for the computed route.
    @State private var turnInstructions: [TurnInstruction] = []

    /// Whether the routing engine is currently computing.
    @State private var isComputing = false

    /// Error message to display in the alert.
    @State private var errorMessage: String?

    /// Whether the error alert is shown.
    @State private var showError = false

    /// The user-provided name for the route (for saving).
    @State private var routeName = ""

    /// Whether the save confirmation alert is shown.
    @State private var showSaveSuccess = false

    /// Whether the directions list is expanded.
    @State private var showDirections = false

    /// The annotation currently being repositioned via long-press, or `nil` if not active.
    @State private var repositioningAnnotation: RouteAnnotation?

    /// The map camera position.
    @State private var cameraPosition: MapCameraPosition = .automatic

    /// Map annotations (start, end, via-points).
    private var annotations: [RouteAnnotation] {
        var result: [RouteAnnotation] = []

        if let start = startCoordinate {
            result.append(RouteAnnotation(
                coordinate: start,
                type: .start,
                index: 0
            ))
        }

        for (index, via) in viaPoints.enumerated() {
            result.append(RouteAnnotation(
                coordinate: via,
                type: .via,
                index: index
            ))
        }

        if let end = endCoordinate {
            result.append(RouteAnnotation(
                coordinate: end,
                type: .end,
                index: 0
            ))
        }

        return result
    }

    /// Instruction text shown below the map guiding the user's next action.
    private var instructionText: String {
        if let annotation = repositioningAnnotation {
            return "Tap the map to reposition \(annotation.label)"
        } else if startCoordinate == nil {
            return "Tap the map to set a start point"
        } else if endCoordinate == nil {
            return "Tap the map to set your destination"
        } else {
            return "Tap to add via-points, or save your route"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Map
                mapContent
                    .frame(maxHeight: .infinity)

                // Instruction hint
                HStack {
                    Text(instructionText)
                        .font(.caption)
                        .foregroundStyle(repositioningAnnotation != nil ? .orange : .secondary)

                    if repositioningAnnotation != nil {
                        Button("Cancel") {
                            repositioningAnnotation = nil
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
                .padding(.vertical, 4)

                // Mode toggle
                modeToggle

                // Stats & Directions
                if computedRoute != nil {
                    statsSection
                }
            }
            .navigationTitle("Plan Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") { saveRoute() }
                        .disabled(computedRoute == nil || isComputing)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
            .alert("Route Saved", isPresented: $showSaveSuccess) {
                Button("OK") { dismiss() }
                Button("Send to Watch") {
                    sendToWatch()
                    dismiss()
                }
            } message: {
                Text("Your route has been saved. Would you like to send it to your Apple Watch?")
            }
        }
    }

    // MARK: - Map Content

    /// The MapKit map view with tap gesture, annotations, and route polyline.
    private var mapContent: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                // Annotations
                ForEach(annotations) { annotation in
                    Annotation(
                        annotation.label,
                        coordinate: annotation.coordinate
                    ) {
                        annotationView(for: annotation)
                    }
                }

                // Route polyline
                if let route = computedRoute, route.coordinates.count >= 2 {
                    MapPolyline(coordinates: route.coordinates)
                        .stroke(.purple, lineWidth: 4)
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .onTapGesture { position in
                if let coordinate = proxy.convert(position, from: .local) {
                    handleMapTap(coordinate)
                }
            }
        }
    }

    /// Returns the appropriate pin view for a route annotation.
    ///
    /// Tap removes the pin. Long-press enters reposition mode, which highlights the pin
    /// with a pulsing ring and makes the next map tap reposition this pin.
    ///
    /// - Parameter annotation: The annotation to render.
    /// - Returns: A colored circle view with tap and long-press gestures.
    @ViewBuilder
    private func annotationView(for annotation: RouteAnnotation) -> some View {
        let isRepositioning = repositioningAnnotation?.id == annotation.id

        Circle()
            .fill(annotation.color)
            .frame(width: 28, height: 28)
            .overlay(
                Circle().stroke(isRepositioning ? .yellow : .white, lineWidth: isRepositioning ? 3 : 2)
            )
            .shadow(color: isRepositioning ? .yellow.opacity(0.6) : .black.opacity(0.2), radius: isRepositioning ? 6 : 2)
            .scaleEffect(isRepositioning ? 1.3 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: isRepositioning)
            .onTapGesture {
                if repositioningAnnotation != nil {
                    repositioningAnnotation = nil
                } else {
                    removeAnnotation(annotation)
                }
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                repositioningAnnotation = annotation
            }
    }

    // MARK: - Mode Toggle

    /// Hiking / Cycling mode picker that re-computes the route when changed.
    private var modeToggle: some View {
        Picker("Mode", selection: $routingMode) {
            Label("Hiking", systemImage: "figure.hiking")
                .tag(RoutingMode.hiking)
            Label("Cycling", systemImage: "bicycle")
                .tag(RoutingMode.cycling)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 4)
        .onChange(of: routingMode) { _, _ in
            computeRouteIfReady()
        }
    }

    // MARK: - Stats Section

    /// Route statistics and expandable directions list.
    private var statsSection: some View {
        VStack(spacing: 0) {
            // Statistics summary
            if let route = computedRoute {
                HStack(spacing: 16) {
                    StatItem(
                        label: "Distance",
                        value: HikeStatsFormatter.formatDistance(route.totalDistance, useMetric: true)
                    )
                    StatItem(
                        label: "Est. Time",
                        value: formatDuration(route.estimatedDuration)
                    )
                    StatItem(
                        label: "Elevation",
                        value: "+\(HikeStatsFormatter.formatElevation(route.elevationGain, useMetric: true)) / -\(HikeStatsFormatter.formatElevation(route.elevationLoss, useMetric: true))"
                    )
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Loading indicator
            if isComputing {
                ProgressView("Computing route...")
                    .padding(.vertical, 4)
            }

            // Directions toggle
            if !turnInstructions.isEmpty {
                DisclosureGroup("Directions (\(turnInstructions.count) steps)", isExpanded: $showDirections) {
                    directionsListContent
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .background(.ultraThinMaterial)
    }

    /// The list of turn-by-turn instructions.
    private var directionsListContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(turnInstructions.enumerated()), id: \.offset) { index, instruction in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: instruction.direction.sfSymbolName)
                        .font(.body)
                        .foregroundStyle(.purple)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(instruction.description)
                            .font(.subheadline)
                        if instruction.distanceFromPrevious > 0 {
                            Text(HikeStatsFormatter.formatDistance(instruction.distanceFromPrevious, useMetric: true))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Actions

    /// Handles a tap on the map by placing the next pin or repositioning a selected pin.
    ///
    /// If a pin is selected for repositioning (via long-press), the tap moves that pin
    /// to the new coordinate and re-computes the route. Otherwise, taps place pins in
    /// sequence: first tap = start, second = end, subsequent = via-points.
    ///
    /// - Parameter coordinate: The tapped geographic coordinate.
    private func handleMapTap(_ coordinate: CLLocationCoordinate2D) {
        // Handle reposition mode
        if let annotation = repositioningAnnotation {
            repositionAnnotation(annotation, to: coordinate)
            repositioningAnnotation = nil
            return
        }

        // Normal pin placement
        if startCoordinate == nil {
            startCoordinate = coordinate
        } else if endCoordinate == nil {
            endCoordinate = coordinate
            computeRouteIfReady()
        } else {
            viaPoints.append(coordinate)
            computeRouteIfReady()
        }
    }

    /// Moves an existing annotation to a new coordinate and re-computes the route.
    ///
    /// - Parameters:
    ///   - annotation: The annotation to reposition.
    ///   - coordinate: The new geographic coordinate.
    private func repositionAnnotation(_ annotation: RouteAnnotation, to coordinate: CLLocationCoordinate2D) {
        switch annotation.type {
        case .start:
            startCoordinate = coordinate
        case .end:
            endCoordinate = coordinate
        case .via:
            if annotation.index < viaPoints.count {
                viaPoints[annotation.index] = coordinate
            }
        }
        computeRouteIfReady()
    }

    /// Removes an annotation (start, end, or via-point) and re-computes the route.
    ///
    /// - Parameter annotation: The annotation to remove.
    private func removeAnnotation(_ annotation: RouteAnnotation) {
        switch annotation.type {
        case .start:
            startCoordinate = nil
            computedRoute = nil
            turnInstructions = []
        case .end:
            endCoordinate = nil
            computedRoute = nil
            turnInstructions = []
        case .via:
            if annotation.index < viaPoints.count {
                viaPoints.remove(at: annotation.index)
                computeRouteIfReady()
            }
        }
    }

    /// Computes the route if both start and end coordinates are set.
    ///
    /// Opens the region's routing database, runs the A* routing engine, generates
    /// turn instructions, and updates the view state. All errors are surfaced via
    /// the error alert.
    private func computeRouteIfReady() {
        guard let start = startCoordinate, let end = endCoordinate else { return }

        isComputing = true
        computedRoute = nil
        turnInstructions = []

        Task.detached(priority: .userInitiated) {
            do {
                let route = try await computeRoute(from: start, to: end, via: viaPoints, mode: routingMode)
                let instructions = TurnInstructionGenerator.generate(from: route)

                await MainActor.run {
                    self.computedRoute = route
                    self.turnInstructions = instructions
                    self.isComputing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isComputing = false
                }
            }
        }
    }

    /// Opens the routing database and computes a route.
    ///
    /// This runs on a background thread to avoid blocking the UI.
    ///
    /// - Parameters:
    ///   - from: Start coordinate.
    ///   - to: End coordinate.
    ///   - via: Via-points.
    ///   - mode: Routing mode.
    /// - Returns: A ``ComputedRoute``.
    /// - Throws: ``RoutingError`` on failure.
    private func computeRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        via: [CLLocationCoordinate2D],
        mode: RoutingMode
    ) throws -> ComputedRoute {
        guard let region = region else {
            throw RoutingError.noRoutingData
        }

        let storage = RegionStorage.shared
        let routingDbURL = storage.routingDbURL(for: region)

        guard FileManager.default.fileExists(atPath: routingDbURL.path) else {
            throw RoutingError.noRoutingData
        }

        let store = RoutingStore(path: routingDbURL.path)
        try store.open()
        defer { store.close() }

        let engine = RoutingEngine(store: store)
        return try engine.findRoute(from: from, to: to, via: via, mode: mode)
    }

    /// Saves the current route to the ``PlannedRouteStore``.
    private func saveRoute() {
        guard let route = computedRoute else { return }

        let name = routeName.isEmpty
            ? "Route — \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))"
            : routeName

        let planned = PlannedRoute.from(
            computedRoute: route,
            name: name,
            mode: routingMode,
            regionId: region?.id
        )

        do {
            try PlannedRouteStore.shared.save(planned)
            showSaveSuccess = true
        } catch {
            errorMessage = "Failed to save route: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Sends the most recently saved route to the Apple Watch.
    private func sendToWatch() {
        guard let route = PlannedRouteStore.shared.routes.first,
              let fileURL = PlannedRouteStore.shared.fileURL(for: route.id) else {
            return
        }

        watchConnectivity.sendPlannedRouteToWatch(fileURL: fileURL, route: route)
    }

    /// Formats a duration in seconds as "Xh Ym".
    ///
    /// - Parameter seconds: Duration in seconds.
    /// - Returns: Formatted string.
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Route Annotation

/// A map annotation representing a point in the route planning flow.
///
/// Used to render start (green), end (red), and via-point (blue) pins on the map.
struct RouteAnnotation: Identifiable {
    /// Unique ID combining type and index.
    var id: String { "\(type.rawValue)-\(index)" }

    /// Geographic coordinate of this annotation.
    let coordinate: CLLocationCoordinate2D

    /// The annotation type (start, end, or via-point).
    let type: AnnotationType

    /// Index within its type (used for via-points).
    let index: Int

    /// The types of route annotations.
    enum AnnotationType: String {
        case start
        case end
        case via
    }

    /// The display color for this annotation type.
    var color: Color {
        switch type {
        case .start: return .green
        case .end:   return .red
        case .via:   return .blue
        }
    }

    /// The display label for this annotation type.
    var label: String {
        switch type {
        case .start: return "Start"
        case .end:   return "End"
        case .via:   return "Via \(index + 1)"
        }
    }
}

// MARK: - Stat Item

/// A small labeled stat display used in the route statistics bar.
private struct StatItem: View {
    /// The stat label (e.g., "Distance").
    let label: String
    /// The stat value (e.g., "12.4 km").
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}
