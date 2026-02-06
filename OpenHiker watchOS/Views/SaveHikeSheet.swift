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

/// A modal sheet presented after the user stops tracking, allowing them to save or discard the hike.
///
/// Shows a summary of the hike statistics (distance, elevation, duration, heart rate, calories)
/// with editable name and comment fields. The user can either save the hike to ``RouteStore``
/// (and trigger a WatchConnectivity transfer to the iPhone) or discard it.
///
/// ## Data Flow
/// 1. ``MapView`` stops tracking and presents this sheet
/// 2. User reviews stats, optionally edits name/comment
/// 3. On **Save**: compress track → create ``SavedRoute`` → insert into ``RouteStore`` → transfer to iPhone
/// 4. On **Discard**: clear track points, dismiss
struct SaveHikeSheet: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var connectivityManager: WatchConnectivityReceiver

    /// User preference for metric (true) or imperial (false) units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    /// The editable name for this hike. Auto-populated with a date-based default.
    @State private var hikeName: String

    /// An optional comment the user can dictate or type.
    @State private var hikeComment = ""

    /// Whether an error alert is displayed during save.
    @State private var showError = false

    /// The error message for the alert.
    @State private var errorMessage = ""

    /// Whether the sheet is currently saving (disables buttons to prevent double-tap).
    @State private var isSaving = false

    @Environment(\.dismiss) private var dismiss

    /// The UUID of the currently loaded map region, if any. Used to link the route to its region.
    let regionId: UUID?

    /// Callback invoked after the user saves or discards, so the parent view can clean up.
    let onComplete: (Bool) -> Void

    /// Creates a SaveHikeSheet.
    ///
    /// - Parameters:
    ///   - regionId: The UUID of the active map region, or `nil`.
    ///   - onComplete: Closure called with `true` if saved, `false` if discarded.
    init(regionId: UUID?, onComplete: @escaping (Bool) -> Void) {
        self.regionId = regionId
        self.onComplete = onComplete
        _hikeName = State(initialValue: SavedRoute.defaultName(for: Date()))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Name field
                    TextField("Hike name", text: $hikeName)
                        .font(.headline)

                    // Statistics summary
                    statsSection

                    // Comment field
                    TextField("Comment (optional)", text: $hikeComment)
                        .font(.caption)

                    // Action buttons
                    HStack {
                        Button("Discard", role: .destructive) {
                            onComplete(false)
                            dismiss()
                        }
                        .disabled(isSaving)

                        Spacer()

                        Button("Save") {
                            saveHike()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving)
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Save Hike")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Save Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Statistics Section

    /// Displays a compact grid of hike statistics.
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            statRow(
                icon: "figure.walk",
                label: "Distance",
                value: HikeStatsFormatter.formatDistance(
                    locationManager.totalDistance,
                    useMetric: useMetricUnits
                )
            )

            statRow(
                icon: "arrow.up.right",
                label: "Elevation",
                value: "+\(HikeStatsFormatter.formatElevation(locationManager.elevationGain, useMetric: useMetricUnits)) / -\(HikeStatsFormatter.formatElevation(locationManager.elevationLoss, useMetric: useMetricUnits))"
            )

            statRow(
                icon: "clock",
                label: "Duration",
                value: HikeStatsFormatter.formatDuration(locationManager.duration ?? 0)
            )

            let times = locationManager.walkingAndRestingTime
            statRow(
                icon: "shoe",
                label: "Walking",
                value: HikeStatsFormatter.formatDuration(times.walking)
            )
            statRow(
                icon: "pause.circle",
                label: "Resting",
                value: HikeStatsFormatter.formatDuration(times.resting)
            )

            if healthKitManager.isAuthorized, let hr = healthKitManager.currentHeartRate {
                statRow(
                    icon: "heart.fill",
                    label: "Avg HR",
                    value: HikeStatsFormatter.formatHeartRate(hr)
                )
            }
        }
        .padding(.vertical, 4)
    }

    /// A single row displaying an icon, label, and value.
    ///
    /// - Parameters:
    ///   - icon: SF Symbol name.
    ///   - label: Short label text.
    ///   - value: Formatted value string.
    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption2.monospacedDigit())
        }
    }

    // MARK: - Save Logic

    /// Compresses the track, creates a ``SavedRoute``, saves it to ``RouteStore``,
    /// exports GPX, and triggers a WatchConnectivity transfer to iPhone.
    private func saveHike() {
        isSaving = true

        let trackPoints = locationManager.trackPoints
        guard let firstPoint = trackPoints.first, let lastPoint = trackPoints.last else {
            errorMessage = "No track data to save."
            showError = true
            isSaving = false
            return
        }

        let times = locationManager.walkingAndRestingTime

        // Compress track data
        let compressedTrack = TrackCompression.encode(trackPoints)

        let route = SavedRoute(
            name: hikeName.isEmpty ? SavedRoute.defaultName(for: Date()) : hikeName,
            startLatitude: firstPoint.coordinate.latitude,
            startLongitude: firstPoint.coordinate.longitude,
            endLatitude: lastPoint.coordinate.latitude,
            endLongitude: lastPoint.coordinate.longitude,
            startTime: firstPoint.timestamp,
            endTime: lastPoint.timestamp,
            totalDistance: locationManager.totalDistance,
            elevationGain: locationManager.elevationGain,
            elevationLoss: locationManager.elevationLoss,
            walkingTime: times.walking,
            restingTime: times.resting,
            averageHeartRate: healthKitManager.isAuthorized ? healthKitManager.currentHeartRate : nil,
            maxHeartRate: nil,
            estimatedCalories: CalorieEstimator.estimateCalories(
                distanceMeters: locationManager.totalDistance,
                elevationGainMeters: locationManager.elevationGain,
                durationSeconds: locationManager.duration ?? 0,
                bodyMassKg: nil
            ),
            comment: hikeComment,
            regionId: regionId,
            trackData: compressedTrack
        )

        // Save to local RouteStore
        do {
            try RouteStore.shared.insert(route)
            print("Saved route: \(route.id.uuidString) — \(route.name)")
        } catch {
            errorMessage = "Failed to save hike: \(error.localizedDescription)"
            showError = true
            isSaving = false
            return
        }

        // Export GPX as well (existing functionality)
        if let gpxData = locationManager.exportTrackAsGPX() {
            saveGPXToDocuments(gpxData, name: route.name)
        }

        // Transfer to iPhone via WatchConnectivity
        transferRouteToPhone(route)

        isSaving = false
        onComplete(true)
        dismiss()
    }

    /// Saves GPX data to the `Documents/routes/` directory.
    ///
    /// - Parameters:
    ///   - data: The GPX XML data to save.
    ///   - name: The file name (without extension).
    private func saveGPXToDocuments(_ data: Data, name: String) {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let routesDir = documentsDir.appendingPathComponent("routes", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: routesDir, withIntermediateDirectories: true)
            // Sanitize file name: replace slashes and other problematic characters
            let safeName = name.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let fileURL = routesDir.appendingPathComponent("\(safeName).gpx")
            try data.write(to: fileURL)
            print("Saved GPX to: \(fileURL.lastPathComponent)")
        } catch {
            print("Error saving GPX: \(error.localizedDescription)")
        }
    }

    /// Transfers a saved route to the iPhone via WatchConnectivity file transfer.
    ///
    /// Encodes the route as JSON and sends it via `transferFile` with metadata
    /// identifying it as a saved route. The iPhone's ``WatchConnectivityManager``
    /// handles reception and inserts it into the local ``RouteStore``.
    ///
    /// - Parameter route: The ``SavedRoute`` to transfer.
    private func transferRouteToPhone(_ route: SavedRoute) {
        // Encode route as JSON to a temporary file
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let jsonData = try? encoder.encode(route) else {
            print("Failed to encode route for transfer")
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("\(route.id.uuidString).hikedata")

        do {
            try jsonData.write(to: tempFile)
        } catch {
            print("Failed to write temp file for route transfer: \(error.localizedDescription)")
            return
        }

        connectivityManager.transferRouteToPhone(fileURL: tempFile, routeId: route.id)
    }
}
