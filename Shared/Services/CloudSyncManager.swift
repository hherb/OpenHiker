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
import os

/// The outcome of the last iCloud sync, published for the UI (#78).
///
/// ``CloudSyncManager`` records every sync here. The iOS app shows a banner while
/// ``errors`` is not empty; macOS shows the state in the sidebar and in Settings.
@MainActor
final class CloudSyncStatus: ObservableObject {

    /// Shared instance that ``CloudSyncManager`` writes to and the views observe.
    static let shared = CloudSyncStatus()

    /// When a sync last finished with no errors, or `nil` if none has yet.
    @Published private(set) var lastSuccess: Date?

    /// One "part: reason" entry per part of the last sync that failed, or an
    /// "iCloud: reason" entry if the account check or subscription setup failed.
    /// Empty after a clean sync or after ``dismissErrors()``.
    @Published private(set) var errors: [String] = []

    /// Records the result of a sync.
    ///
    /// - Parameters:
    ///   - errors: The failures of this sync; empty if it succeeded.
    ///   - date: When the sync finished. Becomes ``lastSuccess`` if `errors` is empty.
    func record(errors: [String], at date: Date = Date()) {
        self.errors = errors
        if errors.isEmpty { lastSuccess = date }
    }

    /// Hides the current errors until the next sync reports new ones.
    func dismissErrors() {
        errors = []
    }
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
/// - Manual "Sync Now" / Retry (via ``performSync()``)
/// - CloudKit push notification (``handleRemoteNotification()``, not yet wired up)
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

