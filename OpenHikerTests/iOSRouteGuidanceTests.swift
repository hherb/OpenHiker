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

    /// Regression test for #41: within the at-turn radius (30 m before the turn) the turn
    /// being approached must still be current, so its at-turn direction haptic can fire.
    func testInstructionDoesNotAdvanceBeforeTurnIsPassed() {
        let guidance = iOSRouteGuidance()
        guidance.start(route: makeRoutWithTurn())

        // ~11 m before the turn at (0, 0.005)
        guidance.updateLocation(CLLocation(latitude: 0, longitude: 0.0049))

        XCTAssertEqual(guidance.currentInstruction?.direction, .left)
        XCTAssertLessThan(guidance.distanceToNextTurn ?? .infinity, RouteGuidanceConfig.atTurnDistanceMetres)
    }

    /// Arrival is handled once per session: repeated fixes at the end do not re-fire it, and
    /// restarting navigation resets it.
    func testArrivalHandledOncePerSession() {
        let guidance = iOSRouteGuidance()
        let route = makeRoutWithTurn()
        guidance.start(route: route)
        XCTAssertFalse(guidance.arrivalHandled)

        guidance.updateLocation(CLLocation(latitude: 0.001, longitude: 0.005)) // past the turn
        guidance.updateLocation(CLLocation(latitude: 0.005, longitude: 0.005)) // at the end
        XCTAssertTrue(guidance.arrivalHandled)
        guidance.updateLocation(CLLocation(latitude: 0.005, longitude: 0.005))
        XCTAssertTrue(guidance.arrivalHandled)

        guidance.stop()
        guidance.start(route: route)
        XCTAssertFalse(guidance.arrivalHandled, "restart resets arrival")
    }

    // MARK: - TurnInstructionProgress (pure functions)

    /// Instructions at cumulative distances 0 (start), 556 (left) and 1112 (arrive).
    private var turnInstructions: [TurnInstruction] { makeRoutWithTurn().turnInstructions }

    /// The index stays put while the user is short of the turn, including inside the at-turn radius.
    func testIndexStaysBeforeTurnIsPassed() {
        XCTAssertEqual(TurnInstructionProgress.indexAfterPassedTurns(
            from: 1, distanceAlongRoute: 100, instructions: turnInstructions), 1)
        XCTAssertEqual(TurnInstructionProgress.indexAfterPassedTurns(
            from: 1, distanceAlongRoute: 540, instructions: turnInstructions), 1)
    }

    /// The index advances once the turn point is reached or passed.
    func testIndexAdvancesOnceTurnIsPassed() {
        XCTAssertEqual(TurnInstructionProgress.indexAfterPassedTurns(
            from: 1, distanceAlongRoute: 556, instructions: turnInstructions), 2)
    }

    /// A GPS gap that jumps over several turns is caught up in one call, stopping at the last instruction.
    func testIndexSkipsSeveralTurnsButNotPastLast() {
        XCTAssertEqual(TurnInstructionProgress.indexAfterPassedTurns(
            from: 0, distanceAlongRoute: 5000, instructions: turnInstructions), 2)
    }

    /// The index never moves backwards when the user walks back along the route.
    func testIndexNeverMovesBackwards() {
        XCTAssertEqual(TurnInstructionProgress.indexAfterPassedTurns(
            from: 2, distanceAlongRoute: 0, instructions: turnInstructions), 2)
    }

    /// An empty instruction list leaves the index unchanged.
    func testIndexWithNoInstructions() {
        XCTAssertEqual(TurnInstructionProgress.indexAfterPassedTurns(
            from: 0, distanceAlongRoute: 100, instructions: []), 0)
    }

    /// Arrival needs both the last instruction and the user within the threshold of the end.
    func testHasArrived() {
        func arrived(_ index: Int, _ distance: Double) -> Bool {
            TurnInstructionProgress.hasArrived(
                currentIndex: index, instructionCount: 3, distanceAlongRoute: distance,
                totalRouteDistance: 1112, arrivalThresholdMetres: 30)
        }
        XCTAssertTrue(arrived(2, 1090))
        XCTAssertTrue(arrived(2, 1082), "exactly at the threshold")
        XCTAssertFalse(arrived(2, 1081.9))
        XCTAssertFalse(arrived(2, 1000), "too far from the end")
        XCTAssertFalse(arrived(1, 1112), "not on the last instruction")
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

    // MARK: - Loop and Out-and-Back Routes (#44)

    /// Builds a route through `points` with a turn instruction at every point: `.start` first,
    /// `.arrive` last, and `middle` directions in between.
    private func makeRoute(_ points: [CLLocationCoordinate2D], middle: TurnDirection) -> PlannedRoute {
        let cumulative = RouteProjection.cumulativeDistances(points)
        let instructions = points.indices.map { i in
            TurnInstruction(
                coordinate: points[i],
                direction: i == 0 ? .start : (i == points.count - 1 ? .arrive : middle),
                bearing: 0,
                distanceFromPrevious: i == 0 ? 0 : cumulative[i] - cumulative[i - 1],
                cumulativeDistance: cumulative[i],
                trailName: nil,
                description: "Step \(i)"
            )
        }
        return PlannedRoute(
            name: "Test", mode: .hiking, startCoordinate: points[0], endCoordinate: points[points.count - 1],
            coordinates: points, turnInstructions: instructions, totalDistance: cumulative.last ?? 0,
            estimatedDuration: 600, elevationGain: 0, elevationLoss: 0
        )
    }

    /// Feeds fixes every tenth of a segment along `points`, skipping the very first point.
    private func walk(_ guidance: iOSRouteGuidance, along points: [CLLocationCoordinate2D]) {
        for i in 1..<points.count {
            for step in 1...10 {
                let t = Double(step) / 10
                guidance.updateLocation(CLLocation(
                    latitude: points[i - 1].latitude + t * (points[i].latitude - points[i - 1].latitude),
                    longitude: points[i - 1].longitude + t * (points[i].longitude - points[i - 1].longitude)
                ))
            }
        }
    }

    /// A square loop: the first fix near the trailhead is nearer the closing segment than the first
    /// one, but must still count as the start, and arrival fires only back at the trailhead.
    func testLoopRouteStartsAtStartAndArrivesAtEnd() {
        let corners = [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.005),
            CLLocationCoordinate2D(latitude: 0.005, longitude: 0.005),
            CLLocationCoordinate2D(latitude: 0.005, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
        ]
        let guidance = iOSRouteGuidance()
        guidance.start(route: makeRoute(corners, middle: .left))

        // ~11 m north of the trailhead, ~1 m east of it: nearest is the closing segment.
        guidance.updateLocation(CLLocation(latitude: 0.0001, longitude: 0.00001))
        XCTAssertFalse(guidance.arrivalHandled, "no arrival at the trailhead")
        XCTAssertLessThan(guidance.progress, 0.05)
        XCTAssertEqual(guidance.currentInstruction?.coordinate.longitude, 0.005, "heading for the first corner")

        walk(guidance, along: corners)
        XCTAssertTrue(guidance.arrivalHandled, "arrives back at the trailhead")
        XCTAssertEqual(guidance.currentInstruction?.direction, .arrive)
    }

    /// An out-and-back route retraces the same trail: on the way back the fix lies on both legs,
    /// and must be placed on the return leg so the route finishes.
    func testOutAndBackRouteFollowsReturnLeg() {
        let points = [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.005),
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
        ]
        let guidance = iOSRouteGuidance()
        guidance.start(route: makeRoute(points, middle: .uTurn))

        walk(guidance, along: Array(points[0...1]))
        XCTAssertEqual(guidance.currentInstruction?.direction, .arrive, "u-turn passed")

        guidance.updateLocation(CLLocation(latitude: 0, longitude: 0.0025))
        XCTAssertEqual(guidance.progress, 0.75, accuracy: 0.01, "on the return leg, not the outbound one")
        XCTAssertFalse(guidance.arrivalHandled)

        walk(guidance, along: Array(points[1...2]))
        XCTAssertTrue(guidance.arrivalHandled, "arrives back at the start")
    }

    // MARK: - RouteProjection (pure functions)

    /// Cumulative distances start at 0 and grow by each segment length; empty input gives [].
    func testCumulativeDistances() {
        XCTAssertEqual(RouteProjection.cumulativeDistances([]), [])
        let d = RouteProjection.cumulativeDistances(makeRoutWithTurn().coordinates)
        XCTAssertEqual(d.count, 3)
        XCTAssertEqual(d[0], 0)
        XCTAssertEqual(d[1], 556, accuracy: 1)
        XCTAssertEqual(d[2], 1112, accuracy: 2)
    }

    /// An empty route has no projection; a one-point route projects onto that point.
    func testProjectDegenerateRoutes() {
        let fix = CLLocationCoordinate2D(latitude: 0.001, longitude: 0)
        XCTAssertNil(RouteProjection.project(fix, onto: [], cumulativeDistances: [], progressHighWaterMark: 0))
        let single = RouteProjection.project(
            fix, onto: [CLLocationCoordinate2D(latitude: 0, longitude: 0)], cumulativeDistances: [0],
            progressHighWaterMark: 0)
        XCTAssertEqual(single?.distanceAlong, 0)
        XCTAssertEqual(single?.distanceFromRoute ?? 0, 111, accuracy: 1)
    }

    /// With only one segment nearby, a walk back along the route is still followed: the high-water
    /// mark breaks ties between legs, it does not pin the user to it.
    func testProjectFollowsGenuineBacktrack() {
        let route = makeRoutWithTurn().coordinates
        let result = RouteProjection.project(
            CLLocationCoordinate2D(latitude: 0, longitude: 0.001), onto: route,
            cumulativeDistances: RouteProjection.cumulativeDistances(route), progressHighWaterMark: 1000)
        XCTAssertEqual(result?.segment, 0)
        XCTAssertEqual(result?.distanceAlong ?? 0, 111, accuracy: 1)
    }
}
