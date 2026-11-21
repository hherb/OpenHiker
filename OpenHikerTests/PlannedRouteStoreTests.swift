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
        XCTAssertEqual(result.skippedFiles.count, 1)
        XCTAssertTrue(try XCTUnwrap(result.skippedFiles.first).hasPrefix("broken.json: "))
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
