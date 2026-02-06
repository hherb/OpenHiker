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

/// Converts between local route formats and the shared community route format.
///
/// Provides three export paths:
/// 1. ``SavedRoute`` -> ``SharedRoute`` JSON (canonical format for the repository)
/// 2. ``SharedRoute`` -> GPX 1.1 XML (for interoperability with other hiking apps)
/// 3. ``SharedRoute`` -> Markdown README (for human-readable display on GitHub)
///
/// Also provides the reverse conversion: ``SharedRoute`` -> ``SavedRoute`` for
/// importing community routes into the local database for offline use.
///
/// ## Thread Safety
/// All methods are pure static functions with no shared state.
enum RouteExporter {

    /// Number of decimal places for coordinate values in JSON and GPX output.
    ///
    /// 5 decimal places gives ~1.1m precision, sufficient for hiking navigation.
    private static let coordinateDecimalPlaces = 5

    /// Multiplier for rounding elevation to 0.1m precision.
    private static let elevationRoundingMultiplier = 10.0

    /// Meters per kilometer, used for formatting distance in Markdown output.
    private static let metersPerKilometer = 1000.0

    /// Seconds per hour, used for formatting duration in Markdown output.
    private static let secondsPerHour = 3600

    /// Seconds per minute, used for formatting duration in Markdown output.
    private static let secondsPerMinute = 60

    /// Fallback slug used when the route name contains no alphanumeric characters.
    private static let fallbackSlug = "untitled"

    // MARK: - SavedRoute -> SharedRoute

    /// Converts a local saved route to the shared community format.
    ///
    /// Decompresses the binary track data and converts it to explicit coordinate arrays.
    /// Waypoints and photos must be provided separately since they are stored outside
    /// the ``SavedRoute`` model.
    ///
    /// - Parameters:
    ///   - route: The local ``SavedRoute`` to convert.
    ///   - activityType: The outdoor activity type for this route.
    ///   - author: The display name of the person sharing this route.
    ///   - description: An optional description of the route.
    ///   - country: ISO 3166-1 alpha-2 country code (e.g., "US", "DE").
    ///   - area: Freeform area name (e.g., "California", "Bavaria").
    ///   - waypoints: Waypoints associated with this route.
    ///   - photos: Photo references for this route.
    /// - Returns: A ``SharedRoute`` ready for JSON serialization and upload.
    static func toSharedRoute(
        _ route: SavedRoute,
        activityType: ActivityType,
        author: String,
        description: String,
        country: String,
        area: String,
        waypoints: [Waypoint],
        photos: [RoutePhoto]
    ) -> SharedRoute {
        let locations = TrackCompression.decode(route.trackData)
        let trackPoints = locations.map { location in
            TrackPoint(
                lat: roundCoordinate(location.coordinate.latitude),
                lon: roundCoordinate(location.coordinate.longitude),
                ele: round(location.altitude * elevationRoundingMultiplier) / elevationRoundingMultiplier,
                time: location.timestamp
            )
        }

        let bbox = computeBoundingBox(from: locations)
        let sharedWaypoints = waypoints.map { wp in
            SharedWaypoint(
                id: wp.id,
                lat: roundCoordinate(wp.latitude),
                lon: roundCoordinate(wp.longitude),
                ele: wp.altitude,
                label: wp.label,
                category: wp.category.rawValue,
                note: wp.note
            )
        }

        return SharedRoute(
            id: route.id,
            version: sharedRouteSchemaVersion,
            name: route.name,
            activityType: activityType,
            author: author,
            description: description,
            createdAt: route.startTime,
            region: RouteRegion(country: country, area: area),
            stats: RouteStats(
                distanceMeters: round(route.totalDistance),
                elevationGainMeters: round(route.elevationGain),
                elevationLossMeters: round(route.elevationLoss),
                durationSeconds: round(route.duration)
            ),
            boundingBox: bbox,
            track: trackPoints,
            waypoints: sharedWaypoints,
            photos: photos
        )
    }

    // MARK: - SharedRoute -> JSON

