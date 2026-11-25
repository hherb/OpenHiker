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

import XCTest
import CloudKit
import CoreLocation
@testable import OpenHiker

/// Tests for the iCloud sync step runner (#81), the published sync result (#78), and
/// the iCloud deletion queue and the stores that fill it (#89).
final class CloudSyncManagerTests: XCTestCase {

    /// A test error with a fixed message.
    private struct StepError: LocalizedError {
        let errorDescription: String?
    }

    /// A failing step must not stop the steps after it, and its error must name the step.
    func testRunStepsContinuesAfterFailureAndLabelsErrors() async {
        var ran: [String] = []
        let errors = await CloudSyncManager.runSteps([
            ("A", { ran.append("A"); throw StepError(errorDescription: "folder unreadable") }),
            ("B", { ran.append("B") }),
            ("C", { ran.append("C"); throw StepError(errorDescription: "offline") }),
        ])
        XCTAssertEqual(ran, ["A", "B", "C"])
        XCTAssertEqual(errors, ["A: folder unreadable", "C: offline"])
    }

    /// Steps that all succeed report no errors.
    func testRunStepsReportsNothingWhenAllSucceed() async {
        let errors = await CloudSyncManager.runSteps([("A", {}), ("B", {})])
        XCTAssertEqual(errors, [])
    }

    /// A step with several problems reports each under its label, so none hides another (#104).
    func testRunStepsReportsEveryProblemOfAStep() async {
        let one = StepError(errorDescription: "2 records could not be read")
        let two = CloudSyncManager.SyncError.unreadableLocalFiles(["x.json"])
        let errors = await CloudSyncManager.runSteps([
            ("A", { try CloudSyncManager.throwAll([one, two]) }),
            ("B", { try CloudSyncManager.throwAll([one]) }),
            ("C", { try CloudSyncManager.throwAll([]) }),
        ])
        XCTAssertEqual(errors, [
            "A: 2 records could not be read",
            "A: \(two.localizedDescription)",
            "B: 2 records could not be read",
        ])
    }

