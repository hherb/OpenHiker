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
}
