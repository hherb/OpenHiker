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

// MARK: - Routing Mode

/// The type of activity used to compute edge traversal costs.
///
/// Different modes apply different surface penalties, elevation costs,
/// and passability rules. For example, cyclists cannot use `steps` or
/// ways tagged `bicycle=no`, and they face harsher penalties on soft surfaces.
enum RoutingMode: String, Codable, Sendable, CaseIterable {
    /// Walking / trail running mode — uses Naismith's rule for elevation costs.
    case hiking
    /// Bicycle mode — steeper elevation penalties, steps impassable.
    case cycling
}

// MARK: - Routing Node

/// A junction or endpoint in the routing graph.
///
/// Routing nodes correspond to OSM nodes that appear in two or more ways
/// (intersections) or that mark the start/end of a way. Only these
/// "structurally significant" nodes are promoted to routing nodes; intermediate
/// points along a trail are stored as compressed geometry on the edge.
struct RoutingNode: Identifiable, Codable, Sendable, Equatable {
    /// OSM node ID (unique within one routing database).
    let id: Int64
    /// Latitude in degrees (WGS 84).
    let latitude: Double
    /// Longitude in degrees (WGS 84).
    let longitude: Double
    /// Elevation above sea level in metres, from Copernicus/SRTM. `nil` if unknown.
    let elevation: Double?

    /// Convenience accessor returning a CoreLocation coordinate.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Routing Edge

/// A trail segment connecting two routing nodes.
///
/// Each edge stores its pre-computed forward and reverse traversal costs,
/// physical properties (surface, highway type, difficulty), and the packed
/// geometry of intermediate points between the two junction nodes.
struct RoutingEdge: Identifiable, Codable, Sendable {
    /// Auto-incremented edge ID within the routing database.
    let id: Int64
    /// OSM node ID of the edge's start node.
    let fromNode: Int64
    /// OSM node ID of the edge's end node.
    let toNode: Int64
    /// Horizontal distance in metres (haversine).
    let distance: Double
    /// Cumulative elevation gain from `fromNode` to `toNode` in metres.
    let elevationGain: Double
    /// Cumulative elevation loss from `fromNode` to `toNode` in metres.
    let elevationLoss: Double
    /// Surface type tag from OSM (e.g. "gravel", "asphalt"). `nil` if unknown.
    let surface: String?
    /// OSM `highway=*` value (e.g. "path", "footway", "track").
    let highwayType: String?
    /// SAC hiking scale tag (e.g. "hiking", "demanding_mountain_hiking"). `nil` if absent.
    let sacScale: String?
    /// Trail visibility tag. `nil` if absent.
    let trailVisibility: String?
    /// Trail name from OSM. `nil` if unnamed.
    let name: String?
    /// Source OSM way ID for attribution.
    let osmWayId: Int64?
    /// Pre-computed forward traversal cost (fromNode → toNode).
    let cost: Double
    /// Pre-computed reverse traversal cost (toNode → fromNode).
    let reverseCost: Double
    /// Whether this edge is one-way (rare for trails, common for steps going up).
    let isOneway: Bool
    /// Packed float32 intermediate coordinates: `[lat0, lon0, lat1, lon1, ...]`.
    /// Empty if the edge is a straight line between the two nodes.
    let geometry: Data?
}

// MARK: - Computed Route

/// The result of a route calculation — an ordered path through the routing graph
/// with aggregated statistics and the full coordinate sequence for rendering.
struct ComputedRoute: Codable, Sendable {
    /// Ordered junction nodes along the route (start → end).
    let nodes: [RoutingNode]
    /// Edges traversed, in order (one fewer than `nodes`).
    let edges: [RoutingEdge]
    /// Total horizontal distance in metres.
    let totalDistance: Double
    /// Sum of edge costs (abstract units, not directly time).
    let totalCost: Double
    /// Estimated walking/cycling time in seconds derived from the cost function.
    let estimatedDuration: TimeInterval
    /// Total elevation gain in metres.
    let elevationGain: Double
    /// Total elevation loss in metres.
    let elevationLoss: Double
    /// Full ordered coordinate sequence including intermediate geometry points,
    /// suitable for rendering a polyline on the map.
    let coordinates: [CLLocationCoordinate2D]

    /// The via-points that were requested when computing this route (excluding start/end).
    /// Stored so that the route can be recomputed if the user edits a via-point.
    let viaPoints: [CLLocationCoordinate2D]
}

// MARK: - Codable CLLocationCoordinate2D wrapper

/// Lightweight wrapper making `CLLocationCoordinate2D` `Codable` for persistence.
///
/// Used inside `ComputedRoute` so that route coordinates can be serialised to JSON
/// for transfer to the watch or for saving to disk.
struct CodableCoordinate: Codable, Sendable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// Make CLLocationCoordinate2D Codable via CodableCoordinate
extension CLLocationCoordinate2D: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let wrapper = try CodableCoordinate(from: decoder)
        self.init(latitude: wrapper.latitude, longitude: wrapper.longitude)
    }

    public func encode(to encoder: Encoder) throws {
        try CodableCoordinate(self).encode(to: encoder)
    }
}

