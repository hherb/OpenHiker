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

    // MARK: - Invalid Altitudes (#63)

    /// Builds a fix `step` × ~11 m north of a fixed start, so consecutive fixes pass
    /// the 5 m high-accuracy distance filter. A negative `vacc` marks the altitude invalid.
    private func fix(step: Int, altitude: Double, vacc: Double = 5, hacc: Double = 5) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 47 + Double(step) * 0.0001, longitude: 11),
            altitude: altitude,
            horizontalAccuracy: hacc,
            verticalAccuracy: vacc,
            timestamp: Date(timeIntervalSince1970: TimeInterval(step))
        )
    }

    /// Feeds fixes through the delegate of a tracking manager and returns it.
    ///
    /// Keep the fixes under 10: the 10th point persists tracking state to disk.
    /// `stopTracking()` runs at teardown to clear any persisted state anyway.
    private func record(_ fixes: [CLLocation]) -> iOSLocationManager {
        let manager = iOSLocationManager()
        manager.isTracking = true
        addTeardownBlock { manager.stopTracking() }
        let clManager = CLLocationManager()
        for f in fixes {
            manager.locationManager(clManager, didUpdateLocations: [f])
        }
        return manager
    }

    /// A mid-hike fix without a valid altitude is stored at the last valid altitude
    /// and adds no gain or loss, while its distance still counts.
    func testInvalidAltitudeFixAddsNoElevation() {
        let manager = record([
            fix(step: 0, altitude: 500),
            fix(step: 1, altitude: 0, vacc: -1),
            fix(step: 2, altitude: 510)
        ])
        XCTAssertEqual(manager.trackPoints.map(\.altitude), [500, 500, 510])
        XCTAssertEqual(manager.elevationGain, 10, accuracy: 0.001)
        XCTAssertEqual(manager.elevationLoss, 0)
        XCTAssertGreaterThan(manager.totalDistance, 20)
    }

    /// Leading fixes without altitude are backfilled, and reaching the first valid
    /// altitude does not count as a climb.
    func testLeadingInvalidAltitudesAreBackfilledWithoutGain() {
        let manager = record([
            fix(step: 0, altitude: 0, vacc: -1),
            fix(step: 1, altitude: 0, vacc: -1),
            fix(step: 2, altitude: 820),
            fix(step: 3, altitude: 830)
        ])
        XCTAssertEqual(manager.trackPoints.map(\.altitude), [820, 820, 820, 830])
        XCTAssertEqual(manager.elevationGain, 10, accuracy: 0.001)
        XCTAssertEqual(manager.elevationLoss, 0)
    }

    /// A low-accuracy fix is not used as the elevation baseline, even with a valid altitude.
    func testLowAccuracyFixIsNotElevationBaseline() {
        let manager = record([
            fix(step: 0, altitude: 500),
            fix(step: 1, altitude: 900, hacc: 150),
            fix(step: 2, altitude: 510)
        ])
        XCTAssertEqual(manager.elevationGain, 10, accuracy: 0.001)
        XCTAssertEqual(manager.elevationLoss, 0)
    }
}
