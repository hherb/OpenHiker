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

    /// Simulated clock for GPS fixes, so ``FixPlausibilityGate`` sees realistic elapsed time.
    private var clock = Date(timeIntervalSince1970: 0)

    /// A fix at (`lat`, `lon`), `seconds` after the previous one. The default of 10 minutes
    /// makes any jump on these test routes plausible; plausibility tests pass shorter gaps.
    /// `speed` and `speedAccuracy` default to -1 (invalid), as when no measured speed is known.
    private func fix(
        _ lat: Double, _ lon: Double, after seconds: TimeInterval = 600,
        speed: Double = -1, speedAccuracy: Double = -1
    ) -> CLLocation {
        clock += seconds
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, course: -1, courseAccuracy: -1,
            speed: speed, speedAccuracy: speedAccuracy, timestamp: clock)
    }

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

    /// Starts navigation and feeds a fix at the route start, so the plausibility gate has an
    /// accepted reference fix (a first fix far along the route is rechecked like any jump).
    private func startAtTrailhead(_ guidance: iOSRouteGuidance, _ route: PlannedRoute) {
        guidance.start(route: route)
        guidance.updateLocation(fix(route.coordinates[0].latitude, route.coordinates[0].longitude))
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

        let location = fix(0, 0.0001)
        guidance.updateLocation(location)

        XCTAssertLessThan(guidance.progress, 0.05, "Should be near the start")
        XCTAssertGreaterThan(guidance.remainingDistance, 1000, "Most of route should remain")
        XCTAssertFalse(guidance.isOffRoute)
    }

    /// Verifies that updating location near the midpoint shows ~50% progress.
    func testLocationUpdateAtMidpoint() {
        let guidance = iOSRouteGuidance()
        let route = makeStraightRoute()
        startAtTrailhead(guidance, route)

        let location = fix(0, 0.005)
        guidance.updateLocation(location)

        XCTAssertGreaterThan(guidance.progress, 0.4)
        XCTAssertLessThan(guidance.progress, 0.6)
    }

    /// Verifies that updating location near the end shows high progress.
    func testLocationUpdateNearEnd() {
        let guidance = iOSRouteGuidance()
        let route = makeStraightRoute()
        startAtTrailhead(guidance, route)

        let location = fix(0, 0.0098)
        guidance.updateLocation(location)

        XCTAssertGreaterThan(guidance.progress, 0.9)
    }

    /// Verifies that a location update when not navigating is a no-op.
    func testLocationUpdateIgnoredWhenNotNavigating() {
        let guidance = iOSRouteGuidance()
        let location = fix(0, 0.005)
        guidance.updateLocation(location)

        XCTAssertEqual(guidance.progress, 0, "Progress should remain 0 when not navigating")
    }

    // MARK: - Off-Route Detection

    /// Verifies that a location far from the route triggers off-route status.
    func testOffRouteDetection() {
        let guidance = iOSRouteGuidance()
        let route = makeStraightRoute()
        startAtTrailhead(guidance, route)

        // Move 0.01 degrees (~1.1 km) north of the east-running route → well off-route
        let farAway = fix(0.01, 0.005)
        guidance.updateLocation(farAway)

        XCTAssertTrue(guidance.isOffRoute)
    }

    /// Verifies that returning near the route clears off-route status.
    func testBackOnRoute() {
        let guidance = iOSRouteGuidance()
        let route = makeStraightRoute()
        startAtTrailhead(guidance, route)

        // Go off route
        let farAway = fix(0.01, 0.005)
        guidance.updateLocation(farAway)
        XCTAssertTrue(guidance.isOffRoute)

        // Come back on route
        let onRoute = fix(0, 0.005)
        guidance.updateLocation(onRoute)
        XCTAssertFalse(guidance.isOffRoute)
    }

    // MARK: - Instruction Advancement

    /// Verifies that current instruction advances when the user passes a turn point.
    func testInstructionAdvancement() {
        let guidance = iOSRouteGuidance()
        let route = makeRoutWithTurn()
        startAtTrailhead(guidance, route)

        // Should start on the "Turn left" instruction (index 1, skipping "Start")
        XCTAssertEqual(guidance.currentInstruction?.direction, .left)

        // Move past the turn point (the turn is at ~556m along the route)
        let pastTurn = fix(0.001, 0.005)
        guidance.updateLocation(pastTurn)

        // Should now advance to "Arrive" instruction
        XCTAssertEqual(guidance.currentInstruction?.direction, .arrive)
    }

    /// Regression test for #41: within the at-turn radius (30 m before the turn) the turn
    /// being approached must still be current, so its at-turn direction haptic can fire.
    func testInstructionDoesNotAdvanceBeforeTurnIsPassed() {
        let guidance = iOSRouteGuidance()
        startAtTrailhead(guidance, makeRoutWithTurn())

        // ~11 m before the turn at (0, 0.005)
        guidance.updateLocation(fix(0, 0.0049))

        XCTAssertEqual(guidance.currentInstruction?.direction, .left)
        XCTAssertLessThan(guidance.distanceToNextTurn ?? .infinity, RouteGuidanceConfig.atTurnDistanceMetres)
    }

    /// Arrival is handled once per session: repeated fixes at the end do not re-fire it, and
    /// restarting navigation resets it.
    func testArrivalHandledOncePerSession() {
        let guidance = iOSRouteGuidance()
        let route = makeRoutWithTurn()
        startAtTrailhead(guidance, route)
        XCTAssertFalse(guidance.arrivalHandled)

        guidance.updateLocation(fix(0.001, 0.005)) // past the turn
        guidance.updateLocation(fix(0.005, 0.005)) // at the end
        XCTAssertTrue(guidance.arrivalHandled)
        guidance.updateLocation(fix(0.005, 0.005))
        XCTAssertTrue(guidance.arrivalHandled)

        guidance.stop()
        startAtTrailhead(guidance, route)
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
        startAtTrailhead(guidance, route)

        // Near start, far from the turn
        let nearStart = fix(0, 0.001)
        guidance.updateLocation(nearStart)
        let distFar = guidance.distanceToNextTurn ?? 0

        // Closer to the turn
        let nearTurn = fix(0, 0.004)
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
                guidance.updateLocation(fix(
                    points[i - 1].latitude + t * (points[i].latitude - points[i - 1].latitude),
                    points[i - 1].longitude + t * (points[i].longitude - points[i - 1].longitude)
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
        guidance.updateLocation(fix(0.0001, 0.00001))
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

        guidance.updateLocation(fix(0, 0.0025))
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

    // MARK: - FixPlausibilityGate

    /// 1 m/s, so the reachable distance is 1.8 m per second plus the 15 m certainty radius.
    private func makeGate() -> FixPlausibilityGate { FixPlausibilityGate(speedMetresPerSecond: 1) }

    /// A forward step within the reachable distance is accepted at once.
    func testGateAcceptsPlausibleFix() {
        var gate = makeGate()
        XCTAssertEqual(gate.evaluate(fix(0, 0, after: 0), progressJump: 0), .accept)
        XCTAssertEqual(gate.evaluate(fix(0, 0.0001, after: 10), progressJump: 33), .accept, "33 <= 1.8*10 + 15")
        XCTAssertFalse(gate.isRechecking)
    }

    /// The reachable distance is the planned speed x 1.8 x elapsed time, plus the certainty radius.
    func testGateReachableDistance() {
        let gate = makeGate()
        XCTAssertEqual(gate.reachableDistance(elapsed: 0), 15)
        XCTAssertEqual(gate.reachableDistance(elapsed: 100), 195, accuracy: 1e-9)
        XCTAssertEqual(gate.reachableDistance(elapsed: -5), 15, "clock skew counts as no time")
    }

    /// An implausible jump is held back until two agreeing rechecks confirm it.
    func testGateConfirmsJumpAfterTwoAgreeingRechecks() {
        var gate = makeGate()
        XCTAssertEqual(gate.evaluate(fix(0, 0, after: 0), progressJump: 0), .accept)
        XCTAssertEqual(gate.evaluate(fix(0, 0.01, after: 1), progressJump: 1000), .recheck)
        XCTAssertTrue(gate.isRechecking)
        XCTAssertEqual(gate.evaluate(fix(0, 0.01005, after: 1), progressJump: 1005), .recheck, "1st recheck")
        XCTAssertEqual(gate.evaluate(fix(0, 0.0101, after: 1), progressJump: 1011), .accept, "2nd recheck")
        XCTAssertFalse(gate.isRechecking)
    }

    /// A recheck that disagrees with the suspect drops it and is judged on its own.
    func testGateDropsSuspectWhenRecheckDisagrees() {
        var gate = makeGate()
        XCTAssertEqual(gate.evaluate(fix(0, 0, after: 0), progressJump: 0), .accept)
        XCTAssertEqual(gate.evaluate(fix(0, 0.01, after: 1), progressJump: 1000), .recheck)
        XCTAssertEqual(gate.evaluate(fix(0, 0.00002, after: 1), progressJump: 2), .accept, "back where we were")
        XCTAssertFalse(gate.isRechecking)
    }

    /// After a long GPS gap, a long forward jump is plausible and accepted at once.
    func testGateAcceptsLongJumpAfterLongGap() {
        var gate = makeGate()
        XCTAssertEqual(gate.evaluate(fix(0, 0, after: 0), progressJump: 0), .accept)
        XCTAssertEqual(gate.evaluate(fix(0, 0.01, after: 1000), progressJump: 1112), .accept, "1112 <= 1815")
    }

    /// Planned speed is distance / duration, falling back to the mode's base speed without a duration.
    func testPlannedSpeed() {
        XCTAssertEqual(FixPlausibilityGate.plannedSpeed(for: makeRoutWithTurn()), 1112.0 / 900, accuracy: 1e-9)
        let route = makeRoutWithTurn()
        let noDuration = PlannedRoute(
            name: route.name, mode: .hiking, startCoordinate: route.startCoordinate,
            endCoordinate: route.endCoordinate, coordinates: route.coordinates,
            turnInstructions: route.turnInstructions, totalDistance: route.totalDistance,
            estimatedDuration: 0, elevationGain: 0, elevationLoss: 0)
        XCTAssertEqual(FixPlausibilityGate.plannedSpeed(for: noDuration),
                       RoutingCostConfig.hikingBaseSpeedMetresPerSecond)
    }

    /// Longitude degrees per metre at the equator, for building fixes a known distance apart.
    private let degreesPerMetre = 0.01 / 1111.95

    /// A measured speed is trusted only when it is valid and its accuracy is good enough.
    func testMeasuredSpeedNeedsGoodAccuracy() {
        XCTAssertEqual(FixPlausibilityGate.measuredSpeed(of: fix(0, 0, speed: 25, speedAccuracy: 1)), 25)
        XCTAssertNil(FixPlausibilityGate.measuredSpeed(of: fix(0, 0, speed: 25, speedAccuracy: 3)), "too inaccurate")
        XCTAssertNil(FixPlausibilityGate.measuredSpeed(of: fix(0, 0, speed: -1, speedAccuracy: 1)), "no speed")
        XCTAssertNil(FixPlausibilityGate.measuredSpeed(of: fix(0, 0, speed: 25, speedAccuracy: -1)), "no accuracy")
    }

    /// Real fast travel comes with a matching measured speed, so its fixes are accepted at once.
    func testGateUsesTrustedMeasuredSpeed() {
        var gate = makeGate()
        XCTAssertEqual(gate.evaluate(fix(0, 0, after: 0), progressJump: 0), .accept)
        XCTAssertEqual(gate.evaluate(
            fix(0, 25 * degreesPerMetre, after: 1, speed: 25, speedAccuracy: 1), progressJump: 25), .accept,
            "25 <= 25*1.8*1 + 15")
        XCTAssertEqual(gate.evaluate(
            fix(0, 50 * degreesPerMetre, after: 1, speed: 25, speedAccuracy: 5), progressJump: 25), .recheck,
            "untrusted speed: 25 > 1*1.8*1 + 15")
    }

    /// Steady travel too fast to confirm still ends the recheck after the cap: the first fix at or
    /// past 10 s since the recheck began is accepted.
    func testGateCapsRecheckDuration() {
        var gate = makeGate()
        XCTAssertEqual(gate.evaluate(fix(0, 0, after: 0), progressJump: 0), .accept)
        let decisions = (1...11).map { i in
            gate.evaluate(fix(0, Double(25 * i) * degreesPerMetre, after: 1), progressJump: Double(25 * i))
        }
        XCTAssertEqual(decisions, Array(repeating: .recheck, count: 10) + [.accept])
        XCTAssertFalse(gate.isRechecking)
    }

    /// Abandoning a recheck clears it, so the GPS burst can end when no fixes arrive.
    func testGateAbandonRecheck() {
        var gate = makeGate()
        XCTAssertEqual(gate.evaluate(fix(0, 0, after: 0), progressJump: 0), .accept)
        XCTAssertEqual(gate.evaluate(fix(0, 0.01, after: 1), progressJump: 1000), .recheck)
        gate.abandonRecheck()
        XCTAssertFalse(gate.isRechecking)
    }

    /// One wild fix far ahead during navigation neither skips the turn nor moves progress; the GPS
    /// is asked for rechecks, and the next real fix resumes guidance.
    func testGuidanceIgnoresSingleWildFix() {
        let guidance = iOSRouteGuidance()
        startAtTrailhead(guidance, makeRoutWithTurn())
        guidance.updateLocation(fix(0, 0.001))
        let progressBefore = guidance.progress

        guidance.updateLocation(fix(0.004, 0.005, after: 1)) // ~1 km ahead, past the turn
        XCTAssertTrue(guidance.isRecheckingFix)
        XCTAssertEqual(guidance.progress, progressBefore, "wild fix not applied")
        XCTAssertEqual(guidance.currentInstruction?.direction, .left, "turn not skipped")

        guidance.updateLocation(fix(0, 0.00101, after: 1)) // back at the real position
        XCTAssertFalse(guidance.isRecheckingFix)
        XCTAssertEqual(guidance.currentInstruction?.direction, .left)
        XCTAssertEqual(guidance.progress, progressBefore, accuracy: 0.01)
    }
}
