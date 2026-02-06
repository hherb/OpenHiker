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

/// Categories for waypoint pins, each associated with an SF Symbol icon name.
///
/// Used to visually distinguish different types of points of interest on the map.
/// The raw value is persisted as a string in SQLite, so new cases can be added
/// without a schema migration as long as they are handled gracefully on older builds.
enum WaypointCategory: String, Codable, CaseIterable, Sendable {
    /// A trail marker or signpost along the path
    case trailMarker    // "signpost.right"
    /// A scenic viewpoint or overlook
    case viewpoint      // "eye"
    /// A water source such as a spring, stream, or tap
    case waterSource    // "drop.fill"
    /// A campsite or bivouac spot
    case campsite       // "tent"
    /// A danger zone or hazard warning
    case danger         // "exclamationmark.triangle"
    /// A food source such as a restaurant, hut, or supply point
    case food           // "fork.knife"
    /// A shelter, hut, or emergency refuge
    case shelter        // "house"
    /// A parking area or trailhead parking lot
    case parking        // "car"
    /// A custom or uncategorized waypoint
    case custom         // "mappin"

    /// The SF Symbol name used to render this category on the map and in UI pickers.
    var iconName: String {
        switch self {
        case .trailMarker:  return "signpost.right"
        case .viewpoint:    return "eye"
        case .waterSource:  return "drop.fill"
        case .campsite:     return "tent"
        case .danger:       return "exclamationmark.triangle"
        case .food:         return "fork.knife"
        case .shelter:      return "house"
        case .parking:      return "car"
        case .custom:       return "mappin"
        }
    }

    /// A short human-readable label for this category, suitable for display in pickers.
    var displayName: String {
        switch self {
        case .trailMarker:  return "Trail Marker"
        case .viewpoint:    return "Viewpoint"
        case .waterSource:  return "Water"
        case .campsite:     return "Campsite"
        case .danger:       return "Danger"
        case .food:         return "Food"
        case .shelter:      return "Shelter"
        case .parking:      return "Parking"
        case .custom:       return "Custom"
        }
    }

    /// A tint color associated with this category for rendering on the map.
    ///
    /// Returns a hex color string (6 chars, no `#` prefix) that can be parsed
    /// into platform-specific color objects. Using hex strings keeps the model
    /// platform-agnostic and `Sendable`.
    var colorHex: String {
        switch self {
        case .trailMarker:  return "4A90D9"  // blue
        case .viewpoint:    return "8E44AD"  // purple
        case .waterSource:  return "3498DB"  // light blue
        case .campsite:     return "27AE60"  // green
        case .danger:       return "E74C3C"  // red
        case .food:         return "F39C12"  // orange
        case .shelter:      return "7F8C8D"  // gray
        case .parking:      return "2C3E50"  // dark blue
        case .custom:       return "E67E22"  // dark orange
        }
    }
}

/// A geotagged waypoint with optional photo and annotation.
///
/// Waypoints are created by the user on either the watch (quick "mark this spot") or
/// the iPhone (full form with photo). They are persisted in a SQLite database via
/// ``WaypointStore`` and synced bidirectionally between devices via WatchConnectivity.
///
/// Photo data (full-res and thumbnail) is stored separately in the database's BLOB
/// columns rather than in this struct, to keep the model lightweight for sync and
/// in-memory operations.
struct Waypoint: Identifiable, Codable, Sendable, Equatable {
    /// Unique identifier for this waypoint.
    let id: UUID

    /// Latitude in WGS84 degrees.
    let latitude: Double

    /// Longitude in WGS84 degrees.
    let longitude: Double

    /// Altitude in meters above sea level, or `nil` if unavailable.
    let altitude: Double?

    /// The date and time when this waypoint was created.
    let timestamp: Date

    /// A short user-provided label (e.g., "Beautiful waterfall").
    var label: String

    /// The category of this waypoint, determining its icon and color.
    var category: WaypointCategory

    /// An optional longer note or description.
    var note: String

