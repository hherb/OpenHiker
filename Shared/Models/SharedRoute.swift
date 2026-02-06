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

/// Schema version for the shared route JSON format.
///
/// Increment this when making breaking changes to the ``SharedRoute`` structure.
/// The GitHub Actions validation workflow uses this to select the correct schema.
let sharedRouteSchemaVersion = 1

/// A route shared to the OpenHikerRoutes community repository on GitHub.
///
/// This is the canonical data model for route exchange. It is serialized as `route.json`
/// in the repository and contains everything needed to display, search, and import a route:
/// - Metadata (name, author, activity type, description)
/// - Statistics (distance, elevation, duration)
/// - Geographic bounds for spatial search
/// - Full track as coordinate arrays
/// - Waypoints with categories and notes
/// - Photo references (filenames + GPS coordinates + captions)
///
/// ## JSON Format
/// The JSON encoder uses `.iso8601` date encoding and `.sortedKeys` for deterministic output.
/// Track coordinates use 5 decimal places (~1.1m precision, sufficient for hiking/cycling).
///
/// ## Relationship to SavedRoute
/// ``RouteExporter`` converts a local ``SavedRoute`` (with compressed binary track data)
/// into a ``SharedRoute`` (with explicit coordinate arrays) for upload. The reverse
/// conversion is used when downloading community routes for offline use.
struct SharedRoute: Codable, Sendable, Equatable, Identifiable {

    /// Unique identifier for this shared route.
    let id: UUID

    /// Schema version number (currently 1). Used by the validation workflow.
    let version: Int

    /// Human-readable name for the route (e.g., "Mount Tamalpais Loop").
    let name: String

    /// The type of outdoor activity (hiking, cycling, running, etc.).
    let activityType: ActivityType

    /// Freeform display name of the person who shared this route.
    let author: String

    /// Optional longer description of the route, conditions, or tips.
    let description: String

    /// ISO 8601 timestamp of when the route was originally recorded.
    let createdAt: Date

    /// Geographic region information for directory organization and search.
    let region: RouteRegion

    /// Summary statistics for the route.
    let stats: RouteStats

    /// Bounding box enclosing the entire track, used for spatial search in `index.json`.
    let boundingBox: SharedBoundingBox

    /// The full GPS track as an ordered array of coordinate points.
    let track: [TrackPoint]

    /// Points of interest along or near the route.
    let waypoints: [SharedWaypoint]

    /// Photos attached to this route, stored as compressed JPEGs in the `photos/` directory.
    let photos: [RoutePhoto]
}

// MARK: - Nested Types

/// Geographic region metadata for organizing routes by location.
///
/// The `country` field uses ISO 3166-1 alpha-2 codes (e.g., "US", "DE", "AU").
/// The `area` field is a freeform string for the sub-region (e.g., "California", "Bavaria").
struct RouteRegion: Codable, Sendable, Equatable {
    /// ISO 3166-1 alpha-2 country code (e.g., "US", "DE").
    let country: String
    /// Freeform area or state name within the country.
    let area: String
}

/// Summary statistics for a shared route.
///
/// All values use SI units (meters, seconds) for consistency. The UI layer
/// handles locale-aware formatting via ``HikeStatsFormatter``.
struct RouteStats: Codable, Sendable, Equatable {
    /// Total distance along the track in meters.
    let distanceMeters: Double
    /// Total cumulative elevation gained in meters.
    let elevationGainMeters: Double
    /// Total cumulative elevation lost in meters.
    let elevationLossMeters: Double
    /// Total elapsed time from start to finish in seconds.
    let durationSeconds: Double
}

/// Axis-aligned bounding box in WGS84 coordinates.
///
/// Used in `index.json` for client-side spatial filtering ("find routes near me").
/// Kept separate from the app's internal ``BoundingBox`` type to decouple the
/// shared JSON schema from the internal model.
struct SharedBoundingBox: Codable, Sendable, Equatable {
    /// Northern boundary latitude in degrees.
    let north: Double
    /// Southern boundary latitude in degrees.
    let south: Double
    /// Eastern boundary longitude in degrees.
    let east: Double
    /// Western boundary longitude in degrees.
    let west: Double

