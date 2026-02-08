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

/// Tests for ``WatchHealthRelay``, which receives live health data from the
/// Apple Watch and publishes it for the iPhone navigation UI.
@MainActor
final class WatchHealthRelayTests: XCTestCase {

    // MARK: - Initial State

    /// Verifies that all published properties start as nil/false/zero.
    func testInitialState() {
        let relay = WatchHealthRelay()
        XCTAssertNil(relay.heartRate)
        XCTAssertNil(relay.spO2)
        XCTAssertNil(relay.uvIndex)
        XCTAssertNil(relay.uvCategory)
        XCTAssertFalse(relay.isReceivingData)
        XCTAssertNil(relay.averageHeartRate)
    }

    // MARK: - Update

    /// Verifies that ``update(heartRate:spO2:uvIndex:)`` stores all values
    /// and sets ``isReceivingData`` to true.
    func testUpdateSetsAllValues() {
        let relay = WatchHealthRelay()
        relay.update(heartRate: 72, spO2: 0.98, uvIndex: 5)

        XCTAssertEqual(relay.heartRate, 72)
        XCTAssertEqual(relay.spO2, 0.98)
        XCTAssertEqual(relay.uvIndex, 5)
        XCTAssertEqual(relay.uvCategory, .moderate)
        XCTAssertTrue(relay.isReceivingData)
    }

    /// Verifies that nil values in an update leave existing readings unchanged.
    func testPartialUpdatePreservesExistingValues() {
        let relay = WatchHealthRelay()
        relay.update(heartRate: 72, spO2: 0.98, uvIndex: 5)
        relay.update(heartRate: 80, spO2: nil, uvIndex: nil)

        XCTAssertEqual(relay.heartRate, 80, "Heart rate should update")
        XCTAssertEqual(relay.spO2, 0.98, "SpO2 should remain from previous update")
        XCTAssertEqual(relay.uvIndex, 5, "UV index should remain from previous update")
    }

    /// Verifies UV category mapping for all tiers.
    func testUVCategoryMapping() {
        let relay = WatchHealthRelay()

        relay.update(heartRate: nil, spO2: nil, uvIndex: 1)
        XCTAssertEqual(relay.uvCategory, .low)

        relay.update(heartRate: nil, spO2: nil, uvIndex: 4)
        XCTAssertEqual(relay.uvCategory, .moderate)

        relay.update(heartRate: nil, spO2: nil, uvIndex: 7)
        XCTAssertEqual(relay.uvCategory, .high)

        relay.update(heartRate: nil, spO2: nil, uvIndex: 9)
        XCTAssertEqual(relay.uvCategory, .veryHigh)

        relay.update(heartRate: nil, spO2: nil, uvIndex: 11)
        XCTAssertEqual(relay.uvCategory, .extreme)
    }

    // MARK: - Heart Rate Averaging

    /// Verifies that ``averageHeartRate`` computes a running mean across all updates.
    func testAverageHeartRateRunningMean() {
        let relay = WatchHealthRelay()

        relay.update(heartRate: 60, spO2: nil, uvIndex: nil)
        XCTAssertEqual(relay.averageHeartRate, 60)

        relay.update(heartRate: 80, spO2: nil, uvIndex: nil)
        XCTAssertEqual(relay.averageHeartRate, 70) // (60+80)/2

        relay.update(heartRate: 90, spO2: nil, uvIndex: nil)
        XCTAssertEqual(relay.averageHeartRate! , (60.0 + 80.0 + 90.0) / 3.0, accuracy: 0.01)
    }

    /// Verifies that ``averageHeartRate`` is nil when no heart rate data received.
    func testAverageHeartRateNilWithoutData() {
        let relay = WatchHealthRelay()
        relay.update(heartRate: nil, spO2: 0.98, uvIndex: 3)
        XCTAssertNil(relay.averageHeartRate)
    }

    // MARK: - Clear

    /// Verifies that ``clearAll()`` resets every property including averages.
    func testClearAllResetsEverything() {
        let relay = WatchHealthRelay()
        relay.update(heartRate: 72, spO2: 0.98, uvIndex: 5)
        relay.clearAll()

        XCTAssertNil(relay.heartRate)
        XCTAssertNil(relay.spO2)
        XCTAssertNil(relay.uvIndex)
        XCTAssertNil(relay.uvCategory)
        XCTAssertFalse(relay.isReceivingData)
        XCTAssertNil(relay.averageHeartRate)
    }

    /// Verifies that heart rate averaging resets after ``clearAll()``.
    func testClearAllResetsAveraging() {
        let relay = WatchHealthRelay()
        relay.update(heartRate: 100, spO2: nil, uvIndex: nil)
        relay.update(heartRate: 200, spO2: nil, uvIndex: nil)
        XCTAssertEqual(relay.averageHeartRate, 150)

        relay.clearAll()
        relay.update(heartRate: 80, spO2: nil, uvIndex: nil)
        XCTAssertEqual(relay.averageHeartRate, 80, "Average should restart after clear")
    }
}
