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
import Compression

/// Downloads and queries elevation data from Tilezen skadi tiles (primary)
/// or OpenTopography SRTM mirror (fallback).
///
/// Each elevation tile covers a 1°×1° cell and is stored in HGT format
/// (raw 16-bit signed big-endian integers on a 3601×3601 grid). Tiles are
/// cached in `Documents/elevation/` and reused across region downloads.
///
/// ## Data sources
/// | Source | Coverage | Resolution | License |
/// |--------|----------|-----------|---------|
/// | Tilezen/Mapzen skadi (SRTM+ASTER) | Global | ~30 m | Public domain |
/// | OpenTopography SRTM GL1 (fallback) | 60°N–56°S | ~30 m | Public domain |
///
/// ## Bilinear interpolation
/// For a query point the four surrounding grid cells are located and their
/// elevations are linearly interpolated for sub-cell precision.
actor ElevationDataManager {

    // MARK: - Configuration

    /// Number of rows/columns in an HGT tile (3601 for 1-arc-second data).
    private static let hgtGridSize: Int = 3601

    /// Void marker in HGT files (–32768 means no data, e.g. ocean).
    private static let hgtVoidValue: Int16 = -32768

    /// Maximum number of download retries per tile before giving up.
    private static let maxRetries: Int = 4

    /// Base URL for Tilezen/Mapzen skadi elevation tiles on AWS (no auth required).
    ///
    /// These are gzip-compressed 1-arc-second HGT files sourced from SRTM and
    /// ASTER GDEM. Coverage is global.
    /// Pattern: `skadi/{N|S}{lat:02d}/{tileName}.hgt.gz`
    private static let skadiBaseURL =
        "https://elevation-tiles-prod.s3.amazonaws.com/skadi"

    /// Nanoseconds per second, used in retry delay calculations.
    private static let nanosecondsPerSecond: UInt64 = 1_000_000_000

    /// Maximum number of tiles to keep in the memory cache.
    /// Each tile is ~25 MB, so 4 tiles ≈ 100 MB.
    private static let maxCachedTiles: Int = 4

    // MARK: - Properties

    /// Cache of loaded HGT grids keyed by tile name (e.g. "N47E011").
    /// Each entry holds the full 3601×3601 grid of Int16 elevation samples.
    private var loadedTiles: [String: [Int16]] = [:]

    /// Directory where downloaded HGT files are cached on disk.
    private let cacheDirectory: URL

    /// URL session for downloading elevation tiles.
    private let session: URLSession

    // MARK: - Init

    /// Create an elevation data manager.
    ///
    /// The cache directory defaults to `Documents/elevation/`.
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.cacheDirectory = docs.appendingPathComponent("elevation", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [
            "User-Agent": "OpenHiker/1.0 (iOS; hiking navigation app)"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Look up elevation for a single coordinate using bilinear interpolation.
    ///
    /// Loads the relevant 1°×1° tile from cache (or downloads it first).
    ///
    /// - Parameter coordinate: The geographic coordinate to query.
    /// - Returns: Elevation in metres above sea level, or `nil` if the
    ///   tile is unavailable or the point falls on water/void.
    func elevation(at coordinate: CLLocationCoordinate2D) async throws -> Double? {
        let tileName = Self.tileName(for: coordinate)
        let grid = try await loadTile(tileName)
        return bilinearInterpolation(grid: grid, coordinate: coordinate)
    }

    /// Look up elevations for multiple coordinates efficiently.
    ///
    /// Groups coordinates by tile so that each tile is loaded only once.
    ///
    /// - Parameter coordinates: The coordinates to query.
    /// - Returns: An array of elevation values (same order as input).
    ///   `nil` entries mean the point's tile is unavailable or the point
    ///   is on water.
    func elevations(for coordinates: [CLLocationCoordinate2D]) async throws -> [Double?] {
        // Group by tile name
        var tileGroups: [String: [(index: Int, coord: CLLocationCoordinate2D)]] = [:]
        for (i, coord) in coordinates.enumerated() {
            let name = Self.tileName(for: coord)
            tileGroups[name, default: []].append((index: i, coord: coord))
        }

        var results = [Double?](repeating: nil, count: coordinates.count)

        for (tileName, entries) in tileGroups {
            do {
                let grid = try await loadTile(tileName)
                for entry in entries {
                    results[entry.index] = bilinearInterpolation(grid: grid, coordinate: entry.coord)
                }
            } catch {
                // Tile unavailable — leave results as nil for these coords
                print("Elevation tile \(tileName) unavailable: \(error.localizedDescription)")
            }
        }

        return results
    }

    /// Download all elevation tiles needed to cover a bounding box.
    ///
    /// Useful for pre-downloading before graph building so that elevation
    /// lookups during graph construction are all cache hits.
    ///
    /// - Parameters:
    ///   - boundingBox: The geographic area to cover.
    ///   - progress: Callback with `(tilesDownloaded, totalTiles)`.
    func downloadTiles(
        for boundingBox: BoundingBox,
        progress: @escaping (Int, Int) -> Void
    ) async throws {
        let tileNames = Self.tileNames(for: boundingBox)
        let total = tileNames.count
        var downloaded = 0

        for tileName in tileNames {
            _ = try await loadTile(tileName)
            downloaded += 1
            progress(downloaded, total)
        }
    }

    /// Clear all cached elevation tiles from disk and memory.
    func clearCache() throws {
        loadedTiles.removeAll()
        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try FileManager.default.removeItem(at: cacheDirectory)
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Tile Loading

    /// Load a tile from memory cache, disk cache, or download it.
    ///
    /// - Parameter tileName: The tile name (e.g. "N47E011").
    /// - Returns: The 3601×3601 grid of Int16 elevation samples.
    private func loadTile(_ tileName: String) async throws -> [Int16] {
        // Memory cache
        if let cached = loadedTiles[tileName] {
            return cached
        }

        // Disk cache
        let diskPath = cacheDirectory.appendingPathComponent("\(tileName).hgt")
        if FileManager.default.fileExists(atPath: diskPath.path) {
            let grid = try readHGT(at: diskPath)
            loadedTiles[tileName] = grid
            return grid
        }

        // Download
        let data = try await downloadHGT(tileName: tileName)
        try data.write(to: diskPath)

        let grid = try readHGT(at: diskPath)
        evictTileIfNeeded()
        loadedTiles[tileName] = grid
        return grid
    }

    /// Read an HGT file from disk into an array of Int16 elevation samples.
    ///
    /// HGT is simply 3601×3601 big-endian Int16 values, row-major order
    /// from north to south. Total file size: 3601 × 3601 × 2 = 25,934,402 bytes.
    ///
    /// - Parameter url: Path to the `.hgt` file.
    /// - Returns: An array of `3601×3601` Int16 values.
    private func readHGT(at url: URL) throws -> [Int16] {
        let data = try Data(contentsOf: url)
        let expectedSize = Self.hgtGridSize * Self.hgtGridSize * 2
        guard data.count >= expectedSize else {
            throw ElevationError.invalidTileData(url.lastPathComponent)
        }

        var grid = [Int16](repeating: 0, count: Self.hgtGridSize * Self.hgtGridSize)
        data.withUnsafeBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            for i in 0..<grid.count {
                let hi = Int16(bytes[i * 2])
                let lo = Int16(bytes[i * 2 + 1])
                grid[i] = (hi << 8) | lo  // Big-endian
            }
        }
        return grid
    }

    // MARK: - Download

    /// Download an HGT file for the given tile.
    ///
    /// Tries the Tilezen skadi tiles first (gzip-compressed HGT on AWS),
    /// then falls back to the OpenTopography SRTM mirror.
    ///
    /// - Parameter tileName: Tile name like "N47E011".
    /// - Returns: The raw HGT file data (uncompressed).
    private func downloadHGT(tileName: String) async throws -> Data {
        // Try Tilezen skadi (gzip-compressed HGT)
        do {
            return try await downloadSkadiTile(tileName: tileName)
        } catch {
            print("Skadi download failed for \(tileName): \(error.localizedDescription), trying fallback...")
        }

        // Fall back to OpenTopography SRTM (raw HGT)
        return try await downloadSRTMTile(tileName: tileName)
    }

    /// Download a gzip-compressed HGT tile from the Tilezen skadi service on AWS S3.
    ///
    /// URL pattern: `https://elevation-tiles-prod.s3.amazonaws.com/skadi/N47/N47E011.hgt.gz`
    ///
    /// - Parameter tileName: Tile name like "N47E011".
    /// - Returns: The decompressed raw HGT data.
    private func downloadSkadiTile(tileName: String) async throws -> Data {
        let latFolder = String(tileName.prefix(3))  // e.g. "N47"
        let urlString = "\(Self.skadiBaseURL)/\(latFolder)/\(tileName).hgt.gz"

        guard let url = URL(string: urlString) else {
            throw ElevationError.invalidTileName(tileName)
        }

        let gzipData = try await downloadWithRetry(url: url)
        return try decompressGzip(gzipData)
    }

    /// Download a raw HGT tile from the OpenTopography SRTM mirror.
    ///
    /// URL pattern: `https://opentopography.s3.sdsc.edu/raster/SRTM_GL1/SRTM_GL1_srtm/N47E011.hgt`
    ///
    /// - Parameter tileName: Tile name like "N47E011".
    /// - Returns: The raw HGT data.
    private func downloadSRTMTile(tileName: String) async throws -> Data {
        let urlString = "https://opentopography.s3.sdsc.edu/raster/SRTM_GL1/SRTM_GL1_srtm/\(tileName).hgt"

        guard let url = URL(string: urlString) else {
            throw ElevationError.invalidTileName(tileName)
        }

        let data = try await downloadWithRetry(url: url)

        // Validate that the downloaded data is the expected HGT size
        let expectedSize = Self.hgtGridSize * Self.hgtGridSize * MemoryLayout<Int16>.size
        guard data.count == expectedSize else {
            throw ElevationError.invalidTileData(tileName)
        }

        return data
    }

    /// Download data from a URL with exponential backoff retry.
    ///
    /// Retries up to ``maxRetries`` times on transient errors (5xx, network)
    /// with delays of 2, 4, 8, 16 seconds. Does not retry on client errors
    /// (4xx) as those indicate permanent failure.
    ///
    /// - Parameter url: The URL to download.
    /// - Returns: The downloaded data.
    private func downloadWithRetry(url: URL) async throws -> Data {
        var lastError: Error = ElevationError.downloadFailed(url.lastPathComponent)

        for attempt in 0..<Self.maxRetries {
            do {
                let (data, response) = try await session.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ElevationError.httpError(0, url.absoluteString)
                }

                switch httpResponse.statusCode {
                case 200:
                    return data
                case 400..<500:
                    // Client errors are permanent — don't retry
                    throw ElevationError.httpError(httpResponse.statusCode, url.absoluteString)
                default:
                    // Server errors (5xx) — retry
                    throw ElevationError.httpError(httpResponse.statusCode, url.absoluteString)
                }
            } catch let error as ElevationError {
                if case .httpError(let code, _) = error, (400..<500).contains(code) {
                    throw error  // Don't retry client errors
                }
                lastError = error
                if attempt < Self.maxRetries - 1 {
                    let delay = UInt64(pow(2.0, Double(attempt + 1))) * Self.nanosecondsPerSecond
                    try await Task.sleep(nanoseconds: delay)
                }
            } catch {
                lastError = error
                if attempt < Self.maxRetries - 1 {
                    let delay = UInt64(pow(2.0, Double(attempt + 1))) * Self.nanosecondsPerSecond
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }
        throw lastError
    }

    /// Decompress gzip-compressed data using the Compression framework.
    ///
    /// - Parameter data: The gzip-compressed input data.
    /// - Returns: The decompressed data.
    /// - Throws: ``ElevationError/invalidTileData(_:)`` if decompression fails.
    private func decompressGzip(_ data: Data) throws -> Data {
        // Expected output: one HGT tile = 3601 × 3601 × 2 bytes
        let expectedSize = Self.hgtGridSize * Self.hgtGridSize * MemoryLayout<Int16>.size
        let bufferSize = expectedSize + 1024  // Small margin for safety

        let decompressed = try data.withUnsafeBytes { (sourceBuffer: UnsafeRawBufferPointer) -> Data in
            guard let sourcePtr = sourceBuffer.baseAddress else {
                throw ElevationError.invalidTileData("empty gzip data")
            }

            let destBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { destBuffer.deallocate() }

            // Skip gzip header (10 bytes minimum) — the Compression framework's
            // COMPRESSION_ZLIB expects raw deflate without the gzip wrapper.
            // Gzip = 10-byte header + optional fields + deflate stream + 8-byte trailer.
            let headerSize = gzipHeaderSize(data)
            guard headerSize > 0, headerSize < data.count else {
                throw ElevationError.invalidTileData("invalid gzip header")
            }

            let compressedStart = sourcePtr.advanced(by: headerSize)
            let compressedSize = data.count - headerSize - 8  // 8-byte gzip trailer

            let decompressedSize = compression_decode_buffer(
                destBuffer, bufferSize,
                compressedStart.assumingMemoryBound(to: UInt8.self), compressedSize,
                nil,
                COMPRESSION_ZLIB
            )

            guard decompressedSize > 0 else {
                throw ElevationError.invalidTileData("gzip decompression failed")
            }

            return Data(bytes: destBuffer, count: decompressedSize)
        }

        return decompressed
    }

    /// Compute the size of a gzip header.
    ///
    /// Gzip header: 2 magic bytes, 1 method, 1 flags, 4 mtime, 1 xfl, 1 os = 10 bytes minimum.
    /// Additional optional fields (FEXTRA, FNAME, FCOMMENT, FHCRC) may follow.
    ///
    /// - Parameter data: The gzip data.
    /// - Returns: The header size in bytes, or 0 if the data is not valid gzip.
    private func gzipHeaderSize(_ data: Data) -> Int {
        guard data.count >= 10 else { return 0 }
        guard data[0] == 0x1f, data[1] == 0x8b else { return 0 }  // Magic number

        let flags = data[3]
        var offset = 10

        // FEXTRA
        if flags & 0x04 != 0 {
            guard offset + 2 <= data.count else { return 0 }
            let extraLen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + extraLen
        }

        // FNAME — null-terminated string
        if flags & 0x08 != 0 {
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1  // Skip null terminator
        }

        // FCOMMENT — null-terminated string
        if flags & 0x10 != 0 {
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }

        // FHCRC — 2-byte header CRC
        if flags & 0x02 != 0 {
            offset += 2
        }

        return offset
    }

    // MARK: - Bilinear Interpolation

    /// Interpolate elevation at a precise coordinate from the HGT grid.
    ///
    /// Finds the four surrounding grid cells and performs bilinear
    /// interpolation for sub-cell accuracy (~30 m at the equator).
    ///
    /// - Parameters:
    ///   - grid: The 3601×3601 Int16 elevation grid.
    ///   - coordinate: The geographic coordinate.
    /// - Returns: Interpolated elevation in metres, or `nil` for void cells.
    private func bilinearInterpolation(
        grid: [Int16],
        coordinate: CLLocationCoordinate2D
    ) -> Double? {
        let lat = coordinate.latitude
        let lon = coordinate.longitude

        // Tile SW corner
        let tileLat = floor(lat)
        let tileLon = floor(lon)

        // Position within tile (0 to 1)
        let fracLat = lat - tileLat
        let fracLon = lon - tileLon

        // Grid indices (row from north = 0)
        let gridSize = Self.hgtGridSize
        let row = Double(gridSize - 1) * (1.0 - fracLat)
        let col = Double(gridSize - 1) * fracLon

        let r0 = Int(floor(row))
        let c0 = Int(floor(col))
        let r1 = min(r0 + 1, gridSize - 1)
        let c1 = min(c0 + 1, gridSize - 1)

        let dr = row - Double(r0)
        let dc = col - Double(c0)

        // Sample four corners
        let e00 = grid[r0 * gridSize + c0]
        let e01 = grid[r0 * gridSize + c1]
        let e10 = grid[r1 * gridSize + c0]
        let e11 = grid[r1 * gridSize + c1]

        // Check for void values — average non-void samples instead of
        // picking an arbitrary one, for smoother coastline behaviour.
        if e00 == Self.hgtVoidValue || e01 == Self.hgtVoidValue ||
           e10 == Self.hgtVoidValue || e11 == Self.hgtVoidValue {
            let samples = [e00, e01, e10, e11].filter { $0 != Self.hgtVoidValue }
            guard !samples.isEmpty else { return nil }
            let sum = samples.reduce(0.0) { $0 + Double($1) }
            return sum / Double(samples.count)
        }

        // Bilinear interpolation
        let top = Double(e00) * (1 - dc) + Double(e01) * dc
        let bottom = Double(e10) * (1 - dc) + Double(e11) * dc
        let elevation = top * (1 - dr) + bottom * dr

        return elevation
    }

    // MARK: - Tile Naming

    /// Compute the HGT tile name for a given coordinate.
    ///
    /// The tile name encodes the SW corner: `N47E011` covers
    /// 47°N–48°N, 11°E–12°E.
    ///
    /// - Parameter coordinate: The geographic coordinate.
    /// - Returns: A tile name string (e.g. "N47E011").
    static func tileName(for coordinate: CLLocationCoordinate2D) -> String {
        let lat = Int(floor(coordinate.latitude))
        let lon = Int(floor(coordinate.longitude))

        let latPrefix = lat >= 0 ? "N" : "S"
        let lonPrefix = lon >= 0 ? "E" : "W"

        return String(format: "%@%02d%@%03d", latPrefix, abs(lat), lonPrefix, abs(lon))
    }

    /// List all tile names needed to cover a bounding box.
    ///
    /// - Parameter bbox: The geographic bounding box.
    /// - Returns: An array of tile name strings.
    static func tileNames(for bbox: BoundingBox) -> [String] {
        let minLat = Int(floor(bbox.south))
        let maxLat = Int(floor(bbox.north))
        let minLon = Int(floor(bbox.west))
        let maxLon = Int(floor(bbox.east))

        var names: [String] = []
        for lat in minLat...maxLat {
            for lon in minLon...maxLon {
                let coord = CLLocationCoordinate2D(
                    latitude: Double(lat) + 0.5,
                    longitude: Double(lon) + 0.5
                )
                names.append(tileName(for: coord))
            }
        }
        return names
    }

    /// Evict the oldest tile from the memory cache when it exceeds ``maxCachedTiles``.
    ///
    /// Uses a simple FIFO strategy: removes an arbitrary entry when the cache
    /// is full. This bounds memory usage to approximately `maxCachedTiles × 25 MB`.
    private func evictTileIfNeeded() {
        while loadedTiles.count >= Self.maxCachedTiles {
            if let key = loadedTiles.keys.first {
                loadedTiles.removeValue(forKey: key)
            }
        }
    }
}

// MARK: - Elevation Errors

/// Errors that can occur during elevation data operations.
enum ElevationError: Error, LocalizedError {
    /// The tile name is malformed.
    case invalidTileName(String)
    /// The downloaded tile data has an unexpected size or format.
    case invalidTileData(String)
    /// Download failed after all retries.
    case downloadFailed(String)
    /// HTTP error with status code.
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidTileName(let name):
            return "Invalid elevation tile name: \(name)"
        case .invalidTileData(let name):
            return "Elevation tile data is corrupt: \(name)"
        case .downloadFailed(let name):
            return "Failed to download elevation tile: \(name)"
        case .httpError(let code, let url):
            return "HTTP \(code) downloading elevation data from \(url)"
        }
    }
}
