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

/// The state of iCloud sync, published for the UI (#78, #84).
///
/// ``CloudSyncManager`` records every sync here. The iOS app shows a red banner while
/// ``errors`` is not empty and a grey one while ``accountNotice`` is set; macOS shows
/// the state in the sidebar and in Settings. macOS always shows ``isSyncing``; iOS shows
/// it as a spinner in place of Retry in the red banner.
@MainActor
final class CloudSyncStatus: ObservableObject {

    /// Shared instance that ``CloudSyncManager`` writes to and the views observe.
    static let shared = CloudSyncStatus()

    /// `UserDefaults` key of the account notice the user dismissed.
    static let dismissedAccountNoticeKey = "cloudSync.dismissedAccountNotice"

    /// When a sync last finished with no errors, or `nil` if none has yet.
    @Published private(set) var lastSuccess: Date?

    /// One "part: reason" entry per part of the last sync that failed, or an
    /// "iCloud: reason" entry if the account check or subscription setup failed.
    /// Empty after a clean sync or after ``dismissErrors()``.
    @Published private(set) var errors: [String] = []

    /// Whether a sync (or the account check before it) is running, so Retry and
    /// "Sync Now" show progress instead of seeming to do nothing.
    @Published private(set) var isSyncing = false

    /// Why iCloud is off when no account is signed in, or `nil`. Not an error: the user
    /// may not use iCloud. `nil` too once the user dismissed this notice, until a sync
    /// finds the account status changed.
    @Published private(set) var accountNotice: String?

    /// Where the dismissed notice is remembered across launches.
    private let defaults: UserDefaults

    /// Creates a status.
    ///
    /// - Parameter defaults: Where a dismissed account notice is remembered; tests pass
    ///   their own suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Marks a sync as started. ``record(errors:at:)`` or ``showAccountNotice(_:)`` ends it.
    func beginSync() {
        isSyncing = true
    }

    /// Records the result of a sync and marks it as finished.
    ///
    /// - Parameters:
    ///   - errors: The failures of this sync; empty if it succeeded.
    ///   - date: When the sync finished. Becomes ``lastSuccess`` if `errors` is empty.
    func record(errors: [String], at date: Date = Date()) {
        self.errors = errors
        if errors.isEmpty { lastSuccess = date }
        isSyncing = false
    }

    /// Hides the current errors until the next sync reports new ones.
    func dismissErrors() {
        errors = []
    }

    /// Records that no iCloud account is signed in, so there was nothing to sync.
    ///
    /// Clears earlier sync errors (they no longer apply) without touching
    /// ``lastSuccess``, and ends the sync. Shows `notice` unless the user dismissed it.
    ///
    /// - Parameter notice: The text to show, from ``CloudKitStore/AccountCheck/notSignedIn(_:)``.
    func showAccountNotice(_ notice: String) {
        errors = []
        isSyncing = false
        accountNotice = defaults.string(forKey: Self.dismissedAccountNoticeKey) == notice ? nil : notice
    }

    /// Records that the account is no longer "not signed in": hides the notice and
    /// forgets its dismissal, so a later sign-out shows it again.
    func clearAccountNotice() {
        accountNotice = nil
        defaults.removeObject(forKey: Self.dismissedAccountNoticeKey)
    }

    /// Hides the account notice until the account status changes, across launches.
    func dismissAccountNotice() {
        if let accountNotice {
            defaults.set(accountNotice, forKey: Self.dismissedAccountNoticeKey)
        }
        accountNotice = nil
    }
}