    /// Encodes a shared route as JSON data using sorted keys and ISO 8601 dates.
    ///
    /// The output is deterministic (sorted keys, consistent formatting) so that
    /// repeated exports of the same route produce identical JSON, which keeps
    /// git diffs clean.
    ///
    /// - Parameter route: The ``SharedRoute`` to encode.
    /// - Returns: UTF-8 encoded JSON data.
    /// - Throws: `EncodingError` if encoding fails.
    static func toJSON(_ route: SharedRoute) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(route)
    }

    /// Decodes a shared route from JSON data.
    ///
    /// - Parameter data: UTF-8 encoded JSON data.
    /// - Returns: The decoded ``SharedRoute``.
    /// - Throws: `DecodingError` if the JSON is malformed or missing required fields.
    static func fromJSON(_ data: Data) throws -> SharedRoute {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SharedRoute.self, from: data)
    }

    // MARK: - SharedRoute -> GPX

    /// Converts a shared route to GPX 1.1 XML format.
    ///
    /// Produces a standard GPX file with a single `<trk>` element containing all track
    /// points, and `<wpt>` elements for waypoints. Compatible with every major hiking
    /// and mapping application (Garmin, Komoot, AllTrails, etc.).
    ///
    /// - Parameter route: The ``SharedRoute`` to convert.
    /// - Returns: UTF-8 encoded GPX XML data.
    static func toGPX(_ route: SharedRoute) -> Data {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="OpenHiker"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
          <metadata>
            <name>\(escapeXML(route.name))</name>
            <desc>\(escapeXML(route.description))</desc>
            <author><name>\(escapeXML(route.author))</name></author>
            <time>\(dateFormatter.string(from: route.createdAt))</time>
          </metadata>\n
        """

        // Waypoints
        for wp in route.waypoints {
            gpx += "  <wpt lat=\"\(wp.lat)\" lon=\"\(wp.lon)\">\n"
            if let ele = wp.ele {
                gpx += "    <ele>\(ele)</ele>\n"
            }
            gpx += "    <name>\(escapeXML(wp.label))</name>\n"
            if !wp.note.isEmpty {
                gpx += "    <desc>\(escapeXML(wp.note))</desc>\n"
            }
            gpx += "    <type>\(escapeXML(wp.category))</type>\n"
            gpx += "  </wpt>\n"
        }

        // Track
        gpx += "  <trk>\n"
        gpx += "    <name>\(escapeXML(route.name))</name>\n"
        gpx += "    <type>\(escapeXML(route.activityType.rawValue))</type>\n"
        gpx += "    <trkseg>\n"

        for point in route.track {
            gpx += "      <trkpt lat=\"\(point.lat)\" lon=\"\(point.lon)\">\n"
            gpx += "        <ele>\(point.ele)</ele>\n"
            gpx += "        <time>\(dateFormatter.string(from: point.time))</time>\n"
            gpx += "      </trkpt>\n"
        }

        gpx += "    </trkseg>\n"
        gpx += "  </trk>\n"
        gpx += "</gpx>\n"

        return Data(gpx.utf8)
    }

    // MARK: - SharedRoute -> Markdown README

    /// Generates a Markdown README for display on GitHub.
    ///
    /// The README includes a stats table, description, waypoints list, and photo
    /// thumbnails. It is auto-generated by the GitHub Actions workflow after each
    /// PR merge, but this method allows the app to preview it locally.
    ///
    /// - Parameter route: The ``SharedRoute`` to describe.
    /// - Returns: A Markdown string.
    static func toMarkdown(_ route: SharedRoute) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none

        let distanceKm = route.stats.distanceMeters / metersPerKilometer
        let durationHours = Int(route.stats.durationSeconds) / secondsPerHour
        let durationMinutes = (Int(route.stats.durationSeconds) % secondsPerHour) / secondsPerMinute

        var md = "# \(route.name)\n\n"
        md += "**\(route.activityType.displayName)** by \(route.author) "
        md += "| \(dateFormatter.string(from: route.createdAt))\n\n"

        if !route.description.isEmpty {
            md += "> \(route.description)\n\n"
        }

        // Stats table
        md += "| Stat | Value |\n"
        md += "|------|-------|\n"
        md += "| Distance | \(String(format: "%.1f km", distanceKm)) |\n"
        md += "| Elevation Gain | \(String(format: "%.0f m", route.stats.elevationGainMeters)) |\n"
        md += "| Elevation Loss | \(String(format: "%.0f m", route.stats.elevationLossMeters)) |\n"
        md += "| Duration | \(durationHours)h \(durationMinutes)m |\n"
        md += "| Region | \(route.region.area), \(route.region.country) |\n\n"

        // Waypoints
        if !route.waypoints.isEmpty {
            md += "## Waypoints\n\n"
            for wp in route.waypoints {
                let eleString = wp.ele.map { String(format: " (%.0f m)", $0) } ?? ""
                md += "- **\(wp.label.isEmpty ? wp.category : wp.label)**\(eleString)"
                if !wp.note.isEmpty {
                    md += " — \(wp.note)"
                }
                md += "\n"
            }
            md += "\n"
        }

        // Photos
        if !route.photos.isEmpty {
            md += "## Photos\n\n"
            for photo in route.photos {
                md += "![" + (photo.caption.isEmpty ? photo.filename : photo.caption) + "](photos/\(photo.filename))\n\n"
            }
        }

        md += "---\n"
        md += "*Shared via [OpenHiker](https://github.com/hherb/OpenHiker) — "
        md += "open-source offline hiking navigation*\n"

        return md
    }

    // MARK: - SharedRoute -> SavedRoute (Import)

    /// Converts a community shared route back to a local ``SavedRoute`` for offline use.
    ///
    /// Re-encodes the track points as compressed binary data via ``TrackCompression``
    /// for efficient local storage.
    ///
    /// - Note: The shared route format does not include separate walking/resting times.
    ///   As an approximation, `walkingTime` is set to the full duration and `restingTime`
    ///   to zero. Heart rate and calorie data are not available in shared routes.
    ///
    /// - Parameter shared: The ``SharedRoute`` to import.
    /// - Returns: A ``SavedRoute`` ready for insertion into ``RouteStore``.
    static func toSavedRoute(_ shared: SharedRoute) -> SavedRoute {
        let locations = shared.track.map { point in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon),
                altitude: point.ele,
                horizontalAccuracy: 0,
                verticalAccuracy: 0,
                timestamp: point.time
            )
        }

        let trackData = TrackCompression.encode(locations)
        let firstPoint = shared.track.first
        let lastPoint = shared.track.last

        return SavedRoute(
            id: shared.id,
            name: shared.name,
            startLatitude: firstPoint?.lat ?? shared.boundingBox.centerLatitude,
            startLongitude: firstPoint?.lon ?? shared.boundingBox.centerLongitude,
            endLatitude: lastPoint?.lat ?? shared.boundingBox.centerLatitude,
            endLongitude: lastPoint?.lon ?? shared.boundingBox.centerLongitude,
            startTime: shared.createdAt,
            endTime: shared.createdAt.addingTimeInterval(shared.stats.durationSeconds),
            totalDistance: shared.stats.distanceMeters,
            elevationGain: shared.stats.elevationGainMeters,
            elevationLoss: shared.stats.elevationLossMeters,
            walkingTime: shared.stats.durationSeconds, // approximate: treat all as walking
            restingTime: 0,
            comment: shared.description,
            trackData: trackData
        )
    }

    // MARK: - Slug Generation

    /// Generates a URL-safe slug from a route name for use as a directory name.
    ///
    /// Lowercases the name, replaces spaces and non-alphanumeric characters with hyphens,
    /// collapses consecutive hyphens, and trims leading/trailing hyphens. Returns
    /// ``fallbackSlug`` if the name contains no alphanumeric characters.
    ///
    /// - Parameter name: The route name to slugify.
    /// - Returns: A URL-safe slug (e.g., "mount-tamalpais-loop"), or ``fallbackSlug``
    ///   if the name is empty or contains only special characters.
    static func slugify(_ name: String) -> String {
        let lowercased = name.lowercased()
        let alphanumeric = lowercased.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : Character("-")
        }
        let collapsed = String(alphanumeric)
            .components(separatedBy: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return collapsed.isEmpty ? fallbackSlug : collapsed
    }

    // MARK: - Private Helpers

    /// Rounds a coordinate to 5 decimal places (~1.1m precision).
    ///
    /// - Parameter value: The coordinate value in degrees.
    /// - Returns: The rounded value.
    private static func roundCoordinate(_ value: Double) -> Double {
        let multiplier = pow(10.0, Double(coordinateDecimalPlaces))
        return round(value * multiplier) / multiplier
    }

    /// Computes a bounding box from an array of CLLocation objects.
    ///
    /// - Parameter locations: The GPS points to compute bounds for.
    /// - Returns: A ``SharedBoundingBox`` enclosing all points.
    private static func computeBoundingBox(from locations: [CLLocation]) -> SharedBoundingBox {
        guard let first = locations.first else {
            return SharedBoundingBox(north: 0, south: 0, east: 0, west: 0)
        }

        var minLat = first.coordinate.latitude
        var maxLat = first.coordinate.latitude
        var minLon = first.coordinate.longitude
        var maxLon = first.coordinate.longitude

        for location in locations.dropFirst() {
            minLat = min(minLat, location.coordinate.latitude)
            maxLat = max(maxLat, location.coordinate.latitude)
            minLon = min(minLon, location.coordinate.longitude)
            maxLon = max(maxLon, location.coordinate.longitude)
        }

        return SharedBoundingBox(
            north: roundCoordinate(maxLat),
            south: roundCoordinate(minLat),
            east: roundCoordinate(maxLon),
            west: roundCoordinate(minLon)
        )
    }

    /// Escapes special XML characters in a string.
    ///
    /// Handles the five XML predefined entities: `&`, `<`, `>`, `"`, `'`.
    ///
    /// - Parameter string: The string to escape.
    /// - Returns: The XML-safe string.
    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
