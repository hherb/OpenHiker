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

import CloudKit
import CoreLocation
import XCTest
@testable import OpenHiker

/// Tests for the iCloud fetch helpers: paging and reporting unreadable records (#85).
final class CloudKitStoreTests: XCTestCase {

    /// A test error with a fixed message.
    private struct LoadError: LocalizedError {
        let errorDescription: String?
    }

    /// Builds a waypoint record with the fields `decodeWaypoint` requires.
    private func waypointRecord(name: String, label: String) -> CKRecord {
        let record = CKRecord(
            recordType: CloudKitStore.waypointRecordType,
            recordID: CKRecord.ID(recordName: name)
        )
        record["localID"] = UUID().uuidString
        record["timestamp"] = Date()
        record["latitude"] = 47.0
        record["longitude"] = 11.0
        record["label"] = label
        return record
    }

    /// Builds a saved-route record with the fields `decodeRoute` requires.
    private func savedRouteRecord(id: UUID) -> CKRecord {
        let record = CKRecord(
            recordType: CloudKitStore.savedRouteRecordType,
            recordID: CKRecord.ID(recordName: id.uuidString)
        )
        record["localID"] = id.uuidString
        record["name"] = "Ridge walk"
        record["startTime"] = Date(timeIntervalSince1970: 1_000)
        record["endTime"] = Date(timeIntervalSince1970: 2_000)
        record["trackData"] = Data([1, 2, 3])
        return record
    }

    /// Wraps records as one page of successful query results.
    private func page(_ records: [CKRecord]) -> CloudKitStore.MatchResults {
        records.map { ($0.recordID, .success($0)) }
    }

    /// Every page is loaded, in order, until a page has no cursor.
    func testCollectPagesFollowsCursorToLastPage() async throws {
        let pages = [
            page([waypointRecord(name: "a", label: "A")]),
            page([waypointRecord(name: "b", label: "B")]),
            page([waypointRecord(name: "c", label: "C")]),
        ]
        var requested: [Int] = []
        let matches = try await CloudKitStore.collectPages(
            first: { (pages[0], Optional(1)) },
            next: { (cursor: Int) in
                requested.append(cursor)
                return (pages[cursor], cursor + 1 < pages.count ? cursor + 1 : nil)
            }
        )
        XCTAssertEqual(requested, [1, 2])
        XCTAssertEqual(matches.map { $0.0.recordName }, ["a", "b", "c"])
    }

    /// An empty page with a cursor does not end paging.
    func testCollectPagesContinuesPastEmptyPage() async throws {
        let pages = [
            page([waypointRecord(name: "a", label: "A")]),
            page([]),
            page([waypointRecord(name: "c", label: "C")]),
        ]
        let matches = try await CloudKitStore.collectPages(
            first: { (pages[0], Optional(1)) },
            next: { (cursor: Int) in (pages[cursor], cursor + 1 < pages.count ? cursor + 1 : nil) }
        )
        XCTAssertEqual(matches.map { $0.0.recordName }, ["a", "c"])
    }

