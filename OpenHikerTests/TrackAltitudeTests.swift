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

/// Tests for ``TrackAltitude``, which keeps fixes without a valid altitude
/// (`verticalAccuracy < 0`) out of the stored track's altitudes and the elevation totals (#63).
final class TrackAltitudeTests: XCTestCase {

    /// Builds a fix. A negative `verticalAccuracy` marks its altitude as invalid.
    private func fix(
        _ altitude: Double,
        verticalAccuracy: Double = 5,
        horizontalAccuracy: Double = 5,
        t: TimeInterval
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 47, longitude: 11),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            timestamp: Date(timeIntervalSince1970: t)
        )
    }

    // MARK: - resolve

    /// A fix with a valid altitude is stored unchanged.
    func testValidFixIsStoredAsIs() {
        var recorded = [fix(500, t: 1)]
        let stored = TrackAltitude.resolve(fix(510, t: 2), recorded: &recorded)
        XCTAssertEqual(stored.altitude, 510)
        XCTAssertEqual(recorded.map(\.altitude), [500])
    }

    /// A fix with an invalid altitude reuses the last valid one and stays marked invalid.
    func testInvalidFixReusesLastValidAltitude() {
        var recorded = [fix(500, t: 1), fix(0, verticalAccuracy: -1, t: 2)]
        recorded[1] = TrackAltitude.resolve(recorded[1], recorded: &recorded)
        let stored = TrackAltitude.resolve(fix(0, verticalAccuracy: -1, t: 3), recorded: &recorded)
        XCTAssertEqual(stored.altitude, 500)
        XCTAssertLessThan(stored.verticalAccuracy, 0)
        XCTAssertEqual(stored.timestamp, Date(timeIntervalSince1970: 3))
    }

    /// Before any valid altitude, an invalid fix stores the placeholder.
    func testNoValidAltitudeYetStoresPlaceholder() {
        var recorded: [CLLocation] = []
        let stored = TrackAltitude.resolve(fix(-37, verticalAccuracy: -1, t: 1), recorded: &recorded)
        XCTAssertEqual(stored.altitude, TrackAltitude.unknownAltitudeMetres)
    }

    /// The first valid altitude rewrites the earlier points that had none.
    func testFirstValidAltitudeBackfillsLeadingPoints() {
        var recorded = [fix(0, verticalAccuracy: -1, t: 1), fix(0, verticalAccuracy: -1, t: 2)]
        let stored = TrackAltitude.resolve(fix(820, t: 3), recorded: &recorded)
        XCTAssertEqual(stored.altitude, 820)
        XCTAssertEqual(recorded.map(\.altitude), [820, 820])
        XCTAssertEqual(recorded.map(\.timestamp.timeIntervalSince1970), [1, 2])
        XCTAssertTrue(recorded.allSatisfy { $0.verticalAccuracy < 0 }, "backfilled points stay marked unmeasured")
    }

    /// Later valid altitudes do not rewrite earlier points.
    func testLaterValidAltitudeDoesNotRewrite() {
        var recorded = [fix(820, t: 1), fix(830, t: 2)]
        _ = TrackAltitude.resolve(fix(900, t: 3), recorded: &recorded)
        XCTAssertEqual(recorded.map(\.altitude), [820, 830])
    }

    // MARK: - elevationChange

    /// A fix without a valid altitude adds no elevation change.
    func testInvalidFixHasNoElevationChange() {
        XCTAssertNil(TrackAltitude.elevationChange(to: fix(0, verticalAccuracy: -1, t: 2), since: [fix(500, t: 1)]))
    }

    /// With no valid baseline yet, there is no elevation change, so the first altitude is no spike.
    func testNoBaselineHasNoElevationChange() {
        let recorded = [fix(0, verticalAccuracy: -1, t: 1)]
        XCTAssertNil(TrackAltitude.elevationChange(to: fix(820, t: 2), since: recorded))
    }

    /// The change is measured from the last valid altitude, across points without one.
    func testChangeIsMeasuredAcrossInvalidPoints() {
        let recorded = [fix(500, t: 1), fix(500, verticalAccuracy: -1, t: 2)]
        XCTAssertEqual(TrackAltitude.elevationChange(to: fix(510, t: 3), since: recorded), 10)
    }

    /// Only points that pass `countingOnly` serve as the baseline.
    func testBaselineSkipsUncountedPoints() {
        let recorded = [fix(500, t: 1), fix(530, horizontalAccuracy: 150, t: 2)]
        let change = TrackAltitude.elevationChange(
            to: fix(510, t: 3), since: recorded, countingOnly: { $0.horizontalAccuracy < 100 }
        )
        XCTAssertEqual(change, 10)
    }

    // MARK: - Waypoint.fromLocation

    /// A waypoint from a fix without a valid altitude has no altitude, not 0 m.
    func testWaypointFromInvalidAltitudeFixHasNoAltitude() {
        XCTAssertNil(Waypoint.fromLocation(fix(0, verticalAccuracy: -1, t: 1)).altitude)
    }

    /// A valid altitude below sea level is kept on the waypoint.
    func testWaypointKeepsValidAltitudeBelowSeaLevel() {
        XCTAssertEqual(Waypoint.fromLocation(fix(-400, t: 1)).altitude, -400)
    }
}
