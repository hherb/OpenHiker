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

/// Rich detail view for a single saved hike on iOS.
///
/// Presents a scrollable layout with:
/// - **Map** with the track polyline overlay (green start pin, red end pin)
/// - **Elevation profile** chart using ``ElevationProfileView``
/// - **Statistics grid** showing distance, elevation, duration, heart rate, calories
/// - **Linked waypoints** (if any exist for this hike)
/// - **Editable comment** field
///
/// The track points are decoded from the compressed binary ``SavedRoute/trackData``
/// via ``TrackCompression/decode(_:)``.
struct HikeDetailView: View {
    /// The saved route to display. Mutable so the user can edit name/comment.
    @State private var route: SavedRoute

    /// Factor applied to track bounds to add visual padding around the polyline on the map.
    ///
    /// 1.2 means the map shows 20% more area beyond the track's bounding box.
    private static let mapBoundsPaddingFactor = 1.2

    /// Minimum coordinate span in degrees for the map region.
    ///
    /// Prevents the map from zooming in too far on very short tracks where the
    /// bounding box would be nearly zero. 0.005 degrees is roughly 500m.
    private static let mapMinSpanDegrees = 0.005

    /// Required length for a valid hex color string (6 hex characters, no prefix).
    static let hexColorStringLength = 6

    /// Decoded track coordinates for the map polyline overlay.
    @State private var trackCoordinates: [CLLocationCoordinate2D] = []

    /// Elevation profile data extracted from the track.
    @State private var elevationProfile: [(distance: Double, elevation: Double)] = []

    /// Waypoints linked to this hike.
    @State private var waypoints: [Waypoint] = []

    /// The map camera position, initialized from the route's start point and refined
    /// once track data is decoded.
    @State private var cameraPosition: MapCameraPosition

    /// Whether an error alert is displayed.
    @State private var showError = false

    /// The error message for the alert.
    @State private var errorMessage = ""

    /// Whether track data has been decoded and the map is ready to display.
    @State private var isDataLoaded = false

    /// Whether the comment is currently being edited.
    @State private var isEditingComment = false

    /// Whether the community upload sheet is presented.
    @State private var showUploadSheet = false

    /// Whether the export sheet is presented.
    @State private var showExportSheet = false

    /// Text field binding for the rename alert.
    @State private var renameText = ""

    /// Whether the rename alert is displayed.
    @State private var showRenameAlert = false

    /// User preference for metric (true) or imperial (false) units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    /// Callback invoked when the route is updated (name or comment change), so the
    /// parent list can refresh.
    let onUpdate: () -> Void

