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
import CoreLocation

/// Represents a downloaded map region stored on the device.
///
/// A region captures all the metadata about a set of offline map tiles that have been
/// downloaded for a specific geographic area. It tracks the bounding box, zoom levels,
/// tile count, file size, and the filename of the MBTiles database on disk.
///
/// Regions are persisted as JSON and displayed in the iOS app's "Downloaded Regions" list.
struct Region: Identifiable, Codable, Sendable, Hashable {
    /// Unique identifier for this region
    let id: UUID
    /// User-provided name for the region (e.g., "Yosemite Valley").
    ///
    /// Mutable so the user can rename a region after download.
    var name: String
    /// Geographic bounding box of the downloaded area
    let boundingBox: BoundingBox
    /// Range of zoom levels included in this download
    let zoomLevels: ClosedRange<Int>
    /// Date when the region was downloaded
    let createdAt: Date
    /// Total number of tiles in this region across all zoom levels
    let tileCount: Int
    /// Size of the MBTiles file on disk in bytes
    let fileSizeBytes: Int64

    /// Whether a routing graph database has been built for this region.
    ///
    /// When `true`, a `.routing.db` file exists alongside the `.mbtiles` file
    /// and can be transferred to the watch for offline route computation.
    let hasRoutingData: Bool

    /// The filename for the MBTiles database, derived from the region's UUID.
    var mbtilesFilename: String {
        "\(id.uuidString).mbtiles"
    }

    /// The filename for the routing graph database, derived from the region's UUID.
    var routingDbFilename: String {
        "\(id.uuidString).routing.db"
    }

    /// Human-readable file size (e.g., "12.3 MB") formatted using the system's byte count formatter.
    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    /// Approximate area covered by this region in square kilometers.
    var areaCoveredKm2: Double {
        boundingBox.areaKm2
    }

    /// Create a new region with the given properties.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to a new UUID).
    ///   - name: User-provided name for the region.
    ///   - boundingBox: Geographic bounding box of the downloaded area.
    ///   - zoomLevels: Range of zoom levels included in the download.
    ///   - createdAt: Timestamp of creation (defaults to now).
    ///   - tileCount: Total number of tiles downloaded.
    ///   - fileSizeBytes: Size of the MBTiles file on disk in bytes.
    ///   - hasRoutingData: Whether a routing graph has been built for this region.
    init(
        id: UUID = UUID(),
        name: String,
        boundingBox: BoundingBox,
        zoomLevels: ClosedRange<Int>,
        createdAt: Date = Date(),
        tileCount: Int,
        fileSizeBytes: Int64,
        hasRoutingData: Bool = false
    ) {
        self.id = id
        self.name = name
        self.boundingBox = boundingBox
        self.zoomLevels = zoomLevels
        self.createdAt = createdAt
        self.tileCount = tileCount
        self.fileSizeBytes = fileSizeBytes
        self.hasRoutingData = hasRoutingData
    }
}

// MARK: - Region Download Progress

/// Tracks the progress of downloading a region's map tiles.
///
/// Instances are created by `TileDownloader` and passed to progress callbacks so the UI
/// can show a progress bar, current zoom level, and status messages to the user.
struct RegionDownloadProgress: Sendable {
    /// The UUID of the region being downloaded
    let regionId: UUID
    /// Total number of tiles to download across all zoom levels
    let totalTiles: Int
    /// Number of tiles downloaded so far
    let downloadedTiles: Int
    /// The zoom level currently being downloaded
    let currentZoom: Int
    /// Current status of the download pipeline
    let status: Status

    /// The stages a region download passes through, from pending to completed.
    enum Status: Sendable {
        case pending
        case downloading
        case rendering
        case packaging
        case downloadingTrailData
        case downloadingElevation
        case buildingRoutingGraph
        case transferring
        case completed
        case failed(Error)

        /// A human-readable description of this status for display in the UI.
        var description: String {
            switch self {
            case .pending: return "Waiting..."
            case .downloading: return "Downloading tiles..."
            case .rendering: return "Rendering map..."
            case .packaging: return "Creating offline package..."
            case .downloadingTrailData: return "Downloading trail data..."
            case .downloadingElevation: return "Downloading elevation data..."
            case .buildingRoutingGraph: return "Building routing graph..."
            case .transferring: return "Transferring to Watch..."
            case .completed: return "Complete"
            case .failed(let error): return "Failed: \(error.localizedDescription)"
            }
        }
    }

    /// Download progress as a fraction from 0.0 to 1.0.
    var progress: Double {
        guard totalTiles > 0 else { return 0 }
        return Double(downloadedTiles) / Double(totalTiles)
    }

    /// Whether the download has completed successfully.
    var isComplete: Bool {
        if case .completed = status { return true }
        return false
    }

    /// Whether the download has failed.
    var hasFailed: Bool {
        if case .failed = status { return true }
        return false
    }
}