    /// Whether a photo is attached to this waypoint in the database.
    var hasPhoto: Bool

    /// Optional link to a saved hike/route (Phase 3 integration).
    var hikeId: UUID?

    /// Creates a new waypoint with the given properties.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to a new UUID).
    ///   - latitude: Latitude in WGS84 degrees.
    ///   - longitude: Longitude in WGS84 degrees.
    ///   - altitude: Altitude in meters, or `nil`.
    ///   - timestamp: Creation timestamp (defaults to now).
    ///   - label: Short label text (defaults to empty string).
    ///   - category: Waypoint category (defaults to `.custom`).
    ///   - note: Longer note text (defaults to empty string).
    ///   - hasPhoto: Whether a photo is attached (defaults to `false`).
    ///   - hikeId: Optional link to a saved hike UUID.
    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        timestamp: Date = Date(),
        label: String = "",
        category: WaypointCategory = .custom,
        note: String = "",
        hasPhoto: Bool = false,
        hikeId: UUID? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timestamp = timestamp
        self.label = label
        self.category = category
        self.note = note
        self.hasPhoto = hasPhoto
        self.hikeId = hikeId
    }

    /// The waypoint's position as a Core Location coordinate.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Creates a waypoint from a Core Location object with the given category and label.
    ///
    /// Extracts latitude, longitude, and altitude from the ``CLLocation``.
    ///
    /// - Parameters:
    ///   - location: The GPS location to create the waypoint from.
    ///   - category: The category for the new waypoint.
    ///   - label: A short label (defaults to empty string).
    ///   - note: A longer note (defaults to empty string).
    /// - Returns: A new ``Waypoint`` at the given location.
    static func fromLocation(
        _ location: CLLocation,
        category: WaypointCategory = .custom,
        label: String = "",
        note: String = ""
    ) -> Waypoint {
        Waypoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude >= 0 ? location.altitude : nil,
            label: label,
            category: category,
            note: note
        )
    }

    /// Encodes this waypoint as a dictionary suitable for WatchConnectivity `transferUserInfo`.
    ///
    /// The dictionary uses string keys and primitive values (String, Double, Bool, Int)
    /// so it can be serialized by `WCSession` without requiring `Codable` on the
    /// receiving side.
    ///
    /// - Returns: A `[String: Any]` dictionary representation of this waypoint.
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "latitude": latitude,
            "longitude": longitude,
            "timestamp": timestamp.timeIntervalSince1970,
            "label": label,
            "category": category.rawValue,
            "note": note,
            "hasPhoto": hasPhoto
        ]
        if let altitude = altitude {
            dict["altitude"] = altitude
        }
        if let hikeId = hikeId {
            dict["hikeId"] = hikeId.uuidString
        }
        return dict
    }

    /// Creates a waypoint from a dictionary received via WatchConnectivity.
    ///
    /// This is the inverse of ``toDictionary()``. Returns `nil` if required
    /// fields are missing or have invalid types.
    ///
    /// - Parameter dict: The dictionary to decode.
    /// - Returns: A ``Waypoint`` if decoding succeeds, or `nil`.
    static func fromDictionary(_ dict: [String: Any]) -> Waypoint? {
        guard let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString),
              let latitude = dict["latitude"] as? Double,
              let longitude = dict["longitude"] as? Double,
              let timestampInterval = dict["timestamp"] as? Double,
              let categoryString = dict["category"] as? String,
              let category = WaypointCategory(rawValue: categoryString) else {
            return nil
        }

        return Waypoint(
            id: id,
            latitude: latitude,
            longitude: longitude,
            altitude: dict["altitude"] as? Double,
            timestamp: Date(timeIntervalSince1970: timestampInterval),
            label: dict["label"] as? String ?? "",
            category: category,
            note: dict["note"] as? String ?? "",
            hasPhoto: dict["hasPhoto"] as? Bool ?? false,
            hikeId: (dict["hikeId"] as? String).flatMap { UUID(uuidString: $0) }
        )
    }
}
