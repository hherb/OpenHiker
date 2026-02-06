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

/// Detail view for a community-shared route.
///
/// Fetches the full route data from GitHub when opened, then displays:
/// - Map with the track polyline
/// - Statistics grid
/// - Description
/// - Waypoints list
/// - "Download for Offline Use" button
///
/// The route is fetched lazily — only the index summary is available initially.
/// The full route (with track points and waypoints) is loaded on demand.
struct CommunityRouteDetailView: View {
    /// The route summary from the index (available immediately).
    let entry: RouteIndexEntry

    /// The full route data (fetched on appear).
    @State private var sharedRoute: SharedRoute?

    /// Decoded track coordinates for the map polyline.
    @State private var trackCoordinates: [CLLocationCoordinate2D] = []

    /// The map camera position (computed from track bounds or bounding box).
    @State private var cameraPosition: MapCameraPosition = .automatic

    /// Whether the route data is being fetched.
    @State private var isLoadingRoute = true

    /// Whether a download-for-offline operation is in progress.
    @State private var isDownloading = false

    /// Whether the route was successfully saved for offline use.
    @State private var isSavedOffline = false

    /// Error message shown on failure.
    @State private var errorMessage: String?

    /// Whether the error alert is displayed.
    @State private var showError = false

    /// Factor applied to track bounds to add visual padding around the polyline.
    private static let mapBoundsPaddingFactor = 1.2

    /// Minimum coordinate span in degrees for the map region.
    private static let mapMinSpanDegrees = 0.005

    /// Height in points for the map section.
    private static let mapHeight: CGFloat = 280

    /// Corner radius in points for rounded containers.
    private static let containerCornerRadius: CGFloat = 12

    /// Content spacing in points between major sections.
    private static let sectionSpacing: CGFloat = 16

    /// Spacing within stat card grids.
    private static let statGridSpacing: CGFloat = 12

    /// Padding inside stat cards.
    private static let statCardPadding: CGFloat = 8

    /// Corner radius for stat cards.
    private static let statCardCornerRadius: CGFloat = 8

    /// Width of a waypoint category icon.
    private static let waypointIconWidth: CGFloat = 24

    /// Stroke width for the track polyline on the map.
    private static let trackLineWidth: CGFloat = 3

