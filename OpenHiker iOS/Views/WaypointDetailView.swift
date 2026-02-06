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

#if os(iOS)
import SwiftUI
import MapKit
import CoreLocation

/// A detail view for viewing and editing an existing waypoint on iOS.
///
/// Shows the waypoint's location on a map, its category, label, note, and
/// full-resolution photo (if attached). The user can edit mutable fields
/// and delete the waypoint with a confirmation dialog.
struct WaypointDetailView: View {
    /// The waypoint being viewed/edited.
    @State var waypoint: Waypoint

    /// Callback invoked after the waypoint is updated.
    var onUpdate: ((Waypoint) -> Void)?

    /// Callback invoked after the waypoint is deleted.
    var onDelete: ((UUID) -> Void)?

    /// Whether the view is currently in edit mode.
    @State private var isEditing = false

    /// The full-resolution photo loaded from the database.
    @State private var fullPhoto: UIImage?

    /// Whether the full-screen photo viewer is displayed.
    @State private var showFullPhoto = false

    /// Whether the delete confirmation dialog is displayed.
    @State private var showDeleteConfirmation = false

    /// Whether an error alert is displayed.
    @State private var showError = false

    /// The error message for the alert.
    @State private var errorMessage = ""

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            // Map section
            Section {
                mapSection
            }

            // Category and details
            Section {
                if isEditing {
                    editableDetailsSection
                } else {
                    readOnlyDetailsSection
                }
            } header: {
                Text("Details")
            }

            // Photo section
            if waypoint.hasPhoto {
                Section {
                    photoSection
                } header: {
                    Text("Photo")
                }
            }

            // Metadata section
            Section {
                metadataSection
            } header: {
                Text("Info")
            }

            // Delete button
            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Delete Waypoint", systemImage: "trash")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle(waypoint.label.isEmpty ? waypoint.category.displayName : waypoint.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        saveChanges()
                    }
                    isEditing.toggle()
                }
            }
        }
        .onAppear {
            loadPhoto()
        }
        .confirmationDialog(
            "Delete Waypoint",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteWaypoint()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This waypoint will be permanently deleted. This action cannot be undone.")
        }
        .fullScreenCover(isPresented: $showFullPhoto) {
            fullPhotoViewer
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Subviews

    /// A map showing the waypoint location with a category-colored marker.
    private var mapSection: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: waypoint.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        ))) {
            Marker(
                waypoint.label.isEmpty ? waypoint.category.displayName : waypoint.label,
                systemImage: waypoint.category.iconName,
                coordinate: waypoint.coordinate
            )
            .tint(.orange)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .disabled(true)
    }

    /// Read-only display of waypoint details.
    private var readOnlyDetailsSection: some View {
        Group {
            HStack {
                Image(systemName: waypoint.category.iconName)
                    .foregroundStyle(.orange)
                Text(waypoint.category.displayName)
            }

            if !waypoint.label.isEmpty {
                HStack {
                    Text("Label")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(waypoint.label)
                }
            }

            if !waypoint.note.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(waypoint.note)
                }
            }
        }
    }

    /// Editable form fields for waypoint details.
    private var editableDetailsSection: some View {
        Group {
            Picker("Category", selection: $waypoint.category) {
                ForEach(WaypointCategory.allCases, id: \.self) { category in
                    Label(category.displayName, systemImage: category.iconName)
                        .tag(category)
                }
            }

            TextField("Label", text: $waypoint.label)

            TextField("Note", text: $waypoint.note, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    /// Photo thumbnail with tap-to-enlarge.
    private var photoSection: some View {
        Group {
            if let photo = fullPhoto {
                Button {
                    showFullPhoto = true
                } label: {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            } else {
                HStack {
                    ProgressView()
                    Text("Loading photo...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Read-only metadata: coordinates, altitude, timestamp.
    private var metadataSection: some View {
        Group {
            HStack {
                Text("Latitude")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.6f", waypoint.latitude))
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Text("Longitude")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.6f", waypoint.longitude))
                    .font(.system(.body, design: .monospaced))
            }

            if let altitude = waypoint.altitude {
                HStack {
                    Text("Altitude")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(altitude)) m")
                }
            }

            HStack {
                Text("Created")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(waypoint.timestamp.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    /// A full-screen photo viewer with dismiss button.
    private var fullPhotoViewer: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let photo = fullPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
            }

            Button {
                showFullPhoto = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding()
            }
        }
    }

    // MARK: - Actions

    /// Loads the full-resolution photo from ``WaypointStore``.
    ///
    /// Falls back to the thumbnail if the full photo is unavailable. Shows an
    /// error alert if both fetches fail.
    private func loadPhoto() {
        guard waypoint.hasPhoto else { return }

        do {
            if let data = try WaypointStore.shared.fetchPhoto(id: waypoint.id),
               let image = UIImage(data: data) {
                fullPhoto = image
            } else if let data = try WaypointStore.shared.fetchThumbnail(id: waypoint.id),
                      let image = UIImage(data: data) {
                // Fall back to thumbnail if no full photo
                fullPhoto = image
            }
        } catch {
            errorMessage = "Failed to load photo: \(error.localizedDescription)"
            showError = true
            print("Error loading photo: \(error.localizedDescription)")
        }
    }

    /// Saves the edited waypoint fields to ``WaypointStore``.
    private func saveChanges() {
        do {
            try WaypointStore.shared.update(waypoint)
            onUpdate?(waypoint)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            print("Error updating waypoint: \(error.localizedDescription)")
        }
    }

    /// Deletes the waypoint from ``WaypointStore`` and dismisses the view.
    private func deleteWaypoint() {
        do {
            try WaypointStore.shared.delete(id: waypoint.id)
            onDelete?(waypoint.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            print("Error deleting waypoint: \(error.localizedDescription)")
        }
    }
}
#endif
