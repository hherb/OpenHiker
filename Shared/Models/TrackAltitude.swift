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

import CoreLocation

/// Rules for recording GPS fixes whose altitude Core Location marks as invalid.
///
/// Core Location sets `verticalAccuracy < 0` when a fix has no usable altitude (its
/// `altitude` is then often 0 m). Recording that value as is shows a drop to sea level
/// in the elevation profile and inflates elevation gain and loss. These functions apply
/// the rules Android uses (#59, #63): `resolveTrackAltitude` for the stored altitude, and
/// `HikeTrackingService`, which skips `updateElevation` for a fix without altitude.
/// Android tests validity with `Location.hasAltitude()` rather than `verticalAccuracy`.
///
/// - A fix with an invalid altitude is stored with the last valid altitude of the track.
/// - The first valid altitude of a track also rewrites the earlier points, which all
///   lacked one, to that value.
/// - A fix with an invalid altitude adds nothing to elevation gain or loss.
///
/// Rewritten points keep their negative `verticalAccuracy`, so the track still records
/// that their altitude was not measured.
enum TrackAltitude {

    /// Altitude stored for a fix recorded before the track has any valid altitude.
    ///
    /// Such points are rewritten once the first valid altitude arrives. The value only
    /// survives if a whole track never gets one. Matches Android's `ALTITUDE_UNKNOWN_METRES`.
    static let unknownAltitudeMetres: CLLocationDistance = 0

    /// Whether Core Location measured an altitude for this fix.
    ///
    /// - Parameter location: A GPS fix.
    /// - Returns: `true` when `verticalAccuracy` is zero or positive.
    static func hasValidAltitude(_ location: CLLocation) -> Bool {
        location.verticalAccuracy >= 0
    }

    /// Returns the fix to append to a track, with an altitude that is safe to store.
    ///
    /// Flow:
    /// 1. A fix with a valid altitude is returned unchanged. If no earlier point has a
    ///    valid altitude, those points are first rewritten to this fix's altitude.
    /// 2. A fix with an invalid altitude is returned as a copy that carries the last valid
    ///    altitude in `recorded`, or ``unknownAltitudeMetres`` if there is none yet.
    ///
    /// - Parameters:
    ///   - fix: The new GPS fix, not yet appended.
    ///   - recorded: The points recorded so far. May be rewritten (backfilled).
    /// - Returns: The location to append to `recorded`.
    static func resolve(_ fix: CLLocation, recorded: inout [CLLocation]) -> CLLocation {
        let lastValid = recorded.last(where: hasValidAltitude)
        if hasValidAltitude(fix) {
            if lastValid == nil && !recorded.isEmpty {
                recorded = recorded.map { replacingAltitude(of: $0, with: fix.altitude) }
            }
            return fix
        }
        return replacingAltitude(of: fix, with: lastValid?.altitude ?? unknownAltitudeMetres)
    }

    /// Elevation change from the last counted point with a valid altitude to `fix`.
    ///
    /// Measuring from the last *valid* altitude, not simply the previous point, means a
    /// run of fixes without altitude neither adds a spike nor loses the climb across it.
    ///
    /// - Parameters:
    ///   - fix: The new GPS fix, not yet appended.
    ///   - recorded: The points recorded so far.
    ///   - isCounted: Which recorded points may serve as the baseline. iOS passes its
    ///     high-accuracy test so noisy points do not count. watchOS uses the default
    ///     (accept all) because it drops fixes of 100 m or worse before recording.
    /// - Returns: The change in metres (positive = climb), or `nil` when `fix` has no
    ///   valid altitude or no recorded point qualifies as a baseline.
    static func elevationChange(
        to fix: CLLocation,
        since recorded: [CLLocation],
        countingOnly isCounted: (CLLocation) -> Bool = { _ in true }
    ) -> Double? {
        guard hasValidAltitude(fix),
              let baseline = recorded.last(where: { hasValidAltitude($0) && isCounted($0) })
        else { return nil }
        return fix.altitude - baseline.altitude
    }

    /// Copies a location with a different altitude.
    ///
    /// Keeps coordinate, both accuracies, course, speed (with their accuracies) and
    /// timestamp. `floor`, `ellipsoidalAltitude` and `sourceInformation` are not copied;
    /// nothing in the app reads them.
    ///
    /// - Parameters:
    ///   - location: The location to copy.
    ///   - altitude: The altitude for the copy, in metres.
    /// - Returns: The copy.
    private static func replacingAltitude(of location: CLLocation, with altitude: CLLocationDistance) -> CLLocation {
        CLLocation(
            coordinate: location.coordinate,
            altitude: altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            course: location.course,
            courseAccuracy: location.courseAccuracy,
            speed: location.speed,
            speedAccuracy: location.speedAccuracy,
            timestamp: location.timestamp
        )
    }
}
