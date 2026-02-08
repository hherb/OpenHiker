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

/// Manages periodic persistence of in-progress track recording state for crash recovery.
///
/// During active hike tracking, this manager periodically saves the current track
/// points, accumulated statistics, and recording metadata to disk. This allows
/// recovery of the hike data if the app is terminated (e.g., by the system under
/// memory pressure, or when battery dies completely).
///
/// ## Storage Location
/// Recovery data is stored as two files in the Documents directory:
/// - `track_recovery_meta.json` — metadata (stats, timestamps, region ID)
/// - `track_recovery_points.bin` — compressed track points via ``TrackCompression``
///
/// ## Recovery Flow
/// 1. On app launch, call ``hasRecoverableTrack()`` to check for saved state
/// 2. If `true`, call ``loadRecoveryState()`` to get the saved track data
/// 3. The app can resume tracking from the saved state or save it as a completed route
/// 4. Call ``clearRecoveryState()`` after successful recovery or discard
///
/// ## Auto-Save Triggers
/// - Periodic timer (default: every 5 minutes during tracking)
/// - Low-battery notification (immediate save when battery hits 5%)
/// - Explicit call from ``MapView`` when stopping tracking
enum TrackRecoveryManager {

    // MARK: - Configuration

    /// How often (in seconds) the track state is auto-saved during active recording.
    ///
    /// 300 seconds (5 minutes) balances data safety against disk I/O overhead.
    /// At worst, a crash loses 5 minutes of track data.
    static let autoSaveIntervalSec: TimeInterval = 300.0

    // MARK: - File Paths

    /// URL for the recovery metadata JSON file.
    private static var metadataURL: URL {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        return documentsDir.appendingPathComponent("track_recovery_meta.json")
    }

    /// URL for the compressed track points binary file.
    private static var trackDataURL: URL {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        return documentsDir.appendingPathComponent("track_recovery_points.bin")
    }

    // MARK: - Recovery Metadata

    /// Metadata saved alongside track points for recovery.
    ///
    /// Contains accumulated statistics and identifiers needed to reconstruct
    /// a ``SavedRoute`` or resume tracking from the saved state.
    struct RecoveryMetadata: Codable {
        /// Total distance covered so far in meters.
        let totalDistance: Double

        /// Total cumulative elevation gain in meters.
        let elevationGain: Double

        /// Total cumulative elevation loss in meters.
        let elevationLoss: Double

        /// Timestamp when tracking was started.
        let trackingStartDate: Date

        /// Timestamp when this recovery state was last saved.
        let lastSaveDate: Date

        /// UUID of the map region being used, if any.
        let regionId: UUID?

        /// Whether tracking was actively recording when state was saved.
        let wasTracking: Bool

        /// Number of track points saved.
        let pointCount: Int
    }

    // MARK: - Save

    /// Saves the current track recording state to disk for crash recovery.
    ///
    /// Writes both the compressed track points and the metadata JSON atomically.
    /// If either write fails, the error is logged but not thrown — recovery is
    /// best-effort and should not interrupt the user's hike.
    ///
    /// - Parameters:
    ///   - trackPoints: The GPS track points recorded so far.
    ///   - totalDistance: Accumulated total distance in meters.
    ///   - elevationGain: Accumulated elevation gain in meters.
    ///   - elevationLoss: Accumulated elevation loss in meters.
    ///   - regionId: UUID of the active map region, or `nil`.
    static func saveState(
        trackPoints: [CLLocation],
        totalDistance: Double,
        elevationGain: Double,
        elevationLoss: Double,
        regionId: UUID?
    ) {
        guard !trackPoints.isEmpty else { return }

        let metadata = RecoveryMetadata(
            totalDistance: totalDistance,
            elevationGain: elevationGain,
            elevationLoss: elevationLoss,
            trackingStartDate: trackPoints.first?.timestamp ?? Date(),
            lastSaveDate: Date(),
            regionId: regionId,
            wasTracking: true,
            pointCount: trackPoints.count
        )

        // Save metadata
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let metaData = try encoder.encode(metadata)
            try metaData.write(to: metadataURL, options: .atomic)
        } catch {
            print("TrackRecoveryManager: Error saving metadata: \(error.localizedDescription)")
            return
        }

