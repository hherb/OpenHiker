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

/// Generates personal hike summary exports from ``SavedRoute`` data.
///
/// Distinct from ``RouteExporter`` which operates on ``SharedRoute`` for community display.
/// This exporter produces richer output that includes heart rate, calories, walking/resting
/// time split, and average speed -- data that ``SavedRoute`` carries but ``SharedRoute``
/// does not.
///
/// ## Supported Formats
/// - **Markdown**: Personal hike summary card with full statistics table
/// - **GPX**: Convenience wrapper that converts ``SavedRoute`` to GPX 1.1 via ``RouteExporter``
///
/// ## Thread Safety
/// All methods are pure static functions with no shared state.
///
/// ## Usage
/// ```swift
/// let markdown = HikeSummaryExporter.toMarkdown(
///     route: savedRoute,
///     waypoints: linkedWaypoints,
///     useMetric: true
/// )
/// let gpxData = HikeSummaryExporter.toGPX(route: savedRoute, waypoints: waypoints)
/// ```
enum HikeSummaryExporter {

    // MARK: - Constants

    /// Number of decimal places for coordinate display in export output.
    ///
    /// 4 decimal places gives ~11m precision -- sufficient for hiking waypoint display.
    private static let coordinateDecimalPlaces = 4

    /// Meters per kilometer, used for metric distance formatting.
    private static let metersPerKilometer = 1000.0

    /// Seconds per hour, used for duration formatting.
    private static let secondsPerHour: TimeInterval = 3600.0

    /// Seconds per minute, used for duration formatting.
    private static let secondsPerMinute: TimeInterval = 60.0

    // MARK: - Markdown Export

    /// Generates a personal hike summary as Markdown text.
    ///
    /// The output includes:
    /// - Title and date/time range
    /// - Duration breakdown (total, walking, resting)
    /// - Full statistics table (distance, elevation, heart rate, calories, average speed)
    /// - Numbered waypoints list with coordinates and notes
    /// - User comment section
    /// - OpenHiker attribution footer
    ///
    /// - Parameters:
    ///   - route: The completed hike to summarize.
    ///   - waypoints: Waypoints linked to this hike (may be empty).
    ///   - useMetric: If `true`, uses km/m; if `false`, uses mi/ft.
    /// - Returns: A Markdown string ready for saving or sharing.
    static func toMarkdown(
        route: SavedRoute,
        waypoints: [Waypoint],
        useMetric: Bool
    ) -> String {
        var md = ""

        // Title
        md += "# Hike: \(route.name)\n\n"

        // Date and time range
        let dateRange = formatDateRange(start: route.startTime, end: route.endTime)
        md += "**Date:** \(dateRange)\n"

        // Duration breakdown
        let totalDuration = formatDurationLong(route.duration)
        let walkingDuration = formatDurationLong(route.walkingTime)
        let restingDuration = formatDurationLong(route.restingTime)
        md += "**Duration:** \(totalDuration) (Walking: \(walkingDuration), Resting: \(restingDuration))\n\n"

        // Statistics table
        md += "## Statistics\n\n"
        md += "| Metric | Value |\n"
        md += "|--------|-------|\n"
        md += "| Distance | \(HikeStatsFormatter.formatDistance(route.totalDistance, useMetric: useMetric)) |\n"
        md += "| Elevation Gain | +\(HikeStatsFormatter.formatElevation(route.elevationGain, useMetric: useMetric)) |\n"
        md += "| Elevation Loss | -\(HikeStatsFormatter.formatElevation(route.elevationLoss, useMetric: useMetric)) |\n"

        if let avgHR = route.averageHeartRate {
            md += "| Avg Heart Rate | \(HikeStatsFormatter.formatHeartRate(avgHR)) |\n"
        }
        if let maxHR = route.maxHeartRate {
            md += "| Max Heart Rate | \(HikeStatsFormatter.formatHeartRate(maxHR)) |\n"
        }
        if let calories = route.estimatedCalories {
            md += "| Calories | ~\(HikeStatsFormatter.formatCalories(calories)) |\n"
        }

        // Average speed (distance / walking time, to exclude resting)
        if route.walkingTime > 0 {
            let avgSpeedMps = route.totalDistance / route.walkingTime
            md += "| Avg Speed | \(HikeStatsFormatter.formatSpeed(avgSpeedMps, useMetric: useMetric)) |\n"
        }

        md += "\n"

        // Waypoints
        if !waypoints.isEmpty {
            md += "## Waypoints\n\n"
            for (index, wp) in waypoints.enumerated() {
                let label = wp.label.isEmpty ? wp.category.displayName : wp.label
                let coord = formatCoordinate(latitude: wp.latitude, longitude: wp.longitude)
                md += "\(index + 1). **\(label)** (\(coord))"
                if !wp.note.isEmpty {
                    md += " — \"\(wp.note)\""
                }
                md += "\n"
            }
            md += "\n"
        }

        // Comment
        if !route.comment.isEmpty {
            md += "## Comments\n\n"
            md += "\(route.comment)\n\n"
        }

        // Footer
        md += "---\n"
        md += "*Recorded with OpenHiker — https://github.com/hherb/OpenHiker*\n"

        return md
    }

