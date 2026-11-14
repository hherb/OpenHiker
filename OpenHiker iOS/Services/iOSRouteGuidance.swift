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

import Foundation
import CoreLocation
import UIKit

// MARK: - iOS Route Guidance

/// Tracks the user's position along a planned route on iPhone, providing
/// turn-by-turn navigation with UIKit haptic feedback.
///
/// Functionally identical to the watchOS ``RouteGuidance`` but uses
/// `UIImpactFeedbackGenerator` and `UINotificationFeedbackGenerator`
/// instead of `WKHapticType` for haptic output.
///
/// ## Usage
/// ```swift
/// let guidance = iOSRouteGuidance()
/// guidance.start(route: plannedRoute)
/// // Feed GPS updates:
/// guidance.updateLocation(newLocation)
/// // When done:
/// guidance.stop()
/// ```
@MainActor
final class iOSRouteGuidance: ObservableObject {

    // MARK: - Published State

    /// The turn instruction the user should follow next.
    @Published var currentInstruction: TurnInstruction?

    /// Distance from the user's current position to the next turn point, in metres.
    @Published var distanceToNextTurn: Double?

    /// Route completion progress from 0.0 (start) to 1.0 (destination).
    @Published var progress: Double = 0

    /// Remaining distance to the destination in metres.
    @Published var remainingDistance: Double = 0

    /// Whether the user is currently more than the off-route threshold from the route.
    @Published var isOffRoute: Bool = false

    /// Whether a suspect GPS fix is being rechecked. Observers should switch the GPS to fast,
    /// high-accuracy updates while this is true. See ``FixPlausibilityGate``.
    @Published private(set) var isRecheckingFix: Bool = false

    /// Whether active navigation is in progress.
    @Published var isNavigating: Bool = false

    /// The planned route being navigated, or `nil` if not navigating.
    @Published var activeRoute: PlannedRoute?

    // MARK: - Internal State

    /// Index into the route's `turnInstructions` array for the current instruction.
    private var currentInstructionIndex: Int = 0

    /// Whether the "approaching turn" haptic has fired for the current instruction.
    private var approachingHapticFired: Bool = false

    /// Whether the "at turn" haptic has fired for the current instruction.
    private var atTurnHapticFired: Bool = false

    /// Whether arrival feedback has fired for this navigation session, so it fires only once.
    private(set) var arrivalHandled: Bool = false

    /// Precomputed cumulative distances along the route polyline at each coordinate index.
    private var cumulativeDistances: [Double] = []

    /// Total length of the route polyline in metres.
    private var totalRouteDistance: Double = 0

    /// The furthest distance along the route reached this session, in metres. Lets
    /// ``RouteProjection`` pick the right leg of a loop or out-and-back route.
    private var progressHighWaterMark: Double = 0

    /// Whether a fix with a trusted course has been accepted this session. Until then the course
    /// picks the leg of an out-and-back (#46); after it, continuity with progress alone decides, so
    /// a short turn-back cannot jump guidance to the other leg.
    private var legChosenByCourse = false

    /// Holds back fixes that jump further along the route than the user could have walked.
    private var plausibilityGate = FixPlausibilityGate(speedMetresPerSecond: 0)

    /// Abandons a recheck that gets no fixes in time, so the GPS cannot stay in burst mode.
    private var recheckTimeout: Task<Void, Never>?

    /// The current time, used to drop fixes that are too old or future-dated. Tests replace it
    /// with their simulated clock.
    var currentDate: () -> Date = Date.init

    /// The monotonic time, used to spot a forward clock jump (#53). Tests replace it with their
    /// simulated clock.
    var currentMonotonicTime: () -> TimeInterval = FixPlausibilityGate.monotonicTime

    /// Haptic feedback generators for iPhone.
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    // MARK: - Public API

