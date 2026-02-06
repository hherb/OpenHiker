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
import WatchKit

// MARK: - Route Guidance Configuration

/// Configuration constants for the route guidance engine.
///
/// Controls off-route detection thresholds, haptic trigger distances,
/// and other navigation parameters.
enum RouteGuidanceConfig {
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

// MARK: - Route Guidance

/// Tracks the user's position along a planned route and provides turn-by-turn navigation.
///
/// Monitors GPS location updates from ``LocationManager``, determines which turn instruction
/// is upcoming, calculates distance to the next turn, detects off-route conditions, and
/// triggers haptic feedback at key moments.
///
/// ## Key responsibilities
/// - Find the nearest point on the route polyline to the user's current GPS position
/// - Calculate distance along the route to determine progress percentage
/// - Advance through turn instructions as the user reaches each junction
/// - Detect off-route conditions (> 50m from polyline) and trigger warning haptics
/// - Play haptic feedback: approaching turn (100m), at turn (30m), off-route, arrived
///
/// ## Usage
/// ```swift
/// let guidance = RouteGuidance()
/// guidance.start(route: plannedRoute)
/// // Feed GPS updates:
/// guidance.updateLocation(newLocation)
/// // When done:
/// guidance.stop()
/// ```
final class RouteGuidance: ObservableObject {

    // MARK: - Published State

    /// The turn instruction the user should follow next.
    @Published var currentInstruction: TurnInstruction?

    /// Distance from the user's current position to the next turn point, in metres.
    @Published var distanceToNextTurn: Double?

    /// Route completion progress from 0.0 (start) to 1.0 (destination).
    @Published var progress: Double = 0

    /// Remaining distance to the destination in metres.
    @Published var remainingDistance: Double = 0

    /// Whether the user is currently more than ``RouteGuidanceConfig/offRouteThresholdMetres``
    /// from the nearest point on the route polyline.
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
    ///
    /// `cumulativeDistances[i]` is the distance from the start to coordinate `i`.
    private var cumulativeDistances: [Double] = []

    /// Total length of the route polyline in metres.
    private var totalRouteDistance: Double = 0

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

        // Precompute cumulative distances for the polyline
        precomputeCumulativeDistances(route.coordinates)

        // Set initial instruction
        if !route.turnInstructions.isEmpty {
            // Start with the second instruction (skip the "Start" instruction)
            if route.turnInstructions.count > 1 {
                currentInstructionIndex = 1
                currentInstruction = route.turnInstructions[1]
            } else {
                currentInstruction = route.turnInstructions[0]
            }
        }

        print("Route guidance started: \(route.name) (\(route.turnInstructions.count) instructions)")
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

        print("Route guidance stopped")
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
    /// For each segment of the polyline, projects the coordinate onto the segment
    /// and finds the minimum distance. Returns the closest point, the segment index,
    /// and the distance along the polyline from the start to that point.
    ///
    /// - Parameters:
    ///   - coordinate: The user's current position.
    ///   - route: The polyline coordinates.
    /// - Returns: A tuple of (closest point, segment index, distance along route).
    func closestPointOnRoute(
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

                // Distance along = distance to segment start + fraction of segment
                let segLength = cumulativeDistanceForSegment(i)
                bestDistanceAlong = (cumulativeDistances.count > i ? cumulativeDistances[i] : 0)
                    + projected.fraction * segLength
            }
        }

