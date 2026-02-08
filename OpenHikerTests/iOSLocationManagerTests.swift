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

/// Tests for ``iOSLocationManager``, which manages GPS tracking and
/// track recording for the iPhone hiking navigation feature.
final class iOSLocationManagerTests: XCTestCase {

    // MARK: - Initial State

    /// Verifies default property values before any tracking begins.
    func testInitialState() {
        let manager = iOSLocationManager()
        XCTAssertNil(manager.currentLocation)
        XCTAssertNil(manager.heading)
        XCTAssertFalse(manager.isTracking)
        XCTAssertNil(manager.trackingError)
        XCTAssertTrue(manager.trackPoints.isEmpty)
        XCTAssertEqual(manager.totalDistance, 0)
        XCTAssertEqual(manager.elevationGain, 0)
        XCTAssertEqual(manager.elevationLoss, 0)
    }

    // MARK: - GPS Modes

    /// Verifies that all GPS modes return sensible accuracy settings.
    func testGPSModeSettings() {
        XCTAssertEqual(
            iOSLocationManager.GPSMode.highAccuracy.desiredAccuracy,
            kCLLocationAccuracyBest
        )
        XCTAssertEqual(
            iOSLocationManager.GPSMode.highAccuracy.distanceFilter,
            5
        )

        XCTAssertEqual(
            iOSLocationManager.GPSMode.balanced.desiredAccuracy,
            kCLLocationAccuracyNearestTenMeters
        )
        XCTAssertEqual(
            iOSLocationManager.GPSMode.balanced.distanceFilter,
            10
        )

        XCTAssertEqual(
            iOSLocationManager.GPSMode.lowPower.desiredAccuracy,
            kCLLocationAccuracyHundredMeters
        )
        XCTAssertEqual(
            iOSLocationManager.GPSMode.lowPower.distanceFilter,
            50
        )
    }

    /// Verifies that all GPS modes have human-readable descriptions.
    func testGPSModeDescriptions() {
        for mode in iOSLocationManager.GPSMode.allCases {
            XCTAssertFalse(mode.description.isEmpty, "\(mode.rawValue) should have a description")
        }
    }

    // MARK: - Duration

    /// Verifies that duration returns nil when there are fewer than 2 track points.
    func testDurationNilWithoutEnoughPoints() {
        let manager = iOSLocationManager()
        XCTAssertNil(manager.duration)
    }

    // MARK: - Default GPS Mode

    /// Verifies that the default GPS mode is high accuracy.
    func testDefaultGPSMode() {
        let manager = iOSLocationManager()
        XCTAssertEqual(manager.gpsMode, .highAccuracy)
    }
}
