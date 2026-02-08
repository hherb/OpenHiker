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

// MARK: - iOS Route Guidance Configuration

/// Configuration constants for the iPhone route guidance engine.
///
/// Matches the watch ``RouteGuidanceConfig`` thresholds for consistent behaviour
/// across both platforms.
enum iOSRouteGuidanceConfig {
    /// Distance in metres from the route polyline beyond which the user is considered off-route.
    static let offRouteThresholdMetres: Double = 50.0

    /// Distance in metres from the route at which the off-route warning is cleared.
    static let offRouteClearThresholdMetres: Double = 30.0

    /// Distance in metres from a turn point at which the "approaching" haptic fires.
    static let approachingTurnDistanceMetres: Double = 100.0

    /// Distance in metres from a turn point at which the "at turn" haptic fires and
    /// the instruction advances to the next one.
    static let atTurnDistanceMetres: Double = 30.0

    /// Distance in metres from the final destination to trigger "arrived" notification.
    static let arrivedDistanceMetres: Double = 30.0
}

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

    /// Precomputed cumulative distances along the route polyline at each coordinate index.
    private var cumulativeDistances: [Double] = []

    /// Total length of the route polyline in metres.
    private var totalRouteDistance: Double = 0

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

        precomputeCumulativeDistances(route.coordinates)

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
        guard isNavigating,
              let route = activeRoute,
              !route.coordinates.isEmpty else { return }

        let userCoord = location.coordinate

        // 1. Find closest point on route
        let closest = closestPointOnRoute(from: userCoord, route: route.coordinates)
        let distanceFromRoute = haversineDistance(
            lat1: userCoord.latitude, lon1: userCoord.longitude,
            lat2: closest.point.latitude, lon2: closest.point.longitude
        )

        // 2. Off-route detection
        updateOffRouteStatus(distanceFromRoute: distanceFromRoute)

        // 3. Progress and remaining distance
        let distanceAlongRoute = closest.distanceAlong
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

    // MARK: - Position on Route

    /// Finds the closest point on a polyline to a given coordinate.
    ///
    /// - Parameters:
    ///   - coordinate: The user's current position.
    ///   - route: The polyline coordinates.
    /// - Returns: A tuple of (closest point, segment index, distance along route).
    private func closestPointOnRoute(
        from coordinate: CLLocationCoordinate2D,
        route: [CLLocationCoordinate2D]
    ) -> (point: CLLocationCoordinate2D, segment: Int, distanceAlong: Double) {
        guard route.count >= 2 else {
            let point = route.first ?? coordinate
            return (point: point, segment: 0, distanceAlong: 0)
        }

        var bestPoint = route[0]
        var bestSegment = 0
        var bestDistance = Double.infinity
        var bestDistanceAlong: Double = 0

        for i in 0..<(route.count - 1) {
            let segStart = route[i]
            let segEnd = route[i + 1]

            let projected = projectPointOntoSegment(
                point: coordinate,
                segStart: segStart,
                segEnd: segEnd
            )

            let dist = haversineDistance(
                lat1: coordinate.latitude, lon1: coordinate.longitude,
                lat2: projected.point.latitude, lon2: projected.point.longitude
            )

            if dist < bestDistance {
                bestDistance = dist
                bestPoint = projected.point
                bestSegment = i

                let segLength = cumulativeDistanceForSegment(i)
                bestDistanceAlong = (cumulativeDistances.count > i ? cumulativeDistances[i] : 0)
                    + projected.fraction * segLength
            }
        }

        return (point: bestPoint, segment: bestSegment, distanceAlong: bestDistanceAlong)
    }

    // MARK: - Private Helpers

    /// Precomputes cumulative distances along the route polyline.
    private func precomputeCumulativeDistances(_ coordinates: [CLLocationCoordinate2D]) {
        cumulativeDistances = [0]
        var cumulative: Double = 0

        for i in 1..<coordinates.count {
            let dist = haversineDistance(
                lat1: coordinates[i - 1].latitude, lon1: coordinates[i - 1].longitude,
                lat2: coordinates[i].latitude, lon2: coordinates[i].longitude
            )
            cumulative += dist
            cumulativeDistances.append(cumulative)
        }

        totalRouteDistance = cumulative
    }

    /// Returns the length of a single polyline segment.
    private func cumulativeDistanceForSegment(_ index: Int) -> Double {
        guard index + 1 < cumulativeDistances.count else { return 0 }
        return cumulativeDistances[index + 1] - cumulativeDistances[index]
    }

    /// Projects a point onto a line segment, returning the closest point and its fraction.
    private func projectPointOntoSegment(
        point: CLLocationCoordinate2D,
        segStart: CLLocationCoordinate2D,
        segEnd: CLLocationCoordinate2D
    ) -> (point: CLLocationCoordinate2D, fraction: Double) {
        let dx = segEnd.longitude - segStart.longitude
        let dy = segEnd.latitude - segStart.latitude
        let px = point.longitude - segStart.longitude
        let py = point.latitude - segStart.latitude

        let segLengthSquared = dx * dx + dy * dy

        guard segLengthSquared > 0 else {
            return (point: segStart, fraction: 0)
        }

        let t = max(0, min(1, (px * dx + py * dy) / segLengthSquared))

        let projectedLat = segStart.latitude + t * dy
        let projectedLon = segStart.longitude + t * dx

        return (
            point: CLLocationCoordinate2D(latitude: projectedLat, longitude: projectedLon),
            fraction: t
        )
    }

    /// Updates the off-route flag and triggers/clears haptic feedback.
    private func updateOffRouteStatus(distanceFromRoute: Double) {
        if distanceFromRoute > iOSRouteGuidanceConfig.offRouteThresholdMetres {
            if !isOffRoute {
                isOffRoute = true
                notificationGenerator.notificationOccurred(.error)
                print("iOS: Off route! Distance: \(Int(distanceFromRoute))m")
            }
        } else if distanceFromRoute < iOSRouteGuidanceConfig.offRouteClearThresholdMetres {
            if isOffRoute {
                isOffRoute = false
                print("iOS: Back on route")
            }
        }
    }

    /// Advances the current turn instruction based on the user's distance along the route.
    private func updateCurrentInstruction(distanceAlongRoute: Double, route: PlannedRoute) {
        let instructions = route.turnInstructions
        guard currentInstructionIndex < instructions.count else { return }

        let current = instructions[currentInstructionIndex]

        if distanceAlongRoute >= current.cumulativeDistance - iOSRouteGuidanceConfig.atTurnDistanceMetres {
            if currentInstructionIndex + 1 < instructions.count {
                currentInstructionIndex += 1
                currentInstruction = instructions[currentInstructionIndex]
                approachingHapticFired = false
                atTurnHapticFired = false
            } else {
                if distanceAlongRoute >= totalRouteDistance - iOSRouteGuidanceConfig.arrivedDistanceMetres {
                    handleArrival()
                }
            }
        }
    }

    /// Checks whether haptic feedback should be triggered based on distance to next turn.
    private func checkHapticTriggers(distanceAlongRoute: Double) {
        guard let instruction = currentInstruction else { return }

        let distToTurn = instruction.cumulativeDistance - distanceAlongRoute

        // Approaching turn (100m)
        if distToTurn <= iOSRouteGuidanceConfig.approachingTurnDistanceMetres
            && distToTurn > iOSRouteGuidanceConfig.atTurnDistanceMetres
            && !approachingHapticFired {
            approachingHapticFired = true
            impactGenerator.impactOccurred()
        }

        // At turn (30m)
        if distToTurn <= iOSRouteGuidanceConfig.atTurnDistanceMetres && !atTurnHapticFired {
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
