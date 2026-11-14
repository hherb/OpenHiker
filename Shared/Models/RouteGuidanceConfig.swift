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

// MARK: - Route Guidance Configuration

/// Configuration constants for the route guidance engine.
///
/// Controls off-route detection thresholds, haptic trigger distances,
/// and other navigation parameters. Shared across iOS and watchOS targets
/// to ensure consistent behaviour on both platforms.
enum RouteGuidanceConfig {
    /// Distance in metres from the route polyline beyond which the user is considered off-route.
    static let offRouteThresholdMetres: Double = 50.0

    /// Distance in metres from the route at which the off-route warning is cleared.
    static let offRouteClearThresholdMetres: Double = 30.0

    /// Distance in metres from a turn point at which the "approaching" haptic fires.
    static let approachingTurnDistanceMetres: Double = 100.0

    /// Distance in metres from a turn point at which the "at turn" haptic fires. The
    /// instruction itself advances only once the turn is passed.
    static let atTurnDistanceMetres: Double = 30.0

    /// Distance in metres from the final destination to trigger "arrived" notification.
    static let arrivedDistanceMetres: Double = 30.0

    /// How much further than the nearest route segment (in metres) another segment may be and
    /// still be considered for a GPS fix. Covers GPS error, so a loop's start and end, or the two
    /// legs of an out-and-back, both count. See ``RouteProjection``.
    static let projectionCandidateToleranceMetres: Double = 20.0

    /// How much more a metre backwards along the route costs than a metre forwards when
    /// ``RouteProjection`` picks between candidate segments. Hikers rarely walk a route backwards.
    static let projectionBacktrackPenalty: Double = 4.0

    /// How many times the route's planned speed counts as still reachable when judging whether a
    /// GPS fix is plausible. See ``FixPlausibilityGate``.
    static let maxSpeedFactor: Double = 1.8

    /// GPS noise allowance in metres: added to the reachable distance, and the radius within which
    /// rechecks must agree with a suspect fix (plus any plausible movement since it).
    static let certaintyRadiusMetres: Double = 15.0

    /// How many agreeing rechecks a suspect fix needs before it is accepted.
    static let recheckConfirmationsRequired: Int = 2
}
