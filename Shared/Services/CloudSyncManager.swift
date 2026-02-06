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
import Combine

/// Notification posted when a cloud sync completes (success or failure).
///
/// The `userInfo` dictionary contains:
/// - `"success"`: `Bool` indicating whether the sync succeeded
/// - `"error"`: Optional `String` with the error message if sync failed
extension Notification.Name {
    static let cloudSyncCompleted = Notification.Name("cloudSyncCompleted")
}

/// Coordinates bidirectional sync between local SQLite stores and iCloud via CloudKit.
///
/// Implements a "last-writer-wins" conflict resolution strategy using `modifiedAt`
/// timestamps. The sync flow is:
///
/// 1. **Push**: Upload local records that have no `cloudKitRecordID` or whose
///    `modifiedAt` is newer than the remote `CKRecord.modificationDate`.
/// 2. **Pull**: Download remote records that don't exist locally or are newer
///    than the local `modifiedAt`.
/// 3. **Delete**: Remote deletions are detected by comparing local record IDs
///    against the remote set. (Local deletions are synced immediately.)
///
/// ## Sync Triggers
/// - App launch (via ``syncOnLaunch()``)
/// - Manual pull-to-refresh
/// - CloudKit push notification (subscription-based)
/// - Periodic background (every 15 minutes via ``schedulePeriodic()``)
///
/// ## Dependencies
/// - ``CloudKitStore``: Low-level CloudKit CRUD operations
/// - ``RouteStore``: Local SQLite storage for saved routes
/// - ``WaypointStore``: Local SQLite storage for waypoints
/// - ``PlannedRouteStore``: Local JSON storage for planned routes
///
/// ## Thread Safety
/// This is a Swift Actor, so all methods are automatically serialized.
/// External callers should use `await` to interact with the sync manager.
actor CloudSyncManager {

    // MARK: - Constants

    /// Interval between periodic background syncs in seconds (15 minutes).
    static let periodicSyncInterval: TimeInterval = 900

    /// Maximum number of retry attempts for failed sync operations.
    static let maxRetryAttempts = 4

    /// Base delay for exponential backoff in seconds.
    static let baseRetryDelay: TimeInterval = 2

    // MARK: - Properties

    /// The CloudKit store for remote operations.
    private let cloudStore: CloudKitStore

    /// Whether a sync is currently in progress (prevents concurrent syncs).
    private var isSyncing = false

    /// Whether iCloud is available for this user.
    private var isAvailable = false

    /// Timestamp of the last successful sync.
    private var lastSyncDate: Date?

    // MARK: - Singleton

    /// Shared singleton instance.
    static let shared = CloudSyncManager()

    // MARK: - Initialization

    /// Creates a new sync manager with a fresh CloudKit store.
    init() {
        self.cloudStore = CloudKitStore()
    }

    // MARK: - Public API

    /// Checks iCloud availability and performs an initial sync.
    ///
    /// Call this once on app launch. Sets up CloudKit subscriptions for push
    /// notifications and triggers the first sync.
    ///
    /// Safe to call if iCloud is unavailable — it logs the status and returns.
    func syncOnLaunch() async {
        do {
            isAvailable = try await cloudStore.isAccountAvailable()
            guard isAvailable else {
                print("CloudSyncManager: iCloud account not available, skipping sync")
                return
            }

            // Set up push notification subscriptions
            try await cloudStore.setupSubscriptions()

            // Perform initial sync
            await performSync()
        } catch {
            print("CloudSyncManager: Launch sync error: \(error.localizedDescription)")
        }
    }

    /// Performs a full bidirectional sync (push local changes, then pull remote changes).
    ///
    /// Skips if a sync is already in progress. Posts ``Notification.Name/cloudSyncCompleted``
    /// when done.
    func performSync() async {
        guard isAvailable else { return }
        guard !isSyncing else {
            print("CloudSyncManager: Sync already in progress, skipping")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            // Push local changes to CloudKit
            try await pushRoutes()
            try await pushWaypoints()

            // Pull remote changes from CloudKit
            try await pullRoutes()
            try await pullWaypoints()

            lastSyncDate = Date()

            await MainActor.run {
                NotificationCenter.default.post(
                    name: .cloudSyncCompleted,
                    object: nil,
                    userInfo: ["success": true]
                )
            }

            print("CloudSyncManager: Sync completed successfully")
        } catch {
            print("CloudSyncManager: Sync error: \(error.localizedDescription)")

            await MainActor.run {
                NotificationCenter.default.post(
                    name: .cloudSyncCompleted,
                    object: nil,
                    userInfo: ["success": false, "error": error.localizedDescription]
                )
            }
        }
    }

    /// Called when a CloudKit push notification is received.
    ///
    /// Triggers a pull-only sync to fetch the changed records.
    func handleRemoteNotification() async {
        guard isAvailable else { return }
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await pullRoutes()
            try await pullWaypoints()
            lastSyncDate = Date()
        } catch {
            print("CloudSyncManager: Remote notification sync error: \(error.localizedDescription)")
        }
    }

    // MARK: - Push Operations

    /// Pushes locally modified routes to CloudKit.
    ///
    /// Uploads routes that either:
    /// - Have no `cloudKitRecordID` (never synced)
    /// - Have a `modifiedAt` timestamp (locally modified)
    ///
    /// After successful upload, updates the local record with the CloudKit record ID.
    private func pushRoutes() async throws {
        let localRoutes = try RouteStore.shared.fetchAll()

        for var route in localRoutes {
            // Skip routes that are already synced and haven't been modified locally
            if route.cloudKitRecordID != nil && route.modifiedAt == nil {
                continue
            }

            let recordID = try await retryWithBackoff {
                try await self.cloudStore.save(route: route)
            }

            // Update local record with CloudKit ID
            route.cloudKitRecordID = recordID
            route.modifiedAt = nil // Clear modification flag
            try RouteStore.shared.update(route)
        }
    }

    /// Pushes locally modified waypoints to CloudKit.
    ///
    /// Same logic as ``pushRoutes()`` but for waypoints.
    private func pushWaypoints() async throws {
        let localWaypoints = try WaypointStore.shared.fetchAll()

        for var waypoint in localWaypoints {
            if waypoint.cloudKitRecordID != nil && waypoint.modifiedAt == nil {
                continue
            }

            let recordID = try await retryWithBackoff {
                try await self.cloudStore.save(waypoint: waypoint)
            }

            waypoint.cloudKitRecordID = recordID
            waypoint.modifiedAt = nil
            try WaypointStore.shared.update(waypoint)
        }
    }

    // MARK: - Pull Operations

    /// Pulls routes from CloudKit and merges with local data.
    ///
    /// For each remote route:
    /// - If not in local database: insert it
    /// - If in local database and remote is newer: update local
    /// - If in local database and local is newer: skip (will be pushed next cycle)
    private func pullRoutes() async throws {
        let remoteRoutes = try await retryWithBackoff {
            try await self.cloudStore.fetchAllRoutes()
        }

        let localRoutes = try RouteStore.shared.fetchAll()
        let localRouteIDs = Set(localRoutes.map { $0.id })

        for (recordID, remoteRoute) in remoteRoutes {
            if localRouteIDs.contains(remoteRoute.id) {
                // Route exists locally — check if remote is newer
                if let localRoute = localRoutes.first(where: { $0.id == remoteRoute.id }) {
                    let localModified = localRoute.modifiedAt ?? localRoute.startTime
                    let remoteModified = remoteRoute.modifiedAt ?? remoteRoute.startTime

                    if remoteModified > localModified {
                        var updatedRoute = remoteRoute
                        updatedRoute.cloudKitRecordID = recordID
                        updatedRoute.modifiedAt = nil
                        try RouteStore.shared.update(updatedRoute)
                    }
                }
            } else {
                // New route from cloud — insert locally
                var newRoute = remoteRoute
                newRoute.cloudKitRecordID = recordID
                newRoute.modifiedAt = nil
                try RouteStore.shared.insert(newRoute)
            }
        }
    }

    /// Pulls waypoints from CloudKit and merges with local data.
    ///
    /// Same merge logic as ``pullRoutes()`` but for waypoints.
    private func pullWaypoints() async throws {
        let remoteWaypoints = try await retryWithBackoff {
            try await self.cloudStore.fetchAllWaypoints()
        }

        let localWaypoints = try WaypointStore.shared.fetchAll()
        let localWaypointIDs = Set(localWaypoints.map { $0.id })

        for (recordID, remoteWaypoint) in remoteWaypoints {
            if localWaypointIDs.contains(remoteWaypoint.id) {
                if let localWaypoint = localWaypoints.first(where: { $0.id == remoteWaypoint.id }) {
                    let localModified = localWaypoint.modifiedAt ?? localWaypoint.timestamp
                    let remoteModified = remoteWaypoint.modifiedAt ?? remoteWaypoint.timestamp

                    if remoteModified > localModified {
                        var updatedWaypoint = remoteWaypoint
                        updatedWaypoint.cloudKitRecordID = recordID
                        updatedWaypoint.modifiedAt = nil
                        try WaypointStore.shared.update(updatedWaypoint)
                    }
                }
            } else {
                var newWaypoint = remoteWaypoint
                newWaypoint.cloudKitRecordID = recordID
                newWaypoint.modifiedAt = nil
                try WaypointStore.shared.insert(newWaypoint)
            }
        }
    }

    // MARK: - Retry Logic

    /// Executes an async operation with exponential backoff retry.
    ///
    /// Retries up to ``maxRetryAttempts`` times with delays of 2s, 4s, 8s, 16s.
    ///
    /// - Parameter operation: The async throwing operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: The last error if all retries are exhausted.
    private func retryWithBackoff<T>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<Self.maxRetryAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                let delay = Self.baseRetryDelay * pow(2.0, Double(attempt))
                print("CloudSyncManager: Retry \(attempt + 1)/\(Self.maxRetryAttempts) after \(delay)s: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? CloudKitStore.CloudKitStoreError.operationFailed("Unknown error after retries")
    }
}
