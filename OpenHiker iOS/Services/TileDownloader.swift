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
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Downloads map tiles from OpenStreetMap-compatible tile servers and packages them
/// into MBTiles (SQLite) databases for offline use on Apple Watch.
///
/// This is a Swift Actor ensuring thread-safe concurrent downloads. It respects the
/// OSM tile usage policy by rate-limiting requests (100ms delay per tile in each batch)
/// and setting a proper User-Agent header.
///
/// ## Download flow
/// 1. Calculate required tiles from the bounding box and zoom levels
/// 2. Create an MBTiles database via ``WritableTileStore``
/// 3. Download tiles in batches of 50, checking the local cache first
/// 4. Insert downloaded tiles into the MBTiles database
/// 5. Report progress via the callback after each tile
actor TileDownloader {
    /// The URL session configured for tile downloads with rate limiting.
    private let session: URLSession

    /// Local file cache directory for downloaded tiles, avoiding re-downloads.
    private let cacheDirectory: URL

    /// Supported tile server configurations.
    ///
    /// Each server provides a URL template for tile retrieval and an attribution
    /// string to comply with the server's usage policy.
    enum TileServer: String, CaseIterable {
        case osmStandard = "OpenStreetMap"
        case osmTopo = "OpenTopoMap"
        case cyclosm = "CyclOSM"

        /// The URL template with `{z}`, `{x}`, `{y}` placeholders for zoom, column, and row.
        var urlTemplate: String {
            switch self {
            case .osmStandard:
                return "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
            case .osmTopo:
                return "https://tile.opentopomap.org/{z}/{x}/{y}.png"
            case .cyclosm:
                return "https://a.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png"
            }
        }

        /// Attribution text required by the tile server's usage policy.
        var attribution: String {
            switch self {
            case .osmStandard:
                return "© OpenStreetMap contributors"
            case .osmTopo:
                return "© OpenStreetMap contributors, SRTM | © OpenTopoMap (CC-BY-SA)"
            case .cyclosm:
                return "© OpenStreetMap contributors, CyclOSM"
            }
        }
    }

    /// Creates a new tile downloader with a configured URL session and cache directory.
    ///
    /// The URL session is configured with:
    /// - Maximum 4 connections per host
    /// - 30-second request timeout, 300-second resource timeout
    /// - A User-Agent header identifying this app (required by OSM tile usage policy)
    init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true

        // Set a proper User-Agent as required by OSM tile usage policy
        config.httpAdditionalHeaders = [
            #if os(macOS)
            "User-Agent": "OpenHiker/1.0 (macOS; hiking navigation app)"
            #else
            "User-Agent": "OpenHiker/1.0 (iOS; hiking navigation app)"
            #endif
        ]

        self.session = URLSession(configuration: config)

        // Cache directory
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = caches.appendingPathComponent("TileCache", isDirectory: true)

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Downloads all tiles for a region and writes them into an MBTiles database.
    ///
    /// Tiles are downloaded zoom level by zoom level, in batches of 50 tiles each.
    /// Each batch is followed by a rate-limiting delay to respect OSM tile usage policy
    /// (100ms per tile). Progress is reported after each individual tile download.
    ///
    /// - Parameters:
    ///   - request: The ``RegionSelectionRequest`` specifying the area and zoom levels.
    ///   - server: The tile server to download from. Defaults to `.osmTopo`.
    ///   - progress: A callback invoked after each tile to report download progress.
    /// - Returns: The file URL of the completed MBTiles database.
    /// - Throws: Errors from file system operations, database writes, or network failures.
    func downloadRegion(
        _ request: RegionSelectionRequest,
        server: TileServer = .osmTopo,
        progress: @escaping (RegionDownloadProgress) -> Void
    ) async throws -> URL {
        let regionId = UUID()
        let tileRanges = request.boundingBox.tileRanges(zoomLevels: request.zoomLevels)
        let totalTiles = tileRanges.reduce(0) { $0 + $1.tileCount }

        // Create output MBTiles file
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let regionsDir = documentsDir.appendingPathComponent("regions", isDirectory: true)
        try FileManager.default.createDirectory(at: regionsDir, withIntermediateDirectories: true)

        let mbtilesPath = regionsDir.appendingPathComponent("\(regionId.uuidString).mbtiles").path

        // Create MBTiles database
        let metadata: [String: String] = [
            "name": request.name,
            "format": "png",
            "minzoom": String(request.zoomLevels.lowerBound),
            "maxzoom": String(request.zoomLevels.upperBound),
            "bounds": "\(request.boundingBox.west),\(request.boundingBox.south),\(request.boundingBox.east),\(request.boundingBox.north)",
            "center": "\(request.boundingBox.center.longitude),\(request.boundingBox.center.latitude),\((request.zoomLevels.lowerBound + request.zoomLevels.upperBound) / 2)",
            "attribution": server.attribution
        ]

        let tileStore = try WritableTileStore(path: mbtilesPath, metadata: metadata)

        var downloadedCount = 0
        var currentZoom = request.zoomLevels.lowerBound

        progress(RegionDownloadProgress(
            regionId: regionId,
            totalTiles: totalTiles,
            downloadedTiles: 0,
            currentZoom: currentZoom,
            status: .downloading
        ))

        // Download tiles zoom level by zoom level
        for tileRange in tileRanges {
            currentZoom = tileRange.zoom

            try tileStore.beginTransaction()

            // Process tiles in batches
            let tiles = tileRange.allTiles()
            let batchSize = 50

            for batch in tiles.chunked(into: batchSize) {
                // Download batch concurrently
                try await withThrowingTaskGroup(of: (TileCoordinate, Data)?.self) { group in
                    for tile in batch {
                        group.addTask {
                            try await self.downloadTile(tile, server: server)
                        }
                    }

                    for try await result in group {
                        if let (tile, data) = result {
                            try tileStore.insertTile(tile, data: data)
                            downloadedCount += 1

                            progress(RegionDownloadProgress(
                                regionId: regionId,
                                totalTiles: totalTiles,
                                downloadedTiles: downloadedCount,
                                currentZoom: currentZoom,
                                status: .downloading
                            ))
                        }
                    }
                }

                // Respect OSM tile usage policy: max 2 tiles per second sustained
                try await Task.sleep(nanoseconds: UInt64(batch.count) * 100_000_000)
            }

            try tileStore.commitTransaction()
        }

        tileStore.close()

        progress(RegionDownloadProgress(
            regionId: regionId,
            totalTiles: totalTiles,
            downloadedTiles: downloadedCount,
            currentZoom: request.zoomLevels.upperBound,
            status: .completed
        ))

        return URL(fileURLWithPath: mbtilesPath)
    }

    /// Downloads a single tile from the server, checking the local cache first.
    ///
    /// If the tile is already cached on disk, the cached data is returned without
    /// making a network request. Otherwise, the tile is downloaded and saved to the cache.
    ///
    /// - Parameters:
    ///   - tile: The ``TileCoordinate`` specifying zoom, column, and row.
    ///   - server: The ``TileServer`` to download from.
    /// - Returns: A tuple of the tile coordinate and its PNG data, or `nil` if the download failed.
    /// - Throws: Network errors from the URL session.
    private func downloadTile(_ tile: TileCoordinate, server: TileServer) async throws -> (TileCoordinate, Data)? {
        // Check cache first
        let cacheFile = cacheDirectory
            .appendingPathComponent(server.rawValue)
            .appendingPathComponent("\(tile.z)")
            .appendingPathComponent("\(tile.x)")
            .appendingPathComponent("\(tile.y).png")

        if FileManager.default.fileExists(atPath: cacheFile.path),
           let cachedData = try? Data(contentsOf: cacheFile) {
            return (tile, cachedData)
        }

        // Build URL
        let urlString = server.urlTemplate
            .replacingOccurrences(of: "{z}", with: String(tile.z))
            .replacingOccurrences(of: "{x}", with: String(tile.x))
            .replacingOccurrences(of: "{y}", with: String(tile.y))

        guard let url = URL(string: urlString) else {
            return nil
        }

        // Download
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        // Cache the tile
        try? FileManager.default.createDirectory(
            at: cacheFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheFile)

        return (tile, data)
    }

    /// Estimates the download size in bytes for a region request.
    ///
    /// Uses the ``RegionSelectionRequest/estimatedSizeBytes`` calculation based on
    /// an average tile size assumption.
    ///
    /// - Parameter request: The ``RegionSelectionRequest`` to estimate.
    /// - Returns: The estimated download size in bytes.
    func estimateDownloadSize(for request: RegionSelectionRequest) -> Int64 {
        request.estimatedSizeBytes
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    /// Splits an array into sub-arrays of the specified size.
    ///
    /// The last chunk may contain fewer elements if the array length is not
    /// evenly divisible by the chunk size.
    ///
    /// - Parameter size: The maximum number of elements in each chunk.
    /// - Returns: An array of sub-arrays, each containing at most `size` elements.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
