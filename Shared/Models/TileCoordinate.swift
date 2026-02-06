import Foundation
import CoreLocation

/// Represents a map tile coordinate using the standard Web Mercator (EPSG:3857) tile scheme.
/// Used by OpenStreetMap, Google Maps, and most online tile providers.
struct TileCoordinate: Hashable, Codable, Sendable {
    let x: Int
    let y: Int
    let z: Int  // Zoom level (0-20 typically, 12-16 for hiking)

    /// Total number of tiles at this zoom level (per axis)
    var tilesPerAxis: Int {
        1 << z  // 2^z
    }

    /// Check if this is a valid tile coordinate
    var isValid: Bool {
        let max = tilesPerAxis
        return x >= 0 && x < max && y >= 0 && y < max && z >= 0 && z <= 22
    }

    /// Create tile coordinate from a geographic location and zoom level
    init(latitude: Double, longitude: Double, zoom: Int) {
        self.z = zoom
        let n = Double(1 << zoom)

        // Convert longitude to tile X
        self.x = Int(floor((longitude + 180.0) / 360.0 * n))

        // Convert latitude to tile Y using Web Mercator projection
        let latRad = latitude * .pi / 180.0
        self.y = Int(floor((1.0 - asinh(tan(latRad)) / .pi) / 2.0 * n))
    }

    init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// Get the northwest corner of this tile in geographic coordinates
    var northWest: CLLocationCoordinate2D {
        let n = Double(tilesPerAxis)
        let lon = Double(x) / n * 360.0 - 180.0
        let latRad = atan(sinh(.pi * (1.0 - 2.0 * Double(y) / n)))
        let lat = latRad * 180.0 / .pi
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Get the southeast corner of this tile in geographic coordinates
    var southEast: CLLocationCoordinate2D {
        let n = Double(tilesPerAxis)
        let lon = Double(x + 1) / n * 360.0 - 180.0
        let latRad = atan(sinh(.pi * (1.0 - 2.0 * Double(y + 1) / n)))
        let lat = latRad * 180.0 / .pi
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Get the center of this tile in geographic coordinates
    var center: CLLocationCoordinate2D {
        let nw = northWest
        let se = southEast
        return CLLocationCoordinate2D(
            latitude: (nw.latitude + se.latitude) / 2.0,
            longitude: (nw.longitude + se.longitude) / 2.0
        )
    }

    /// Get the parent tile at the next lower zoom level
    var parent: TileCoordinate? {
        guard z > 0 else { return nil }
        return TileCoordinate(x: x / 2, y: y / 2, z: z - 1)
    }

    /// Get the four child tiles at the next higher zoom level
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

    /// Get neighboring tiles (including diagonals)
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

    /// Standard tile size in pixels
    static let tileSize: Int = 256

    /// Calculate approximate meters per pixel at this tile's latitude
    var metersPerPixel: Double {
        let lat = center.latitude
        let earthCircumference = 40075016.686 // meters at equator
        let latRadians = lat * .pi / 180.0
        return earthCircumference * cos(latRadians) / Double(tilesPerAxis) / Double(Self.tileSize)
    }
}

// MARK: - Tile Range for Region Selection

/// Represents a range of tiles covering a geographic region
struct TileRange: Codable, Sendable {
    let minX: Int
    let maxX: Int
    let minY: Int
    let maxY: Int
    let zoom: Int

    /// Create a tile range from a bounding box at a specific zoom level
    init(boundingBox: BoundingBox, zoom: Int) {
        let nw = TileCoordinate(latitude: boundingBox.north, longitude: boundingBox.west, zoom: zoom)
        let se = TileCoordinate(latitude: boundingBox.south, longitude: boundingBox.east, zoom: zoom)

        self.minX = min(nw.x, se.x)
        self.maxX = max(nw.x, se.x)
        self.minY = min(nw.y, se.y)
        self.maxY = max(nw.y, se.y)
        self.zoom = zoom
    }

    init(minX: Int, maxX: Int, minY: Int, maxY: Int, zoom: Int) {
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
        self.zoom = zoom
    }

    /// Total number of tiles in this range
    var tileCount: Int {
        (maxX - minX + 1) * (maxY - minY + 1)
    }

    /// Iterate over all tiles in this range
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

    /// Check if a tile coordinate is within this range
    func contains(_ tile: TileCoordinate) -> Bool {
        tile.z == zoom &&
        tile.x >= minX && tile.x <= maxX &&
        tile.y >= minY && tile.y <= maxY
    }
}

// MARK: - Bounding Box

/// A geographic bounding box defined by its corners
struct BoundingBox: Codable, Sendable, Equatable {
    let north: Double  // Max latitude
    let south: Double  // Min latitude
    let east: Double   // Max longitude
    let west: Double   // Min longitude

    init(north: Double, south: Double, east: Double, west: Double) {
        self.north = north
        self.south = south
        self.east = east
        self.west = west
    }

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

    /// Check if a coordinate is within this bounding box
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude >= south &&
        coordinate.latitude <= north &&
        coordinate.longitude >= west &&
        coordinate.longitude <= east
    }

    /// Get the center of the bounding box
    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (north + south) / 2.0,
            longitude: (east + west) / 2.0
        )
    }

    /// Approximate area in square kilometers
    var areaKm2: Double {
        let latDelta = north - south
        let lonDelta = east - west
        let avgLat = (north + south) / 2.0

        let kmPerDegreeLat = 111.0
        let kmPerDegreeLon = 111.0 * cos(avgLat * .pi / 180.0)

        return latDelta * kmPerDegreeLat * lonDelta * kmPerDegreeLon
    }

    /// Calculate tile ranges for multiple zoom levels
    func tileRanges(zoomLevels: ClosedRange<Int>) -> [TileRange] {
        zoomLevels.map { TileRange(boundingBox: self, zoom: $0) }
    }

    /// Estimate total tile count across zoom levels
    func estimateTileCount(zoomLevels: ClosedRange<Int>) -> Int {
        tileRanges(zoomLevels: zoomLevels).reduce(0) { $0 + $1.tileCount }
    }
}