    /// A clean sync clears earlier errors and sets the success time; a failed one keeps
    /// the previous success time.
    @MainActor
    func testStatusRecordsSuccessAndFailure() {
        let status = CloudSyncStatus()
        let first = Date(timeIntervalSince1970: 1_000)

        status.record(errors: ["iCloud: offline"], at: Date(timeIntervalSince1970: 500))
        XCTAssertNil(status.lastSuccess, "a failed first sync must not count as a success")

        status.record(errors: [], at: first)
        XCTAssertEqual(status.lastSuccess, first)
        XCTAssertEqual(status.errors, [])

        status.record(errors: ["Planned routes: folder unreadable"], at: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(status.lastSuccess, first)
        XCTAssertEqual(status.errors, ["Planned routes: folder unreadable"])

        status.dismissErrors()
        XCTAssertEqual(status.errors, [])

        let third = Date(timeIntervalSince1970: 3_000)
        status.record(errors: [], at: third)
        XCTAssertEqual(status.lastSuccess, third)
    }

    /// `report` publishes a sync's errors, and a clean sync's success, to the status the
    /// UI observes (#78).
    func testReportPublishesToStatus() async {
        let status = await CloudSyncStatus()
        XCTAssertEqual(CloudSyncManager.upload("Waypoints"), "Waypoints (upload)")
        XCTAssertEqual(CloudSyncManager.download("Waypoints"), "Waypoints (download)")

        await CloudSyncManager.report(["Waypoints (upload): offline"], to: status)
        let errors = await status.errors
        XCTAssertEqual(errors, ["Waypoints (upload): offline"])

        await CloudSyncManager.report([], to: status)
        let cleared = await status.errors
        let lastSuccess = await status.lastSuccess
        XCTAssertEqual(cleared, [])
        XCTAssertNotNil(lastSuccess)
    }

    /// A deletion queue in its own `UserDefaults` suite, removed when the test ends.
    private func makeDeletionQueue() throws -> CloudDeletionQueue {
        let suite = "CloudSyncManagerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return CloudDeletionQueue(defaults: defaults)
    }

    /// The queue keeps each record once, per record type, and survives a new instance (#89).
    func testDeletionQueueAddsOncePerTypeAndRemoves() throws {
        let suite = "CloudSyncManagerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let queue = CloudDeletionQueue(defaults: defaults)

        queue.add(recordID: "a", recordType: "Waypoint")
        queue.add(recordID: "b", recordType: "Waypoint")
        queue.add(recordID: "a", recordType: "Waypoint")
        queue.add(recordID: "a", recordType: "SavedRoute")

        let reopened = CloudDeletionQueue(defaults: defaults)
        XCTAssertEqual(reopened.pending(recordType: "Waypoint"), ["a", "b"])
        XCTAssertEqual(reopened.pending(recordType: "SavedRoute"), ["a"])

        reopened.remove(recordID: "a", recordType: "Waypoint")
        XCTAssertEqual(queue.pending(recordType: "Waypoint"), ["b"])
        XCTAssertEqual(queue.pending(recordType: "SavedRoute"), ["a"])
        XCTAssertEqual(queue.pending(recordType: "PlannedRoute"), [])
    }

    /// Deleted records leave the queue. A failure stops the run and moves the failed
    /// record to the back, so it does not block the others next time (#89).
    func testPushDeletionsStopsAtFirstFailureAndMovesItToTheBack() async throws {
        let queue = try makeDeletionQueue()
        for id in ["a", "b", "c"] { queue.add(recordID: id, recordType: "Waypoint") }
        queue.add(recordID: "x", recordType: "SavedRoute")
        var deleted: [String] = []

        do {
            try await CloudSyncManager.pushDeletions(recordType: "Waypoint", queue: queue) { id in
                if id == "b" { throw StepError(errorDescription: "offline") }
                deleted.append(id)
            }
            XCTFail("Expected the failed deletion to throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "offline")
        }
        XCTAssertEqual(deleted, ["a"])
        XCTAssertEqual(queue.pending(recordType: "Waypoint"), ["c", "b"])
        XCTAssertEqual(queue.pending(recordType: "SavedRoute"), ["x"])

        try await CloudSyncManager.pushDeletions(recordType: "Waypoint", queue: queue) { deleted.append($0) }
        XCTAssertEqual(deleted, ["a", "c", "b"])
        XCTAssertEqual(queue.pending(recordType: "Waypoint"), [])
    }

    /// Moving a record that is not queued must not add it.
    func testMoveToBackIgnoresUnqueuedRecord() throws {
        let queue = try makeDeletionQueue()
        queue.add(recordID: "a", recordType: "Waypoint")
        queue.moveToBack(recordID: "z", recordType: "Waypoint")
        queue.moveToBack(recordID: "a", recordType: "SavedRoute")
        XCTAssertEqual(queue.pending(recordType: "Waypoint"), ["a"])
        XCTAssertEqual(queue.pending(recordType: "SavedRoute"), [])
    }

    /// The deletion step is labelled like the upload and download steps.
    func testDeleteStepLabel() {
        XCTAssertEqual(CloudSyncManager.delete("Waypoints"), "Waypoints (delete)")
    }

    /// Pulls merge only records that no device deleted (#93).
    func testItemsToMergeSkipsDeletedRecords() {
        let fetched: [(recordID: String, item: Int)] = [("a", 1), ("b", 2), ("c", 3)]

        let merged = CloudSyncManager.itemsToMerge(fetched, skipping: ["b", "z"])

        XCTAssertEqual(merged.map(\.recordID), ["a", "c"])
        XCTAssertEqual(merged.map(\.item), [1, 3])
        XCTAssertEqual(CloudSyncManager.itemsToMerge(fetched, skipping: []).count, 3)
    }

    /// A pull never writes an iCloud copy over a local route file that cannot be read: the
    /// failure may be temporary and the file may hold an unsynced edit (#80).
    func testPlannedRoutesToMergeHoldsBackUnreadableLocalFiles() {
        func route() -> PlannedRoute {
            let point = CLLocationCoordinate2D(latitude: 47, longitude: 11)
            return PlannedRoute(
                name: "R", mode: .hiking, startCoordinate: point, endCoordinate: point,
                coordinates: [point], turnInstructions: [], totalDistance: 0,
                estimatedDuration: 0, elevationGain: 0, elevationLoss: 0
            )
        }
        let readable = route()
        let broken = route()
        let fetched: [(recordID: String, item: PlannedRoute)] = [("a", readable), ("b", broken)]

        let split = CloudSyncManager.plannedRoutesToMerge(fetched, unreadable: [broken.id, UUID()])

        XCTAssertEqual(split.merge.map(\.recordID), ["a"])
        XCTAssertEqual(split.heldBack, [broken.id])
        XCTAssertEqual(CloudSyncManager.plannedRoutesToMerge(fetched, unreadable: []).merge.count, 2)
    }

    /// A tombstone deletes an unreadable `<uuid>.json` of a route deleted elsewhere; other
    /// unreadable files stay for the user to delete (#80, #105).
    func testUnreadableRoutesToDeleteMatchesTombstonedUUIDs() {
        let dir = URL(fileURLWithPath: "/routes")
        let deleted = UUID()
        let kept = UUID()
        let lowercase = UUID()
        let skipped = [
            "\(deleted.uuidString).json", "\(kept.uuidString).json", "broken.json",
            "\(lowercase.uuidString.lowercased()).json",
        ].map {
            PlannedRouteStore.SkippedFile(url: dir.appendingPathComponent($0), reason: "bad")
        }

        XCTAssertEqual(
            CloudSyncManager.unreadableRoutesToDelete(
                skipped, tombstoned: [deleted.uuidString, lowercase.uuidString, "broken"]
            ),
            [skipped[0], skipped[3]],
            "a lowercase file name matches its tombstone too (#107)"
        )
        XCTAssertEqual(CloudSyncManager.unreadableRoutesToDelete(skipped, tombstoned: []), [])
    }

    /// Requests made during a run fold into exactly one more run; none make none (#104, #107).
    func testRunCoalescerRunsOnceMoreAfterRequestsDuringARun() {
        var runs = RunCoalescer()
        XCTAssertTrue(runs.begin())
        XCTAssertFalse(runs.begin())
        XCTAssertFalse(runs.begin())
        XCTAssertTrue(runs.isRunning)

        XCTAssertTrue(runs.endRun(), "two requests meanwhile: one more run")
        XCTAssertFalse(runs.endRun(), "nothing asked for during the extra run")
        XCTAssertFalse(runs.isRunning)

        XCTAssertTrue(runs.begin(), "idle again, so the next request runs at once")
        XCTAssertFalse(runs.endRun())
    }

    /// Tombstones are grouped by record type, so a waypoint's deletion never deletes a
    /// hike with the same record name (#91).
    func testRecordNamesByTypeGroupsTombstones() {
        let tombstones = [
            CloudKitStore.Tombstone(recordType: CloudKitStore.waypointRecordType, recordName: "x"),
            CloudKitStore.Tombstone(recordType: CloudKitStore.waypointRecordType, recordName: "y"),
            CloudKitStore.Tombstone(recordType: CloudKitStore.savedRouteRecordType, recordName: "z"),
        ]

        let byType = CloudSyncManager.recordNamesByType(tombstones)

        XCTAssertEqual(byType[CloudKitStore.waypointRecordType], ["x", "y"])
        XCTAssertEqual(byType[CloudKitStore.savedRouteRecordType], ["z"])
        XCTAssertNil(byType[CloudKitStore.plannedRouteRecordType])
        XCTAssertTrue(CloudSyncManager.recordNamesByType([]).isEmpty)
    }

    /// Uploads skip deleted items, but an item added again after its deletion (never
    /// synced, under a tombstoned UUID) restores itself instead of vanishing (#91).
    func testUploadActionSkipsDeletedAndRestoresReAddedItems() {
        let id = UUID()
        let name = id.uuidString

        XCTAssertEqual(CloudSyncManager.uploadAction(cloudKitRecordID: nil, id: id, queued: [], tombstoned: []), .upload)
        XCTAssertEqual(CloudSyncManager.uploadAction(cloudKitRecordID: name, id: id, queued: [], tombstoned: []), .upload)
        // Deleted here, not yet in iCloud.
        XCTAssertEqual(CloudSyncManager.uploadAction(cloudKitRecordID: nil, id: id, queued: [name], tombstoned: [name]), .skip)
        // Synced copy deleted on another device.
        XCTAssertEqual(CloudSyncManager.uploadAction(cloudKitRecordID: "r", id: id, queued: [], tombstoned: ["r"]), .skip)
        // Re-downloaded or P2P-imported after its deletion.
        XCTAssertEqual(CloudSyncManager.uploadAction(cloudKitRecordID: nil, id: id, queued: [], tombstoned: [name]), .restoreThenUpload)
    }

    /// Only synced items are deleted by another device's tombstone; a never-synced item
    /// with a tombstoned UUID was added again and stays (#91).
    func testIsDeletedRemotelyOnlyForSyncedItems() {
        XCTAssertTrue(CloudSyncManager.isDeletedRemotely(cloudKitRecordID: "r", tombstoned: ["r"]))
        XCTAssertFalse(CloudSyncManager.isDeletedRemotely(cloudKitRecordID: "r", tombstoned: ["s"]))
        XCTAssertFalse(CloudSyncManager.isDeletedRemotely(cloudKitRecordID: nil, tombstoned: ["r"]))
    }

    /// A temporary database path, removed when the test ends.
    private func makeDatabasePath() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSyncManagerTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent("store.db").path
    }

    /// Deleting a hike queues its iCloud record name, or its UUID if it has none; a failed
    /// delete queues nothing (#89).
    func testRouteStoreDeleteQueuesRecordName() throws {
        let queue = try makeDeletionQueue()
        let store = RouteStore(path: makeDatabasePath(), deletionQueue: queue)
        try store.open()
        defer { store.close() }
        func route(_ recordID: String?) -> SavedRoute {
            SavedRoute(
                name: "Hike", startLatitude: 0, startLongitude: 0, endLatitude: 0, endLongitude: 0,
                startTime: Date(), endTime: Date(), totalDistance: 0, elevationGain: 0,
                elevationLoss: 0, walkingTime: 0, restingTime: 0, trackData: Data(),
                cloudKitRecordID: recordID
            )
        }
        let synced = route("record-1")
        let unsynced = route(nil)
        try store.insert(synced)
        try store.insert(unsynced)

        try store.delete(id: synced.id)
        try store.delete(id: unsynced.id)
        XCTAssertThrowsError(try store.delete(id: UUID()))

        XCTAssertEqual(
            queue.pending(recordType: CloudKitStore.savedRouteRecordType),
            ["record-1", unsynced.id.uuidString]
        )
        XCTAssertEqual(queue.pending(recordType: CloudKitStore.waypointRecordType), [])
        XCTAssertTrue(try store.fetchAll().isEmpty)
    }

    /// Deleting a waypoint queues its iCloud record name, or its UUID if it has none; a
    /// failed delete queues nothing (#89).
    func testWaypointStoreDeleteQueuesRecordName() throws {
        let queue = try makeDeletionQueue()
        let store = WaypointStore(path: makeDatabasePath(), deletionQueue: queue)
        try store.open()
        defer { store.close() }
        let synced = Waypoint(latitude: 1, longitude: 2, cloudKitRecordID: "record-1")
        let unsynced = Waypoint(latitude: 3, longitude: 4)
        try store.insert(synced)
        try store.insert(unsynced)

        try store.delete(id: synced.id)
        try store.delete(id: unsynced.id)
        XCTAssertThrowsError(try store.delete(id: UUID()))

        XCTAssertEqual(
            queue.pending(recordType: CloudKitStore.waypointRecordType),
            ["record-1", unsynced.id.uuidString]
        )
        XCTAssertEqual(queue.pending(recordType: CloudKitStore.savedRouteRecordType), [])
        XCTAssertTrue(try store.fetchAll().isEmpty)
    }

    // MARK: - Sync progress, account notice and retries (#84, #86)

    /// A status that remembers dismissals in its own `UserDefaults` suite.
    @MainActor
    private func makeStatus() throws -> (CloudSyncStatus, UserDefaults) {
        let suite = "CloudSyncStatusTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (CloudSyncStatus(defaults: defaults), defaults)
    }

    /// A sync is in progress from `beginSync` until its result or the account notice.
    @MainActor
    func testStatusIsSyncingUntilResultOrNotice() throws {
        let (status, _) = try makeStatus()
        XCTAssertFalse(status.isSyncing)
        status.beginSync()
        XCTAssertTrue(status.isSyncing)
        status.record(errors: ["iCloud: offline"])
        XCTAssertFalse(status.isSyncing)

        status.beginSync()
        status.showAccountNotice("Not signed in")
        XCTAssertFalse(status.isSyncing)
    }

    /// The notice clears old sync errors without counting as a successful sync.
    @MainActor
    func testAccountNoticeClearsErrorsButNotLastSuccess() throws {
        let (status, _) = try makeStatus()
        status.record(errors: ["Waypoints (upload): offline"])
        status.showAccountNotice("Not signed in")
        XCTAssertEqual(status.errors, [])
        XCTAssertNil(status.lastSuccess)
        XCTAssertEqual(status.accountNotice, "Not signed in")
    }

    /// A dismissed notice stays hidden across launches until the account status changes.
    @MainActor
    func testDismissedAccountNoticeStaysHiddenUntilStatusChanges() throws {
        let (status, defaults) = try makeStatus()
        status.showAccountNotice("Not signed in")
        status.dismissAccountNotice()
        XCTAssertNil(status.accountNotice)

        let relaunched = CloudSyncStatus(defaults: defaults)
        relaunched.showAccountNotice("Not signed in")
        XCTAssertNil(relaunched.accountNotice, "a dismissed notice must not come back on the next launch")

        relaunched.clearAccountNotice()
        relaunched.showAccountNotice("Not signed in")
        XCTAssertEqual(relaunched.accountNotice, "Not signed in", "signing out again must show it again")
    }

    /// Subscription failures become one "iCloud:" entry; none means no entry.
    func testSubscriptionsError() {
        XCTAssertNil(CloudSyncManager.subscriptionsError([]))
        XCTAssertEqual(
            CloudSyncManager.subscriptionsError(["Waypoint: offline", "SavedRoute: offline"]),
            "iCloud: change notifications unavailable (Waypoint: offline; SavedRoute: offline)"
        )
    }

    /// A transient error is retried with 2, 4, 8 s backoff until the attempts run out.
    func testRetryWithBackoffRetriesTransientErrors() async {
        var attempts = 0
        var delays: [TimeInterval] = []
        do {
            _ = try await CloudSyncManager.retryWithBackoff(sleep: { delays.append($0) }) { () async throws -> Int in
                attempts += 1
                throw CKError(.networkUnavailable)
            }
            XCTFail("must throw after the last attempt")
        } catch {
            XCTAssertEqual((error as? CKError)?.code, .networkUnavailable)
        }
        XCTAssertEqual(attempts, CloudSyncManager.maxRetryAttempts)
        XCTAssertEqual(delays, [2, 4, 8])
    }

    /// A non-recoverable error fails at once; the server's retry-after delay wins over backoff.
    func testRetryWithBackoffStopsOnPermanentErrorAndHonoursRetryAfter() async throws {
        var attempts = 0
        var delays: [TimeInterval] = []
        do {
            _ = try await CloudSyncManager.retryWithBackoff(sleep: { delays.append($0) }) { () async throws -> Int in
                attempts += 1
                throw CloudKitStore.CloudKitStoreError.cloudKit(CKError(.quotaExceeded))
            }
            XCTFail("must throw")
        } catch CloudKitStore.CloudKitStoreError.cloudKit(let ckError) {
            XCTAssertEqual(ckError.code, .quotaExceeded, "the original error must reach the caller")
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(delays, [])

        attempts = 0
        let value = try await CloudSyncManager.retryWithBackoff(sleep: { delays.append($0) }) { () async throws -> Int in
            attempts += 1
            if attempts == 1 { throw CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 30.0]) }
            return 7
        }
        XCTAssertEqual(value, 7)
        XCTAssertEqual(delays, [30])
    }

