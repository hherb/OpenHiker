import Foundation
import UIKit

/// Downloads map tiles from OpenStreetMap tile servers
actor TileDownloader {
    private let session: URLSession
    private let cacheDirectory: URL

    /// Supported tile server configurations
    enum TileServer: String, CaseIterable {
        case osmStandard = "OpenStreetMap"
        case osmTopo = "OpenTopoMap"
        case cyclosm = "CyclOSM"

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

    init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true

        // Set a proper User-Agent as required by OSM tile usage policy
        config.httpAdditionalHeaders = [
            "User-Agent": "OpenHiker/1.0 (iOS; hiking navigation app)"
        ]

        self.session = URLSession(configuration: config)

        // Cache directory
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = caches.appendingPathComponent("TileCache", isDirectory: true)

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Download tiles for a region and create an MBTiles file
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

    /// Download a single tile
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

    /// Estimate download size for a region
    func estimateDownloadSize(for request: RegionSelectionRequest) -> Int64 {
        request.estimatedSizeBytes
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