    /// Starts active navigation along the given planned route.
    ///
    /// Resets all state, precomputes cumulative distances along the polyline,
    /// and sets the first turn instruction as current.
    ///
    /// - Parameter route: The ``PlannedRoute`` to navigate.
    func start(route: PlannedRoute) {
        activeRoute = route
        isNavigating = true
        isOffRoute = false
        progress = 0
        remainingDistance = route.totalDistance
        currentInstructionIndex = 0
        approachingHapticFired = false
        atTurnHapticFired = false
        arrivalHandled = false

        cumulativeDistances = RouteProjection.cumulativeDistances(route.coordinates)
        totalRouteDistance = cumulativeDistances.last ?? 0
        progressHighWaterMark = 0
        legChosenByCourse = false
        plausibilityGate = FixPlausibilityGate(
            speedMetresPerSecond: FixPlausibilityGate.plannedSpeed(for: route), monotonicClock: currentMonotonicTime)
        syncRecheckState()

        // Prepare haptic generators for low-latency feedback
        impactGenerator.prepare()
        heavyImpactGenerator.prepare()
        notificationGenerator.prepare()

        // Set initial instruction (skip the "Start" instruction)
        if !route.turnInstructions.isEmpty {
            if route.turnInstructions.count > 1 {
                currentInstructionIndex = 1
                currentInstruction = route.turnInstructions[1]
            } else {
                currentInstruction = route.turnInstructions[0]
            }
        }

        print("iOS route guidance started: \(route.name) (\(route.turnInstructions.count) instructions)")
    }

    /// Stops active navigation and clears all guidance state.
    func stop() {
        isNavigating = false
        activeRoute = nil
        currentInstruction = nil
        distanceToNextTurn = nil
        progress = 0
        remainingDistance = 0
        isOffRoute = false
        currentInstructionIndex = 0
        cumulativeDistances = []
        totalRouteDistance = 0
        progressHighWaterMark = 0
        legChosenByCourse = false
        plausibilityGate.abandonRecheck()
        syncRecheckState()

        print("iOS route guidance stopped")
    }

    /// Processes a new GPS location update during active navigation.
    ///
    /// This is the main update loop that:
    /// 1. Finds the closest point on the route polyline
    /// 2. Checks for off-route condition
    /// 3. Calculates progress and remaining distance
    /// 4. Determines which turn instruction is upcoming
    /// 5. Calculates distance to the next turn
    /// 6. Triggers haptic feedback at appropriate moments
    ///
    /// - Parameter location: The user's current GPS location.
    func updateLocation(_ location: CLLocation) {
        // A cached fix minutes old or a future-dated fix would skew the plausibility gate's clock (#47, #49).
        guard isNavigating,
              let route = activeRoute,
              !route.coordinates.isEmpty,
              !FixPlausibilityGate.isStale(location, now: currentDate()) else { return }

        // 1. Find the point on the route, keeping continuity with progress so far (#44)
        //    and, until the leg is chosen, with the direction of travel (#46)
        let course = legChosenByCourse ? nil : RouteProjection.trustedCourse(of: location)
        guard let closest = RouteProjection.project(
            location.coordinate,
            onto: route.coordinates,
            cumulativeDistances: cumulativeDistances,
            progressHighWaterMark: progressHighWaterMark,
            course: course
        ) else { return }

        // Hold back a fix further ahead than the user could have walked until rechecks confirm it.
        let decision = plausibilityGate.evaluate(
            location, progressJump: closest.distanceAlong - progressHighWaterMark, now: currentDate())
        syncRecheckState()
        guard decision == .accept else { return }
        if course != nil { legChosenByCourse = true }

        let distanceAlongRoute = closest.distanceAlong
        progressHighWaterMark = max(progressHighWaterMark, distanceAlongRoute)

        // 2. Off-route detection
        updateOffRouteStatus(distanceFromRoute: closest.distanceFromRoute)

        // 3. Progress and remaining distance
        progress = totalRouteDistance > 0 ? min(1.0, distanceAlongRoute / totalRouteDistance) : 0
        remainingDistance = max(0, totalRouteDistance - distanceAlongRoute)

        // 4. Update current instruction
        updateCurrentInstruction(distanceAlongRoute: distanceAlongRoute, route: route)

        // 5. Distance to next turn
        if let instruction = currentInstruction {
            distanceToNextTurn = max(0, instruction.cumulativeDistance - distanceAlongRoute)
        }

        // 6. Haptic feedback
        checkHapticTriggers(distanceAlongRoute: distanceAlongRoute)
    }

    // MARK: - Private Helpers