    /// Creates a HikeDetailView for the given route.
    ///
    /// - Parameters:
    ///   - route: The ``SavedRoute`` to display.
    ///   - onUpdate: Closure called when the route is modified.
    init(route: SavedRoute, onUpdate: @escaping () -> Void) {
        _route = State(initialValue: route)
        self.onUpdate = onUpdate

        // Initialize camera from the route's known start/end coordinates so the Map
        // never starts with .automatic (which can crash during the transition to
        // .region on some devices).
        let centerLat = (route.startLatitude + route.endLatitude) / 2
        let centerLon = (route.startLongitude + route.endLongitude) / 2
        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        let initialRegion = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: Self.mapMinSpanDegrees * 10,
                longitudeDelta: Self.mapMinSpanDegrees * 10
            )
        )
        _cameraPosition = State(initialValue: .region(initialRegion))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Map with track overlay (deferred until track data is decoded)
                if isDataLoaded {
                    mapSection
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary)
                        .frame(height: 280)
                        .overlay {
                            ProgressView("Loading track...")
                        }
                }

                // Elevation profile
                if !elevationProfile.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Elevation Profile")
                            .font(.headline)
                        ElevationProfileView(
                            elevationData: elevationProfile,
                            useMetric: useMetricUnits
                        )
                        .frame(height: 160)
                    }
                }

                // Statistics grid
                statsSection

                // Waypoints
                if !waypoints.isEmpty {
                    waypointsSection
                }

                // Comment
                commentSection
            }
            .padding()
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        renameText = route.name
                        showRenameAlert = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button {
                        showExportSheet = true
                    } label: {
                        Label("Export Hike...", systemImage: "doc.badge.arrow.up")
                    }

                    Button {
                        showUploadSheet = true
                    } label: {
                        Label("Share to Community", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showUploadSheet) {
            RouteUploadView(route: route, waypoints: waypoints)
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheet(route: route, waypoints: waypoints)
        }
        .onAppear {
            decodeTrackData()
            loadWaypoints()
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

    /// Map view showing the track polyline with start (green) and end (red) pins.
    private var mapSection: some View {
        Map(position: $cameraPosition) {
            // Track polyline
            if trackCoordinates.count >= 2 {
                MapPolyline(coordinates: trackCoordinates)
                    .stroke(.orange, lineWidth: 3)
            }

            // Start pin (green)
            if let first = trackCoordinates.first {
                Annotation("Start", coordinate: first) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
            }

            // End pin (red)
            if let last = trackCoordinates.last, trackCoordinates.count > 1 {
                Annotation("End", coordinate: last) {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(.red)
                        .font(.title3)
                }
            }

            // Waypoints
            ForEach(waypoints) { waypoint in
                Annotation(waypoint.label, coordinate: waypoint.coordinate) {
                    Image(systemName: waypoint.category.iconName)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color(hex: waypoint.category.colorHex)))
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
    }

    // MARK: - Statistics Section

    /// A grid displaying all hike statistics.
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Statistics")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                statCard(
                    icon: "figure.walk",
                    label: "Distance",
                    value: HikeStatsFormatter.formatDistance(route.totalDistance, useMetric: useMetricUnits)
                )

                statCard(
                    icon: "arrow.up.right",
                    label: "Elevation",
                    value: "+\(HikeStatsFormatter.formatElevation(route.elevationGain, useMetric: useMetricUnits)) / -\(HikeStatsFormatter.formatElevation(route.elevationLoss, useMetric: useMetricUnits))"
                )

                statCard(
                    icon: "clock",
                    label: "Duration",
                    value: HikeStatsFormatter.formatDuration(route.duration)
                )

                statCard(
                    icon: "shoe",
                    label: "Walking",
                    value: HikeStatsFormatter.formatDuration(route.walkingTime)
                )

                statCard(
                    icon: "pause.circle",
                    label: "Resting",
                    value: HikeStatsFormatter.formatDuration(route.restingTime)
                )

                if let avgHR = route.averageHeartRate {
                    statCard(
                        icon: "heart.fill",
                        label: "Avg HR",
                        value: HikeStatsFormatter.formatHeartRate(avgHR),
                        iconColor: .red
                    )
                }

                if let maxHR = route.maxHeartRate {
                    statCard(
                        icon: "heart.fill",
                        label: "Max HR",
                        value: HikeStatsFormatter.formatHeartRate(maxHR),
                        iconColor: .red
                    )
                }

                if let calories = route.estimatedCalories {
                    statCard(
                        icon: "flame.fill",
                        label: "Calories",
                        value: HikeStatsFormatter.formatCalories(calories),
                        iconColor: .orange
                    )
                }
            }
        }
    }

    /// A single statistics card with icon, label, and value.
    ///
    /// - Parameters:
    ///   - icon: SF Symbol name.
    ///   - label: Description label.
    ///   - value: Formatted value.
    ///   - iconColor: Icon tint color (defaults to blue).
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

    // MARK: - Waypoints Section

    /// Displays a list of waypoints linked to this hike.
    private var waypointsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Waypoints (\(waypoints.count))")
                .font(.headline)

            ForEach(waypoints) { waypoint in
                HStack(spacing: 8) {
                    Image(systemName: waypoint.category.iconName)
                        .foregroundStyle(Color(hex: waypoint.category.colorHex))
                        .frame(width: 24)

                    VStack(alignment: .leading) {
                        Text(waypoint.label.isEmpty ? waypoint.category.displayName : waypoint.label)
                            .font(.subheadline)
                        if !waypoint.note.isEmpty {
                            Text(waypoint.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if let altitude = waypoint.altitude {
                        Text(HikeStatsFormatter.formatElevation(altitude, useMetric: useMetricUnits))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Comment Section

    /// An editable comment section for adding notes about the hike.
    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Comment")
                .font(.headline)

            if isEditingComment {
                TextEditor(text: $route.comment)
                    .frame(minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.secondary.opacity(0.3), lineWidth: 1)
                    )

                Button("Done") {
                    isEditingComment = false
                    saveComment()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text(route.comment.isEmpty ? "Tap to add a comment..." : route.comment)
                    .foregroundStyle(route.comment.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isEditingComment = true
                    }
            }
        }
    }

    // MARK: - Data Loading

    /// Decodes the compressed track data and computes the map region and elevation profile.
    ///
    /// Sets ``isDataLoaded`` to `true` when decoding completes so the map section
    /// transitions from a loading placeholder to the full ``Map`` view. This avoids
    /// presenting the ``Map`` with empty data which can cause rendering crashes on
    /// some devices.
    private func decodeTrackData() {
        let locations = TrackCompression.decode(route.trackData)
        trackCoordinates = locations.map { $0.coordinate }
        elevationProfile = TrackCompression.extractElevationProfile(route.trackData)

        // Compute map region from track bounds
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
            let region = MKCoordinateRegion(center: center, span: span)
            cameraPosition = .region(region)
        } else if route.trackData.isEmpty {
            errorMessage = "This hike has no track data recorded."
            showError = true
        }

        isDataLoaded = true
    }

    /// Loads waypoints linked to this hike from the ``WaypointStore``.
    private func loadWaypoints() {
        do {
            waypoints = try WaypointStore.shared.fetchForHike(route.id)
        } catch {
            print("Error loading waypoints for hike: \(error.localizedDescription)")
        }
    }

    /// Persists the updated comment to the ``RouteStore``.
    private func saveComment() {
        do {
            try RouteStore.shared.update(route)
            onUpdate()
        } catch {
            errorMessage = "Could not save comment: \(error.localizedDescription)"
            showError = true
            print("Error saving route comment: \(error.localizedDescription)")
        }
    }
}

// MARK: - Color from Hex String

/// Extension to create a SwiftUI `Color` from a 6-character hex string.
///
/// Used by waypoint category colors which are stored as hex strings in the model
/// to keep it platform-agnostic.
extension Color {
    /// Creates a Color from a hex string (6 characters, no `#` prefix).
    ///
    /// If the string is not exactly 6 hex characters, falls back to a 50% gray
    /// so the UI remains usable even with malformed data.
    ///
    /// - Parameter hex: A 6-character hex color string (e.g., "4A90D9").
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count == HikeDetailView.hexColorStringLength,
              trimmed.allSatisfy({ $0.isHexDigit }) else {
            self.init(white: 0.5)
            return
        }

        let scanner = Scanner(string: trimmed)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