    // MARK: - GPX Export

    /// Converts a ``SavedRoute`` to GPX 1.1 format.
    ///
    /// Internally converts the saved route to a ``SharedRoute`` via ``RouteExporter``,
    /// then generates GPX from that. This reuses the existing GPX generation logic.
    ///
    /// - Parameters:
    ///   - route: The completed hike to export.
    ///   - waypoints: Waypoints linked to this hike (included as `<wpt>` elements).
    /// - Returns: UTF-8 encoded GPX XML data.
    static func toGPX(route: SavedRoute, waypoints: [Waypoint]) -> Data {
        let sharedRoute = RouteExporter.toSharedRoute(
            route,
            activityType: .hiking,
            author: "OpenHiker User",
            description: route.comment,
            country: "",
            area: "",
            waypoints: waypoints,
            photos: []
        )
        return RouteExporter.toGPX(sharedRoute)
    }

    // MARK: - Private Formatting Helpers

    /// Formats a date range as "6 February 2026, 08:15 -- 12:38".
    ///
    /// Uses the user's locale for date and time formatting.
    ///
    /// - Parameters:
    ///   - start: The start timestamp.
    ///   - end: The end timestamp.
    /// - Returns: A formatted date range string.
    private static func formatDateRange(start: Date, end: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let dateString = dateFormatter.string(from: start)
        let startTime = timeFormatter.string(from: start)
        let endTime = timeFormatter.string(from: end)

        return "\(dateString), \(startTime) \u{2013} \(endTime)"
    }

    /// Formats a duration as "Xh Ym" (e.g., "4h 23m" or "35m" if under 1 hour).
    ///
    /// - Parameter interval: The time interval in seconds.
    /// - Returns: A compact duration string.
    private static func formatDurationLong(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval / secondsPerMinute)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Formats a coordinate as "47.4211\u{00B0}N, 10.9853\u{00B0}E" with N/S/E/W suffixes.
    ///
    /// Uses ``coordinateDecimalPlaces`` decimal places.
    ///
    /// - Parameters:
    ///   - latitude: Latitude in degrees.
    ///   - longitude: Longitude in degrees.
    /// - Returns: A formatted coordinate string.
    private static func formatCoordinate(latitude: Double, longitude: Double) -> String {
        let latDir = latitude >= 0 ? "N" : "S"
        let lonDir = longitude >= 0 ? "E" : "W"
        let latStr = String(format: "%.\(coordinateDecimalPlaces)f", abs(latitude))
        let lonStr = String(format: "%.\(coordinateDecimalPlaces)f", abs(longitude))
        return "\(latStr)\u{00B0}\(latDir), \(lonStr)\u{00B0}\(lonDir)"
    }
}
