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
import CoreLocation
@testable import OpenHiker

/// Tests for ``PlannedRouteStore`` read errors (#75): an unreadable folder must not look
/// like "no routes", and broken route files must be reported instead of silently skipped.
final class PlannedRouteStoreTests: XCTestCase {

    /// A fresh temporary folder per test; removed in `tearDown`.
    private var tempDir: URL!

    /// The store's route folder inside `tempDir` (not created until a test needs it).
    private var routesDir: URL { tempDir.appendingPathComponent("planned_routes", isDirectory: true) }

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlannedRouteStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Builds a minimal valid route.
    private func route(regionId: UUID? = nil) -> PlannedRoute {
        let start = CLLocationCoordinate2D(latitude: 47, longitude: 11)
        let end = CLLocationCoordinate2D(latitude: 47.01, longitude: 11.01)
        return PlannedRoute(
            name: "Test", mode: .hiking, startCoordinate: start, endCoordinate: end,
            coordinates: [start, end], turnInstructions: [], totalDistance: 1500,
            estimatedDuration: 1200, elevationGain: 50, elevationLoss: 10, regionId: regionId
        )
    }

    /// Puts a regular file where the route folder should be, so listing it fails.
    private func makeFolderUnlistable() throws {
        try? FileManager.default.removeItem(at: routesDir)
        try Data("not a folder".utf8).write(to: routesDir)
    }