// MARK: - Routing Cost Configuration

/// Central configuration for all cost-function multipliers and constants.
///
/// Every magic number used in cost computation lives here so that it can be
/// tuned without hunting through code. Values are based on Naismith's rule
/// and Tobler's hiking function, with surface and SAC-scale penalties from
/// empirical hiking data.
enum RoutingCostConfig {

    // MARK: Naismith's Rule (Hiking)

    /// Metres of climb treated as equivalent to 1 metre of flat walking.
    /// Naismith: 1 hour per 600 m gain ≈ 7.92× flat distance cost.
    static let hikingClimbPenaltyPerMetre: Double = 7.92

    /// Base flat walking speed used to convert cost to estimated duration (m/s).
    static let hikingBaseSpeedMetresPerSecond: Double = 1.33  // ~4.8 km/h

    /// Base flat cycling speed used to convert cost to estimated duration (m/s).
    static let cyclingBaseSpeedMetresPerSecond: Double = 4.17  // ~15 km/h

    /// Cycling climb penalty per metre of gain (harder than walking).
    static let cyclingClimbPenaltyPerMetre: Double = 12.0

    // MARK: Surface Multipliers

    /// Surface-type cost multipliers for hiking mode.
    /// Keys are OSM `surface=*` tag values.
    static let hikingSurfaceMultipliers: [String: Double] = [
        "paved": 1.0,
        "asphalt": 1.0,
        "concrete": 1.0,
        "compacted": 1.1,
        "fine_gravel": 1.1,
        "gravel": 1.2,
        "ground": 1.3,
        "dirt": 1.3,
        "earth": 1.3,
        "grass": 1.4,
        "sand": 1.8,
        "rock": 1.5,
        "pebblestone": 1.5,
        "mud": 2.0,
        "wood": 1.1
    ]

    /// Default surface multiplier when the surface tag is missing.
    static let defaultHikingSurfaceMultiplier: Double = 1.3

    /// Surface-type cost multipliers for cycling mode.
    static let cyclingSurfaceMultipliers: [String: Double] = [
        "paved": 1.0,
        "asphalt": 1.0,
        "concrete": 1.0,
        "compacted": 1.2,
        "fine_gravel": 1.3,
        "gravel": 1.5,
        "ground": 2.0,
        "dirt": 2.0,
        "earth": 2.0,
        "grass": 3.0,
        "sand": 3.0,
        "rock": 2.5,
        "pebblestone": 2.0,
        "mud": 4.0,
        "wood": 1.2
    ]

    /// Default surface multiplier for cycling when the surface tag is missing.
    static let defaultCyclingSurfaceMultiplier: Double = 1.5

    // MARK: SAC Scale Multipliers

    /// SAC hiking scale cost multipliers.
    /// Keys match OSM `sac_scale=*` tag values.
    static let sacScaleMultipliers: [String: Double] = [
        "hiking": 1.0,
        "mountain_hiking": 1.2,
        "demanding_mountain_hiking": 1.5,
        "alpine_hiking": 2.0,
        "demanding_alpine_hiking": 3.0,
        "difficult_alpine_hiking": 5.0
    ]

    /// Default SAC scale multiplier when the tag is absent.
    static let defaultSacMultiplier: Double = 1.0

    // MARK: Descent Cost (Tobler's Hiking Function)

    /// Returns a descent cost multiplier based on the average grade percentage.
    ///
    /// Gentle downhills are faster than flat walking; steep descents become
    /// slower than the equivalent ascent because the hiker must brake.
    ///
    /// - Parameter gradePercent: Absolute value of the downhill grade as a
    ///   percentage (e.g. 15 for a 15 % slope). Must be ≥ 0.
    /// - Returns: A multiplier applied to the equivalent ascent cost.
    static func descentMultiplier(gradePercent: Double) -> Double {
        switch gradePercent {
        case ..<10:
            return 0.5   // gentle — faster than flat
        case 10..<20:
            return 0.8   // moderate — starting to brake
        case 20..<30:
            return 1.0   // steep — as slow as flat
        default:
            return 1.5   // very steep — dangerous, very slow
        }
    }

    // MARK: Impassable Edge Sentinel

    /// Cost value representing an impassable edge (e.g. steps for cyclists).
    /// Using `Double.infinity` ensures A* will never choose this edge.
    static let impassableCost: Double = Double.infinity

    // MARK: Nearest-Node Search

    /// Maximum radius in metres when snapping a user tap to the nearest routing node.
    static let nearestNodeSearchRadiusMetres: Double = 500.0

