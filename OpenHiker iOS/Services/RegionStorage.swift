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

import Foundation

/// Manages persistent storage of downloaded map regions on iOS.
///
/// This singleton handles saving, loading, and deleting ``Region`` objects and their
/// associated MBTiles database files. Region metadata is persisted as a JSON array
/// in the app's Documents directory, while tile data is stored as individual `.mbtiles`
/// files in a `regions/` subdirectory.
///
/// ## Storage layout
/// ```
/// Documents/
///   regions_metadata.json       ← JSON array of Region objects
///   regions/
///     <uuid>.mbtiles            ← SQLite MBTiles databases (one per region)
/// ```
class RegionStorage: ObservableObject {
    /// Shared singleton instance used throughout the iOS app.
    static let shared = RegionStorage()

    /// All currently saved regions, sorted by creation date (newest first).
    @Published var regions: [Region] = []

    private let fileManager = FileManager.default

    /// Filename for the JSON metadata file that stores all region information.
    private let metadataFileName = "regions_metadata.json"

    /// The app's Documents directory URL.
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// The subdirectory where MBTiles database files are stored.
    private var regionsDirectory: URL {
        documentsDirectory.appendingPathComponent("regions", isDirectory: true)
    }

    /// Full URL to the JSON metadata file.
    private var metadataURL: URL {
        documentsDirectory.appendingPathComponent(metadataFileName)
    }

    /// Updates the published ``regions`` array on the main thread to avoid
    /// "Publishing changes from background threads" warnings from SwiftUI.
    private func updateRegions(_ newValue: [Region]) {
        if Thread.isMainThread {
            regions = newValue
        } else {
            DispatchQueue.main.async { self.regions = newValue }
        }
    }

    /// Private initializer enforcing singleton pattern.
    /// Creates the regions directory if needed and loads existing region metadata.
    private init() {
        ensureDirectoriesExist()
        loadRegions()
    }

    /// Creates the `regions/` subdirectory if it doesn't already exist.
    private func ensureDirectoriesExist() {
        try? fileManager.createDirectory(at: regionsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public Methods

    /// Loads all saved regions from the JSON metadata file on disk.
    ///
    /// Populates the ``regions`` array sorted by creation date (newest first).
    /// If the metadata file doesn't exist or can't be decoded, the array is set to empty.
    func loadRegions() {
        guard fileManager.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let loadedRegions = try? JSONDecoder().decode([Region].self, from: data) else {
            updateRegions([])
            return
        }
        updateRegions(loadedRegions.sorted { $0.createdAt > $1.createdAt })
    }

    /// Saves a new or updated region to persistent storage.
    ///
    /// If a region with the same ID already exists, it is replaced. The updated
    /// list is written to the JSON metadata file and the ``regions`` property is refreshed.
    ///
    /// - Parameter region: The ``Region`` to save.
    func saveRegion(_ region: Region) {
        var allRegions = regions
        allRegions.removeAll { $0.id == region.id }
        allRegions.append(region)
        allRegions.sort { $0.createdAt > $1.createdAt }

        do {
            let data = try JSONEncoder().encode(allRegions)
            try data.write(to: metadataURL)
            updateRegions(allRegions)
        } catch {
            print("Error saving region metadata: \(error.localizedDescription)")
        }
    }

    /// Renames a region and persists the change to disk.
    ///
    /// Creates a copy of the region with the new name and saves it,
    /// replacing the existing entry. The caller should also trigger
    /// ``WatchConnectivityManager/sendAvailableRegions()`` to push
    /// the updated name to the watch.
    ///
    /// - Parameters:
    ///   - region: The region to rename.
    ///   - newName: The new name for the region.
    func renameRegion(_ region: Region, to newName: String) {
        var updatedRegion = region
        updatedRegion.name = newName
        saveRegion(updatedRegion)
    }

    /// Deletes a region and its associated MBTiles file from disk.
    ///
    /// Removes the `.mbtiles` database file from the `regions/` directory, then
    /// updates the JSON metadata to reflect the deletion.
    ///
    /// - Parameter region: The ``Region`` to delete.
    func deleteRegion(_ region: Region) {
        // Delete the MBTiles file
        let mbtilesURL = regionsDirectory.appendingPathComponent(region.mbtilesFilename)
        try? fileManager.removeItem(at: mbtilesURL)

        // Delete the routing database file if it exists
        let routingURL = regionsDirectory.appendingPathComponent(region.routingDbFilename)
        try? fileManager.removeItem(at: routingURL)

        // Update metadata
        var allRegions = regions
        allRegions.removeAll { $0.id == region.id }

        do {
            let data = try JSONEncoder().encode(allRegions)
            try data.write(to: metadataURL)
            updateRegions(allRegions)
        } catch {
            print("Error updating region metadata after deletion: \(error.localizedDescription)")
        }
    }

    /// Deletes regions at the specified index offsets from the ``regions`` array.
    ///
    /// Convenience method for SwiftUI's `onDelete` modifier.
    ///
    /// - Parameter offsets: The index set of regions to delete.
    func deleteRegions(at offsets: IndexSet) {
        for index in offsets {
            deleteRegion(regions[index])
        }
    }

    /// Returns the file URL for a region's MBTiles database.
    ///
    /// - Parameter region: The ``Region`` whose MBTiles file URL is needed.
    /// - Returns: The full file URL to the `.mbtiles` file in the `regions/` directory.
    func mbtilesURL(for region: Region) -> URL {
        regionsDirectory.appendingPathComponent(region.mbtilesFilename)
    }

    /// Returns the file URL for a region's routing graph database.
    ///
    /// - Parameter region: The ``Region`` whose routing database file URL is needed.
    /// - Returns: The full file URL to the `.routing.db` file in the `regions/` directory.
    func routingDbURL(for region: Region) -> URL {
        regionsDirectory.appendingPathComponent(region.routingDbFilename)
    }

    /// Creates a ``Region`` object from a completed download.
    ///
    /// Extracts the file size from the downloaded MBTiles file and constructs a
    /// ``Region`` with the metadata from the original download request.
    ///
    /// - Parameters:
    ///   - request: The original ``RegionSelectionRequest`` that initiated the download.
    ///   - mbtilesURL: The URL of the downloaded MBTiles file.
    ///   - tileCount: The total number of tiles that were downloaded.
    /// - Returns: A fully populated ``Region`` ready to be saved.
    func createRegion(
        from request: RegionSelectionRequest,
        mbtilesURL: URL,
        tileCount: Int,
        hasRoutingData: Bool = false
    ) -> Region {
        let fileSize = (try? fileManager.attributesOfItem(atPath: mbtilesURL.path)[.size] as? Int64) ?? 0

        return Region(
            id: UUID(uuidString: mbtilesURL.deletingPathExtension().lastPathComponent) ?? UUID(),
            name: request.name,
            boundingBox: request.boundingBox,
            zoomLevels: request.zoomLevels,
            tileCount: tileCount,
            fileSizeBytes: fileSize,
            hasRoutingData: hasRoutingData
        )
    }

    /// Converts a ``Region`` to a ``RegionMetadata`` object for watch transfer.
    ///
    /// ``RegionMetadata`` is a lightweight representation used when sending region
    /// information to the Apple Watch via WatchConnectivity.
    ///
    /// - Parameter region: The ``Region`` to convert.
    /// - Returns: A ``RegionMetadata`` suitable for watch transfer.
    func metadata(for region: Region) -> RegionMetadata {
        RegionMetadata(from: region)
    }
}
