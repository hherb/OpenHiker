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

    /// The region whose routing database and map tiles to use.
    let region: Region

    /// The routing mode: hiking or cycling.
    @State private var routingMode: RoutingMode = .hiking

    /// Ordered waypoints placed by the user. First = start, last = end (or loop back).
    @State private var waypoints: [CLLocationCoordinate2D] = []

    /// Whether the last computed route is a loop (returns to start).
    @State private var isLoopRoute = false

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

    /// Map annotations derived from the ordered waypoints list.
    ///
    /// First waypoint is green (start), last is red (end), middle ones are blue (via).
    /// When only one waypoint exists, it is shown as start (green).
    private var annotations: [RouteAnnotation] {
        waypoints.enumerated().map { index, coordinate in
            let type: RouteAnnotation.AnnotationType
            if index == 0 {
                type = .start
            } else if index == waypoints.count - 1 {
                type = .end
            } else {
                type = .via
            }
            return RouteAnnotation(
                coordinate: coordinate,
                type: type,
                index: index
            )
        }
    }

    /// Instruction text shown below the map guiding the user's next action.
    private var instructionText: String {
        if let annotation = repositioningAnnotation {
            return "Tap the map to reposition \(annotation.label)"
        } else if waypoints.isEmpty {
            return "Tap the map to place waypoints"
        } else if waypoints.count == 1 {
            return "Tap to add more waypoints (need at least 2)"
        } else {
            return "Tap to add waypoints, or compute your route"
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

                // Mode toggle + route computation buttons
                modeToggle
                routeActionButtons

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

    /// Path to the region's MBTiles file for offline topographic tile rendering.
    private var regionMBTilesPath: String? {
        let url = RegionStorage.shared.mbtilesURL(for: region)
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }

    /// Initial latitude span for the map, derived from the region's bounding box.
    private var regionLatSpan: Double {
        region.boundingBox.north - region.boundingBox.south
    }

    /// Initial longitude span for the map, derived from the region's bounding box.
    private var regionLonSpan: Double {
        region.boundingBox.east - region.boundingBox.west
    }

    /// The `MKMapView`-based map with offline topographic tiles, annotations, and route polyline.
    private var mapContent: some View {
        RoutePlanningMapView(
            mbtilesPath: regionMBTilesPath,
            initialCenter: region.boundingBox.center,
            initialLatSpan: regionLatSpan,
            initialLonSpan: regionLonSpan,
            annotations: annotations,
            routeCoordinates: computedRoute?.coordinates ?? [],
            repositioningAnnotationId: repositioningAnnotation?.id,
            onMapTap: { coordinate in
                handleMapTap(coordinate)
            },
            onAnnotationTap: { annotation in
                if repositioningAnnotation != nil {
                    repositioningAnnotation = nil
                } else {
                    removeAnnotation(annotation)
                }
            },
            onAnnotationLongPress: { annotation in
                repositioningAnnotation = annotation
            }
        )
    }

    // MARK: - Mode Toggle

    /// Hiking / Cycling mode picker.
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
    }

    /// Buttons for computing the route from the placed waypoints.
    ///
    /// - "Start → End": routes through waypoints in order (1→2→3→4→5)
    /// - "Back to Start": routes through all waypoints and returns to the first (1→2→3→4→5→1)
    private var routeActionButtons: some View {
        HStack(spacing: 12) {
            Button {
                computeRouteFromWaypoints(loop: false)
            } label: {
                Label("Start → End", systemImage: "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(waypoints.count < 2 || isComputing)

            Button {
                computeRouteFromWaypoints(loop: true)
            } label: {
                Label("Back to Start", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(waypoints.count < 2 || isComputing)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
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

    /// Handles a tap on the map by placing the next waypoint or repositioning a selected pin.
    ///
    /// If a pin is selected for repositioning (via long-press), the tap moves that pin
    /// to the new coordinate. Otherwise, taps append waypoints sequentially.
    ///
    /// - Parameter coordinate: The tapped geographic coordinate.
    private func handleMapTap(_ coordinate: CLLocationCoordinate2D) {
        // Handle reposition mode
        if let annotation = repositioningAnnotation {
            repositionAnnotation(annotation, to: coordinate)
            repositioningAnnotation = nil
            return
        }

        // Append new waypoint
        waypoints.append(coordinate)
        // Clear any previously computed route since waypoints changed
        computedRoute = nil
        turnInstructions = []
    }

    /// Moves an existing annotation to a new coordinate.
    ///
    /// - Parameters:
    ///   - annotation: The annotation to reposition.
    ///   - coordinate: The new geographic coordinate.
    private func repositionAnnotation(_ annotation: RouteAnnotation, to coordinate: CLLocationCoordinate2D) {
        if annotation.index < waypoints.count {
            waypoints[annotation.index] = coordinate
        }
        // Clear route since waypoints changed
        computedRoute = nil
        turnInstructions = []
    }

    /// Removes a waypoint and clears the computed route.
    ///
    /// - Parameter annotation: The annotation to remove.
    private func removeAnnotation(_ annotation: RouteAnnotation) {
        if annotation.index < waypoints.count {
            waypoints.remove(at: annotation.index)
        }
        computedRoute = nil
        turnInstructions = []
    }

    /// Computes a route through all waypoints in order.
    ///
    /// Uses the first waypoint as start and last as end, with all intermediate
    /// waypoints as via-points. If `loop` is true, the route returns to the start.
    ///
    /// - Parameter loop: If true, routes back to the first waypoint (round-trip).
    private func computeRouteFromWaypoints(loop: Bool) {
        guard waypoints.count >= 2 else { return }

        let start = waypoints[0]
        let end = loop ? waypoints[0] : waypoints[waypoints.count - 1]
        let via: [CLLocationCoordinate2D]
        if loop {
            // Loop: 1→2→3→4→5→1, via = waypoints[1..<count]
            via = Array(waypoints.dropFirst())
        } else {
            // One-way: 1→2→3→4→5, via = waypoints[1..<count-1]
            via = waypoints.count > 2 ? Array(waypoints[1..<waypoints.count - 1]) : []
        }

        isLoopRoute = loop
        isComputing = true
        computedRoute = nil
        turnInstructions = []

        Task.detached(priority: .userInitiated) {
            do {
                let route = try await computeRoute(from: start, to: end, via: via, mode: routingMode)
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
    ///   - via: Ordered via-points between start and end.
    ///   - mode: Routing mode (hiking or cycling).
    /// - Returns: A ``ComputedRoute``.
    /// - Throws: ``RoutingError`` on failure.
    private func computeRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        via: [CLLocationCoordinate2D],
        mode: RoutingMode
    ) throws -> ComputedRoute {
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

    /// The display label showing the waypoint number.
    var label: String {
        switch type {
        case .start: return "WP 1"
        case .end:   return "WP \(index + 1)"
        case .via:   return "WP \(index + 1)"
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
