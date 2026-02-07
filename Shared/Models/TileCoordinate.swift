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

/// Represents a map tile coordinate using the standard Web Mercator (EPSG:3857) tile scheme.
///
/// Each tile is identified by three values: `x` (column), `y` (row), and `z` (zoom level).
/// This is the same coordinate system used by OpenStreetMap, Google Maps, and most online
/// tile providers. Zoom level 0 has a single tile covering the whole world; each subsequent
/// zoom level doubles the number of tiles per axis (so zoom 14 has 2^14 = 16384 tiles per axis).
///
/// The struct provides conversions between geographic coordinates (latitude/longitude) and
/// tile coordinates, as well as helpers for navigating the tile hierarchy (parent, children,
/// neighbors) and computing geographic bounds of a tile.
struct TileCoordinate: Hashable, Codable, Sendable {
    /// Tile column index (0-based, from the left)
    let x: Int
    /// Tile row index (0-based, from the top)
    let y: Int
    /// Zoom level (0-20 typically, 12-16 for hiking)
    let z: Int

    /// Total number of tiles at this zoom level (per axis).
    ///
    /// At zoom level `z`, each axis has `2^z` tiles.
    var tilesPerAxis: Int {
        1 << z  // 2^z
    }

    /// Whether this tile coordinate falls within the valid range for its zoom level.
    ///
    /// A tile is valid when `x` and `y` are in `[0, 2^z)` and `z` is in `[0, 22]`.
    var isValid: Bool {
        let max = tilesPerAxis
        return x >= 0 && x < max && y >= 0 && y < max && z >= 0 && z <= 22
    }

    /// Create a tile coordinate from a geographic location and zoom level.
    ///
    /// Converts latitude/longitude to tile x/y using the Web Mercator projection formula.
    ///
    /// - Parameters:
    ///   - latitude: The latitude in degrees (-85.05 to 85.05 for Web Mercator).
    ///   - longitude: The longitude in degrees (-180 to 180).
    ///   - zoom: The desired zoom level.
    init(latitude: Double, longitude: Double, zoom: Int) {
        self.z = zoom
        let n = Double(1 << zoom)

        // Convert longitude to tile X
        self.x = Int(floor((longitude + 180.0) / 360.0 * n))

        // Convert latitude to tile Y using Web Mercator projection
        let latRad = latitude * .pi / 180.0
        self.y = Int(floor((1.0 - asinh(tan(latRad)) / .pi) / 2.0 * n))
    }

