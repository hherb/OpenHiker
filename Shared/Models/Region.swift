import Foundation
import CoreLocation

/// Represents a downloaded map region stored on the device
struct Region: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let boundingBox: BoundingBox
    let zoomLevels: ClosedRange<Int>
    let createdAt: Date
    let tileCount: Int
    let fileSizeBytes: Int64

    /// The filename for the MBTiles database
    var mbtilesFilename: String {
        "\(id.uuidString).mbtiles"
    }

    /// Human-readable file size
    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    /// Approximate area covered in square kilometers
    var areaCoveredKm2: Double {
        boundingBox.areaKm2
    }

    init(
        id: UUID = UUID(),
        name: String,
        boundingBox: BoundingBox,
        zoomLevels: ClosedRange<Int>,
        createdAt: Date = Date(),
        tileCount: Int,
        fileSizeBytes: Int64
    ) {
        self.id = id
        self.name = name
        self.boundingBox = boundingBox
        self.zoomLevels = zoomLevels
        self.createdAt = createdAt
        self.tileCount = tileCount
        self.fileSizeBytes = fileSizeBytes
    }
}

// MARK: - Region Download Progress

/// Tracks the progress of downloading a region
struct RegionDownloadProgress: Sendable {
    let regionId: UUID
    let totalTiles: Int
    let downloadedTiles: Int
    let currentZoom: Int
    let status: Status

    enum Status: Sendable {
        case pending
        case downloading
        case rendering
        case packaging
        case transferring
        case completed
        case failed(Error)

        var description: String {
            switch self {
            case .pending: return "Waiting..."
            case .downloading: return "Downloading tiles..."
            case .rendering: return "Rendering map..."
            case .packaging: return "Creating offline package..."
            case .transferring: return "Transferring to Watch..."
            case .completed: return "Complete"
            case .failed(let error): return "Failed: \(error.localizedDescription)"
            }
        }
    }

    var progress: Double {
        guard totalTiles > 0 else { return 0 }
        return Double(downloadedTiles) / Double(totalTiles)
    }

    var isComplete: Bool {
        if case .completed = status { return true }
        return false
    }

    var hasFailed: Bool {
        if case .failed = status { return true }
        return false
    }
}

// MARK: - Region Selection Request

/// Parameters for selecting a new region to download
struct RegionSelectionRequest: Codable, Sendable {
    let name: String
    let boundingBox: BoundingBox
    let zoomLevels: ClosedRange<Int>
    let includeContours: Bool

    /// Default zoom levels for hiking (enough detail for trail navigation)
    static let defaultHikingZoomLevels: ClosedRange<Int> = 12...16

    /// Estimate the download size in bytes
    var estimatedSizeBytes: Int64 {
        let tileCount = boundingBox.estimateTileCount(zoomLevels: zoomLevels)
        // Average tile size: ~15KB for raster tiles
        let avgTileSize: Int64 = 15_000
        var size = Int64(tileCount) * avgTileSize

        // Contours add roughly 30% more data
        if includeContours {
            size = Int64(Double(size) * 1.3)
        }

        return size
    }

    /// Estimate download size formatted for display
    var estimatedSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: estimatedSizeBytes, countStyle: .file)
    }

    init(
        name: String,
        boundingBox: BoundingBox,
        zoomLevels: ClosedRange<Int> = Self.defaultHikingZoomLevels,
        includeContours: Bool = true
    ) {
        self.name = name
        self.boundingBox = boundingBox
        self.zoomLevels = zoomLevels
        self.includeContours = includeContours
    }
}

// MARK: - Region Metadata for Watch

/// Lightweight region metadata for the watch app
struct RegionMetadata: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let boundingBox: BoundingBox
    let minZoom: Int
    let maxZoom: Int
    let tileCount: Int

    var zoomLevels: ClosedRange<Int> {
        minZoom...maxZoom
    }

    init(from region: Region) {
        self.id = region.id
        self.name = region.name
        self.boundingBox = region.boundingBox
        self.minZoom = region.zoomLevels.lowerBound
        self.maxZoom = region.zoomLevels.upperBound
        self.tileCount = region.tileCount
    }

    init(
        id: UUID,
        name: String,
        boundingBox: BoundingBox,
        minZoom: Int,
        maxZoom: Int,
        tileCount: Int
    ) {
        self.id = id
        self.name = name
        self.boundingBox = boundingBox
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.tileCount = tileCount
    }

    /// Check if a location is within this region
    func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        boundingBox.contains(coordinate)
    }
}
