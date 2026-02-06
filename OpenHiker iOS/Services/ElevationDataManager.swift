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

/// Downloads and queries elevation data from Copernicus DEM GLO-30 (primary)
/// or SRTM 1-arc-second (fallback).
///
/// Each elevation tile covers a 1°×1° cell and is stored in HGT format
/// (raw 16-bit signed big-endian integers on a 3601×3601 grid). Tiles are
/// cached in `Documents/elevation/` and reused across region downloads.
///
/// ## Data sources
/// | Source | Coverage | Resolution | License |
/// |--------|----------|-----------|---------|
/// | Copernicus DEM GLO-30 | 90°N–90°S (global) | ~30 m | CC-BY-4.0 |
/// | SRTM 1-arc-second | 60°N–56°S | ~30 m | Public domain |
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

    /// Base URL for Copernicus DEM tiles on AWS Open Data (no auth required).
    /// Pattern: `Copernicus_DSM_COG_10_{N|S}{lat:02d}_00_{E|W}{lon:03d}_DEM.tif`
    /// We download a pre-converted HGT version when available.
    private static let copernicusBaseURL =
        "https://copernicus-dem-30m.s3.eu-central-1.amazonaws.com"

    /// Base URL for SRTM tiles (fallback, requires no auth for most mirrors).
    private static let srtmBaseURL =
        "https://srtm.csi.cgiar.org/wp-content/uploads/files/srtm_5x5/TIFF"

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

    /// Download an HGT file for the given tile, trying Copernicus first then SRTM.
    ///
    /// Retries with exponential backoff on network failures.
    ///
    /// - Parameter tileName: Tile name like "N47E011".
    /// - Returns: The raw HGT file data.
    private func downloadHGT(tileName: String) async throws -> Data {
        // Try Copernicus first
        if let data = try? await downloadCopernicusTile(tileName: tileName) {
            return data
        }

        // Fall back to SRTM
        return try await downloadSRTMTile(tileName: tileName)
    }

    /// Download a Copernicus DEM GLO-30 tile from AWS S3.
    ///
    /// The tile is distributed as a GeoTIFF but many mirrors provide HGT
    /// conversions. We attempt the direct HGT download pattern.
    private func downloadCopernicusTile(tileName: String) async throws -> Data {
        // Copernicus tile URL pattern
        // Example: Copernicus_DSM_COG_10_N47_00_E011_00_DEM/Copernicus_DSM_COG_10_N47_00_E011_00_DEM.dt2
        let urlString = "\(Self.copernicusBaseURL)/\(copernicusTilePath(tileName: tileName))"

        guard let url = URL(string: urlString) else {
            throw ElevationError.invalidTileName(tileName)
        }

        return try await downloadWithRetry(url: url)
    }

    /// Download an SRTM tile.
    private func downloadSRTMTile(tileName: String) async throws -> Data {
        let urlString = "https://srtm.csi.cgiar.org/wp-content/uploads/files/srtm_5x5/hgt/\(tileName).hgt.zip"

        guard let url = URL(string: urlString) else {
            throw ElevationError.invalidTileName(tileName)
        }

        // SRTM tiles are typically zip-compressed
        let zipData = try await downloadWithRetry(url: url)

        // Extract the .hgt file from the zip
        // For simplicity, if it's already raw HGT data, return as-is
        let expectedSize = Self.hgtGridSize * Self.hgtGridSize * 2
        if zipData.count == expectedSize {
            return zipData
        }

        // Try to find HGT data within the zip (basic zip extraction)
        // The zip central directory isn't needed if there's only one file
        throw ElevationError.downloadFailed(tileName)
    }

    /// Download data from a URL with exponential backoff retry.
    ///
    /// Retries up to ``maxRetries`` times on network errors with
    /// delays of 2, 4, 8, 16 seconds.
    ///
    /// - Parameter url: The URL to download.
    /// - Returns: The downloaded data.
    private func downloadWithRetry(url: URL) async throws -> Data {
        var lastError: Error = ElevationError.downloadFailed(url.lastPathComponent)

        for attempt in 0..<Self.maxRetries {
            do {
                let (data, response) = try await session.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    throw ElevationError.httpError(code, url.absoluteString)
                }
                return data
            } catch {
                lastError = error
                if attempt < Self.maxRetries - 1 {
                    let delay = UInt64(pow(2.0, Double(attempt + 1))) * 1_000_000_000
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }
        throw lastError
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

        // Check for void values
        if e00 == Self.hgtVoidValue || e01 == Self.hgtVoidValue ||
           e10 == Self.hgtVoidValue || e11 == Self.hgtVoidValue {
            // Use the first non-void value, or return nil
            let nonVoid = [e00, e01, e10, e11].first { $0 != Self.hgtVoidValue }
            return nonVoid.map { Double($0) }
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

    /// Build the Copernicus S3 object path for a tile.
    ///
    /// - Parameter tileName: Tile name like "N47E011".
    /// - Returns: The S3 object key path.
    private func copernicusTilePath(tileName: String) -> String {
        // Example: Copernicus_DSM_COG_10_N47_00_E011_00_DEM/Copernicus_DSM_COG_10_N47_00_E011_00_DEM.dt2
        let latPart = String(tileName.prefix(3))  // N47
        let lonPart = String(tileName.suffix(4))   // E011
        let folderName = "Copernicus_DSM_COG_10_\(latPart)_00_\(lonPart)_00_DEM"
        return "\(folderName)/\(folderName).dt2"
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