    /// Logger for sync operations (debug-level for routine events).
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openhiker",
        category: "CloudSyncManager"
    )

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
    /// Errors from the account check or subscription setup are recorded in
    /// ``CloudSyncStatus`` as an "iCloud: reason" entry.
    func syncOnLaunch() async {
        do {
            isAvailable = try await cloudStore.isAccountAvailable()
            guard isAvailable else {
                Self.logger.info("iCloud account not available, skipping sync")
                return
            }

            // Set up push notification subscriptions (may partially fail on first
            // launch if record types haven't been created yet — that's OK)
            try await cloudStore.setupSubscriptions()

            // Perform initial sync (this creates record types via first push)
            await performSync()

            // Retry subscriptions if they failed due to missing record types.
            // After the sync above, record types should now exist.
            if await !cloudStore.subscriptionsReady {
                Self.logger.debug("Retrying subscriptions after initial sync")
                try await cloudStore.setupSubscriptions()
            }
        } catch {
            await Self.report(["iCloud: \(error.localizedDescription)"], to: CloudSyncStatus.shared)
        }
    }

    /// Performs a full bidirectional sync: for saved hikes, waypoints and planned routes
    /// in turn, push local changes, then pull remote changes.
    ///
    /// Each upload and each download is its own step, so a failure in one (for example
    /// an unreadable `planned_routes/` folder) does not stop the others (#81). Skips if
    /// a sync is already in progress. Records the result in ``CloudSyncStatus``.
    ///
    /// If iCloud was not available at the last check (for example the launch check
    /// failed while offline), this reruns ``syncOnLaunch()`` instead, so Retry and
    /// "Sync Now" check the account again rather than doing nothing.
    func performSync() async {
        guard isAvailable else {
            await syncOnLaunch()
            return
        }
        guard !isSyncing else {
            Self.logger.debug("Sync already in progress, skipping")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        // When subscriptions aren't ready the CloudKit schema may not exist
        // (e.g. fresh container or development schema reset). Force-push all
        // local records so the record types get auto-created server-side.
        let forceAll = await !cloudStore.subscriptionsReady
        if forceAll {
            Self.logger.debug("Schema not ready, force-pushing all local records")
        }

        // Upload and download are separate steps: a record that fails to upload must
        // not block downloads. Pulls never delete and keep newer local edits.
        let errors = await Self.runSteps([
            (Self.upload(Self.savedHikesLabel), { try await self.pushRoutes(forceAll: forceAll) }),
            (Self.download(Self.savedHikesLabel), { try await self.pullRoutes() }),
            (Self.upload(Self.waypointsLabel), { try await self.pushWaypoints(forceAll: forceAll) }),
            (Self.download(Self.waypointsLabel), { try await self.pullWaypoints() }),
            (Self.upload(Self.plannedRoutesLabel), { try await self.pushPlannedRoutes(forceAll: forceAll) }),
            (Self.download(Self.plannedRoutesLabel), { try await self.pullPlannedRoutes() }),
        ])
        await Self.report(errors, to: CloudSyncStatus.shared)
    }

    /// Called when a CloudKit push notification is received.
    ///
    /// Triggers a pull-only sync to fetch the changed records, with the same independent
    /// steps and reporting as ``performSync()``.
    func handleRemoteNotification() async {
        guard isAvailable else { return }
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        let errors = await Self.runSteps([
            (Self.download(Self.savedHikesLabel), { try await self.pullRoutes() }),
            (Self.download(Self.waypointsLabel), { try await self.pullWaypoints() }),
            (Self.download(Self.plannedRoutesLabel), { try await self.pullPlannedRoutes() }),
        ])
        // shortcut: a clean pull here clears earlier upload errors and sets lastSuccess
        // although nothing was pushed; nothing calls this yet, so merge instead of
        // replace when it gets wired to push notifications.
        await Self.report(errors, to: CloudSyncStatus.shared)
    }

    // MARK: - Steps and Reporting

    /// User-facing name of the saved-hikes part of a sync, used in error entries.
    static let savedHikesLabel = "Saved hikes"

    /// User-facing name of the waypoints part of a sync, used in error entries.
    static let waypointsLabel = "Waypoints"

    /// User-facing name of the planned-routes part of a sync, used in error entries.
    static let plannedRoutesLabel = "Planned routes"

    /// Label of the upload half of a part, e.g. "Waypoints (upload)".
    static func upload(_ part: String) -> String { "\(part) (upload)" }

    /// Label of the download half of a part, e.g. "Waypoints (download)".
    static func download(_ part: String) -> String { "\(part) (download)" }

    /// Runs every step in order, even after an earlier one fails.
    ///
    /// - Parameter steps: Pairs of a user-facing label and the work to run.
    /// - Returns: One "label: reason" entry per step that threw, in step order.
    static func runSteps(
        _ steps: [(label: String, run: () async throws -> Void)]
    ) async -> [String] {
        var errors: [String] = []
        for step in steps {
            do {
                try await step.run()
            } catch {
                errors.append("\(step.label): \(error.localizedDescription)")
            }
        }
        return errors
    }

    /// Logs the result of a sync and publishes it for the UI.
    ///
    /// - Parameters:
    ///   - errors: The failures of this sync; empty if it succeeded.
    ///   - status: Where to publish it; the app passes ``CloudSyncStatus/shared``.
    static func report(_ errors: [String], to status: CloudSyncStatus) async {
        if errors.isEmpty {
            logger.info("Sync completed successfully")
        }
        for entry in errors {
            logger.error("Sync error: \(entry)")
        }
        await status.record(errors: errors)
    }

    // MARK: - Push Operations

    /// Pushes locally modified routes to CloudKit.
    ///
    /// Uploads routes that either:
    /// - Have no `cloudKitRecordID` (never synced)
    /// - Have a `modifiedAt` timestamp (locally modified)
    ///
    /// When `forceAll` is true, pushes every local record regardless of sync
    /// state. This is used to re-initialize the CloudKit schema after a reset.
    ///
    /// After successful upload, updates the local record with the CloudKit record ID.
    private func pushRoutes(forceAll: Bool = false) async throws {
        let localRoutes = try RouteStore.shared.fetchAll()

        for var route in localRoutes {
            // Skip routes that are already synced and haven't been modified locally
            if !forceAll && route.cloudKitRecordID != nil && route.modifiedAt == nil {
                continue
            }

            let routeToSave = route
            let recordID = try await retryWithBackoff {
                try await self.cloudStore.save(route: routeToSave)
            }

            // Update local record with CloudKit ID
            route.cloudKitRecordID = recordID
            route.modifiedAt = nil // Clear modification flag
            try RouteStore.shared.update(route)
        }
    }

    /// Pushes locally modified waypoints to CloudKit.
    ///
    /// Same logic as ``pushRoutes(forceAll:)`` but for waypoints.
    private func pushWaypoints(forceAll: Bool = false) async throws {
        let localWaypoints = try WaypointStore.shared.fetchAll()

        for var waypoint in localWaypoints {
            if !forceAll && waypoint.cloudKitRecordID != nil && waypoint.modifiedAt == nil {
                continue
            }

            let waypointToSave = waypoint
            let recordID = try await retryWithBackoff {
                try await self.cloudStore.save(waypoint: waypointToSave)
            }

            waypoint.cloudKitRecordID = recordID
            waypoint.modifiedAt = nil
            try WaypointStore.shared.update(waypoint)
        }
    }

    /// Pushes locally modified planned routes to CloudKit.
    ///
    /// Same logic as ``pushRoutes(forceAll:)`` but for planned routes. Uses
    /// ``PlannedRouteStore`` (JSON file-based) instead of ``RouteStore`` (SQLite).
    private func pushPlannedRoutes(forceAll: Bool = false) async throws {
        let localRoutes = try loadLocalPlannedRoutes()

        for var route in localRoutes {
            // Skip routes that are already synced and haven't been modified locally
            if !forceAll && route.cloudKitRecordID != nil && route.modifiedAt == nil {
                continue
            }

            let routeToSave = route
            let recordID = try await retryWithBackoff {
                try await self.cloudStore.save(plannedRoute: routeToSave)
            }

            // Update local record with CloudKit ID
            route.cloudKitRecordID = recordID
            route.modifiedAt = nil
            try PlannedRouteStore.shared.save(route)
        }
    }

    /// Reads the local planned routes for a push or pull.
    ///
    /// Reads from disk rather than the in-memory cache to avoid a race where
    /// syncOnLaunch() runs before loadAll()'s main-queue dispatch has populated
    /// the routes array. Unreadable route files are logged and left out. Pulling
    /// then treats them as missing, so if the cloud has a route with the same ID
    /// (file `<id>.json`), its copy replaces the broken file. Other broken files
    /// stay, and the route list shows them from its last ``PlannedRouteStore/loadAll()``.
    ///
    /// - Returns: Every local planned route that could be read.
    /// - Throws: If the routes folder exists but cannot be listed. The planned-routes
    ///   step of the sync stops (the other parts still run), so cloud copies never
    ///   overwrite local routes that only look missing.
    private func loadLocalPlannedRoutes() throws -> [PlannedRoute] {
        let result = try PlannedRouteStore.shared.loadAllFromDisk()
        for entry in result.skippedFiles {
            Self.logger.error("Planned routes: skipped local file \(entry)")
        }
        return result.routes
    }

    // MARK: - Pull Operations

    /// Pulls routes from CloudKit and merges with local data.
    ///
    /// For each remote route:
    /// - If not in local database: insert it
    /// - If in local database and remote is newer: update local
    /// - If in local database and local is newer: skip (will be pushed next cycle)
    ///
    /// Cloud records that could not be read are reported by throwing after the merge,
    /// so the readable ones still sync (#85).
    private func pullRoutes() async throws {
        let remoteRoutes = try await retryWithBackoff {
            try await self.cloudStore.fetchAllRoutes()
        }

        let localRoutes = try RouteStore.shared.fetchAll()
        let localRouteIDs = Set(localRoutes.map { $0.id })

        for (recordID, remoteRoute) in remoteRoutes.items {
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
        // After the merge, so one unreadable record does not block the readable ones.
        try remoteRoutes.throwIfSkipped()
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

        for (recordID, remoteWaypoint) in remoteWaypoints.items {
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
        // After the merge, so one unreadable record does not block the readable ones.
        try remoteWaypoints.throwIfSkipped()
    }

    /// Pulls planned routes from CloudKit and merges with local data.
    ///
    /// Same merge logic as ``pullRoutes()`` but for planned routes. Uses
    /// `createdAt` as the fallback timestamp for conflict resolution since
    /// planned routes don't have a `startTime`.
    ///
    /// Posts ``Notification.Name/plannedRouteSyncReceived`` when new routes
    /// are pulled so views can refresh.
    private func pullPlannedRoutes() async throws {
        let remotePlannedRoutes = try await retryWithBackoff {
            try await self.cloudStore.fetchAllPlannedRoutes()
        }

        let localRoutes = try loadLocalPlannedRoutes()
        let localRouteIDs = Set(localRoutes.map { $0.id })
        var didChange = false

        for (recordID, remoteRoute) in remotePlannedRoutes.items {
            if localRouteIDs.contains(remoteRoute.id) {
                // Route exists locally — check if remote is newer
                if let localRoute = localRoutes.first(where: { $0.id == remoteRoute.id }) {
                    let localModified = localRoute.modifiedAt ?? localRoute.createdAt
                    let remoteModified = remoteRoute.modifiedAt ?? remoteRoute.createdAt

                    if remoteModified > localModified {
                        var updatedRoute = remoteRoute
                        updatedRoute.cloudKitRecordID = recordID
                        updatedRoute.modifiedAt = nil
                        try PlannedRouteStore.shared.save(updatedRoute)
                        didChange = true
                    }
                }
            } else {
                // New route from cloud — insert locally
                var newRoute = remoteRoute
                newRoute.cloudKitRecordID = recordID
                newRoute.modifiedAt = nil
                try PlannedRouteStore.shared.save(newRoute)
                didChange = true
            }
        }

        if didChange {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .plannedRouteSyncReceived,
                    object: nil
                )
            }
        }
        // After the merge, so one unreadable record does not block the readable ones.
        try remotePlannedRoutes.throwIfSkipped()
    }

    // MARK: - Retry Logic

    /// Executes an async operation with exponential backoff retry.
    ///
    /// Makes up to ``maxRetryAttempts`` attempts, waiting 2s, 4s, 8s between them. It
    /// does not wait after the last attempt, so the error reaches the user sooner.
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
                guard attempt < Self.maxRetryAttempts - 1 else { break }
                let delay = Self.baseRetryDelay * pow(2.0, Double(attempt))
                Self.logger.debug("Retry \(attempt + 1)/\(Self.maxRetryAttempts) after \(delay)s: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? CloudKitStore.CloudKitStoreError.operationFailed("Unknown error after retries")
    }
}