        // Save compressed track points
        let compressedTrack = TrackCompression.encode(trackPoints)
        do {
            try compressedTrack.write(to: trackDataURL, options: .atomic)
            print("TrackRecoveryManager: Saved \(trackPoints.count) track points (\(compressedTrack.count) bytes compressed)")
        } catch {
            print("TrackRecoveryManager: Error saving track data: \(error.localizedDescription)")
        }
    }

    // MARK: - Load

    /// Checks whether a recoverable track exists on disk.
    ///
    /// - Returns: `true` if both the metadata and track data files exist.
    static func hasRecoverableTrack() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: metadataURL.path) &&
               fm.fileExists(atPath: trackDataURL.path)
    }

    /// Loads the saved recovery state from disk.
    ///
    /// - Returns: A tuple of (metadata, track points), or `nil` if no recovery
    ///   data exists or decoding fails.
    static func loadRecoveryState() -> (metadata: RecoveryMetadata, trackPoints: [CLLocation])? {
        guard hasRecoverableTrack() else { return nil }

        // Load metadata
        guard let metaData = try? Data(contentsOf: metadataURL) else {
            print("TrackRecoveryManager: Failed to read metadata file")
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let metadata = try? decoder.decode(RecoveryMetadata.self, from: metaData) else {
            print("TrackRecoveryManager: Failed to decode metadata")
            return nil
        }

        // Load and decompress track points
        guard let compressedTrack = try? Data(contentsOf: trackDataURL) else {
            print("TrackRecoveryManager: Failed to read track data file")
            return nil
        }

        let trackPoints = TrackCompression.decode(compressedTrack)
        guard !trackPoints.isEmpty else {
            print("TrackRecoveryManager: Decoded zero track points")
            return nil
        }

        print("TrackRecoveryManager: Loaded recovery state — \(trackPoints.count) points, \(String(format: "%.1f", metadata.totalDistance))m distance")
        return (metadata: metadata, trackPoints: trackPoints)
    }

    // MARK: - Clear

    /// Deletes the recovery state files from disk.
    ///
    /// Call this after the track has been successfully saved as a ``SavedRoute``
    /// or when the user discards the recovered track.
    static func clearRecoveryState() {
        let fm = FileManager.default
        try? fm.removeItem(at: metadataURL)
        try? fm.removeItem(at: trackDataURL)
        print("TrackRecoveryManager: Cleared recovery state")
    }

    // MARK: - Emergency Save as Route

    /// Saves the current track state as a completed ``SavedRoute`` for emergency preservation.
    ///
    /// Called when battery reaches critical level to ensure the track data is
    /// preserved in the SQLite database and queued for transfer to the iPhone.
    /// The route name includes "(low battery)" to indicate it was auto-saved.
    ///
    /// - Parameters:
    ///   - trackPoints: The GPS track points recorded so far.
    ///   - totalDistance: Accumulated total distance in meters.
    ///   - elevationGain: Accumulated elevation gain in meters.
    ///   - elevationLoss: Accumulated elevation loss in meters.
    ///   - regionId: UUID of the active map region, or `nil`.
    ///   - averageHeartRate: Average heart rate during the hike, or `nil`.
    ///   - connectivityManager: The WatchConnectivity receiver for iPhone transfer.
    static func emergencySaveAsRoute(
        trackPoints: [CLLocation],
        totalDistance: Double,
        elevationGain: Double,
        elevationLoss: Double,
        regionId: UUID?,
        averageHeartRate: Double?,
        connectivityManager: WatchConnectivityReceiver
    ) {
        guard let firstPoint = trackPoints.first,
              let lastPoint = trackPoints.last else {
            print("TrackRecoveryManager: No track points for emergency save")
            return
        }

        let times = LocationManager.computeWalkingAndRestingTime(from: trackPoints)
        let duration = lastPoint.timestamp.timeIntervalSince(firstPoint.timestamp)
        let compressedTrack = TrackCompression.encode(trackPoints)

        let route = SavedRoute(
            name: SavedRoute.defaultName(for: firstPoint.timestamp) + " (low battery)",
            startLatitude: firstPoint.coordinate.latitude,
            startLongitude: firstPoint.coordinate.longitude,
            endLatitude: lastPoint.coordinate.latitude,
            endLongitude: lastPoint.coordinate.longitude,
            startTime: firstPoint.timestamp,
            endTime: lastPoint.timestamp,
            totalDistance: totalDistance,
            elevationGain: elevationGain,
            elevationLoss: elevationLoss,
            walkingTime: times.walking,
            restingTime: times.resting,
            averageHeartRate: averageHeartRate,
            estimatedCalories: CalorieEstimator.estimateCalories(
                distanceMeters: totalDistance,
                elevationGainMeters: elevationGain,
                durationSeconds: duration,
                bodyMassKg: nil
            ),
            comment: "Auto-saved due to low battery",
            regionId: regionId,
            trackData: compressedTrack
        )

        // Save to local RouteStore
        do {
            try RouteStore.shared.insert(route)
            print("TrackRecoveryManager: Emergency saved route \(route.id.uuidString)")
        } catch {
            print("TrackRecoveryManager: Failed to emergency save route: \(error.localizedDescription)")
            return
        }

        // Queue for transfer to iPhone
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let jsonData = try? encoder.encode(route) else {
            print("TrackRecoveryManager: Failed to encode route for transfer")
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("\(route.id.uuidString).hikedata")

        do {
            try jsonData.write(to: tempFile)
            connectivityManager.transferRouteToPhone(fileURL: tempFile, routeId: route.id)
            print("TrackRecoveryManager: Queued emergency route for iPhone transfer")
        } catch {
            print("TrackRecoveryManager: Failed to write temp file for transfer: \(error.localizedDescription)")
        }
    }
}
