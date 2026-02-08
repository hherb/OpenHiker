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

/// macOS detail view for a single saved hike.
///
/// Provides a wide-format layout with:
/// - Map with track polyline overlay (fills the top portion)
/// - Elevation profile chart
/// - Two-column statistics grid
/// - Waypoints table
/// - Export toolbar button (Markdown, GPX, PDF via ``MacPDFExporter``)
///
/// Uses a horizontal split for statistics that takes advantage of the wider
/// macOS window compared to the iOS view.
struct MacHikeDetailView: View {
    /// The saved route to display. Mutable so the user can edit name/comment.
    @State private var route: SavedRoute

    /// Decoded track coordinates for the map polyline overlay.
    @State private var trackCoordinates: [CLLocationCoordinate2D] = []

    /// Elevation profile data extracted from the track.
    @State private var elevationProfile: [(distance: Double, elevation: Double)] = []

    /// Waypoints linked to this hike.
    @State private var waypoints: [Waypoint] = []

    /// The map camera position (computed from track bounds).
    @State private var cameraPosition: MapCameraPosition = .automatic

    /// Whether the export file dialog is shown.
    @State private var showExportDialog = false

    /// The selected export format.
    @State private var exportFormat: MacExportFormat = .markdown

    /// Whether an error alert is displayed.
    @State private var showError = false

    /// The error message for the alert.
    @State private var errorMessage = ""

    /// Text field binding for the rename alert.
    @State private var renameText = ""

    /// Whether the rename alert is displayed.
    @State private var showRenameAlert = false

    /// User preference for metric (true) or imperial (false) units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    /// Factor applied to track bounds to add visual padding around the polyline.
    private static let mapBoundsPaddingFactor = 1.2

    /// Minimum coordinate span in degrees for the map region.
    private static let mapMinSpanDegrees = 0.005

    /// Height of the map section in the detail view.
    private static let mapSectionHeight: CGFloat = 350

    /// Height of the elevation profile chart.
    private static let elevationChartHeight: CGFloat = 180

    /// Estimated row height for the waypoints table.
    private static let waypointTableRowHeight: CGFloat = 30

    /// Extra padding for the waypoints table header/borders.
    private static let waypointTablePadding: CGFloat = 40

    /// Maximum height for the waypoints table before scrolling.
    private static let waypointTableMaxHeight: CGFloat = 250

    /// Callback invoked when the route is updated so the parent list can refresh.
    let onUpdate: () -> Void

    /// Creates a MacHikeDetailView for the given route.
    ///
    /// - Parameters:
    ///   - route: The ``SavedRoute`` to display.
    ///   - onUpdate: Closure called when the route is modified.
    init(route: SavedRoute, onUpdate: @escaping () -> Void) {
        _route = State(initialValue: route)
        self.onUpdate = onUpdate
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Map with track overlay
                mapSection
                    .frame(height: Self.mapSectionHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Elevation profile
                if !elevationProfile.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Elevation Profile")
                            .font(.headline)
                        ElevationProfileView(
                            elevationData: elevationProfile,
                            useMetric: useMetricUnits
                        )
                        .frame(height: Self.elevationChartHeight)
                    }
                }

                // Statistics grid
                statsSection

                // Waypoints table
                if !waypoints.isEmpty {
                    waypointsSection
                }