    /// The center latitude of this bounding box.
    var centerLatitude: Double { (north + south) / 2.0 }

    /// The center longitude of this bounding box.
    var centerLongitude: Double { (east + west) / 2.0 }

    /// Whether a coordinate falls within this bounding box.
    ///
    /// - Parameters:
    ///   - latitude: The latitude to test.
    ///   - longitude: The longitude to test.
    /// - Returns: `true` if the point is inside the box.
    func contains(latitude: Double, longitude: Double) -> Bool {
        latitude >= south && latitude <= north && longitude >= west && longitude <= east
    }
}

/// A single GPS track point with coordinates, elevation, and timestamp.
///
/// Uses 5 decimal places for lat/lon (~1.1m precision) when serialized to JSON.
struct TrackPoint: Codable, Sendable, Equatable {
    /// Latitude in WGS84 degrees.
    let lat: Double
    /// Longitude in WGS84 degrees.
    let lon: Double
    /// Altitude in meters above sea level.
    let ele: Double
    /// ISO 8601 timestamp of when this point was recorded.
    let time: Date
}

/// A waypoint shared as part of a route or independently.
///
/// Maps closely to the app's internal ``Waypoint`` model but uses simple string
/// types for the category to allow forward-compatible extensibility in the JSON schema.
struct SharedWaypoint: Codable, Sendable, Equatable, Identifiable {
    /// Unique identifier for this waypoint.
    let id: UUID
    /// Latitude in WGS84 degrees.
    let lat: Double
    /// Longitude in WGS84 degrees.
    let lon: Double
    /// Altitude in meters, or `nil` if unavailable.
    let ele: Double?
    /// Short label for the waypoint (e.g., "Spring", "Summit").
    let label: String
    /// Category string matching ``WaypointCategory`` raw values.
    let category: String
    /// Optional longer note or description.
    let note: String
}

/// Reference to a photo file stored in the route's `photos/` directory.
///
/// Photos are downsampled to 640x400 JPEG before upload to keep repository size manageable.
/// The GPS coordinates allow the app to display photos on the map at their capture location.
struct RoutePhoto: Codable, Sendable, Equatable {
    /// Filename of the photo in the `photos/` directory (e.g., "summit_view.jpg").
    let filename: String
    /// Latitude where the photo was taken, or `nil` if unknown.
    let lat: Double?
    /// Longitude where the photo was taken, or `nil` if unknown.
    let lon: Double?
    /// User-provided caption for the photo.
    let caption: String
    /// UUID of the waypoint this photo is associated with, or `nil`.
    let waypointId: UUID?
}

// MARK: - Route Index

/// A lightweight summary of a shared route for the `index.json` master index.
///
/// The index is fetched by the app on launch to populate the community browse view.
/// It contains just enough data for list display and spatial/activity-type filtering,
/// without the full track or photo data.
struct RouteIndexEntry: Codable, Sendable, Equatable, Identifiable {
    /// Unique identifier matching the full ``SharedRoute/id``.
    let id: UUID
    /// Route name for display in list rows.
    let name: String
    /// Activity type for filtering.
    let activityType: ActivityType
    /// Author display name.
    let author: String
    /// Short description (first 200 characters of the full description).
    let summary: String
    /// Route creation date for sorting.
    let createdAt: Date
    /// Geographic region for display and organization.
    let region: RouteRegion
    /// Summary statistics for the route.
    let stats: RouteStats
    /// Bounding box for spatial search.
    let boundingBox: SharedBoundingBox
    /// Relative path within the repository (e.g., "routes/US/mount-tamalpais-loop").
    let path: String
    /// Number of photos included with this route.
    let photoCount: Int
    /// Number of waypoints included with this route.
    let waypointCount: Int
}

/// The top-level structure of the `index.json` file in the community repository.
///
/// Contains metadata about the index itself and the array of route entries.
/// The app fetches this single file to populate the entire community browse view.
struct RouteIndex: Codable, Sendable, Equatable {
    /// ISO 8601 timestamp of when the index was last regenerated.
    let updatedAt: Date
    /// Total number of routes in the repository.
    let routeCount: Int
    /// All route entries, sorted by creation date (newest first).
    let routes: [RouteIndexEntry]
}
