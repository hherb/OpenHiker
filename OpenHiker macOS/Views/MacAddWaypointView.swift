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
import AppKit
import CoreLocation

/// macOS view for creating or editing a waypoint.
///
/// Uses ``NSOpenPanel`` for photo selection (no camera on Mac).
/// Supports drag-and-drop of image files onto the photo well.
/// The waypoint is saved to ``WaypointStore`` and synced via iCloud.
struct MacAddWaypointView: View {
    @Environment(\.dismiss) private var dismiss

    /// The latitude for the new waypoint.
    let latitude: Double

    /// The longitude for the new waypoint.
    let longitude: Double

    /// Callback invoked when the waypoint is saved.
    var onSave: ((Waypoint) -> Void)?

    // MARK: - Form State

    /// The user-entered label for the waypoint.
    @State private var label = ""

    /// The selected waypoint category.
    @State private var category: WaypointCategory = .trailMarker

    /// Notes / description for the waypoint.
    @State private var notes = ""

    /// The selected photo data (JPEG).
    @State private var photoData: Data?

    /// Whether an error alert is shown.
    @State private var showError = false

    /// The error message.
    @State private var errorMessage = ""

    /// Whether a file is being dragged over the photo well.
    @State private var isDragTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Location") {
                    LabeledContent("Latitude") {
                        Text(String(format: "%.6f", latitude))
                            .monospacedDigit()
                    }
                    LabeledContent("Longitude") {
                        Text(String(format: "%.6f", longitude))
                            .monospacedDigit()
                    }
                }

                Section("Details") {
                    TextField("Label", text: $label)

                    Picker("Category", selection: $category) {
                        ForEach(WaypointCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.iconName)
                                .tag(cat)
                        }
                    }

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Photo") {
                    photoWell
                }
            }
            .formStyle(.grouped)

            // Action buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save Waypoint") {
                    saveWaypoint()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400, height: 500)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    /// The photo well with drag-and-drop support and file picker button.
    private var photoWell: some View {
        VStack(spacing: 8) {
            if let data = photoData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button("Remove Photo") {
                    photoData = nil
                }
                .font(.caption)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDragTargeted ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.1))
                    .frame(height: 100)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("Drop image here or click to choose")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDrop(of: [.image, .fileURL], isTargeted: $isDragTargeted) { providers in
                        handleDrop(providers)
                    }
            }

            Button("Choose Photo...") {
                choosePhoto()
            }
        }
    }

    // MARK: - Actions

    /// Saves the waypoint to ``WaypointStore``.
    private func saveWaypoint() {
        // Compress photo if present
        var compressedPhoto: Data?
        if let data = photoData {
            compressedPhoto = PhotoCompressor.compressData(data)
        }

        let waypoint = Waypoint(
            id: UUID(),
            latitude: latitude,
            longitude: longitude,
            elevation: nil,
            label: label,
            category: category,
            notes: notes,
            photoData: compressedPhoto,
            createdAt: Date()
        )

        do {
            try WaypointStore.shared.insert(waypoint)
            onSave?(waypoint)
            dismiss()
        } catch {
            errorMessage = "Failed to save waypoint: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Opens an ``NSOpenPanel`` to choose a photo file.
    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.title = "Choose Photo"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                photoData = try Data(contentsOf: url)
            } catch {
                errorMessage = "Failed to read image: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    /// Handles drag-and-drop of image files onto the photo well.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { object, _ in
                if let image = object as? NSImage, let tiffData = image.tiffRepresentation {
                    DispatchQueue.main.async {
                        self.photoData = tiffData
                    }
                }
            }
            return true
        }

        return false
    }
}