                // Comment
                commentSection
            }
            .padding()
        }
        .navigationTitle(route.name)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        renameText = route.name
                        showRenameAlert = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Divider()

                    ForEach(MacExportFormat.allCases) { format in
                        Button {
                            exportFormat = format
                            showExportDialog = true
                        } label: {
                            Label(format.rawValue, systemImage: format.iconName)
                        }
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .onAppear {
            decodeTrackData()
            loadWaypoints()
        }
        .fileExporter(
            isPresented: $showExportDialog,
            document: ExportDocument(
                route: route,
                waypoints: waypoints,
                format: exportFormat,
                useMetric: useMetricUnits
            ),
            contentType: exportFormat.contentType,
            defaultFilename: "\(route.name).\(exportFormat.fileExtension)"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = "Export failed: \(error.localizedDescription)"
                showError = true
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Rename Hike", isPresented: $showRenameAlert) {
            TextField("Hike name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                route.name = trimmed
                route.modifiedAt = Date()
                do {
                    try RouteStore.shared.update(route)
                    onUpdate()
                } catch {
                    errorMessage = "Could not rename hike: \(error.localizedDescription)"
                    showError = true
                }
            }
        } message: {
            Text("Enter a new name for this hike.")
        }
    }

    // MARK: - Map Section

    /// Map view showing the track polyline with start and end markers.
    private var mapSection: some View {
        Map(position: $cameraPosition) {
            if trackCoordinates.count >= 2 {
                MapPolyline(coordinates: trackCoordinates)
                    .stroke(.orange, lineWidth: 3)
            }

            if let first = trackCoordinates.first {
                Annotation("Start", coordinate: first) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
            }

            if let last = trackCoordinates.last, trackCoordinates.count > 1 {
                Annotation("End", coordinate: last) {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(.red)
                        .font(.title3)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
    }

    // MARK: - Stats Section

    /// Statistics grid showing all hike metrics in a multi-column layout.
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Statistics")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                statCard(icon: "figure.walk", label: "Distance",
                         value: HikeStatsFormatter.formatDistance(route.totalDistance, useMetric: useMetricUnits))
                statCard(icon: "arrow.up.right", label: "Elevation",
                         value: "+\(HikeStatsFormatter.formatElevation(route.elevationGain, useMetric: useMetricUnits)) / -\(HikeStatsFormatter.formatElevation(route.elevationLoss, useMetric: useMetricUnits))")
                statCard(icon: "clock", label: "Duration",
                         value: HikeStatsFormatter.formatDuration(route.duration))
                statCard(icon: "shoe", label: "Walking",
                         value: HikeStatsFormatter.formatDuration(route.walkingTime))
                statCard(icon: "pause.circle", label: "Resting",
                         value: HikeStatsFormatter.formatDuration(route.restingTime))

                if let avgHR = route.averageHeartRate {
                    statCard(icon: "heart.fill", label: "Avg HR",
                             value: HikeStatsFormatter.formatHeartRate(avgHR), iconColor: .red)
                }
                if let maxHR = route.maxHeartRate {
                    statCard(icon: "heart.fill", label: "Max HR",
                             value: HikeStatsFormatter.formatHeartRate(maxHR), iconColor: .red)
                }
                if let calories = route.estimatedCalories {
                    statCard(icon: "flame.fill", label: "Calories",
                             value: HikeStatsFormatter.formatCalories(calories), iconColor: .orange)
                }
            }
        }
    }

    /// A single statistics card.
    private func statCard(icon: String, label: String, value: String, iconColor: Color = .blue) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
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
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Waypoints

    /// Displays waypoints in a macOS-native table format.
    private var waypointsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Waypoints (\(waypoints.count))")
                .font(.headline)

            Table(waypoints) {
                TableColumn("Category") { wp in
                    Label(wp.category.displayName, systemImage: wp.category.iconName)
                        .font(.caption)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Label") { wp in
                    Text(wp.label.isEmpty ? "-" : wp.label)
                        .font(.caption)
                }
                .width(min: 100, ideal: 150)

                TableColumn("Coordinate") { wp in
                    Text(wp.formattedCoordinate)
                        .font(.system(.caption, design: .monospaced))
                }
                .width(min: 130, ideal: 150)

                TableColumn("Note") { wp in
                    Text(wp.note)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .frame(height: min(
                CGFloat(waypoints.count) * Self.waypointTableRowHeight + Self.waypointTablePadding,
                Self.waypointTableMaxHeight
            ))
        }
    }

    // MARK: - Comment

    /// An editable comment section.
    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Comment")
                .font(.headline)

            TextEditor(text: $route.comment)
                .font(.body)
                .frame(minHeight: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.secondary.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: route.comment) {
                    saveComment()
                }
        }
    }

    // MARK: - Data Loading

    /// Decodes the compressed track data and computes the map region.
    private func decodeTrackData() {
        let locations = TrackCompression.decode(route.trackData)
        trackCoordinates = locations.map { $0.coordinate }
        elevationProfile = TrackCompression.extractElevationProfile(route.trackData)

        if !trackCoordinates.isEmpty {
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
            let latDelta = (maxLat - minLat) * Self.mapBoundsPaddingFactor
            let lonDelta = (maxLon - minLon) * Self.mapBoundsPaddingFactor
            let span = MKCoordinateSpan(
                latitudeDelta: max(latDelta, Self.mapMinSpanDegrees),
                longitudeDelta: max(lonDelta, Self.mapMinSpanDegrees)
            )
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    /// Loads waypoints linked to this hike from the store.
    private func loadWaypoints() {
        do {
            waypoints = try WaypointStore.shared.fetchForHike(route.id)
        } catch {
            print("Error loading waypoints for hike: \(error.localizedDescription)")
        }
    }

    /// Persists the updated comment to the route store.
    private func saveComment() {
        do {
            try RouteStore.shared.update(route)
            onUpdate()
        } catch {
            errorMessage = "Could not save comment: \(error.localizedDescription)"
            showError = true
        }
    }
}
