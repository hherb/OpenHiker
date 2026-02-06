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

/// A completed hike with full track data and statistics.
///
/// This is the core data model for Phase 3 (Save Routes & Review Past Hikes).
/// It stores everything needed to review a past hike:
/// - **Geographic bounds**: start/end coordinates
/// - **Statistics**: distance, elevation, time, heart rate, calories
/// - **Track data**: compressed binary representation of GPS points (see ``TrackCompression``)
/// - **User annotation**: editable name and comment
///
/// The `trackData` field holds a zlib-compressed binary encoding of all GPS
/// points recorded during the hike. Use ``TrackCompression/encode(_:)`` and
/// ``TrackCompression/decode(_:)`` to convert between `[CLLocation]` and `Data`.
///
/// ## Persistence
/// Stored in a SQLite database managed by ``RouteStore``. The `trackData` BLOB
/// is the largest field — typically 10-20 KB for a 1000-point hike after compression.
///
/// ## Transfer
/// Transferred from watch to iPhone via `WCSession.transferFile()` as a
/// JSON-encoded file with metadata identifying it as `type: "savedRoute"`.
struct SavedRoute: Identifiable, Codable, Sendable, Equatable {
    /// Unique identifier for this saved route.
    let id: UUID

    /// User-editable name for the hike (auto-generated as "Hike — <date>" by default).
    var name: String

    /// Latitude of the first recorded track point in WGS84 degrees.
    let startLatitude: Double

    /// Longitude of the first recorded track point in WGS84 degrees.
    let startLongitude: Double

    /// Latitude of the last recorded track point in WGS84 degrees.
    let endLatitude: Double

    /// Longitude of the last recorded track point in WGS84 degrees.
    let endLongitude: Double

    /// Timestamp when tracking was started.
    let startTime: Date

    /// Timestamp when tracking was stopped.
    let endTime: Date

    /// Total distance covered in meters, measured along the GPS track.
    let totalDistance: Double

    /// Total cumulative elevation gained in meters (only uphill segments).
    let elevationGain: Double

    /// Total cumulative elevation lost in meters (only downhill segments, stored as positive value).
    let elevationLoss: Double

    /// Time spent actively moving in seconds (speed >= ``HikeStatisticsConfig/restingSpeedThreshold``).
    let walkingTime: TimeInterval

    /// Time spent stationary or nearly stationary in seconds.
    let restingTime: TimeInterval

    /// Average heart rate during the hike in BPM, or `nil` if HealthKit data unavailable.
    let averageHeartRate: Double?

    /// Maximum heart rate recorded during the hike in BPM, or `nil` if unavailable.
    let maxHeartRate: Double?

    /// Estimated energy burned in kilocalories, or `nil` if unavailable.
    let estimatedCalories: Double?

    /// User-editable comment or notes about the hike.
    var comment: String

    /// UUID of the map region used during this hike, or `nil` if unknown.
    let regionId: UUID?

    /// Compressed binary representation of the GPS track.
    ///
    /// Encoded via ``TrackCompression/encode(_:)`` using packed Float32/Float64 records
    /// with zlib compression. Decode with ``TrackCompression/decode(_:)``.
    let trackData: Data

    /// Creates a new SavedRoute with the given properties.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to a new UUID).
    ///   - name: Human-readable hike name.
    ///   - startLatitude: Latitude of the start point.
    ///   - startLongitude: Longitude of the start point.
    ///   - endLatitude: Latitude of the end point.
    ///   - endLongitude: Longitude of the end point.
    ///   - startTime: When tracking began.
    ///   - endTime: When tracking ended.
    ///   - totalDistance: Total distance in meters.
    ///   - elevationGain: Cumulative elevation gain in meters.
    ///   - elevationLoss: Cumulative elevation loss in meters.
    ///   - walkingTime: Active walking time in seconds.
    ///   - restingTime: Resting time in seconds.
    ///   - averageHeartRate: Average HR in BPM, or `nil`.
    ///   - maxHeartRate: Max HR in BPM, or `nil`.
    ///   - estimatedCalories: Estimated kcal, or `nil`.
    ///   - comment: User comment (defaults to empty string).
    ///   - regionId: Associated map region UUID, or `nil`.
    ///   - trackData: Compressed binary track data.
    init(
        id: UUID = UUID(),
        name: String,
        startLatitude: Double,
        startLongitude: Double,
        endLatitude: Double,
        endLongitude: Double,
        startTime: Date,
        endTime: Date,
        totalDistance: Double,
        elevationGain: Double,
        elevationLoss: Double,
        walkingTime: TimeInterval,
        restingTime: TimeInterval,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        estimatedCalories: Double? = nil,
        comment: String = "",
        regionId: UUID? = nil,
        trackData: Data
    ) {
        self.id = id
        self.name = name
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.endLatitude = endLatitude
        self.endLongitude = endLongitude
        self.startTime = startTime
        self.endTime = endTime
        self.totalDistance = totalDistance
        self.elevationGain = elevationGain
        self.elevationLoss = elevationLoss
        self.walkingTime = walkingTime
        self.restingTime = restingTime
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.estimatedCalories = estimatedCalories
        self.comment = comment
        self.regionId = regionId
        self.trackData = trackData
    }

    /// Total elapsed time from start to finish in seconds.
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    /// The start date formatted for display in list rows (e.g., "6 Feb 2026").
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: startTime)
    }

    /// The start time formatted for display (e.g., "09:30").
    var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }

    /// Generates a default hike name using the localized date format.
    ///
    /// - Parameter date: The date to use in the name.
    /// - Returns: A string like "Hike — 6 Feb 2026".
    static func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Hike — \(formatter.string(from: date))"
    }
}
