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
import Charts

// MARK: - Route Detail View

/// Read-only view of a saved planned route.
///
/// Shows the route polyline on a MapKit map, statistics summary (distance, time,
/// elevation), and a scrollable list of turn-by-turn directions. Provides a
/// "Send to Watch" button to transfer the route for active guidance.
struct RouteDetailView: View {
    @EnvironmentObject var watchConnectivity: WatchConnectivityManager

    /// The planned route to display. Mutable so the user can rename.
    @State private var route: PlannedRoute

    /// Callback invoked when the route is updated (e.g. renamed), so the parent list can refresh.
    var onUpdate: () -> Void = {}

    /// Whether the "sent to watch" confirmation is shown.
    @State private var showSentConfirmation = false

    /// Error message from failed transfers.
    @State private var errorMessage: String?

    /// Whether the error alert is displayed.
    @State private var showError = false

    /// Text field binding for the rename alert.
    @State private var renameText = ""

    /// Whether the rename alert is displayed.
    @State private var showRenameAlert = false

    /// Creates a RouteDetailView for the given route.
    ///
    /// - Parameters:
    ///   - route: The ``PlannedRoute`` to display.
    ///   - onUpdate: Closure called when the route is modified (defaults to no-op).
    init(route: PlannedRoute, onUpdate: @escaping () -> Void = {}) {
        _route = State(initialValue: route)
        self.onUpdate = onUpdate
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Map with route polyline
                mapSection

                // Statistics
                statsSection

                // Elevation profile
                if let profile = route.elevationProfile, profile.count >= 2 {
                    elevationProfileSection(profile)
                }

                // Send to Watch button
                sendToWatchButton

                // Turn-by-turn directions
                directionsSection
            }
            .padding()
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    renameText = route.name
                    showRenameAlert = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .alert("Sent to Watch", isPresented: $showSentConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The route has been queued for transfer to your Apple Watch.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An error occurred.")
        }
        .alert("Rename Route", isPresented: $showRenameAlert) {
            TextField("Route name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                route.name = trimmed
                route.modifiedAt = Date()
                try? PlannedRouteStore.shared.save(route)
                onUpdate()
            }
        } message: {
            Text("Enter a new name for this route.")
        }
    }

    // MARK: - Map Section

    /// Path to the region's MBTiles file for offline topographic tile rendering.
    ///
    /// Looks up the region by the route's stored `regionId`, then resolves the MBTiles
    /// file path via ``RegionStorage``. Returns `nil` if the region is unknown or the
    /// file has been deleted.
    private var routeMBTilesPath: String? {
        guard let regionId = route.regionId,
              let region = RegionStorage.shared.regions.first(where: { $0.id == regionId }) else {
            return nil
        }
        let url = RegionStorage.shared.mbtilesURL(for: region)
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }

    /// Geographic center of the route, computed from the bounding box of all coordinates.
    private var routeCenter: CLLocationCoordinate2D {
        let lats = route.coordinates.map(\.latitude)
        let lons = route.coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return route.startCoordinate
        }
        return CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
    }

    /// Latitude span of the route with 30% padding for comfortable viewing.
    private var routeLatSpan: Double {
        let lats = route.coordinates.map(\.latitude)
        guard let minLat = lats.min(), let maxLat = lats.max() else { return 0.05 }
        let padding: Double = 1.3
        return (maxLat - minLat) * padding
    }

    /// Longitude span of the route with 30% padding for comfortable viewing.
    private var routeLonSpan: Double {
        let lons = route.coordinates.map(\.longitude)
        guard let minLon = lons.min(), let maxLon = lons.max() else { return 0.05 }
        let padding: Double = 1.3
        return (maxLon - minLon) * padding
    }

    /// Route annotations built from the saved start, end, and via-point coordinates.
    private var routeAnnotations: [RouteAnnotation] {
        var result: [RouteAnnotation] = []
        result.append(RouteAnnotation(coordinate: route.startCoordinate, type: .start, index: 0))
        for (i, via) in route.viaPoints.enumerated() {
            result.append(RouteAnnotation(coordinate: via, type: .via, index: i))
        }
        result.append(RouteAnnotation(coordinate: route.endCoordinate, type: .end, index: 0))
        return result
    }

    /// The map showing the route polyline and start/end markers on topographic tiles.
    private var mapSection: some View {
        RoutePlanningMapView(
            mbtilesPath: routeMBTilesPath,
            initialCenter: routeCenter,
            initialLatSpan: routeLatSpan,
            initialLonSpan: routeLonSpan,
            annotations: routeAnnotations,
            routeCoordinates: route.coordinates,
            repositioningAnnotationId: nil
        )
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Stats Section

    /// Route statistics grid showing distance, time, and elevation.
    private var statsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Route Details")
                    .font(.headline)
                Spacer()
                Text(route.mode == .hiking ? "Hiking" : "Cycling")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(route.mode == .hiking ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                    )
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                DetailStatItem(
                    icon: "ruler",
                    label: "Distance",
                    value: HikeStatsFormatter.formatDistance(route.totalDistance, useMetric: true)
                )
                DetailStatItem(
                    icon: "clock",
                    label: "Est. Time",
                    value: route.formattedDuration
                )
                DetailStatItem(
                    icon: "arrow.up.right",
                    label: "Gain",
                    value: "+\(HikeStatsFormatter.formatElevation(route.elevationGain, useMetric: true))"
                )
                DetailStatItem(
                    icon: "arrow.down.right",
                    label: "Loss",
                    value: "-\(HikeStatsFormatter.formatElevation(route.elevationLoss, useMetric: true))"
                )
                DetailStatItem(
                    icon: "calendar",
                    label: "Created",
                    value: route.formattedDate
                )
                DetailStatItem(
                    icon: "point.bottomleft.forward.to.point.topright.scurvepath",
                    label: "Turns",
                    value: "\(route.turnInstructions.count)"
                )
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    // MARK: - Elevation Profile

    /// Elevation profile chart rendered from the route's pre-computed elevation data.
    ///
    /// - Parameter profile: Array of ``ElevationPoint``s with distance and elevation.
    /// - Returns: A chart view wrapped in a card container.
    private func elevationProfileSection(_ profile: [ElevationPoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Elevation Profile")
                .font(.headline)

            let data = profile.map { (distance: $0.distance, elevation: $0.elevation) }
            ElevationProfileView(elevationData: data, useMetric: true)
                .frame(height: 160)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    // MARK: - Send to Watch

    /// Button to transfer the planned route to the Apple Watch.
    private var sendToWatchButton: some View {
        Button {
            sendToWatch()
        } label: {
            Label("Send to Watch", systemImage: "applewatch.radiowaves.left.and.right")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(.purple)
    }

    // MARK: - Directions Section

    /// Scrollable list of turn-by-turn directions.
    private var directionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Directions")
                .font(.headline)

            ForEach(Array(route.turnInstructions.enumerated()), id: \.offset) { index, instruction in
                HStack(alignment: .top, spacing: 12) {
                    // Step number
                    Text("\(index + 1)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.purple.opacity(0.15)))

                    // Direction icon
                    Image(systemName: instruction.direction.sfSymbolName)
                        .font(.body)
                        .foregroundStyle(.purple)
                        .frame(width: 24)

                    // Instruction text
                    VStack(alignment: .leading, spacing: 2) {
                        Text(instruction.description)
                            .font(.subheadline)
                        if instruction.distanceFromPrevious > 0 {
                            Text("In \(HikeStatsFormatter.formatDistance(instruction.distanceFromPrevious, useMetric: true))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 4)

                if index < route.turnInstructions.count - 1 {
                    Divider()
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    // MARK: - Actions

    /// Transfers the planned route JSON file to the Apple Watch.
    private func sendToWatch() {
        guard let fileURL = PlannedRouteStore.shared.fileURL(for: route.id) else {
            errorMessage = "Route file not found. Try saving the route again."
            showError = true
            return
        }

        watchConnectivity.sendPlannedRouteToWatch(fileURL: fileURL, route: route)
        showSentConfirmation = true
    }
}

// MARK: - Detail Stat Item

/// A stat item with icon, label, and value for the route detail view.
private struct DetailStatItem: View {
    /// SF Symbol name for the stat icon.
    let icon: String
    /// Label text (e.g., "Distance").
    let label: String
    /// Value text (e.g., "12.4 km").
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.purple)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