    /// A server delay above ``CloudSyncManager/maxServerRetryDelay`` fails at once rather
    /// than keep the sync (and its spinner) waiting for minutes.
    func testRetryWithBackoffGivesUpWhenServerDelayIsTooLong() async {
        var attempts = 0
        var delays: [TimeInterval] = []
        let tooLong = CloudSyncManager.maxServerRetryDelay + 1
        do {
            _ = try await CloudSyncManager.retryWithBackoff(sleep: { delays.append($0) }) { () async throws -> Int in
                attempts += 1
                throw CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: tooLong])
            }
            XCTFail("must throw")
        } catch {
            XCTAssertEqual((error as? CKError)?.code, .requestRateLimited)
        }
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(delays, [])
    }

    /// Each account check result reaches the status: available clears the notice, no
    /// account shows it without an error, and everything else is an "iCloud:" error.
    @MainActor
    func testPublishAccountCheck() async throws {
        let (status, _) = try makeStatus()

        let signedOut = await CloudSyncManager.publish(.success(.notSignedIn("Not signed in")), to: status)
        XCTAssertFalse(signedOut)
        XCTAssertEqual(status.accountNotice, "Not signed in")
        XCTAssertEqual(status.errors, [])

        let available = await CloudSyncManager.publish(.success(.available), to: status)
        XCTAssertTrue(available)
        XCTAssertNil(status.accountNotice, "signing in must hide the notice")

        status.showAccountNotice("Not signed in")
        let restricted = await CloudSyncManager.publish(.success(.unusable("restricted")), to: status)
        XCTAssertFalse(restricted)
        XCTAssertNil(status.accountNotice, "an unusable account is an error, not the grey notice")
        XCTAssertEqual(status.errors, ["iCloud: restricted"])

        let failed = await CloudSyncManager.publish(.failure(CKError(.networkUnavailable)), to: status)
        XCTAssertFalse(failed)
        XCTAssertEqual(status.errors.count, 1)
        XCTAssertTrue(status.errors[0].hasPrefix("iCloud: "))
        XCTAssertFalse(status.isSyncing)
    }
}
