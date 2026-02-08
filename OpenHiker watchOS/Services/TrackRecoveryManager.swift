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
import os

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

    /// Logger for recovery manager events.
    private static let logger = Logger(
        subsystem: "com.openhiker.watchos",
        category: "TrackRecovery"
    )

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

        /// Whether an emergency route was already saved to RouteStore for this track.
        ///
        /// Set to `true` after ``emergencySaveAsRoute()`` succeeds. Prevents duplicate
        /// route creation if the app is relaunched and recovery is triggered again.
        let routeAlreadySaved: Bool
    }

    // MARK: - Save

    /// Saves the current track recording state to disk for crash recovery.
    ///
    /// Writes both the compressed track points and the metadata JSON atomically.
    /// Both files are written to temporary locations first, then renamed to their
    /// final paths only after both writes succeed, preventing inconsistent state.
    ///
    /// - Parameters:
    ///   - trackPoints: The GPS track points recorded so far.
    ///   - totalDistance: Accumulated total distance in meters.
    ///   - elevationGain: Accumulated elevation gain in meters.
    ///   - elevationLoss: Accumulated elevation loss in meters.
    ///   - regionId: UUID of the active map region, or `nil`.
    ///   - routeAlreadySaved: Whether an emergency route was already saved for this track.
    /// - Returns: `true` if the state was saved successfully.
    @discardableResult
    static func saveState(
        trackPoints: [CLLocation],
        totalDistance: Double,
        elevationGain: Double,
        elevationLoss: Double,
        regionId: UUID?,
        routeAlreadySaved: Bool = false
    ) -> Bool {
        guard !trackPoints.isEmpty else { return false }

        let metadata = RecoveryMetadata(
            totalDistance: totalDistance,
            elevationGain: elevationGain,
            elevationLoss: elevationLoss,
            trackingStartDate: trackPoints.first?.timestamp ?? Date(),
            lastSaveDate: Date(),
            regionId: regionId,
            wasTracking: true,
            pointCount: trackPoints.count,
            routeAlreadySaved: routeAlreadySaved
        )

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
        let tempMetaURL = tempDir.appendingPathComponent("track_recovery_meta_tmp.json")
        let tempTrackURL = tempDir.appendingPathComponent("track_recovery_points_tmp.bin")

        // Encode metadata
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let metaData: Data
        do {
            metaData = try encoder.encode(metadata)
        } catch {
            logger.error("Failed to encode metadata: \(error.localizedDescription)")
            return false
        }

        // Compress track points
        let compressedTrack = TrackCompression.encode(trackPoints)

        // Write both to temp files first
        do {
            try metaData.write(to: tempMetaURL, options: .atomic)
        } catch {
            logger.error("Failed to write temp metadata: \(error.localizedDescription)")
            return false
        }

        do {
            try compressedTrack.write(to: tempTrackURL, options: .atomic)
        } catch {
            logger.error("Failed to write temp track data: \(error.localizedDescription)")
            try? fm.removeItem(at: tempMetaURL)
            return false
        }

        // Move both atomically to final locations
        do {
            // Remove existing files first (moveItem fails if destination exists)
            if fm.fileExists(atPath: metadataURL.path) {
                try fm.removeItem(at: metadataURL)
            }
            try fm.moveItem(at: tempMetaURL, to: metadataURL)

            if fm.fileExists(atPath: trackDataURL.path) {
                try fm.removeItem(at: trackDataURL)
            }
            try fm.moveItem(at: tempTrackURL, to: trackDataURL)
        } catch {
            logger.error("Failed to move recovery files to final location: \(error.localizedDescription)")
            // Clean up temp files
            try? fm.removeItem(at: tempMetaURL)
            try? fm.removeItem(at: tempTrackURL)
            return false
        }

        logger.info("Saved \(trackPoints.count) track points (\(compressedTrack.count) bytes compressed)")
        return true
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
    ///   data exists or decoding fails. On failure, the error is logged but
    ///   recovery files are NOT deleted — they may be recoverable after an
    ///   app update or device restart.
    static func loadRecoveryState() -> (metadata: RecoveryMetadata, trackPoints: [CLLocation])? {
        guard hasRecoverableTrack() else { return nil }

        // Load metadata
        let metaData: Data
        do {
            metaData = try Data(contentsOf: metadataURL)
        } catch {
            logger.error("Failed to read metadata file: \(error.localizedDescription)")
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata: RecoveryMetadata
        do {
            metadata = try decoder.decode(RecoveryMetadata.self, from: metaData)
        } catch {
            logger.error("Failed to decode metadata: \(error.localizedDescription)")
            return nil
        }

        // Load and decompress track points
        let compressedTrack: Data
        do {
            compressedTrack = try Data(contentsOf: trackDataURL)
        } catch {
            logger.error("Failed to read track data file: \(error.localizedDescription)")
            return nil
        }

        let trackPoints = TrackCompression.decode(compressedTrack)
        guard !trackPoints.isEmpty else {
            logger.error("Decoded zero track points from recovery data")
            return nil
        }

        logger.info("Loaded recovery state — \(trackPoints.count) points, \(String(format: "%.1f", metadata.totalDistance))m distance")
        return (metadata: metadata, trackPoints: trackPoints)
    }

    // MARK: - Clear

    /// Deletes the recovery state files from disk.
    ///
    /// Call this after the track has been successfully saved as a ``SavedRoute``
    /// or when the user explicitly discards the recovered track.
    ///
    /// - Returns: `true` if both files were successfully removed (or did not exist).
    @discardableResult
    static func clearRecoveryState() -> Bool {
        let fm = FileManager.default
        var success = true

        if fm.fileExists(atPath: metadataURL.path) {
            do {
                try fm.removeItem(at: metadataURL)
            } catch {
                logger.error("Failed to remove metadata file: \(error.localizedDescription)")
                success = false
            }
        }

        if fm.fileExists(atPath: trackDataURL.path) {
            do {
                try fm.removeItem(at: trackDataURL)
            } catch {
                logger.error("Failed to remove track data file: \(error.localizedDescription)")
                success = false
            }
        }

        if success {
            logger.info("Cleared recovery state")
        }
        return success
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
    /// - Returns: `true` if the route was successfully saved to RouteStore.
    @discardableResult
    static func emergencySaveAsRoute(
        trackPoints: [CLLocation],
        totalDistance: Double,
        elevationGain: Double,
        elevationLoss: Double,
        regionId: UUID?,
        averageHeartRate: Double?,
        connectivityManager: WatchConnectivityReceiver
    ) -> Bool {
        guard let firstPoint = trackPoints.first,
              let lastPoint = trackPoints.last else {
            logger.error("No track points for emergency save")
            return false
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
            logger.info("Emergency saved route \(route.id.uuidString)")
        } catch {
            logger.error("Failed to emergency save route: \(error.localizedDescription)")
            return false
        }

        // Queue for transfer to iPhone
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let jsonData = try encoder.encode(route)
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent("\(route.id.uuidString).hikedata")
            try jsonData.write(to: tempFile)
            connectivityManager.transferRouteToPhone(fileURL: tempFile, routeId: route.id)
            logger.info("Queued emergency route for iPhone transfer")
        } catch {
            logger.error("Failed to queue route for iPhone transfer: \(error.localizedDescription)")
            // Route is saved locally even if transfer queueing fails — not a critical failure
        }

        return true
    }
}
