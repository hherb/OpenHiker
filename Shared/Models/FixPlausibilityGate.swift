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
/// reachable since the last accepted fix (no time at all for the first fix, so a first fix more
/// than the certainty radius along the route is rechecked): the route's planned speed ×
/// ``RouteGuidanceConfig/maxSpeedFactor`` × elapsed time, plus
/// ``RouteGuidanceConfig/certaintyRadiusMetres`` for GPS noise. A fix beyond that becomes a
/// *suspect*. It is accepted only after ``RouteGuidanceConfig/recheckConfirmationsRequired``
/// further fixes agree with it, each within the certainty radius plus the distance reachable
/// since the suspect. A fix that disagrees drops the suspect and is judged afresh.
///
/// Two safeguards stop real fast travel (a car or bus ride with guidance on) from freezing
/// guidance with the GPS stuck in burst mode:
/// - The speed used is the larger of the planned speed and the fix's own Doppler-measured speed,
///   when its `speedAccuracy` is good (``measuredSpeed(of:)``). A position jump caused by a signal
///   reflection does not come with a matching measured speed.
/// - A recheck lasts at most ``RouteGuidanceConfig/maxRecheckDurationSeconds``. A fix arriving
///   after that is accepted as it is; if no fix arrives for that long, the caller ends the
///   recheck with ``abandonRecheck()``.
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
        /// Ignore the fix: more fixes are needed to confirm or reject a suspect jump, or the fix is
        /// no newer than one already seen.
        case recheck
    }

    /// The speed in metres per second the reachable distance is based on.
    let speedMetresPerSecond: Double

    /// Timestamp of the last accepted fix, or `nil` before the first one.
    private var lastAcceptedTime: Date?

    /// Timestamp of the newest fix evaluated, or `nil` before the first one.
    private var newestFixTime: Date?

    /// The fix waiting for confirmation, if any.
    private var suspect: CLLocation?

    /// How many fixes have agreed with ``suspect`` so far.
    private var confirmations = 0

    /// Timestamp of the fix that started the current recheck. A disagreeing recheck that becomes
    /// the new suspect does not reset it, so a chain of suspects is still capped.
    private var recheckStartedAt: Date?

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

    /// The fix's Doppler-measured speed in metres per second, or `nil` if it is invalid or its
    /// `speedAccuracy` is worse than ``RouteGuidanceConfig/measuredSpeedMaxAccuracyMetresPerSecond``.
    ///
    /// - Parameter fix: The GPS fix.
    /// - Returns: The measured speed, or `nil` if it should not be trusted.
    static func measuredSpeed(of fix: CLLocation) -> Double? {
        guard fix.speed >= 0, fix.speedAccuracy >= 0,
              fix.speedAccuracy <= RouteGuidanceConfig.measuredSpeedMaxAccuracyMetresPerSecond else { return nil }
        return fix.speed
    }

    /// Whether a fix's timestamp is too far from `now` for guidance to use: older than
    /// ``RouteGuidanceConfig/maxFixAgeSeconds`` (#47) or later than
    /// ``RouteGuidanceConfig/maxFixLeadSeconds`` (#49). Callers drop such fixes before
    /// ``evaluate(_:progressJump:now:)``. A cached first fix would set the gate's clock minutes back,
    /// and a future-dated fix would make every real fix look out of order until the clock caught up.
    /// Each rejected fix is logged, so a clock offset that drops every fix shows up in the logs.
    ///
    /// - Parameters:
    ///   - fix: The GPS fix.
    ///   - now: The current time.
    /// - Returns: `true` if the fix should be ignored.
    static func isStale(_ fix: CLLocation, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(fix.timestamp)
        let stale = age > RouteGuidanceConfig.maxFixAgeSeconds || -age > RouteGuidanceConfig.maxFixLeadSeconds
        if stale {
            print("Route guidance: ignoring fix timestamped \(Int(-age)) s from now")
        }
        return stale
    }

    /// The distance in metres the user could plausibly cover in `elapsed` seconds, plus GPS noise.
    ///
    /// - Parameters:
    ///   - elapsed: Seconds since the reference fix; negative values count as 0.
    ///   - measuredSpeed: A trusted measured speed (``measuredSpeed(of:)``); the planned speed is
    ///     used when it is `nil` or lower.
    /// - Returns: The reachable distance in metres.
    func reachableDistance(elapsed: TimeInterval, measuredSpeed: Double? = nil) -> Double {
        max(speedMetresPerSecond, measuredSpeed ?? 0) * RouteGuidanceConfig.maxSpeedFactor * max(0, elapsed)
            + RouteGuidanceConfig.certaintyRadiusMetres
    }

    /// Decides whether to use a fix.
    ///
    /// - Parameters:
    ///   - fix: The GPS fix (its `timestamp` is used for elapsed time).
    ///   - progressJump: How far the fix lies beyond the progress high-water mark, in metres
    ///     (`distanceAlong - highWaterMark`; zero or negative means no forward jump).
    ///   - now: The current time. If the newest fix seen is more than
    ///     ``RouteGuidanceConfig/maxFixLeadSeconds`` after it, the device clock has jumped back, and
    ///     the gate starts afresh as for a first fix (#51).
    /// - Returns: ``Decision/accept`` to use the fix, ``Decision/recheck`` to ignore it for now.
    mutating func evaluate(_ fix: CLLocation, progressJump: Double, now: Date) -> Decision {
        // After a backward clock jump every fix would look older than the stored newest one (#51).
        if let newest = newestFixTime, newest.timeIntervalSince(now) > RouteGuidanceConfig.maxFixLeadSeconds {
            print("Route guidance: clock moved back \(Int(newest.timeIntervalSince(now))) s; restarting fix checks")
            newestFixTime = nil
            lastAcceptedTime = nil
            abandonRecheck()
        }

        // A re-delivered or out-of-order fix would confirm a suspect by itself or rewind the clock.
        if let newest = newestFixTime, fix.timestamp <= newest { return .recheck }
        newestFixTime = fix.timestamp

        if let started = recheckStartedAt,
           fix.timestamp.timeIntervalSince(started) >= RouteGuidanceConfig.maxRecheckDurationSeconds {
            print("Route guidance: recheck cap reached; accepting fix \(Int(progressJump)) m ahead")
            return accept(fix) // Cap reached: accept rather than freeze guidance with the GPS in burst mode.
        }

        let speed = Self.measuredSpeed(of: fix)
        if let suspect {
            let sinceSuspect = fix.timestamp.timeIntervalSince(suspect.timestamp)
            if fix.distance(from: suspect) <= reachableDistance(elapsed: sinceSuspect, measuredSpeed: speed) {
                confirmations += 1
                return confirmations >= RouteGuidanceConfig.recheckConfirmationsRequired ? accept(fix) : .recheck
            }
            // The recheck disagrees with the suspect: drop it and judge this fix on its own.
            self.suspect = nil
            confirmations = 0
        }

        let sinceAccepted = lastAcceptedTime.map { fix.timestamp.timeIntervalSince($0) } ?? 0
        if progressJump <= reachableDistance(elapsed: sinceAccepted, measuredSpeed: speed) {
            return accept(fix)
        }
        print("Route guidance: holding back fix \(Int(progressJump)) m ahead for recheck")
        suspect = fix
        confirmations = 0
        if recheckStartedAt == nil { recheckStartedAt = fix.timestamp }
        return .recheck
    }

    /// Clears any pending suspect and recheck. Callers use it when a recheck has had no fixes for
    /// ``RouteGuidanceConfig/maxRecheckDurationSeconds`` (so the GPS can leave burst mode) and
    /// when navigation stops; the gate uses it after an accept. The next fix is judged against the
    /// last accepted fix.
    mutating func abandonRecheck() {
        suspect = nil
        confirmations = 0
        recheckStartedAt = nil
    }

    /// Records `fix` as accepted and clears any suspect.
    private mutating func accept(_ fix: CLLocation) -> Decision {
        lastAcceptedTime = fix.timestamp
        abandonRecheck()
        return .accept
    }
}
