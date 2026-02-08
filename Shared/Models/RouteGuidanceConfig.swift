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

    /// Distance in metres from a turn point at which the "at turn" haptic fires and
    /// the instruction advances to the next one.
    static let atTurnDistanceMetres: Double = 30.0

    /// Distance in metres from the final destination to trigger "arrived" notification.
    static let arrivedDistanceMetres: Double = 30.0
}
