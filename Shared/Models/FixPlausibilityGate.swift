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

// MARK: - Fix Plausibility Gate

/// Holds back a GPS fix that moves the user further along the route than they could have walked.
///
/// Route guidance never moves its turn index or progress high-water mark backwards, so one wild
/// fix far ahead would skip turns for good. Each fix's forward progress is compared with what is
/// reachable since the last accepted fix: the route's planned speed ×
/// ``RouteGuidanceConfig/maxSpeedFactor`` × elapsed time, plus
/// ``RouteGuidanceConfig/certaintyRadiusMetres`` for GPS noise. A fix beyond that becomes a
/// *suspect*. It is accepted only after ``RouteGuidanceConfig/recheckConfirmationsRequired``
/// further fixes agree with it, each within the certainty radius plus the distance reachable
/// since the suspect. A fix that disagrees drops the suspect and is judged afresh.
///
/// While ``isRechecking`` is true, callers should switch the GPS to fast, high-accuracy updates
/// so the rechecks arrive within seconds (see `isFixRecheckActive` on the location managers).
///
/// Shared by iOS (`iOSRouteGuidance`) and watchOS (`RouteGuidance`); compiled into those two
/// targets only, like ``RouteGuidanceConfig``.
struct FixPlausibilityGate {

    /// What the caller should do with a fix.
    enum Decision: Equatable {
        /// Use the fix for guidance.
        case accept
        /// Ignore the fix for now; more fixes are needed to confirm or reject a suspect jump.
        case recheck
    }

    /// The speed in metres per second the reachable distance is based on.
    let speedMetresPerSecond: Double

    /// Timestamp of the last accepted fix, or `nil` before the first one.
    private var lastAcceptedTime: Date?

    /// The fix waiting for confirmation, if any.
    private var suspect: CLLocation?

    /// How many fixes have agreed with ``suspect`` so far.
    private var confirmations = 0

    /// Whether a suspect fix is waiting for confirmation.
    var isRechecking: Bool { suspect != nil }

    /// Creates a gate for one navigation session.
    ///
    /// - Parameter speedMetresPerSecond: The expected average speed, usually ``plannedSpeed(for:)``.
    init(speedMetresPerSecond: Double) {
        self.speedMetresPerSecond = speedMetresPerSecond
    }

    /// The route's planned average speed in metres per second.
    ///
    /// Uses `totalDistance / estimatedDuration` (the router's terrain-aware pace). Falls back to
    /// the routing base speed for the route's mode when the duration is unknown (0).
    ///
    /// - Parameter route: The route being navigated.
    /// - Returns: A positive speed in metres per second.
    static func plannedSpeed(for route: PlannedRoute) -> Double {
        if route.estimatedDuration > 0 && route.totalDistance > 0 {
            return route.totalDistance / route.estimatedDuration
        }
        switch route.mode {
        case .hiking: return RoutingCostConfig.hikingBaseSpeedMetresPerSecond
        case .cycling: return RoutingCostConfig.cyclingBaseSpeedMetresPerSecond
        }
    }

    /// The distance in metres the user could plausibly cover in `elapsed` seconds, plus GPS noise.
    ///
    /// - Parameter elapsed: Seconds since the reference fix; negative values count as 0.
    /// - Returns: The reachable distance in metres.
    func reachableDistance(elapsed: TimeInterval) -> Double {
        speedMetresPerSecond * RouteGuidanceConfig.maxSpeedFactor * max(0, elapsed)
            + RouteGuidanceConfig.certaintyRadiusMetres
    }

    /// Decides whether to use a fix.
    ///
    /// - Parameters:
    ///   - fix: The GPS fix (its `timestamp` is used for elapsed time).
    ///   - progressJump: How far the fix lies beyond the progress high-water mark, in metres
    ///     (`distanceAlong - highWaterMark`; zero or negative means no forward jump).
    /// - Returns: ``Decision/accept`` to use the fix, ``Decision/recheck`` to ignore it for now.
    mutating func evaluate(_ fix: CLLocation, progressJump: Double) -> Decision {
        if let suspect {
            let sinceSuspect = fix.timestamp.timeIntervalSince(suspect.timestamp)
            if fix.distance(from: suspect) <= reachableDistance(elapsed: sinceSuspect) {
                confirmations += 1
                return confirmations >= RouteGuidanceConfig.recheckConfirmationsRequired ? accept(fix) : .recheck
            }
            // The recheck disagrees with the suspect: drop it and judge this fix on its own.
            self.suspect = nil
            confirmations = 0
        }

        let sinceAccepted = lastAcceptedTime.map { fix.timestamp.timeIntervalSince($0) } ?? 0
        if progressJump <= reachableDistance(elapsed: sinceAccepted) {
            return accept(fix)
        }
        suspect = fix
        confirmations = 0
        return .recheck
    }

    /// Records `fix` as accepted and clears any suspect.
    private mutating func accept(_ fix: CLLocation) -> Decision {
        lastAcceptedTime = fix.timestamp
        suspect = nil
        confirmations = 0
        return .accept
    }
}
