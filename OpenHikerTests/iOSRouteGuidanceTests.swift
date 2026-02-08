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

/// Tests for ``iOSRouteGuidance``, which tracks the user's position along a
/// planned route and provides turn-by-turn navigation feedback.
@MainActor
final class iOSRouteGuidanceTests: XCTestCase {

    // MARK: - Test Helpers

    /// Creates a simple straight-line route from (0,0) to (0,0.01) with two
    /// turn instructions: "Start" at the beginning and "Arrive" at the end.
    ///
    /// Route is approximately 1.1 km long (0.01 degrees longitude at equator).
    private func makeStraightRoute() -> PlannedRoute {
        let start = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let end = CLLocationCoordinate2D(latitude: 0, longitude: 0.01)

        let coordinates = [start, end]
        let totalDistance = 1111.95 // ~0.01 degrees at equator in metres

        let instructions = [
            TurnInstruction(
                coordinate: start,
                direction: .start,
                bearing: 90,
                distanceFromPrevious: 0,
                cumulativeDistance: 0,
                trailName: nil,
                description: "Start heading east"
            ),
            TurnInstruction(
                coordinate: end,
                direction: .arrive,
                bearing: 90,
                distanceFromPrevious: totalDistance,
                cumulativeDistance: totalDistance,
                trailName: nil,
                description: "Arrive at destination"
            ),
        ]

        return PlannedRoute(
            name: "Test Route",
            mode: .hiking,
            startCoordinate: start,
            endCoordinate: end,
            coordinates: coordinates,
            turnInstructions: instructions,
            totalDistance: totalDistance,
            estimatedDuration: 600,
            elevationGain: 0,
            elevationLoss: 0
        )
    }

    /// Creates a route with a left turn in the middle for testing instruction
    /// advancement and off-route detection.
    ///
    /// Route: (0,0) → (0,0.005) → (0.005,0.005) with a left turn at the midpoint.
    private func makeRoutWithTurn() -> PlannedRoute {
        let p1 = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let p2 = CLLocationCoordinate2D(latitude: 0, longitude: 0.005)
        let p3 = CLLocationCoordinate2D(latitude: 0.005, longitude: 0.005)

        let coordinates = [p1, p2, p3]
        let segDist = 556.0 // approx distance of each segment in metres
        let totalDistance = segDist * 2

        let instructions = [
            TurnInstruction(
                coordinate: p1,
                direction: .start,
                bearing: 90,
                distanceFromPrevious: 0,
                cumulativeDistance: 0,
                trailName: nil,
                description: "Start heading east"
            ),
            TurnInstruction(
                coordinate: p2,
                direction: .left,
                bearing: 0,
                distanceFromPrevious: segDist,
                cumulativeDistance: segDist,
                trailName: "North Trail",
                description: "Turn left onto North Trail"
            ),
            TurnInstruction(
                coordinate: p3,
                direction: .arrive,
                bearing: 0,
                distanceFromPrevious: segDist,
                cumulativeDistance: totalDistance,
                trailName: nil,
                description: "Arrive at destination"
            ),
        ]

        return PlannedRoute(
            name: "Turn Route",
            mode: .hiking,
            startCoordinate: p1,
            endCoordinate: p3,
            coordinates: coordinates,
            turnInstructions: instructions,
            totalDistance: totalDistance,
            estimatedDuration: 900,
            elevationGain: 0,
            elevationLoss: 0
        )
    }

    // MARK: - Initial State

    /// Verifies default state before starting navigation.
    func testInitialState() {
        let guidance = iOSRouteGuidance()
        XCTAssertFalse(guidance.isNavigating)
        XCTAssertNil(guidance.activeRoute)
        XCTAssertNil(guidance.currentInstruction)
        XCTAssertNil(guidance.distanceToNextTurn)
        XCTAssertEqual(guidance.progress, 0)
        XCTAssertEqual(guidance.remainingDistance, 0)
        XCTAssertFalse(guidance.isOffRoute)
    }

    // MARK: - Start / Stop

    /// Verifies that ``start(route:)`` sets navigation state correctly.
    func testStartSetsNavigationState() {
        let guidance = iOSRouteGuidance()
        let route = makeStraightRoute()

        guidance.start(route: route)

        XCTAssertTrue(guidance.isNavigating)
        XCTAssertNotNil(guidance.activeRoute)
        XCTAssertEqual(guidance.activeRoute?.name, "Test Route")
        XCTAssertFalse(guidance.isOffRoute)
    }

    /// Verifies that the first non-start instruction is set as current.
    func testStartSkipsStartInstruction() {
        let guidance = iOSRouteGuidance()
        let route = makeStraightRoute()

        guidance.start(route: route)

        // Should skip "Start" and set "Arrive" as current instruction
        XCTAssertEqual(guidance.currentInstruction?.direction, .arrive)
    }