    /// Create a tile coordinate from explicit x, y, z values.
    ///
    /// - Parameters:
    ///   - x: The tile column index (0-based, from the left).
    ///   - y: The tile row index (0-based, from the top).
    ///   - z: The zoom level (0 = whole world, higher = more detail).
    init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// The northwest (top-left) corner of this tile in geographic coordinates.
    ///
    /// Uses the inverse Web Mercator projection to convert the tile's top-left pixel
    /// back to latitude/longitude.
    var northWest: CLLocationCoordinate2D {
        let n = Double(tilesPerAxis)
        let lon = Double(x) / n * 360.0 - 180.0
        let latRad = atan(sinh(.pi * (1.0 - 2.0 * Double(y) / n)))
        let lat = latRad * 180.0 / .pi
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// The southeast (bottom-right) corner of this tile in geographic coordinates.
    ///
    /// Uses the inverse Web Mercator projection to convert the tile's bottom-right pixel
    /// back to latitude/longitude.
    var southEast: CLLocationCoordinate2D {
        let n = Double(tilesPerAxis)
        let lon = Double(x + 1) / n * 360.0 - 180.0
        let latRad = atan(sinh(.pi * (1.0 - 2.0 * Double(y + 1) / n)))
        let lat = latRad * 180.0 / .pi
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// The geographic center of this tile, computed as the midpoint of northwest and southeast corners.
    var center: CLLocationCoordinate2D {
        let nw = northWest
        let se = southEast
        return CLLocationCoordinate2D(
            latitude: (nw.latitude + se.latitude) / 2.0,
            longitude: (nw.longitude + se.longitude) / 2.0
        )
    }

    /// The parent tile at the next lower zoom level, or `nil` if already at zoom 0.
    ///
    /// Each tile has exactly one parent that covers the same area at one zoom level less.
    var parent: TileCoordinate? {
        guard z > 0 else { return nil }
        return TileCoordinate(x: x / 2, y: y / 2, z: z - 1)
    }

    /// The four child tiles at the next higher zoom level.
    ///
    /// Each tile subdivides into a 2x2 grid of children with one zoom level more detail.
    var children: [TileCoordinate] {
        let childZ = z + 1
        let childX = x * 2
        let childY = y * 2
        return [
            TileCoordinate(x: childX, y: childY, z: childZ),
            TileCoordinate(x: childX + 1, y: childY, z: childZ),
            TileCoordinate(x: childX, y: childY + 1, z: childZ),
            TileCoordinate(x: childX + 1, y: childY + 1, z: childZ)
        ]
    }

    /// All valid neighboring tiles at the same zoom level, including diagonals (up to 8).
    ///
    /// Tiles at the edge of the world may have fewer than 8 neighbors since invalid
    /// coordinates are excluded.
    var neighbors: [TileCoordinate] {
        var result: [TileCoordinate] = []
        for dx in -1...1 {
            for dy in -1...1 {
                if dx == 0 && dy == 0 { continue }
                let neighbor = TileCoordinate(x: x + dx, y: y + dy, z: z)
                if neighbor.isValid {
                    result.append(neighbor)
                }
            }
        }
        return result
    }

    /// Standard tile size in pixels (256x256 is the universal web map tile size).
    static let tileSize: Int = 256

    /// Approximate meters per pixel at this tile's latitude.
    ///
    /// This varies by latitude because the Mercator projection stretches tiles
    /// near the poles. Uses the Earth's equatorial circumference and adjusts
    /// for the cosine of the latitude.
    var metersPerPixel: Double {
        let lat = center.latitude
        let earthCircumference = 40075016.686 // meters at equator
        let latRadians = lat * .pi / 180.0
        return earthCircumference * cos(latRadians) / Double(tilesPerAxis) / Double(Self.tileSize)
    }
}

// MARK: - Tile Range for Region Selection

/// Represents a rectangular range of tiles covering a geographic region at a single zoom level.
///
/// Used during region download to enumerate all tiles that need to be fetched. The range
/// is defined by min/max x and y tile indices at a given zoom level.
struct TileRange: Codable, Sendable {
    /// Minimum tile column index (leftmost tile)
    let minX: Int
    /// Maximum tile column index (rightmost tile)
    let maxX: Int
    /// Minimum tile row index (topmost tile)
    let minY: Int
    /// Maximum tile row index (bottommost tile)
    let maxY: Int
    /// Zoom level for this tile range
    let zoom: Int

    /// Create a tile range from a bounding box at a specific zoom level.
    ///
    /// Converts the geographic corners of the bounding box to tile coordinates and
    /// establishes the min/max bounds.
    ///
    /// - Parameters:
    ///   - boundingBox: The geographic area to cover.
    ///   - zoom: The zoom level for the tile range.
    init(boundingBox: BoundingBox, zoom: Int) {
        let nw = TileCoordinate(latitude: boundingBox.north, longitude: boundingBox.west, zoom: zoom)
        let se = TileCoordinate(latitude: boundingBox.south, longitude: boundingBox.east, zoom: zoom)

        self.minX = min(nw.x, se.x)
        self.maxX = max(nw.x, se.x)
        self.minY = min(nw.y, se.y)
        self.maxY = max(nw.y, se.y)
        self.zoom = zoom
    }

    /// Create a tile range from explicit bounds.
    ///
    /// - Parameters:
    ///   - minX: Minimum tile column index.
    ///   - maxX: Maximum tile column index.
    ///   - minY: Minimum tile row index.
    ///   - maxY: Maximum tile row index.
    ///   - zoom: The zoom level.
    init(minX: Int, maxX: Int, minY: Int, maxY: Int, zoom: Int) {
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
        self.zoom = zoom
    }

    /// Total number of tiles in this range (width * height).
    var tileCount: Int {
        (maxX - minX + 1) * (maxY - minY + 1)
    }

    /// Generate an array of all tile coordinates within this range.
    ///
    /// Iterates column by column, row by row, producing one `TileCoordinate` per tile.
    /// The returned array is pre-allocated with `tileCount` capacity for efficiency.
    ///
    /// - Returns: An array of all `TileCoordinate` values in the range.
    func allTiles() -> [TileCoordinate] {
        var tiles: [TileCoordinate] = []
        tiles.reserveCapacity(tileCount)
        for x in minX...maxX {
            for y in minY...maxY {
                tiles.append(TileCoordinate(x: x, y: y, z: zoom))
            }
        }
        return tiles
    }

    /// Check if a tile coordinate is within this range.
    ///
    /// The tile must match the range's zoom level and fall within the x/y bounds.
    ///
    /// - Parameter tile: The tile coordinate to test.
    /// - Returns: `true` if the tile is within this range.
    func contains(_ tile: TileCoordinate) -> Bool {
        tile.z == zoom &&
        tile.x >= minX && tile.x <= maxX &&
        tile.y >= minY && tile.y <= maxY
    }
}

// MARK: - Bounding Box

/// A geographic bounding box defined by its north, south, east, and west edges.
///
/// Used throughout the app to define the geographic extent of a map region. Supports
/// creating from explicit edges or from a center point and radius, and provides helpers
/// for area estimation, tile range calculation, and containment tests.
struct BoundingBox: Codable, Sendable, Equatable, Hashable {
    /// Maximum latitude (northern edge) in degrees
    let north: Double
    /// Minimum latitude (southern edge) in degrees
    let south: Double
    /// Maximum longitude (eastern edge) in degrees
    let east: Double
    /// Minimum longitude (western edge) in degrees
    let west: Double

    /// Create a bounding box from explicit edge coordinates.
    ///
    /// - Parameters:
    ///   - north: Maximum latitude (northern edge).
    ///   - south: Minimum latitude (southern edge).
    ///   - east: Maximum longitude (eastern edge).
    ///   - west: Minimum longitude (western edge).
    init(north: Double, south: Double, east: Double, west: Double) {
        self.north = north
        self.south = south
        self.east = east
        self.west = west
    }

    /// Create a bounding box centered on a geographic point with a given radius in meters.
    ///
    /// Uses an approximate degrees-per-meter conversion that accounts for latitude.
    /// Clamps latitude to the Web Mercator range of -85 to 85 degrees.
    ///
    /// - Parameters:
    ///   - center: The center coordinate.
    ///   - radiusMeters: The radius from center to each edge in meters.
    init(center: CLLocationCoordinate2D, radiusMeters: Double) {
        // Approximate degrees per meter at this latitude
        let metersPerDegreeLat = 111320.0
        let metersPerDegreeLon = 111320.0 * cos(center.latitude * .pi / 180.0)

        let latDelta = radiusMeters / metersPerDegreeLat
        let lonDelta = radiusMeters / metersPerDegreeLon

        self.north = min(center.latitude + latDelta, 85.0)
        self.south = max(center.latitude - latDelta, -85.0)
        self.east = center.longitude + lonDelta
        self.west = center.longitude - lonDelta
    }

    /// Check if a coordinate falls within this bounding box.
    ///
    /// - Parameter coordinate: The geographic coordinate to test.
    /// - Returns: `true` if the coordinate is inside the box (inclusive of edges).
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude >= south &&
        coordinate.latitude <= north &&
        coordinate.longitude >= west &&
        coordinate.longitude <= east
    }

    /// The geographic center of the bounding box.
    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (north + south) / 2.0,
            longitude: (east + west) / 2.0
        )
    }

    /// Approximate area of the bounding box in square kilometers.
    ///
    /// Uses the average latitude to adjust for the Mercator projection's distortion
    /// of east-west distances at different latitudes.
    var areaKm2: Double {
        let latDelta = north - south
        let lonDelta = east - west
        let avgLat = (north + south) / 2.0

        let kmPerDegreeLat = 111.0
        let kmPerDegreeLon = 111.0 * cos(avgLat * .pi / 180.0)

        return latDelta * kmPerDegreeLat * lonDelta * kmPerDegreeLon
    }

    /// Calculate tile ranges for each zoom level in the given range.
    ///
    /// - Parameter zoomLevels: A closed range of zoom levels (e.g., `12...16`).
    /// - Returns: An array of `TileRange` values, one per zoom level.
    func tileRanges(zoomLevels: ClosedRange<Int>) -> [TileRange] {
        zoomLevels.map { TileRange(boundingBox: self, zoom: $0) }
    }

    /// Estimate the total tile count across multiple zoom levels.
    ///
    /// Useful for showing the user how large a download will be before starting.
    ///
    /// - Parameter zoomLevels: A closed range of zoom levels (e.g., `12...16`).
    /// - Returns: The sum of tile counts across all zoom levels.
    func estimateTileCount(zoomLevels: ClosedRange<Int>) -> Int {
        tileRanges(zoomLevels: zoomLevels).reduce(0) { $0 + $1.tileCount }
    }
}