        return (point: bestPoint, segment: bestSegment, distanceAlong: bestDistanceAlong)
    }

    // MARK: - Private Helpers

    /// Precomputes cumulative distances along the route polyline.
    ///
    /// - Parameter coordinates: The route polyline coordinates.
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
    ///
    /// - Parameter index: The segment index (0-based, from coordinate[index] to coordinate[index+1]).
    /// - Returns: The segment length in metres.
    private func cumulativeDistanceForSegment(_ index: Int) -> Double {
        guard index + 1 < cumulativeDistances.count else { return 0 }
        return cumulativeDistances[index + 1] - cumulativeDistances[index]
    }

    /// Projects a point onto a line segment, returning the closest point and its fraction along the segment.
    ///
    /// Uses a simplified planar projection (adequate for short hiking distances).
    ///
    /// - Parameters:
    ///   - point: The coordinate to project.
    ///   - segStart: The segment start coordinate.
    ///   - segEnd: The segment end coordinate.
    /// - Returns: The projected point and the fraction (0-1) along the segment.
    private func projectPointOntoSegment(
        point: CLLocationCoordinate2D,
        segStart: CLLocationCoordinate2D,
        segEnd: CLLocationCoordinate2D
    ) -> (point: CLLocationCoordinate2D, fraction: Double) {
        // Convert to a local planar coordinate system for projection
        let dx = segEnd.longitude - segStart.longitude
        let dy = segEnd.latitude - segStart.latitude
        let px = point.longitude - segStart.longitude
        let py = point.latitude - segStart.latitude

        let segLengthSquared = dx * dx + dy * dy

        guard segLengthSquared > 0 else {
            return (point: segStart, fraction: 0)
        }

        // Fraction along the segment (clamped to 0-1)
        let t = max(0, min(1, (px * dx + py * dy) / segLengthSquared))

        let projectedLat = segStart.latitude + t * dy
        let projectedLon = segStart.longitude + t * dx

        return (
            point: CLLocationCoordinate2D(latitude: projectedLat, longitude: projectedLon),
            fraction: t
        )
    }

    /// Updates the off-route flag and triggers/clears haptic feedback.
    ///
    /// - Parameter distanceFromRoute: Distance from the user to the nearest point on the route.
    private func updateOffRouteStatus(distanceFromRoute: Double) {
        if distanceFromRoute > RouteGuidanceConfig.offRouteThresholdMetres {
            if !isOffRoute {
                isOffRoute = true
                playHaptic(.failure)
                print("Off route! Distance from route: \(Int(distanceFromRoute))m")
            }
        } else if distanceFromRoute < RouteGuidanceConfig.offRouteClearThresholdMetres {
            if isOffRoute {
                isOffRoute = false
                print("Back on route")
            }
        }
    }

    /// Advances the current turn instruction based on the user's distance along the route.
    ///
    /// When the user passes a turn point (within ``RouteGuidanceConfig/atTurnDistanceMetres``),
    /// the guidance advances to the next instruction.
    ///
    /// - Parameters:
    ///   - distanceAlongRoute: The user's current distance along the route polyline.
    ///   - route: The active planned route.
    private func updateCurrentInstruction(distanceAlongRoute: Double, route: PlannedRoute) {
        let instructions = route.turnInstructions
        guard currentInstructionIndex < instructions.count else { return }

        let current = instructions[currentInstructionIndex]

        // Check if user has passed the current instruction point
        if distanceAlongRoute >= current.cumulativeDistance - RouteGuidanceConfig.atTurnDistanceMetres {
            // Advance to next instruction
            if currentInstructionIndex + 1 < instructions.count {
                currentInstructionIndex += 1
                currentInstruction = instructions[currentInstructionIndex]
                approachingHapticFired = false
                atTurnHapticFired = false
            } else {
                // Reached the last instruction (arrive)
                if distanceAlongRoute >= totalRouteDistance - RouteGuidanceConfig.arrivedDistanceMetres {
                    handleArrival()
                }
            }
        }
    }

    /// Checks whether haptic feedback should be triggered based on distance to next turn.
    ///
    /// - Parameter distanceAlongRoute: The user's current distance along the route polyline.
    private func checkHapticTriggers(distanceAlongRoute: Double) {
        guard let instruction = currentInstruction else { return }

        let distToTurn = instruction.cumulativeDistance - distanceAlongRoute

        // Approaching turn (100m)
        if distToTurn <= RouteGuidanceConfig.approachingTurnDistanceMetres
            && distToTurn > RouteGuidanceConfig.atTurnDistanceMetres
            && !approachingHapticFired {
            approachingHapticFired = true
            playHaptic(.click)
        }

        // At turn (30m)
        if distToTurn <= RouteGuidanceConfig.atTurnDistanceMetres && !atTurnHapticFired {
            atTurnHapticFired = true
            playDirectionHaptic(instruction.direction)
        }
    }

    /// Handles arrival at the destination.
    private func handleArrival() {
        playHaptic(.success)
        print("Arrived at destination!")
        // Don't auto-stop — let the user dismiss manually
    }

    /// Plays a haptic feedback pattern on the Apple Watch.
    ///
    /// - Parameter type: The ``WKHapticType`` to play.
    private func playHaptic(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }

    /// Plays a direction-appropriate haptic for a turn.
    ///
    /// Uses `.directionUp` for right turns and `.directionDown` for left turns,
    /// providing intuitive physical feedback.
    ///
    /// - Parameter direction: The ``TurnDirection`` of the upcoming turn.
    private func playDirectionHaptic(_ direction: TurnDirection) {
        switch direction {
        case .left, .slightLeft, .sharpLeft:
            playHaptic(.directionDown)
        case .right, .slightRight, .sharpRight:
            playHaptic(.directionUp)
        case .uTurn:
            playHaptic(.failure)
        case .arrive:
            playHaptic(.success)
        default:
            playHaptic(.click)
        }
    }
}