    /// Waits until blocks the store dispatched to the main queue have run.
    private func drainMainQueue() {
        let done = expectation(description: "main queue drained")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    func testMissingFolderLoadsNothingWithoutError() throws {
        let result = try PlannedRouteStore(storageDirectory: routesDir).loadAllFromDisk()
        XCTAssertTrue(result.routes.isEmpty)
        XCTAssertTrue(result.skippedFiles.isEmpty)
    }

    func testBrokenFileIsSkippedAndListed() throws {
        let store = PlannedRouteStore(storageDirectory: routesDir)
        let good = route()
        try store.save(good)
        try Data("{ broken".utf8).write(to: routesDir.appendingPathComponent("broken.json"))

        let result = try store.loadAllFromDisk()

        XCTAssertEqual(result.routes.map(\.id), [good.id])
        XCTAssertEqual(result.skippedFiles.map(\.url.lastPathComponent), ["broken.json"])
        XCTAssertTrue(try XCTUnwrap(result.skippedFiles.first).message.hasPrefix("broken.json: "))
        XCTAssertNil(result.skippedFiles.first?.routeID, "not named after a route UUID")
    }

    /// Deleting the unreadable files keeps readable routes and queues no iCloud deletion,
    /// so the iCloud copy of the route comes back at the next sync (#80).
    func testDeleteUnreadableFilesKeepsGoodRoutesAndQueuesNothing() throws {
        let suite = "PlannedRouteStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let queue = CloudDeletionQueue(defaults: defaults)
        let store = PlannedRouteStore(storageDirectory: routesDir, deletionQueue: queue)
        let good = route()
        try store.save(good)
        let broken = UUID()
        try Data("not json".utf8).write(to: routesDir.appendingPathComponent("\(broken.uuidString).json"))
        try Data("{ broken".utf8).write(to: routesDir.appendingPathComponent("broken.json"))
        let skipped = try store.loadAllFromDisk().skippedFiles
        XCTAssertEqual(skipped.compactMap(\.routeID), [broken])

        try store.deleteUnreadableFiles(skipped.map(\.url))
        drainMainQueue()

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: routesDir.path),
            ["\(good.id.uuidString).json"]
        )
        XCTAssertTrue(queue.pending(recordType: CloudKitStore.plannedRouteRecordType).isEmpty)
        XCTAssertTrue(store.loadErrors.isEmpty)
        XCTAssertTrue(store.unreadableFiles.isEmpty)
    }

    /// A lowercase `<uuid>.json` is deleted by its URL and returned, as iCloud sync does for
    /// a route deleted on another device; `delete(id:)` looks for the uppercase name (#107).
    func testDeleteUnreadableFilesFindsLowercaseNameAndReturnsDeleted() throws {
        let store = PlannedRouteStore(storageDirectory: routesDir)
        try FileManager.default.createDirectory(at: routesDir, withIntermediateDirectories: true)
        let lowercase = UUID()
        try Data("not json".utf8).write(to: routesDir.appendingPathComponent("\(lowercase.uuidString.lowercased()).json"))
        let skipped = try store.loadAllFromDisk().skippedFiles
        XCTAssertEqual(skipped.compactMap(\.routeID), [lowercase])

        let deleted = try store.deleteUnreadableFiles(skipped.map(\.url))
        drainMainQueue()

        XCTAssertEqual(deleted.map(\.lastPathComponent), ["\(lowercase.uuidString.lowercased()).json"])
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: routesDir.path).isEmpty)
    }

    /// A file listed as unreadable that has since been saved again must survive the delete.
    func testDeleteUnreadableFilesKeepsFileThatBecameReadable() throws {
        let store = PlannedRouteStore(storageDirectory: routesDir)
        let healed = route()
        try store.save(healed)
        let file = routesDir.appendingPathComponent("\(healed.id.uuidString).json")
        try Data("not json".utf8).write(to: file)
        store.loadAll()
        drainMainQueue()
        XCTAssertEqual(store.unreadableFiles.map(\.lastPathComponent), [file.lastPathComponent])

        try store.save(healed)
        try store.deleteUnreadableFiles(store.unreadableFiles)
        drainMainQueue()

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(store.routes.map(\.id), [healed.id])
        XCTAssertTrue(store.unreadableFiles.isEmpty)
    }

    /// A file that became unreadable after the user confirmed the list is not deleted (#104).
    func testDeleteUnreadableFilesKeepsFileTheUserDidNotConfirm() throws {
        let store = PlannedRouteStore(storageDirectory: routesDir)
        try FileManager.default.createDirectory(at: routesDir, withIntermediateDirectories: true)
        let confirmed = routesDir.appendingPathComponent("broken.json")
        try Data("{ broken".utf8).write(to: confirmed)
        let later = routesDir.appendingPathComponent("later.json")
        try Data("{ broken".utf8).write(to: later)

        try store.deleteUnreadableFiles([confirmed])
        drainMainQueue()

        XCTAssertFalse(FileManager.default.fileExists(atPath: confirmed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: later.path))
        XCTAssertEqual(store.unreadableFiles.map(\.lastPathComponent), ["later.json"])
    }

    /// A file that cannot be deleted is named in the error and stays listed.
    func testDeleteUnreadableFilesReportsFilesNotDeleted() throws {
        let store = PlannedRouteStore(storageDirectory: routesDir)
        try store.save(route())
        try Data("{ broken".utf8).write(to: routesDir.appendingPathComponent("broken.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: routesDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: routesDir.path)
        }

        XCTAssertThrowsError(try store.deleteUnreadableFiles([routesDir.appendingPathComponent("broken.json")])) { error in
            guard case .notDeleted(let entries)? = error as? PlannedRouteStore.DeleteUnreadableError else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(entries.count, 1)
            XCTAssertTrue(entries[0].hasPrefix("broken.json: "))
        }
        drainMainQueue()
        XCTAssertEqual(store.unreadableFiles.map(\.lastPathComponent), ["broken.json"])
    }

    func testUnlistableFolderThrows() throws {
        try makeFolderUnlistable()
        let store = PlannedRouteStore(storageDirectory: routesDir)
        XCTAssertThrowsError(try store.loadAllFromDisk())
        XCTAssertThrowsError(try store.fetchForRegion(UUID()))
    }

    func testFetchForRegionFiltersByRegion() throws {
        let store = PlannedRouteStore(storageDirectory: routesDir)
        let regionId = UUID()
        let inRegion = route(regionId: regionId)
        try store.save(inRegion)
        try store.save(route(regionId: UUID()))

        XCTAssertEqual(try store.fetchForRegion(regionId).map(\.id), [inRegion.id])
    }

    /// Deleting a route queues its iCloud record name, or its UUID if it has none or its
    /// file cannot be read (#89).
    func testDeleteQueuesRecordNameOrUUID() throws {
        let suite = "PlannedRouteStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let queue = CloudDeletionQueue(defaults: defaults)
        let store = PlannedRouteStore(storageDirectory: routesDir, deletionQueue: queue)
        var synced = route()
        synced.cloudKitRecordID = "record-1"
        let unsynced = route()
        try store.save(synced)
        try store.save(unsynced)
        let broken = UUID()
        try Data("not json".utf8).write(to: routesDir.appendingPathComponent("\(broken.uuidString).json"))

        try store.delete(id: synced.id)
        try store.delete(id: unsynced.id)
        try store.delete(id: broken)

        XCTAssertEqual(
            queue.pending(recordType: CloudKitStore.plannedRouteRecordType),
            ["record-1", unsynced.id.uuidString, broken.uuidString]
        )
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: routesDir.path).isEmpty)
    }

    /// One broken file must not block a region transfer, and must reach the route lists.
    func testFetchForRegionSkipsBrokenFileAndPublishesIt() throws {
        let store = PlannedRouteStore(storageDirectory: routesDir)
        let regionId = UUID()
        let inRegion = route(regionId: regionId)
        try store.save(inRegion)
        try Data("{ broken".utf8).write(to: routesDir.appendingPathComponent("broken.json"))

        XCTAssertEqual(try store.fetchForRegion(regionId).map(\.id), [inRegion.id])
        drainMainQueue()
        XCTAssertEqual(store.loadErrors.count, 1)
    }

    func testLoadAllPublishesSkippedFiles() throws {
        let store = PlannedRouteStore(storageDirectory: routesDir)
        try store.save(route())
        try Data("{ broken".utf8).write(to: routesDir.appendingPathComponent("broken.json"))

        store.loadAll()
        drainMainQueue()

        XCTAssertEqual(store.routes.count, 1)
        XCTAssertEqual(store.loadErrors.count, 1)
        XCTAssertEqual(store.unreadableFiles.map(\.lastPathComponent), ["broken.json"])

        // Once the file is gone, the next load clears the banner.
        try FileManager.default.removeItem(at: routesDir.appendingPathComponent("broken.json"))
        store.loadAll()
        drainMainQueue()
        XCTAssertTrue(store.loadErrors.isEmpty)
    }

    func testLoadAllKeepsRoutesWhenFolderUnreadable() throws {
        let store = PlannedRouteStore(storageDirectory: routesDir)
        try store.save(route())
        store.loadAll()
        drainMainQueue()
        XCTAssertEqual(store.routes.count, 1)

        try makeFolderUnlistable()
        store.loadAll()
        drainMainQueue()

        XCTAssertEqual(store.routes.count, 1, "an unreadable folder must not empty the list")
        XCTAssertEqual(store.loadErrors.count, 1)
        XCTAssertTrue(try XCTUnwrap(store.loadErrors.first).hasPrefix("Cannot read the planned routes folder"))
    }
}
