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
import CoreLocation

/// A compact sheet for quickly dropping a waypoint pin on the watch.
///
/// Presented when the user taps the pin button on the map. Shows the current GPS
/// coordinates (read-only), a 3x3 grid of category icons for quick selection, an
/// optional label via dictation, and a Save button.
///
/// On save, creates a ``Waypoint`` at the current GPS location, inserts it into
/// ``WaypointStore``, and syncs it to the iPhone via WatchConnectivity.
struct AddWaypointSheet: View {
    /// The GPS location manager, providing the current position.
    @EnvironmentObject var locationManager: LocationManager

    /// The WatchConnectivity receiver, used to sync waypoints to iPhone.
    @EnvironmentObject var connectivityManager: WatchConnectivityReceiver

    /// The selected category for the new waypoint (defaults to trail marker).
    @State private var selectedCategory: WaypointCategory = .trailMarker

    /// The user-entered label text (via dictation or keyboard on newer watchOS).
    @State private var label: String = ""

    /// Whether a save error alert is currently displayed.
    @State private var showError = false

    /// The error message to display in the alert.
    @State private var errorMessage = ""

    /// Dismiss action for closing the sheet after saving.
    @Environment(\.dismiss) private var dismiss

    /// Callback invoked after a waypoint is successfully saved.
    ///
    /// The parent view uses this to trigger a map marker refresh.
    var onSave: ((Waypoint) -> Void)?

    /// The number of columns in the category picker grid.
    private let gridColumns = 3

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Current coordinates display
                coordinatesHeader

                // Category picker grid
                categoryGrid

                // Label input
                TextField("Label (optional)", text: $label)
                    .textContentType(.none)

                // Save button
                Button(action: saveWaypoint) {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                        Text("Save Pin")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(locationManager.currentLocation == nil)
            }
            .padding(.horizontal)
        }
        .navigationTitle("Drop Pin")
        .alert("Save Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Subviews

    /// Displays the current GPS coordinates at the top of the sheet.
    ///
    /// Shows latitude and longitude formatted to 5 decimal places, or a
    /// "Waiting for GPS..." message if no location is available yet.
    private var coordinatesHeader: some View {
        Group {
            if let location = locationManager.currentLocation {
                VStack(spacing: 2) {
                    Text(Waypoint.formatCoordinate(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if location.altitude >= 0 {
                        Text("\(Int(location.altitude))m alt")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Waiting for GPS...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// A 3x3 grid of category buttons, each showing the category's SF Symbol.
    ///
    /// The selected category is highlighted with a blue background and white icon.
    /// Unselected categories use a translucent material background.
    private var categoryGrid: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 6),
            count: gridColumns
        )

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(WaypointCategory.allCases, id: \.self) { category in
                Button {
                    selectedCategory = category
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: category.iconName)
                            .font(.system(size: 18))
                        Text(category.displayName)
                            .font(.system(size: 8))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        selectedCategory == category
                            ? AnyShapeStyle(.blue)
                            : AnyShapeStyle(.ultraThinMaterial)
                    )
                    .foregroundStyle(
                        selectedCategory == category ? .white : .primary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    /// Creates a waypoint from the current GPS location and saves it.
    ///
    /// Inserts the waypoint into ``WaypointStore``, syncs it to the iPhone
    /// via WatchConnectivity `transferUserInfo`, and dismisses the sheet.
    /// If the save fails, an error alert is shown.
    private func saveWaypoint() {
        guard let location = locationManager.currentLocation else {
            errorMessage = "No GPS location available. Please wait for a GPS fix."
            showError = true
            return
        }

        let waypoint = Waypoint.fromLocation(
            location,
            category: selectedCategory,
            label: label
        )

        do {
            try WaypointStore.shared.insert(waypoint)

            // Sync to iPhone via WatchConnectivity
            connectivityManager.syncWaypointToPhone(waypoint)

            onSave?(waypoint)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            print("Error saving waypoint: \(error.localizedDescription)")
        }
    }

}
