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

/// Tests for the iCloud sync step runner (#81) and the published sync result (#78).
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
}