    /// Publishes the gate's recheck state and restarts the recheck timeout.
    ///
    /// Called after every fix, so the timeout fires only when no fix arrives for
    /// ``RouteGuidanceConfig/maxRecheckDurationSeconds``; while fixes arrive, the gate's own cap
    /// ends a recheck.
    private func syncRecheckState() {
        isRecheckingFix = plausibilityGate.isRechecking
        recheckTimeout?.cancel()
        recheckTimeout = nil
        guard isRecheckingFix else { return }
        recheckTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(RouteGuidanceConfig.maxRecheckDurationSeconds))
            guard !Task.isCancelled, let self else { return }
            print("Route guidance: no GPS fix during recheck; ending the GPS burst")
            self.plausibilityGate.abandonRecheck()
            self.syncRecheckState()
        }
    }

    /// Updates the off-route flag and triggers/clears haptic feedback.
    private func updateOffRouteStatus(distanceFromRoute: Double) {
        if distanceFromRoute > RouteGuidanceConfig.offRouteThresholdMetres {
            if !isOffRoute {
                isOffRoute = true
                notificationGenerator.notificationOccurred(.error)
                print("iOS: Off route! Distance: \(Int(distanceFromRoute))m")
            }
        } else if distanceFromRoute < RouteGuidanceConfig.offRouteClearThresholdMetres {
            if isOffRoute {
                isOffRoute = false
                print("iOS: Back on route")
            }
        }
    }

    /// Advances the current turn instruction based on the user's distance along the route.
    ///
    /// Once the user has passed a turn point, the guidance advances to the next instruction;
    /// arrival feedback fires once near the end. See ``TurnInstructionProgress``.
    private func updateCurrentInstruction(distanceAlongRoute: Double, route: PlannedRoute) {
        let instructions = route.turnInstructions
        guard currentInstructionIndex < instructions.count else { return }

        let newIndex = TurnInstructionProgress.indexAfterPassedTurns(
            from: currentInstructionIndex,
            distanceAlongRoute: distanceAlongRoute,
            instructions: instructions
        )
        if newIndex != currentInstructionIndex {
            currentInstructionIndex = newIndex
            currentInstruction = instructions[newIndex]
            approachingHapticFired = false
            atTurnHapticFired = false
        }

        if !arrivalHandled && TurnInstructionProgress.hasArrived(
            currentIndex: currentInstructionIndex,
            instructionCount: instructions.count,
            distanceAlongRoute: distanceAlongRoute,
            totalRouteDistance: totalRouteDistance,
            arrivalThresholdMetres: RouteGuidanceConfig.arrivedDistanceMetres
        ) {
            arrivalHandled = true
            handleArrival()
        }
    }

    /// Checks whether haptic feedback should be triggered based on distance to next turn.
    private func checkHapticTriggers(distanceAlongRoute: Double) {
        guard let instruction = currentInstruction else { return }

        let distToTurn = instruction.cumulativeDistance - distanceAlongRoute

        // Approaching turn (100m)
        if distToTurn <= RouteGuidanceConfig.approachingTurnDistanceMetres
            && distToTurn > RouteGuidanceConfig.atTurnDistanceMetres
            && !approachingHapticFired {
            approachingHapticFired = true
            impactGenerator.impactOccurred()
        }

        // At turn (30m)
        // Skipped for .arrive: handleArrival() owns the arrival haptic, so it plays once.
        if distToTurn <= RouteGuidanceConfig.atTurnDistanceMetres && !atTurnHapticFired
            && instruction.direction != .arrive {
            atTurnHapticFired = true
            playDirectionHaptic(instruction.direction)
        }
    }

    /// Handles arrival at the destination.
    private func handleArrival() {
        notificationGenerator.notificationOccurred(.success)
        print("iOS: Arrived at destination!")
    }

    /// Plays a direction-appropriate haptic for a turn.
    ///
    /// Uses notification feedback for important turns and impact feedback
    /// for minor direction changes.
    ///
    /// - Parameter direction: The ``TurnDirection`` of the upcoming turn.
    private func playDirectionHaptic(_ direction: TurnDirection) {
        switch direction {
        case .left, .right, .sharpLeft, .sharpRight:
            heavyImpactGenerator.impactOccurred()
        case .uTurn:
            notificationGenerator.notificationOccurred(.warning)
        case .arrive:
            notificationGenerator.notificationOccurred(.success)
        default:
            impactGenerator.impactOccurred()
        }
    }
}
