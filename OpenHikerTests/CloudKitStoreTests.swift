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
        record["label"] = label
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
