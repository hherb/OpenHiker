import Foundation

/// Manages persistent storage of downloaded regions on iOS
class RegionStorage: ObservableObject {
    static let shared = RegionStorage()

    @Published var regions: [Region] = []

    private let fileManager = FileManager.default
    private let metadataFileName = "regions_metadata.json"

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private var regionsDirectory: URL {
        documentsDirectory.appendingPathComponent("regions", isDirectory: true)
    }

    private var metadataURL: URL {
        documentsDirectory.appendingPathComponent(metadataFileName)
    }

    private init() {
        ensureDirectoriesExist()
        loadRegions()
    }

    private func ensureDirectoriesExist() {
        try? fileManager.createDirectory(at: regionsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public Methods

    /// Load all saved regions from disk
    func loadRegions() {
        guard fileManager.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let loadedRegions = try? JSONDecoder().decode([Region].self, from: data) else {
            regions = []
            return
        }
        regions = loadedRegions.sorted { $0.createdAt > $1.createdAt }
    }

    /// Save a new region after download completes
    func saveRegion(_ region: Region) {
        var allRegions = regions
        allRegions.removeAll { $0.id == region.id }
        allRegions.append(region)
        allRegions.sort { $0.createdAt > $1.createdAt }

        do {
            let data = try JSONEncoder().encode(allRegions)
            try data.write(to: metadataURL)
            regions = allRegions
        } catch {
            print("Error saving region metadata: \(error.localizedDescription)")
        }
    }

    /// Delete a region and its MBTiles file
    func deleteRegion(_ region: Region) {
        // Delete the MBTiles file
        let mbtilesURL = regionsDirectory.appendingPathComponent(region.mbtilesFilename)
        try? fileManager.removeItem(at: mbtilesURL)

        // Update metadata
        var allRegions = regions
        allRegions.removeAll { $0.id == region.id }

        do {
            let data = try JSONEncoder().encode(allRegions)
            try data.write(to: metadataURL)
            regions = allRegions
        } catch {
            print("Error updating region metadata after deletion: \(error.localizedDescription)")
        }
    }

    /// Delete regions at the given offsets
    func deleteRegions(at offsets: IndexSet) {
        for index in offsets {
            deleteRegion(regions[index])
        }
    }

    /// Get the URL for a region's MBTiles file
    func mbtilesURL(for region: Region) -> URL {
        regionsDirectory.appendingPathComponent(region.mbtilesFilename)
    }

    /// Create a Region object from download results
    func createRegion(
        from request: RegionSelectionRequest,
        mbtilesURL: URL,
        tileCount: Int
    ) -> Region {
        let fileSize = (try? fileManager.attributesOfItem(atPath: mbtilesURL.path)[.size] as? Int64) ?? 0

        return Region(
            id: UUID(uuidString: mbtilesURL.deletingPathExtension().lastPathComponent) ?? UUID(),
            name: request.name,
            boundingBox: request.boundingBox,
            zoomLevels: request.zoomLevels,
            tileCount: tileCount,
            fileSizeBytes: fileSize
        )
    }

    /// Convert a Region to RegionMetadata for watch transfer
    func metadata(for region: Region) -> RegionMetadata {
        RegionMetadata(from: region)
    }
}