/// Coordinates bidirectional sync between local SQLite stores and iCloud via CloudKit.
///
/// Implements a "last-writer-wins" conflict resolution strategy using `modifiedAt`
/// timestamps. The sync flow is:
///
/// 1. **Deletions from other devices**: Every deleted record leaves a tombstone in
///    iCloud (``CloudKitStore/Tombstone``). Each sync first deletes the synced local
///    items that have one, even if they have unsynced edits: deletion wins, as on
///    Android (#91). Uploads and pulls skip tombstoned records, and uploads wait until
///    the tombstones were read in this sync. A never-synced item under a tombstoned name
///    was added again (a re-downloaded community route, a P2P import, a watch hike), so
///    its upload deletes the tombstone instead of the item.
/// 2. **Delete**: Items deleted on this device are queued in ``CloudDeletionQueue``
///    by the local stores. Each sync saves a tombstone for each and then deletes its
///    record, and uploads and pulls skip queued records (#89).
/// 3. **Push**: Upload local records that have no `cloudKitRecordID` or whose
///    `modifiedAt` is newer than the remote `CKRecord.modificationDate`.
/// 4. **Pull**: Download remote records that don't exist locally or are newer
///    than the local `modifiedAt`.
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

    /// Longest server-requested retry delay a sync waits for, in seconds. A longer one
    /// fails the step at once, so the spinner does not run for minutes; the user can
    /// retry later.
    static let maxServerRetryDelay: TimeInterval = 30

    // MARK: - Error Types

    /// Errors of the sync steps themselves, as opposed to CloudKit's.
    enum SyncError: Error, LocalizedError, Equatable {
        /// The tombstones could not be read in this sync, so uploads wait (#91).
        case deletionsNotChecked
        /// Local copies of items deleted on another device could not be deleted; one
        /// "item: reason" entry each.
        case localDeletesFailed([String])
        /// iCloud copies of these planned routes were not downloaded, because their local
        /// files exist but cannot be read (#80); one file name each.
        case unreadableLocalFiles([String])
        /// A step found several problems; ``runSteps(_:)`` reports one entry per reason,
        /// so none hides another (#104).
        case several([String])

        var errorDescription: String? {
            switch self {
            case .several(let reasons):
                return reasons.joined(separator: "; ")
            case .deletionsNotChecked:
                return "Skipped until deletions from other devices can be checked"
            case .localDeletesFailed(let entries):
                return "\(entries.count) local copies could not be deleted: \(entries.joined(separator: "; "))"
            case .unreadableLocalFiles(let files):
                return "\(files.count) iCloud routes not downloaded because the local files cannot be read: "
                    + files.joined(separator: ", ")
                    + ". Delete the unreadable files in the route list to get the iCloud copies."
            }
        }
    }

    /// What an upload does with one local item (see ``uploadAction(cloudKitRecordID:id:queued:tombstoned:)``).
    enum UploadAction: Equatable {
        /// Upload it.
        case upload
        /// Leave it alone: it was deleted here or on another device.
        case skip
        /// Delete its tombstone, then upload it: the user added a deleted item again.
        case restoreThenUpload
    }

    // MARK: - Properties

    /// The CloudKit store for remote operations.
    private let cloudStore: CloudKitStore

    /// Records deleted on this device that iCloud has not deleted yet.
    private let deletionQueue = CloudDeletionQueue.shared

    /// Record names with a tombstone, by record type, read by this sync; `nil` until its
    /// tombstone fetch succeeds, so uploads never run on an old or missing set.
    private var remoteDeletions: [String: Set<String>]?

    /// Lets one sync or pull run at a time. A ``performSync()`` or push-notification pull
    /// asked for while one runs makes a full sync run once more when it ends, so a request
    /// made mid-sync (for example after deleting unreadable route files) is never lost
    /// (#104, #107).
    private var runs = RunCoalescer()

    /// Whether the last account check found an account that can sync.
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

    /// Performs the first sync after app launch; see ``performSync()``.
    ///
    /// Call this once on app launch.
    func syncOnLaunch() async {
        await performSync()
    }

    /// Checks the iCloud account and publishes what it found.
    ///
    /// - Returns: Whether the account can sync.
    private func checkAccount() async -> Bool {
        let check: Result<CloudKitStore.AccountCheck, Error>
        do {
            check = .success(try await cloudStore.checkAccount())
        } catch {
            check = .failure(error)
        }
        isAvailable = await Self.publish(check, to: CloudSyncStatus.shared)
        return isAvailable
    }

    /// Publishes the result of an account check in `status` (#84).
    ///
    /// No account shows the neutral notice and no error. An account that cannot sync, or
    /// a failed check, is an "iCloud: reason" error. Each ends the sync in `status`
    /// except `.available`, whose sync goes on.
    ///
    /// - Parameters:
    ///   - check: What ``CloudKitStore/checkAccount()`` returned or threw.
    ///   - status: Where to publish it; the app passes ``CloudSyncStatus/shared``.
    /// - Returns: Whether the account can sync.
    static func publish(
        _ check: Result<CloudKitStore.AccountCheck, Error>,
        to status: CloudSyncStatus
    ) async -> Bool {
        switch check {
        case .success(.available):
            await status.clearAccountNotice()
            return true
        case .success(.notSignedIn(let notice)):
            logger.info("iCloud account not signed in, skipping sync")
            await status.showAccountNotice(notice)
            return false
        case .success(.unusable(let reason)):
            await status.clearAccountNotice()
            await report(["iCloud: \(reason)"], to: status)
            return false
        case .failure(let error):
            await report(["iCloud: \(error.localizedDescription)"], to: status)
            return false
        }
    }

    /// Performs a full bidirectional sync: for saved hikes, waypoints and planned routes
    /// in turn, push local changes, then pull remote changes.
    ///
    /// It checks the iCloud account first, every time, so signing in or out while the
    /// app runs is noticed at the next sync (#84); with no usable account it publishes
    /// the notice or error and stops. Each upload and each download is its own step, so
    /// a failure in one (for example an unreadable `planned_routes/` folder) does not
    /// stop the others (#81). If a sync is already in progress, it runs once more when
    /// that one ends, however often this was called meanwhile (#104);
    /// ``CloudSyncStatus/isSyncing`` shows the running sync to the user. Records the result in
    /// ``CloudSyncStatus``.
    ///
    /// While change-notification subscriptions are missing, it tries to create them
    /// before the steps (so existing ones are found and records are not force-pushed)
    /// and again after them (a first push may just have created the record types), and
    /// reports what still fails as "iCloud: change notifications unavailable (…)" (#86).
    func performSync() async {
        guard runs.begin() else {
            Self.logger.debug("Sync already in progress, running again when it ends")
            return
        }
        repeat {
            await syncOnce()
        } while runs.endRun()
    }

    /// One full sync run, for ``performSync()`` and the rerun after
    /// ``handleRemoteNotification()``; the caller holds `runs`.
    private func syncOnce() async {
        await CloudSyncStatus.shared.beginSync()

        guard await checkAccount() else { return }
        if await !cloudStore.subscriptionsReady {
            _ = await cloudStore.setupSubscriptions()
        }

        // When subscriptions aren't ready the CloudKit schema may not exist
        // (e.g. fresh container or development schema reset). Force-push all
        // local records so the record types get auto-created server-side.
        let forceAll = await !cloudStore.subscriptionsReady
        if forceAll {
            Self.logger.debug("Schema not ready, force-pushing all local records")
        }

        // Each part is a separate step, so a failure in one does not block the next.
        // Remote deletions run first; if they fail, uploads fail too rather than bring a
        // deleted item back. Pulls skip deleted records and keep newer local edits.
        var errors = await Self.runSteps([
            (Self.remoteDeletionsLabel, { try await self.applyRemoteDeletions() }),
            (Self.delete(Self.savedHikesLabel), { try await self.pushDeletions(CloudKitStore.savedRouteRecordType) }),
            (Self.upload(Self.savedHikesLabel), { try await self.pushRoutes(forceAll: forceAll) }),
            (Self.download(Self.savedHikesLabel), { try await self.pullRoutes() }),
            (Self.delete(Self.waypointsLabel), { try await self.pushDeletions(CloudKitStore.waypointRecordType) }),
            (Self.upload(Self.waypointsLabel), { try await self.pushWaypoints(forceAll: forceAll) }),
            (Self.download(Self.waypointsLabel), { try await self.pullWaypoints() }),
            (Self.delete(Self.plannedRoutesLabel), { try await self.pushDeletions(CloudKitStore.plannedRouteRecordType) }),
            (Self.upload(Self.plannedRoutesLabel), { try await self.pushPlannedRoutes(forceAll: forceAll) }),
            (Self.download(Self.plannedRoutesLabel), { try await self.pullPlannedRoutes() }),
        ])
        // After the steps: a first push may just have created the record types.
        if await !cloudStore.subscriptionsReady,
           let entry = Self.subscriptionsError(await cloudStore.setupSubscriptions()) {
            errors.append(entry)
        }
        await Self.report(errors, to: CloudSyncStatus.shared)
    }

    /// The error entry for change-notification subscriptions that could not be created.
    ///
    /// - Parameter failures: What ``CloudKitStore/setupSubscriptions()`` returned.
    /// - Returns: "iCloud: change notifications unavailable (failures)", or `nil` if
    ///   nothing failed.
    static func subscriptionsError(_ failures: [String]) -> String? {
        guard !failures.isEmpty else { return nil }
        return "iCloud: change notifications unavailable (\(failures.joined(separator: "; ")))"
    }

    /// Called when a CloudKit push notification is received.
    ///
    /// Triggers a pull-only sync to fetch the changed records, with the same independent
    /// steps and reporting as ``performSync()``. While a sync or pull runs, a full sync
    /// runs once more when it ends instead, which pulls the change too (#107).
    func handleRemoteNotification() async {
        guard isAvailable else { return }
        guard runs.begin() else {
            Self.logger.debug("Sync in progress, pulling the notified change when it runs again")
            return
        }

        await CloudSyncStatus.shared.beginSync()

        let errors = await Self.runSteps([
            (Self.remoteDeletionsLabel, { try await self.applyRemoteDeletions() }),
            (Self.download(Self.savedHikesLabel), { try await self.pullRoutes() }),
            (Self.download(Self.waypointsLabel), { try await self.pullWaypoints() }),
            (Self.download(Self.plannedRoutesLabel), { try await self.pullPlannedRoutes() }),
        ])
        // shortcut: a clean pull here clears earlier upload errors and sets lastSuccess
        // although nothing was pushed; nothing calls this yet, so merge instead of
        // replace when it gets wired to push notifications.
        await Self.report(errors, to: CloudSyncStatus.shared)
        // A sync asked for meanwhile still runs (#104).
        while runs.endRun() { await syncOnce() }
    }

    // MARK: - Steps and Reporting

    /// User-facing name of the saved-hikes part of a sync, used in error entries.
    static let savedHikesLabel = "Saved hikes"

    /// User-facing name of the waypoints part of a sync, used in error entries.
    static let waypointsLabel = "Waypoints"

    /// User-facing name of the planned-routes part of a sync, used in error entries.
    static let plannedRoutesLabel = "Planned routes"

    /// User-facing name of the step that applies other devices' deletions.
    static let remoteDeletionsLabel = "Deletions from other devices"

    /// Label of the upload half of a part, e.g. "Waypoints (upload)".
    static func upload(_ part: String) -> String { "\(part) (upload)" }

    /// Label of the download half of a part, e.g. "Waypoints (download)".
    static func download(_ part: String) -> String { "\(part) (download)" }

    /// Label of the deletion step of a part, e.g. "Waypoints (delete)".
    static func delete(_ part: String) -> String { "\(part) (delete)" }

    /// Runs every step in order, even after an earlier one fails.
    ///
    /// - Parameter steps: Pairs of a user-facing label and the work to run.
    /// - Returns: One "label: reason" entry per step that threw, or one per reason for
    ///   ``SyncError/several(_:)``, in step order.
    static func runSteps(
        _ steps: [(label: String, run: () async throws -> Void)]
    ) async -> [String] {
        var errors: [String] = []
        for step in steps {
            do {
                try await step.run()
            } catch SyncError.several(let reasons) {
                errors += reasons.map { "\(step.label): \($0)" }
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

    /// Deletes from iCloud the records of one type that were deleted on this device.
    ///
    /// Saves each record's tombstone before deleting it, so other devices learn of the
    /// deletion (#91) and a record is never gone without one.
    ///
    /// - Parameter recordType: The CloudKit record type, e.g. ``CloudKitStore/waypointRecordType``.
    /// - Throws: The first deletion that fails after retries; it and the untried records
    ///   stay queued.
    private func pushDeletions(_ recordType: String) async throws {
        try await Self.pushDeletions(recordType: recordType, queue: deletionQueue) { recordID in
            let tombstone = CloudKitStore.Tombstone(recordType: recordType, recordName: recordID)
            try await self.retryWithBackoff { try await self.cloudStore.save(tombstone: tombstone) }
            try await self.retryWithBackoff { try await self.cloudStore.delete(recordID: recordID) }
        }
    }

    /// Runs `delete` for each queued record of one type, oldest first, and removes each
    /// record from the queue once its deletion succeeded.
    ///
    /// Stops at the first failure, so an offline sync makes one failed attempt rather
    /// than one per record. The failed record moves to the back of the queue, so a
    /// record that keeps failing does not block the others on later syncs.
    ///
    /// - Parameters:
    ///   - recordType: The CloudKit record type whose queue to work through.
    ///   - queue: The deletion queue; the app uses ``CloudDeletionQueue/shared``.
    ///   - delete: Deletes one record from iCloud by record name.
    /// - Throws: The first error from `delete`; that record and the untried ones stay
    ///   queued for the next sync.
    static func pushDeletions(
        recordType: String,
        queue: CloudDeletionQueue,
        delete: (String) async throws -> Void
    ) async throws {
        for recordID in queue.pending(recordType: recordType) {
            do {
                try await delete(recordID)
                queue.remove(recordID: recordID, recordType: recordType)
            } catch {
                queue.moveToBack(recordID: recordID, recordType: recordType)
                throw error
            }
        }
    }

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
        let tombstoned = try tombstonesForUpload(CloudKitStore.savedRouteRecordType)

        for var route in localRoutes {
            // Skip routes that are already synced and haven't been modified locally
            if !forceAll && route.cloudKitRecordID != nil && route.modifiedAt == nil {
                continue
            }
            guard try await shouldUpload(
                CloudKitStore.savedRouteRecordType, cloudKitRecordID: route.cloudKitRecordID, id: route.id, tombstoned: tombstoned
            ) else { continue }

            let routeToSave = route
            let recordID = try await retryWithBackoff {
                try await self.cloudStore.save(route: routeToSave)
            }

            // Update local record with CloudKit ID
            route.cloudKitRecordID = recordID
            route.modifiedAt = nil // Clear modification flag
            do {
                try RouteStore.shared.update(route)
            } catch RouteStoreError.routeNotFound where isQueuedForDeletion(recordID, CloudKitStore.savedRouteRecordType) {
                // Deleted while the upload was in flight; the next sync deletes the record.
            }
        }
    }

    /// Pushes locally modified waypoints to CloudKit.
    ///
    /// Same logic as ``pushRoutes(forceAll:)`` but for waypoints.
    private func pushWaypoints(forceAll: Bool = false) async throws {
        let localWaypoints = try WaypointStore.shared.fetchAll()
        let tombstoned = try tombstonesForUpload(CloudKitStore.waypointRecordType)

        for var waypoint in localWaypoints {
            if !forceAll && waypoint.cloudKitRecordID != nil && waypoint.modifiedAt == nil {
                continue
            }
            guard try await shouldUpload(
                CloudKitStore.waypointRecordType, cloudKitRecordID: waypoint.cloudKitRecordID, id: waypoint.id, tombstoned: tombstoned
            ) else { continue }

            let waypointToSave = waypoint
            let recordID = try await retryWithBackoff {
                try await self.cloudStore.save(waypoint: waypointToSave)
            }

            waypoint.cloudKitRecordID = recordID
            waypoint.modifiedAt = nil
            do {
                try WaypointStore.shared.update(waypoint)
            } catch WaypointStoreError.waypointNotFound where isQueuedForDeletion(recordID, CloudKitStore.waypointRecordType) {
                // Deleted while the upload was in flight; the next sync deletes the record.
            }
        }
    }

    /// Pushes locally modified planned routes to CloudKit.
    ///
    /// Same logic as ``pushRoutes(forceAll:)`` but for planned routes. Uses
    /// ``PlannedRouteStore`` (JSON file-based) instead of ``RouteStore`` (SQLite).
    private func pushPlannedRoutes(forceAll: Bool = false) async throws {
        let localRoutes = try loadLocalPlannedRoutes().routes
        let tombstoned = try tombstonesForUpload(CloudKitStore.plannedRouteRecordType)

        for var route in localRoutes {
            // Skip routes that are already synced and haven't been modified locally
            if !forceAll && route.cloudKitRecordID != nil && route.modifiedAt == nil {
                continue
            }
            guard try await shouldUpload(
                CloudKitStore.plannedRouteRecordType, cloudKitRecordID: route.cloudKitRecordID, id: route.id, tombstoned: tombstoned
            ) else { continue }

            let routeToSave = route
            let recordID = try await retryWithBackoff {
                try await self.cloudStore.save(plannedRoute: routeToSave)
            }

            // Writing the file back would bring the deleted route back on this device.
            if isQueuedForDeletion(recordID, CloudKitStore.plannedRouteRecordType) { continue }

            // Update local record with CloudKit ID
            route.cloudKitRecordID = recordID
            route.modifiedAt = nil
            try PlannedRouteStore.shared.save(route)
            // Deleted between the check above and the save, which brought the file back.
            if isQueuedForDeletion(recordID, CloudKitStore.plannedRouteRecordType) {
                try PlannedRouteStore.shared.delete(id: route.id)
            }
        }
    }

    /// Whether an item was deleted on this device while its upload was in flight.
    ///
    /// The upload then must not write the item back (#89): its record is already queued
    /// for deletion, and the next sync deletes the record it just uploaded. Saved hikes
    /// and waypoints ask after their write-back failed with "not found"; planned routes
    /// ask before and after theirs, since saving a file recreates it (#93).
    ///
    /// - Parameters:
    ///   - recordID: The CloudKit record name the upload returned.
    ///   - recordType: The CloudKit record type of the item.
    /// - Returns: `true` if the record is in ``CloudDeletionQueue``.
    private func isQueuedForDeletion(_ recordID: String, _ recordType: String) -> Bool {
        deletionQueue.pending(recordType: recordType).contains(recordID)
    }

    /// The record names of one type that pulls must skip: deleted on this device and not
    /// yet in iCloud, or tombstoned (as far as this sync could read the tombstones).
    ///
    /// - Parameter recordType: The CloudKit record type.
    /// - Returns: The record names to leave alone.
    private func recordNamesToSkip(_ recordType: String) -> Set<String> {
        Set(deletionQueue.pending(recordType: recordType)).union(remoteDeletions?[recordType] ?? [])
    }

    /// The tombstoned record names of one type, for an upload.
    ///
    /// - Parameter recordType: The CloudKit record type.
    /// - Returns: The names tombstoned in this sync's fetch.
    /// - Throws: ``SyncError/deletionsNotChecked`` if this sync could not read the
    ///   tombstones: uploading then could bring back an item deleted on another device.
    private func tombstonesForUpload(_ recordType: String) throws -> Set<String> {
        guard let remoteDeletions else { throw SyncError.deletionsNotChecked }
        return remoteDeletions[recordType] ?? []
    }

    /// Decides whether to upload one local item, deleting its tombstone first if the
    /// user added a deleted item again.
    ///
    /// - Parameters:
    ///   - recordType: The CloudKit record type of the item.
    ///   - cloudKitRecordID: The item's record name, or `nil` if this device never synced it.
    ///   - id: The item's UUID.
    ///   - tombstoned: This record type's tombstoned names, from ``tombstonesForUpload(_:)``.
    /// - Returns: `true` to upload the item.
    /// - Throws: If its tombstone cannot be deleted after retries.
    private func shouldUpload(
        _ recordType: String,
        cloudKitRecordID: String?,
        id: UUID,
        tombstoned: Set<String>
    ) async throws -> Bool {
        let queued = Set(deletionQueue.pending(recordType: recordType))
        switch Self.uploadAction(cloudKitRecordID: cloudKitRecordID, id: id, queued: queued, tombstoned: tombstoned) {
        case .upload:
            return true
        case .skip:
            return false
        case .restoreThenUpload:
            let tombstone = CloudKitStore.Tombstone(recordType: recordType, recordName: id.uuidString)
            try await retryWithBackoff { try await self.cloudStore.delete(tombstone: tombstone) }
            remoteDeletions?[recordType]?.remove(id.uuidString)
            Self.logger.info("\(recordType) \(id.uuidString) was added again here; removed its tombstone")
            return true
        }
    }

    /// What an upload does with one local item, given the deletions this sync knows of.
    ///
    /// The record name is the item's `cloudKitRecordID`, or its UUID if this device never
    /// synced it. A queued name was deleted here, and a tombstoned name was deleted on some
    /// device. A tombstoned item that was never synced was added again (a re-downloaded
    /// community route, a P2P import, a watch hike), so it undoes the deletion.
    ///
    /// - Parameters:
    ///   - cloudKitRecordID: The item's record name, or `nil` if never synced.
    ///   - id: The item's UUID.
    ///   - queued: Record names in ``CloudDeletionQueue`` for this type.
    ///   - tombstoned: Record names with a tombstone for this type.
    /// - Returns: Whether to upload, skip, or restore and upload the item.
    static func uploadAction(
        cloudKitRecordID: String?,
        id: UUID,
        queued: Set<String>,
        tombstoned: Set<String>
    ) -> UploadAction {
        let name = cloudKitRecordID ?? id.uuidString
        if queued.contains(name) { return .skip }
        guard tombstoned.contains(name) else { return .upload }
        return cloudKitRecordID == nil ? .restoreThenUpload : .skip
    }

    /// Whether a local item must be deleted because another device deleted it.
    ///
    /// Only synced items qualify: a never-synced item under a tombstoned name was added
    /// again, and its upload removes the tombstone (see ``uploadAction(cloudKitRecordID:id:queued:tombstoned:)``).
    ///
    /// - Parameters:
    ///   - cloudKitRecordID: The item's record name, or `nil` if never synced.
    ///   - tombstoned: Record names with a tombstone for the item's type.
    /// - Returns: `true` if the item is synced and its record is tombstoned.
    static func isDeletedRemotely(cloudKitRecordID: String?, tombstoned: Set<String>) -> Bool {
        cloudKitRecordID.map(tombstoned.contains) ?? false
    }

    /// Drops the fetched records that a pull must not merge (#93).
    ///
    /// - Parameters:
    ///   - items: The fetched records' names and decoded items.
    ///   - skipping: Record names deleted on this device or on another one.
    /// - Returns: The items whose record name is not in `skipping`, in order.
    static func itemsToMerge<Item>(
        _ items: [(recordID: String, item: Item)],
        skipping: Set<String>
    ) -> [(recordID: String, item: Item)] {
        items.filter { !skipping.contains($0.recordID) }
    }

    /// Groups tombstones by record type.
    ///
    /// - Parameter tombstones: The fetched tombstones.
    /// - Returns: For each record type, the names of its deleted records.
    static func recordNamesByType(_ tombstones: [CloudKitStore.Tombstone]) -> [String: Set<String>] {
        Dictionary(grouping: tombstones, by: \.recordType).mapValues { Set($0.map(\.recordName)) }
    }

    // MARK: - Remote Deletions

    /// Deletes the local items that were deleted on another device (#91).
    ///
    /// Fetches every tombstone and deletes each synced local hike, waypoint and planned
    /// route whose `cloudKitRecordID` has one, unsynced edits included (see
    /// ``isDeletedRemotely(cloudKitRecordID:tombstoned:)``). Deleting through the stores
    /// queues the record for deletion; the next "(delete)" step then saves the same
    /// tombstone and finds the record already gone, which costs two calls but deletes any
    /// copy an older app version uploaded again.
    ///
    /// One failed local delete does not stop the others; an item already deleted here
    /// counts as done. Each deletion is logged.
    ///
    /// - Throws: If the tombstones cannot be fetched (uploads in this sync then fail with
    ///   ``SyncError/deletionsNotChecked``), ``SyncError/localDeletesFailed(_:)`` if local
    ///   deletes failed, or the unreadable tombstones after the readable ones were applied.
    private func applyRemoteDeletions() async throws {
        remoteDeletions = nil
        let fetched = try await retryWithBackoff { try await self.cloudStore.fetchAllTombstones() }
        let tombstoned = Self.recordNamesByType(fetched.items.map(\.item))
        remoteDeletions = tombstoned

        var failures: [String] = []
        /// Deletes one local item; "not found" means the user deleted it here meanwhile.
        func deleteLocal(_ recordType: String, _ id: UUID, _ delete: (UUID) throws -> Void) {
            do {
                try delete(id)
                Self.logger.info("Deleted local \(recordType) \(id.uuidString): deleted on another device")
            } catch RouteStoreError.routeNotFound, WaypointStoreError.waypointNotFound {
                // Already gone.
            } catch {
                Self.logger.error("Cannot delete local \(recordType) \(id.uuidString): \(error.localizedDescription)")
                failures.append("\(recordType) \(id.uuidString): \(error.localizedDescription)")
            }
        }

        let routes = tombstoned[CloudKitStore.savedRouteRecordType] ?? []
        for route in try RouteStore.shared.fetchAll()
        where Self.isDeletedRemotely(cloudKitRecordID: route.cloudKitRecordID, tombstoned: routes) {
            deleteLocal(CloudKitStore.savedRouteRecordType, route.id, RouteStore.shared.delete(id:))
        }

        let waypoints = tombstoned[CloudKitStore.waypointRecordType] ?? []
        for waypoint in try WaypointStore.shared.fetchAll()
        where Self.isDeletedRemotely(cloudKitRecordID: waypoint.cloudKitRecordID, tombstoned: waypoints) {
            deleteLocal(CloudKitStore.waypointRecordType, waypoint.id, WaypointStore.shared.delete(id:))
        }

        let plannedRoutes = tombstoned[CloudKitStore.plannedRouteRecordType] ?? []
        let localPlanned = try loadLocalPlannedRoutes()
        for route in localPlanned.routes
        where Self.isDeletedRemotely(cloudKitRecordID: route.cloudKitRecordID, tombstoned: plannedRoutes) {
            deleteLocal(CloudKitStore.plannedRouteRecordType, route.id, PlannedRouteStore.shared.delete(id:))
        }
        failures += Self.deleteUnreadableRoutes(
            Self.unreadableRoutesToDelete(localPlanned.skippedFiles, tombstoned: plannedRoutes),
            in: PlannedRouteStore.shared
        )

        // Both problems are reported, so neither hides the other.
        var problems: [Error] = []
        if !failures.isEmpty { problems.append(SyncError.localDeletesFailed(failures)) }
        do { try fetched.throwIfSkipped() } catch { problems.append(error) }
        try Self.throwAll(problems)
    }

    /// The unreadable local planned-route files a tombstone deletes (#80, as Android #77).
    ///
    /// An unreadable file's record name is unknown, but one named `<uuid>.json` after a
    /// tombstoned UUID holds a route deleted on another device. Other names are kept.
    ///
    /// - Parameters:
    ///   - skipped: The local route files that could not be read.
    ///   - tombstoned: Planned-route record names with a tombstone.
    /// - Returns: The files to delete, in file order.
    static func unreadableRoutesToDelete(
        _ skipped: [PlannedRouteStore.SkippedFile],
        tombstoned: Set<String>
    ) -> [PlannedRouteStore.SkippedFile] {
        skipped.filter { $0.routeID.map { tombstoned.contains($0.uuidString) } ?? false }
    }

    /// Deletes unreadable planned-route files of routes deleted on another device, and logs
    /// each file it deleted, after a partial failure too (#80, #107).
    ///
    /// Files go by their URL, not ``PlannedRouteStore/delete(id:)``, which would miss a
    /// lowercase `<uuid>.json` on a case-sensitive volume (#107). The store calls
    /// `loadAll()`, so `unreadableFiles` stops naming the deleted files (#104).
    ///
    /// - Parameters:
    ///   - files: The files to delete, from ``unreadableRoutesToDelete(_:tombstoned:)``.
    ///   - store: The store holding them.
    /// - Returns: One failure line for the sync errors, or none if all were deleted.
    static func deleteUnreadableRoutes(
        _ files: [PlannedRouteStore.SkippedFile],
        in store: PlannedRouteStore
    ) -> [String] {
        guard !files.isEmpty else { return [] }
        let type = CloudKitStore.plannedRouteRecordType
        let deleted: [URL]
        var failures: [String] = []
        do {
            deleted = try store.deleteUnreadableFiles(files.map(\.url))
        } catch {
            if case let .notDeleted(_, partial)? = error as? PlannedRouteStore.DeleteUnreadableError {
                deleted = partial
            } else {
                deleted = []
            }
            logger.error("Cannot delete unreadable local \(type) files: \(error.localizedDescription)")
            failures.append("\(type) files: \(error.localizedDescription)")
        }
        for url in deleted {
            logger.info("Deleted unreadable local \(type) file \(url.lastPathComponent): deleted on another device")
        }
        return failures
    }

    /// Reads the local planned routes for a push or pull.
    ///
    /// Reads from disk rather than the in-memory cache to avoid a race where
    /// syncOnLaunch() runs before loadAll()'s main-queue dispatch has populated
    /// the routes array. Unreadable route files are logged and returned too. Sync
    /// never uploads them or writes a cloud copy over them, because the read failure
    /// may be temporary and the file may hold an unsynced edit (#80). The route list
    /// shows them and lets the user delete them.
    ///
    /// - Returns: Every local planned route that could be read, and the files that could not.
    /// - Throws: If the routes folder exists but cannot be listed. The planned-routes
    ///   step of the sync stops (the other parts still run), so cloud copies never
    ///   overwrite local routes that only look missing.
    private func loadLocalPlannedRoutes() throws -> PlannedRouteStore.LoadResult {
        let result = try PlannedRouteStore.shared.loadAllFromDisk()
        for entry in result.skippedFiles {
            Self.logger.error("Planned routes: skipped local file \(entry.message)")
        }
        return result
    }

    /// Splits the fetched planned routes into those a pull may merge and those it holds back
    /// because the local file of the same route exists but cannot be read (#80).
    ///
    /// - Parameters:
    ///   - items: The fetched records' names and decoded routes, already without deleted ones.
    ///   - unreadable: UUIDs of the routes whose local `<uuid>.json` cannot be read.
    /// - Returns: The routes to merge, in order, and the UUIDs held back.
    static func plannedRoutesToMerge(
        _ items: [(recordID: String, item: PlannedRoute)],
        unreadable: Set<UUID>
    ) -> (merge: [(recordID: String, item: PlannedRoute)], heldBack: [UUID]) {
        (items.filter { !unreadable.contains($0.item.id) },
         items.map(\.item.id).filter(unreadable.contains))
    }

    // MARK: - Pull Operations

    /// Pulls routes from CloudKit and merges with local data.
    ///
    /// For each remote route:
    /// - If not in local database: insert it
    /// - If in local database and remote is newer: update local
    /// - If in local database and local is newer: skip (will be pushed next cycle)
    /// - If deleted on this device and still queued in ``CloudDeletionQueue``, or
    ///   tombstoned by any device: skip
    ///
    /// Cloud records that could not be read are reported by throwing after the merge,
    /// so the readable ones still sync (#85).
    private func pullRoutes() async throws {
        let remoteRoutes = try await retryWithBackoff {
            try await self.cloudStore.fetchAllRoutes()
        }

        let localRoutes = try RouteStore.shared.fetchAll()
        let localRouteIDs = Set(localRoutes.map { $0.id })
        // Inserting a deleted record again would undo the deletion.
        let deleted = recordNamesToSkip(CloudKitStore.savedRouteRecordType)

        for (recordID, remoteRoute) in Self.itemsToMerge(remoteRoutes.items, skipping: deleted) {
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
        let deleted = recordNamesToSkip(CloudKitStore.waypointRecordType)

        for (recordID, remoteWaypoint) in Self.itemsToMerge(remoteWaypoints.items, skipping: deleted) {
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

        let local = try loadLocalPlannedRoutes()
        let localRoutes = local.routes
        let localRouteIDs = Set(localRoutes.map { $0.id })
        let deleted = recordNamesToSkip(CloudKitStore.plannedRouteRecordType)
        var didChange = false
        let (toMerge, heldBack) = Self.plannedRoutesToMerge(
            Self.itemsToMerge(remotePlannedRoutes.items, skipping: deleted),
            unreadable: Set(local.skippedFiles.compactMap(\.routeID))
        )

        for (recordID, remoteRoute) in toMerge {
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
        // Both problems are reported, so neither hides the other (#104).
        var problems: [Error] = []
        do { try remotePlannedRoutes.throwIfSkipped() } catch { problems.append(error) }
        if !heldBack.isEmpty {
            problems.append(SyncError.unreadableLocalFiles(heldBack.map { "\($0.uuidString).json" }))
        }
        try Self.throwAll(problems)
    }

    /// Throws nothing for no problems, the problem itself for one, and
    /// ``SyncError/several(_:)`` for more, which ``runSteps(_:)`` reports one by one.
    ///
    /// - Parameter problems: What a step found, in the order to report it.
    /// - Throws: As above.
    static func throwAll(_ problems: [Error]) throws {
        switch problems.count {
        case 0: return
        case 1: throw problems[0]
        default: throw SyncError.several(problems.map(\.localizedDescription))
        }
    }

    // MARK: - Retry Logic

    /// Executes an async operation with exponential backoff retry.
    ///
    /// See ``retryWithBackoff(sleep:_:)``.
    private func retryWithBackoff<T>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        try await Self.retryWithBackoff(operation)
    }

    /// Executes an async operation, retrying failures that may clear up by themselves.
    ///
    /// Makes up to ``maxRetryAttempts`` attempts, waiting 2s, 4s, 8s between them, or the
    /// delay the server asked for (`CKError.retryAfterSeconds`). It stops at once when
    /// ``CloudKitStore/retryAdvice(for:)`` says a retry cannot help, such as an exceeded
    /// quota or a record that is too large (#86), or when the server asks for a wait
    /// longer than ``maxServerRetryDelay``. It does not wait after the last attempt, so
    /// the error reaches the user sooner.
    ///
    /// - Parameters:
    ///   - sleep: Waits the given number of seconds; tests pass one that only records it.
    ///   - operation: The async throwing operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: The error of the last attempt.
    static func retryWithBackoff<T>(
        sleep: (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
        _ operation: () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch {
                attempt += 1
                guard attempt < maxRetryAttempts,
                      case .retry(let serverDelay) = CloudKitStore.retryAdvice(for: error),
                      (serverDelay ?? 0) <= maxServerRetryDelay else {
                    throw error
                }
                let delay = serverDelay ?? baseRetryDelay * pow(2.0, Double(attempt - 1))
                logger.debug("Retry \(attempt)/\(maxRetryAttempts - 1) after \(delay)s: \(error.localizedDescription)")
                try await sleep(delay)
            }
        }
    }
}

// MARK: - Run Coalescing

/// Lets one run of some work go at a time, and folds every request made during a run into
/// exactly one more run (#104, #107).
///
/// Usage: call ``begin()``; if it returns `true`, do the work, then call ``endRun()`` and do
/// the work again for as long as it returns `true`. If ``begin()`` returns `false`, a run is
/// already going and will run once more, so the caller just returns.
struct RunCoalescer {
    /// Whether a run is going.
    private(set) var isRunning = false

    /// Whether ``begin()`` was called during the current run.
    private var requestedWhileRunning = false

    /// Asks for a run.
    ///
    /// - Returns: `true` if the caller should run now; `false` if a run is already going,
    ///   which then runs once more.
    mutating func begin() -> Bool {
        if isRunning {
            requestedWhileRunning = true
            return false
        }
        isRunning = true
        return true
    }

    /// Ends a run.
    ///
    /// - Returns: `true` if a run was asked for meanwhile, so the caller should run again
    ///   (and call this again afterwards); `false` once nothing was asked for, which ends
    ///   the run.
    mutating func endRun() -> Bool {
        if requestedWhileRunning {
            requestedWhileRunning = false
            return true
        }
        isRunning = false
        return false
    }
}