    /// Verifies that ``stop()`` clears all navigation state.
    func testStopClearsState() {
        let guidance = iOSRouteGuidance()
        let route = makeStraightRoute()

        guidance.start(route: route)
        guidance.stop()

        XCTAssertFalse(guidance.isNavigating)
        XCTAssertNil(guidance.activeRoute)
        XCTAssertNil(guidance.currentInstruction)
        XCTAssertNil(guidance.distanceToNextTurn)
        XCTAssertEqual(guidance.progress, 0)
        XCTAssertEqual(guidance.remainingDistance, 0)
        XCTAssertFalse(guidance.isOffRoute)
    }

    // MARK: - Location Updates

    /// Verifies that updating location near the route start shows low progress
    /// and high remaining distance.
    func testLocationUpdateNearStart() {
        let guidance = iOSRouteGuidance()
        let route = makeStraightRoute()
        guidance.start(route: route)

        let location = CLLocation(latitude: 0, longitude: 0.0001)
        guidance.updateLocation(location)

        XCTAssertLessThan(guidance.progress, 0.05, "Should be near the start")
        XCTAssertGreaterThan(guidance.remainingDistance, 1000, "Most of route should remain")
        XCTAssertFalse(guidance.isOffRoute)
    }

    /// Verifies that updating location near the midpoint shows ~50% progress.
    func testLocationUpdateAtMidpoint() {
        let guidance = iOSRouteGuidance()
        let route = makeStraightRoute()
        guidance.start(route: route)

        let location = CLLocation(latitude: 0, longitude: 0.005)
        guidance.updateLocation(location)

        XCTAssertGreaterThan(guidance.progress, 0.4)
        XCTAssertLessThan(guidance.progress, 0.6)
    }

    /// Verifies that updating location near the end shows high progress.
    func testLocationUpdateNearEnd() {
        let guidance = iOSRouteGuidance()
        let route = makeStraightRoute()
        guidance.start(route: route)

        let location = CLLocation(latitude: 0, longitude: 0.0098)
        guidance.updateLocation(location)

        XCTAssertGreaterThan(guidance.progress, 0.9)
    }

    /// Verifies that a location update when not navigating is a no-op.
    func testLocationUpdateIgnoredWhenNotNavigating() {
        let guidance = iOSRouteGuidance()
        let location = CLLocation(latitude: 0, longitude: 0.005)
        guidance.updateLocation(location)

        XCTAssertEqual(guidance.progress, 0, "Progress should remain 0 when not navigating")
    }

    // MARK: - Off-Route Detection

    /// Verifies that a location far from the route triggers off-route status.
    func testOffRouteDetection() {
        let guidance = iOSRouteGuidance()
        let route = makeStraightRoute()
        guidance.start(route: route)

        // Move 0.01 degrees (~1.1 km) north of the east-running route → well off-route
        let farAway = CLLocation(latitude: 0.01, longitude: 0.005)
        guidance.updateLocation(farAway)

        XCTAssertTrue(guidance.isOffRoute)
    }

    /// Verifies that returning near the route clears off-route status.
    func testBackOnRoute() {
        let guidance = iOSRouteGuidance()
        let route = makeStraightRoute()
        guidance.start(route: route)

        // Go off route
        let farAway = CLLocation(latitude: 0.01, longitude: 0.005)
        guidance.updateLocation(farAway)
        XCTAssertTrue(guidance.isOffRoute)

        // Come back on route
        let onRoute = CLLocation(latitude: 0, longitude: 0.005)
        guidance.updateLocation(onRoute)
        XCTAssertFalse(guidance.isOffRoute)
    }

    // MARK: - Instruction Advancement

    /// Verifies that current instruction advances when the user passes a turn point.
    func testInstructionAdvancement() {
        let guidance = iOSRouteGuidance()
        let route = makeRoutWithTurn()
        guidance.start(route: route)

        // Should start on the "Turn left" instruction (index 1, skipping "Start")
        XCTAssertEqual(guidance.currentInstruction?.direction, .left)

        // Move past the turn point (the turn is at ~556m along the route)
        let pastTurn = CLLocation(latitude: 0.001, longitude: 0.005)
        guidance.updateLocation(pastTurn)

        // Should now advance to "Arrive" instruction
        XCTAssertEqual(guidance.currentInstruction?.direction, .arrive)
    }

    // MARK: - Distance to Next Turn

    /// Verifies that ``distanceToNextTurn`` decreases as the user approaches.
    func testDistanceToNextTurnDecreases() {
        let guidance = iOSRouteGuidance()
        let route = makeRoutWithTurn()
        guidance.start(route: route)

        // Near start, far from the turn
        let nearStart = CLLocation(latitude: 0, longitude: 0.001)
        guidance.updateLocation(nearStart)
        let distFar = guidance.distanceToNextTurn ?? 0

        // Closer to the turn
        let nearTurn = CLLocation(latitude: 0, longitude: 0.004)
        guidance.updateLocation(nearTurn)
        let distClose = guidance.distanceToNextTurn ?? 0

        XCTAssertGreaterThan(distFar, distClose, "Distance should decrease as user approaches turn")
    }
}