// MARK: - Region Selection Request

/// Parameters for selecting a new region to download.
///
/// Captures the user's choices from the download configuration sheet: the region name,
/// geographic bounds, zoom levels, and whether to include contour lines. Also provides
/// estimates of the download size to help the user make informed decisions.
struct RegionSelectionRequest: Codable, Sendable {
    /// User-provided name for the new region
    let name: String
    /// Geographic bounding box defining the area to download
    let boundingBox: BoundingBox
    /// Range of zoom levels to download tiles for
    let zoomLevels: ClosedRange<Int>
    /// Whether to include contour line tiles (adds ~30% more data)
    let includeContours: Bool
    /// Whether to build an offline routing graph for this region.
    ///
    /// When enabled, OSM trail data and elevation data are downloaded
    /// and compiled into a `.routing.db` SQLite database alongside the
    /// MBTiles tile data.
    let includeRoutingData: Bool

    /// Default zoom levels for hiking: 12-16 provides enough detail for trail navigation.
    static let defaultHikingZoomLevels: ClosedRange<Int> = 12...16

    /// Estimate the download size in bytes.
    ///
    /// Uses an average tile size of ~15KB for raster tiles, with a 30% increase
    /// when contour lines are included.
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

    /// Human-readable estimated download size for display in the UI.
    var estimatedSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: estimatedSizeBytes, countStyle: .file)
    }

    /// Create a new region selection request.
    ///
    /// - Parameters:
    ///   - name: User-provided name for the region.
    ///   - boundingBox: Geographic area to download.
    ///   - zoomLevels: Zoom levels to include (defaults to `12...16` for hiking).
    ///   - includeContours: Whether to include contour line data (defaults to `true`).
    ///   - includeRoutingData: Whether to build a routing graph (defaults to `true`).
    init(
        name: String,
        boundingBox: BoundingBox,
        zoomLevels: ClosedRange<Int> = Self.defaultHikingZoomLevels,
        includeContours: Bool = true,
        includeRoutingData: Bool = true
    ) {
        self.name = name
        self.boundingBox = boundingBox
        self.zoomLevels = zoomLevels
        self.includeContours = includeContours
        self.includeRoutingData = includeRoutingData
    }
}

// MARK: - Region Metadata for Watch

/// Lightweight region metadata for the watch app.
///
/// This is a slimmed-down version of `Region` that omits iOS-specific fields like
/// file size and creation date. It is sent to the watch via WatchConnectivity along
/// with the MBTiles file, and persisted as JSON on the watch for offline access.
struct RegionMetadata: Identifiable, Codable, Sendable {
    /// Unique identifier matching the corresponding `Region` on iOS
    let id: UUID
    /// User-provided name for the region.
    ///
    /// Mutable so the user can rename a region after transfer.
    var name: String
    /// Geographic bounding box of the region
    let boundingBox: BoundingBox
    /// Minimum zoom level available in this region's tiles
    let minZoom: Int
    /// Maximum zoom level available in this region's tiles
    let maxZoom: Int
    /// Total number of tiles in the region
    let tileCount: Int

    /// Whether an offline routing graph database is available for this region.
    let hasRoutingData: Bool

    /// The range of available zoom levels as a `ClosedRange`.
    var zoomLevels: ClosedRange<Int> {
        minZoom...maxZoom
    }

    /// Create metadata from a full `Region` object.
    ///
    /// Used on iOS when preparing to transfer a region to the watch.
    ///
    /// - Parameter region: The full region to extract metadata from.
    init(from region: Region) {
        self.id = region.id
        self.name = region.name
        self.boundingBox = region.boundingBox
        self.minZoom = region.zoomLevels.lowerBound
        self.maxZoom = region.zoomLevels.upperBound
        self.tileCount = region.tileCount
        self.hasRoutingData = region.hasRoutingData
    }

    /// Create metadata from explicit values.
    ///
    /// Used on the watch when reconstructing metadata from a received WatchConnectivity transfer.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for the region.
    ///   - name: User-provided name for the region.
    ///   - boundingBox: Geographic bounding box.
    ///   - minZoom: Minimum available zoom level.
    ///   - maxZoom: Maximum available zoom level.
    ///   - tileCount: Total number of tiles.
    ///   - hasRoutingData: Whether a routing database is available.
    init(
        id: UUID,
        name: String,
        boundingBox: BoundingBox,
        minZoom: Int,
        maxZoom: Int,
        tileCount: Int,
        hasRoutingData: Bool = false
    ) {
        self.id = id
        self.name = name
        self.boundingBox = boundingBox
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.tileCount = tileCount
        self.hasRoutingData = hasRoutingData
    }

    /// Check if a geographic coordinate is within this region's bounding box.
    ///
    /// - Parameter coordinate: The coordinate to test.
    /// - Returns: `true` if the coordinate falls within the region.
    func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        boundingBox.contains(coordinate)
    }
}
