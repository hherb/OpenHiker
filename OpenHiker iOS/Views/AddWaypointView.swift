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
import PhotosUI
import CoreLocation

/// A form view for creating a new waypoint on iOS.
///
/// Opened from a long-press on the map or from a toolbar action. Provides:
/// - A small map preview showing the pin location
/// - Category picker (segmented/grid)
/// - Label and note text fields
/// - Photo section: camera and photo library buttons with thumbnail preview
/// - Save / Cancel buttons
///
/// On save, inserts the waypoint into ``WaypointStore`` with optional photo
/// data and syncs it to the Apple Watch via ``WatchConnectivityManager``.
struct AddWaypointView: View {
    /// The pre-filled latitude from the long-press location.
    let latitude: Double

    /// The pre-filled longitude from the long-press location.
    let longitude: Double

    /// Callback invoked after a waypoint is successfully saved.
    var onSave: ((Waypoint) -> Void)?

    /// The WatchConnectivity manager for syncing waypoints to the watch.
    @EnvironmentObject var watchConnectivity: WatchConnectivityManager

    /// The selected category for the new waypoint.
    @State private var selectedCategory: WaypointCategory = .custom

    /// The user-entered label text.
    @State private var label = ""

    /// The user-entered note text.
    @State private var note = ""

    /// The selected photo from the photo library.
    @State private var selectedPhotoItem: PhotosPickerItem?

    /// The full-resolution photo data (JPEG).
    @State private var photoData: Data?

    /// The thumbnail image data (100x100 JPEG).
    @State private var thumbnailData: Data?

    /// The preview image displayed in the form.
    @State private var photoPreview: UIImage?

    /// Whether the camera sheet is currently displayed.
    @State private var showCamera = false

    /// Whether a save error alert is displayed.
    @State private var showError = false

    /// The error message for the alert.
    @State private var errorMessage = ""

    @Environment(\.dismiss) private var dismiss

    /// Thumbnail size in points (100x100 as specified in the Phase 2 spec).
    private let thumbnailSize: CGFloat = 100

    /// JPEG compression quality for stored photos (0.0–1.0).
    private let photoCompressionQuality: CGFloat = 0.8

    /// JPEG compression quality for thumbnails.
    private let thumbnailCompressionQuality: CGFloat = 0.7

    var body: some View {
        NavigationStack {
            Form {
                // Map preview section
                Section {
                    mapPreview
                } header: {
                    Text("Location")
                }

                // Category picker
                Section {
                    categoryPicker
                } header: {
                    Text("Category")
                }

                // Label and note
                Section {
                    TextField("Label", text: $label)
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Details")
                }

                // Photo section
                Section {
                    photoSection
                } header: {
                    Text("Photo")
                }
            }
            .navigationTitle("New Waypoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveWaypoint)
                        .bold()
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                loadPhoto(from: newItem)
            }
            .sheet(isPresented: $showCamera) {
                CameraView(onCapture: { image in
                    processPhoto(image)
                    showCamera = false
                })
            }
            .alert("Save Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Subviews

    /// A small map showing the pin location.
    private var mapPreview: some View {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return Map(initialPosition: .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        ))) {
            Marker("", coordinate: coordinate)
                .tint(.orange)
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .disabled(true)
        .overlay(alignment: .bottomTrailing) {
            Text(String(format: "%.5f, %.5f", latitude, longitude))
                .font(.caption2)
                .padding(4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(6)
        }
    }

    /// A scrollable horizontal list of category buttons.
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WaypointCategory.allCases, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: category.iconName)
                                .font(.title3)
                            Text(category.displayName)
                                .font(.caption2)
                        }
                        .frame(width: 65, height: 60)
                        .background(
                            selectedCategory == category
                                ? Color.blue.opacity(0.2)
                                : Color(.systemGray6)
                        )
                        .foregroundStyle(
                            selectedCategory == category ? .blue : .primary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    selectedCategory == category ? .blue : .clear,
                                    lineWidth: 2
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Photo capture buttons and preview thumbnail.
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Camera button
                Button {
                    showCamera = true
                } label: {
                    Label("Camera", systemImage: "camera")
                }
                .buttonStyle(.bordered)

                // Photo library picker
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Library", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)

                Spacer()

                // Remove photo button
                if photoPreview != nil {
                    Button(role: .destructive) {
                        clearPhoto()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Photo preview
            if let preview = photoPreview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Actions

    /// Creates and saves the waypoint with optional photo data.
    private func saveWaypoint() {
        let hasPhoto = photoData != nil
        let waypoint = Waypoint(
            latitude: latitude,
            longitude: longitude,
            altitude: nil,
            label: label,
            category: selectedCategory,
            note: note,
            hasPhoto: hasPhoto
        )

        do {
            try WaypointStore.shared.insert(waypoint, photo: photoData, thumbnail: thumbnailData)

            // Sync to watch (only thumbnail, not full photo)
            watchConnectivity.sendWaypointToWatch(waypoint, thumbnail: thumbnailData)

            onSave?(waypoint)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            print("Error saving waypoint: \(error.localizedDescription)")
        }
    }

    /// Loads a photo from a ``PhotosPickerItem`` selected from the library.
    ///
    /// - Parameter item: The selected photo item, or `nil` if deselected.
    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item = item else { return }

        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    processPhoto(image)
                }
            }
        }
    }

    /// Processes a captured or selected photo: generates JPEG data and thumbnail.
    ///
    /// - Parameter image: The source image from the camera or photo library.
    private func processPhoto(_ image: UIImage) {
        photoPreview = image
        photoData = image.jpegData(compressionQuality: photoCompressionQuality)
        thumbnailData = generateThumbnail(from: image)
    }

    /// Clears all photo-related state.
    private func clearPhoto() {
        photoPreview = nil
        photoData = nil
        thumbnailData = nil
        selectedPhotoItem = nil
    }

    /// Generates a 100x100 JPEG thumbnail from a source image.
    ///
    /// Uses `UIGraphicsImageRenderer` for efficient, GPU-accelerated scaling.
    /// The thumbnail is compressed at 0.7 quality to keep it small enough for
    /// WatchConnectivity transfer.
    ///
    /// - Parameter image: The source image.
    /// - Returns: JPEG data for the 100x100 thumbnail, or `nil` if rendering fails.
    private func generateThumbnail(from image: UIImage) -> Data? {
        let size = CGSize(width: thumbnailSize, height: thumbnailSize)
        let renderer = UIGraphicsImageRenderer(size: size)

        let thumbnailImage = renderer.image { context in
            // Calculate aspect-fill scaling
            let sourceSize = image.size
            let widthRatio = size.width / sourceSize.width
            let heightRatio = size.height / sourceSize.height
            let scale = max(widthRatio, heightRatio)

            let scaledWidth = sourceSize.width * scale
            let scaledHeight = sourceSize.height * scale
            let originX = (size.width - scaledWidth) / 2.0
            let originY = (size.height - scaledHeight) / 2.0

            image.draw(in: CGRect(x: originX, y: originY, width: scaledWidth, height: scaledHeight))
        }

        return thumbnailImage.jpegData(compressionQuality: thumbnailCompressionQuality)
    }
}

// MARK: - Camera View

/// A UIKit camera wrapper for taking photos within the waypoint creation flow.
///
/// Uses `UIImagePickerController` with `.camera` source type. The captured image
/// is passed back via the `onCapture` callback.
struct CameraView: UIViewControllerRepresentable {
    /// Callback invoked with the captured image.
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    /// Coordinator handling UIImagePickerController delegate callbacks.
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
#endif