    // MARK: Highway Types

    /// OSM `highway=*` values considered routable for hiking or cycling.
    static let routableHighwayValues: Set<String> = [
        "path", "footway", "track", "cycleway", "bridleway", "steps",
        "pedestrian", "residential", "unclassified", "tertiary",
        "secondary", "primary", "trunk", "living_street", "service"
    ]
}

// MARK: - Routing Error

/// Errors that can occur during route computation or graph access.
enum RoutingError: Error, LocalizedError {
    /// No routing database is loaded for the current region.
    case noRoutingData
    /// The start or end coordinate could not be snapped to a nearby routing node.
    case noNearbyNode(CLLocationCoordinate2D)
    /// A* exhausted all reachable nodes without finding a path to the destination.
    case noRouteFound
    /// A via-point could not be snapped to the graph.
    case viaPointNotReachable(index: Int, coordinate: CLLocationCoordinate2D)
    /// The routing database is corrupt or has an unexpected schema.
    case databaseCorrupted(String)
    /// A SQLite operation failed.
    case databaseError(String)

    var errorDescription: String? {
        switch self {
        case .noRoutingData:
            return "No routing data available for this region."
        case .noNearbyNode(let coord):
            return String(format: "No trail found near (%.4f, %.4f). Try a point closer to a trail.",
                          coord.latitude, coord.longitude)
        case .noRouteFound:
            return "No route could be found between the selected points. They may be on disconnected trail networks."
        case .viaPointNotReachable(let index, let coord):
            return String(format: "Via-point %d at (%.4f, %.4f) is not near any trail.",
                          index + 1, coord.latitude, coord.longitude)
        case .databaseCorrupted(let detail):
            return "Routing database is corrupted: \(detail)"
        case .databaseError(let message):
            return "Database error: \(message)"
        }
    }
}

// MARK: - Edge Geometry Helpers

/// Pure-function helpers for packing and unpacking intermediate edge geometry.
///
/// Geometry is stored as a flat array of packed `Float32` pairs:
/// `[lat0, lon0, lat1, lon1, ...]`.  Using Float32 instead of Float64
/// halves storage with sub-metre precision at hiking scales.
enum EdgeGeometry {

    /// Pack an array of coordinates into a compact `Data` blob.
    ///
    /// - Parameter coordinates: The intermediate coordinates to pack
    ///   (excluding the edge's start and end nodes).
    /// - Returns: A `Data` blob of packed float32 pairs, or `nil` if the
    ///   array is empty.
    static func pack(_ coordinates: [CLLocationCoordinate2D]) -> Data? {
        guard !coordinates.isEmpty else { return nil }
        var data = Data(capacity: coordinates.count * 8) // 2 × Float32 per point
        for coord in coordinates {
            var lat = Float32(coord.latitude)
            var lon = Float32(coord.longitude)
            withUnsafeBytes(of: &lat) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &lon) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// Unpack a geometry blob into an array of coordinates.
    ///
    /// - Parameter data: The packed float32 blob (may be `nil` for edges
    ///   with no intermediate geometry).
    /// - Returns: An array of coordinates, empty if `data` is `nil` or empty.
    static func unpack(_ data: Data?) -> [CLLocationCoordinate2D] {
        guard let data = data, !data.isEmpty else { return [] }
        let floatCount = data.count / MemoryLayout<Float32>.size
        guard floatCount >= 2, floatCount.isMultiple(of: 2) else { return [] }

        var coordinates: [CLLocationCoordinate2D] = []
        coordinates.reserveCapacity(floatCount / 2)

        data.withUnsafeBytes { buffer in
            let floats = buffer.bindMemory(to: Float32.self)
            for i in stride(from: 0, to: floats.count, by: 2) {
                let lat = Double(floats[i])
                let lon = Double(floats[i + 1])
                coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
        return coordinates
    }
}

// MARK: - Haversine Distance

/// Computes the great-circle distance between two geographic coordinates.
///
/// Uses the haversine formula for good accuracy at hiking distances (metres to
/// tens of kilometres). Returns the result in metres.
///
/// - Parameters:
///   - lat1: Latitude of the first point in degrees.
///   - lon1: Longitude of the first point in degrees.
///   - lat2: Latitude of the second point in degrees.
///   - lon2: Longitude of the second point in degrees.
/// - Returns: Distance in metres.
func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let earthRadiusMetres: Double = 6_371_000.0
    let dLat = (lat2 - lat1) * .pi / 180.0
    let dLon = (lon2 - lon1) * .pi / 180.0
    let lat1Rad = lat1 * .pi / 180.0
    let lat2Rad = lat2 * .pi / 180.0

    let a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1Rad) * cos(lat2Rad) *
            sin(dLon / 2) * sin(dLon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return earthRadiusMetres * c
}