    /// User preference for metric (true) or imperial (false) units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                // Map
                mapSection
                    .frame(height: Self.mapHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Self.containerCornerRadius))

                // Stats
                statsSection

                // Description
                if let route = sharedRoute, !route.description.isEmpty {
                    descriptionSection(route.description)
                }

                // Waypoints
                if let route = sharedRoute, !route.waypoints.isEmpty {
                    waypointsSection(route.waypoints)
                }

                // Actions
                actionsSection
            }
            .padding()
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupInitialMapRegion()
            loadFullRoute()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Map Section

    /// Map showing the track polyline (or bounding box outline while loading).
    private var mapSection: some View {
        Map(position: $cameraPosition) {
            if trackCoordinates.count >= 2 {
                MapPolyline(coordinates: trackCoordinates)
                    .stroke(.orange, lineWidth: Self.trackLineWidth)
            }

            // Start pin
            if let first = trackCoordinates.first {
                Annotation("Start", coordinate: first) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
            }

            // End pin
            if let last = trackCoordinates.last, trackCoordinates.count > 1 {
                Annotation("End", coordinate: last) {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(.red)
                        .font(.title3)
                }
            }

            // Waypoints
            if let route = sharedRoute {
                ForEach(route.waypoints) { wp in
                    Annotation(wp.label, coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lon)) {
                        Image(systemName: WaypointCategory(rawValue: wp.category)?.iconName ?? "mappin")
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(Color(hex: WaypointCategory(rawValue: wp.category)?.colorHex ?? "E67E22")))
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .overlay {
            if isLoadingRoute {
                ProgressView()
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Self.statCardCornerRadius))
            }
        }
    }

    // MARK: - Stats Section

    /// Statistics grid showing route metrics.
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: entry.activityType.iconName)
                    .foregroundStyle(.blue)
                Text(entry.activityType.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("by \(entry.author)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Self.statGridSpacing) {
                statCard(
                    icon: "figure.walk",
                    label: "Distance",
                    value: HikeStatsFormatter.formatDistance(entry.stats.distanceMeters, useMetric: useMetricUnits)
                )

                statCard(
                    icon: "arrow.up.right",
                    label: "Elevation",
                    value: "+\(HikeStatsFormatter.formatElevation(entry.stats.elevationGainMeters, useMetric: useMetricUnits))"
                )

                statCard(
                    icon: "clock",
                    label: "Duration",
                    value: HikeStatsFormatter.formatDuration(entry.stats.durationSeconds)
                )

                statCard(
                    icon: "mappin",
                    label: "Region",
                    value: "\(entry.region.area)"
                )
            }
        }
    }

    /// A single statistics card.
    private func statCard(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                    .font(.caption)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.subheadline.monospacedDigit())
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
        .padding(Self.statCardPadding)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: Self.statCardCornerRadius))
    }

    // MARK: - Description Section

    /// Shows the route's full description text.
    ///
    /// - Parameter text: The description string.
    private func descriptionSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Description")
                .font(.headline)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Waypoints Section

    /// Displays a list of waypoints from the shared route.
    ///
    /// - Parameter waypoints: The shared waypoints to display.
    private func waypointsSection(_ waypoints: [SharedWaypoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Waypoints (\(waypoints.count))")
                .font(.headline)

            ForEach(waypoints) { wp in
                HStack(spacing: 8) {
                    Image(systemName: WaypointCategory(rawValue: wp.category)?.iconName ?? "mappin")
                        .foregroundStyle(Color(hex: WaypointCategory(rawValue: wp.category)?.colorHex ?? "E67E22"))
                        .frame(width: Self.waypointIconWidth)

                    VStack(alignment: .leading) {
                        Text(wp.label.isEmpty ? wp.category : wp.label)
                            .font(.subheadline)
                        if !wp.note.isEmpty {
                            Text(wp.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    if let ele = wp.ele {
                        Text(HikeStatsFormatter.formatElevation(ele, useMetric: useMetricUnits))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Actions Section

    /// Download button and offline status.
    private var actionsSection: some View {
        VStack(spacing: 12) {
            if isSavedOffline {
                Label("Saved for Offline Use", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                Button {
                    downloadForOffline()
                } label: {
                    HStack {
                        if isDownloading {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Downloading...")
                        } else {
                            Label("Download for Offline Use", systemImage: "arrow.down.circle.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDownloading || isLoadingRoute)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Data Loading

    /// Sets up the initial map region from the bounding box (before the full route loads).
    private func setupInitialMapRegion() {
        let bbox = entry.boundingBox
        let center = CLLocationCoordinate2D(
            latitude: bbox.centerLatitude,
            longitude: bbox.centerLongitude
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((bbox.north - bbox.south) * Self.mapBoundsPaddingFactor, Self.mapMinSpanDegrees),
            longitudeDelta: max((bbox.east - bbox.west) * Self.mapBoundsPaddingFactor, Self.mapMinSpanDegrees)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    /// Fetches the full route data from GitHub.
    private func loadFullRoute() {
        Task {
            do {
                let route = try await GitHubRouteService.shared.fetchRoute(at: entry.path)
                await MainActor.run {
                    sharedRoute = route
                    trackCoordinates = route.track.map {
                        CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                    }
                    isLoadingRoute = false

                    // Refine map region from actual track data
                    if !trackCoordinates.isEmpty {
                        updateMapRegion()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoadingRoute = false
                }
            }
        }
    }

    /// Updates the map region to fit the actual track coordinates.
    private func updateMapRegion() {
        guard !trackCoordinates.isEmpty else { return }

        var minLat = trackCoordinates[0].latitude
        var maxLat = trackCoordinates[0].latitude
        var minLon = trackCoordinates[0].longitude
        var maxLon = trackCoordinates[0].longitude

        for coord in trackCoordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * Self.mapBoundsPaddingFactor, Self.mapMinSpanDegrees),
            longitudeDelta: max((maxLon - minLon) * Self.mapBoundsPaddingFactor, Self.mapMinSpanDegrees)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    // MARK: - Offline Download

    /// Downloads the full route and saves it to the local ``RouteStore`` for offline use.
    private func downloadForOffline() {
        guard let route = sharedRoute else { return }
        isDownloading = true

        Task {
            do {
                let savedRoute = RouteExporter.toSavedRoute(route)
                try RouteStore.shared.insert(savedRoute)

                // Also save waypoints if any
                for sharedWP in route.waypoints {
                    let waypoint = Waypoint(
                        id: sharedWP.id,
                        latitude: sharedWP.lat,
                        longitude: sharedWP.lon,
                        altitude: sharedWP.ele,
                        label: sharedWP.label,
                        category: WaypointCategory(rawValue: sharedWP.category) ?? .custom,
                        note: sharedWP.note,
                        hikeId: savedRoute.id
                    )
                    try WaypointStore.shared.insert(waypoint)
                }

                await MainActor.run {
                    isSavedOffline = true
                    isDownloading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Could not save route: \(error.localizedDescription)"
                    showError = true
                    isDownloading = false
                }
            }
        }
    }
}