    /// A failure on a later page fails the fetch instead of returning the earlier pages.
    func testCollectPagesThrowsWhenLaterPageFails() async {
        do {
            _ = try await CloudKitStore.collectPages(
                first: { (self.page([self.waypointRecord(name: "a", label: "A")]), Optional(1)) },
                next: { (_: Int) -> (matchResults: CloudKitStore.MatchResults, queryCursor: Int?) in
                    throw LoadError(errorDescription: "page lost")
                }
            )
            XCTFail("expected the page error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "page lost")
        }
    }

    /// The error text names a few skipped records and counts the rest.
    func testUnreadableRecordsTextIsCapped() {
        let one = CloudKitStore.CloudKitStoreError.unreadableRecords(["a: bad"])
        XCTAssertEqual(one.localizedDescription, "1 record could not be read: a: bad")

        let five = CloudKitStore.CloudKitStoreError.unreadableRecords(["a", "b", "c", "d", "e"])
        XCTAssertEqual(five.localizedDescription, "5 records could not be read: a; b; c; and 2 more")
    }

    /// A complete saved-route record decodes, keeping its record name.
    func testDecodeRouteReadsCompleteRecord() throws {
        let id = UUID()
        let route = try CloudKitStore.decodeRoute(from: savedRouteRecord(id: id))
        XCTAssertEqual(route.id, id)
        XCTAssertEqual(route.name, "Ridge walk")
        XCTAssertEqual(route.cloudKitRecordID, id.uuidString)
    }

    /// A planned route round-trips through its `routeData` blob and gets its record name.
    func testDecodePlannedRouteReadsRouteData() throws {
        let start = CLLocationCoordinate2D(latitude: 47, longitude: 11)
        let end = CLLocationCoordinate2D(latitude: 47.01, longitude: 11.01)
        let original = PlannedRoute(
            name: "Test", mode: .hiking, startCoordinate: start, endCoordinate: end,
            coordinates: [start, end], turnInstructions: [], totalDistance: 1500,
            estimatedDuration: 1200, elevationGain: 50, elevationLoss: 10, regionId: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let record = CKRecord(
            recordType: CloudKitStore.plannedRouteRecordType,
            recordID: CKRecord.ID(recordName: "planned-1")
        )
        record["routeData"] = try encoder.encode(original)

        let route = try CloudKitStore.decodePlannedRoute(from: record)
        XCTAssertEqual(route.id, original.id)
        XCTAssertEqual(route.cloudKitRecordID, "planned-1")
    }

    /// A waypoint without coordinates, or with a broken hike link, is rejected, not
    /// read as a pin at 0,0 or an unlinked waypoint.
    func testDecodeWaypointRejectsMissingCoordinatesAndBadHikeId() {
        let noCoordinates = waypointRecord(name: "w", label: "W")
        noCoordinates["latitude"] = nil
        XCTAssertThrowsError(try CloudKitStore.decodeWaypoint(from: noCoordinates))

        let badLink = waypointRecord(name: "w", label: "W")
        badLink["hikeId"] = "not-a-uuid"
        XCTAssertThrowsError(try CloudKitStore.decodeWaypoint(from: badLink)) { error in
            XCTAssertEqual(error.localizedDescription, "CloudKit serialization error: invalid hikeId")
        }

        let route = savedRouteRecord(id: UUID())
        route["regionId"] = "not-a-uuid"
        XCTAssertThrowsError(try CloudKitStore.decodeRoute(from: route))
    }

    /// A record that fails to load or to decode is skipped with its name and reason;
    /// the others are still returned.
    func testDecodeAllKeepsReadableRecordsAndNamesSkippedOnes() throws {
        let good = waypointRecord(name: "good", label: "Spring")
        let incomplete = CKRecord(
            recordType: CloudKitStore.waypointRecordType,
            recordID: CKRecord.ID(recordName: "incomplete")
        )
        let matches: CloudKitStore.MatchResults = [
            (good.recordID, .success(good)),
            (CKRecord.ID(recordName: "failed"), .failure(LoadError(errorDescription: "network lost"))),
            (incomplete.recordID, .success(incomplete)),
        ]

        let result = CloudKitStore.decodeAll(matches, decode: CloudKitStore.decodeWaypoint)

        XCTAssertEqual(result.items.map { $0.recordID }, ["good"])
        XCTAssertEqual(result.items.first?.item.label, "Spring")
        XCTAssertEqual(result.skipped, [
            "failed: network lost",
            "incomplete: CloudKit serialization error: missing required fields",
        ])
        XCTAssertThrowsError(try result.throwIfSkipped()) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "2 records could not be read: failed: network lost; "
                    + "incomplete: CloudKit serialization error: missing required fields"
            )
        }
    }

    /// A fetch with nothing skipped does not throw.
    func testThrowIfSkippedIsSilentWhenAllRecordsRead() throws {
        let result = CloudKitStore.decodeAll(
            page([waypointRecord(name: "a", label: "A")]),
            decode: CloudKitStore.decodeWaypoint
        )
        XCTAssertNoThrow(try result.throwIfSkipped())
    }

    /// Saved-route and planned-route decoders throw instead of returning nothing.
    func testRouteDecodersThrowForIncompleteRecords() {
        let route = CKRecord(recordType: CloudKitStore.savedRouteRecordType)
        route["localID"] = UUID().uuidString
        XCTAssertThrowsError(try CloudKitStore.decodeRoute(from: route))

        let planned = CKRecord(recordType: CloudKitStore.plannedRouteRecordType)
        XCTAssertThrowsError(try CloudKitStore.decodePlannedRoute(from: planned))
        planned["routeData"] = Data("not json".utf8)
        XCTAssertThrowsError(try CloudKitStore.decodePlannedRoute(from: planned)) { error in
            XCTAssertTrue(error.localizedDescription.contains("invalid routeData"))
        }
    }
}
