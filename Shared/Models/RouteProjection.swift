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

// MARK: - Route Projection

/// Pure functions that place a GPS fix on a route polyline.
///
/// Shared by iOS (`iOSRouteGuidance`) and watchOS (`RouteGuidance`). Compiled into
/// those two targets only, like ``RouteGuidanceConfig``; macOS has no live guidance.
enum RouteProjection {

    /// Where a GPS fix lands on the route.
    struct Result {
        /// The point on the polyline the fix was projected onto.
        let point: CLLocationCoordinate2D
        /// Index of the segment (from `route[segment]` to `route[segment + 1]`).
        let segment: Int
        /// Distance from the route start to `point`, in metres.
        let distanceAlong: Double
        /// Distance from the fix to `point`, in metres.
        let distanceFromRoute: Double
    }

    /// Returns the distance from the start to each coordinate of a polyline.
    ///
    /// `result[i]` is the distance in metres from `coordinates[0]` to `coordinates[i]`,
    /// so `result.last` is the route length. Empty input gives `[]`.
    ///
    /// - Parameter coordinates: The route polyline.
    /// - Returns: One cumulative distance per coordinate.
    static func cumulativeDistances(_ coordinates: [CLLocationCoordinate2D]) -> [Double] {
        guard !coordinates.isEmpty else { return [] }
        var result: [Double] = [0]
        result.reserveCapacity(coordinates.count)
        for i in 1..<coordinates.count {
            result.append(result[i - 1] + haversineDistance(
                lat1: coordinates[i - 1].latitude, lon1: coordinates[i - 1].longitude,
                lat2: coordinates[i].latitude, lon2: coordinates[i].longitude
            ))
        }
        return result
    }

    /// Projects a GPS fix onto the route, keeping continuity with the user's progress so far.
    ///
    /// A loop route starts and ends at the same place, and an out-and-back route walks the same
    /// trail twice. There, a fix is about equally close to two parts of the route, and the plain
    /// nearest segment can be the wrong one (#44). So every segment within
    /// ``RouteGuidanceConfig/projectionCandidateToleranceMetres`` of the nearest one is a
    /// candidate, and the candidate that best fits `progressHighWaterMark` wins: going forward
    /// from it costs its distance in metres, and going back costs
    /// ``RouteGuidanceConfig/projectionBacktrackPenalty`` times as much.
    ///
    /// - Parameters:
    ///   - coordinate: The GPS fix.
    ///   - route: The route polyline.
    ///   - cumulativeDistances: ``cumulativeDistances(_:)`` of `route`.
    ///   - progressHighWaterMark: The furthest `distanceAlong` reached so far this session (0 at start).
    /// - Returns: The projection, or `nil` if `route` is empty.
    static func project(
        _ coordinate: CLLocationCoordinate2D,
        onto route: [CLLocationCoordinate2D],
        cumulativeDistances: [Double],
        progressHighWaterMark: Double
    ) -> Result? {
        guard let first = route.first else { return nil }
        guard route.count >= 2, cumulativeDistances.count == route.count else {
            return Result(point: first, segment: 0, distanceAlong: 0,
                          distanceFromRoute: distance(coordinate, first))
        }

        let projections: [Result] = (0..<(route.count - 1)).map { i in
            let projected = projectPointOntoSegment(point: coordinate, segStart: route[i], segEnd: route[i + 1])
            let segLength = cumulativeDistances[i + 1] - cumulativeDistances[i]
            return Result(point: projected.point, segment: i,
                          distanceAlong: cumulativeDistances[i] + projected.fraction * segLength,
                          distanceFromRoute: distance(coordinate, projected.point))
        }

        // Non-empty: route.count >= 2 gives at least one segment.
        let nearest = projections.map(\.distanceFromRoute).min()!
        let maxCandidateDistance = nearest + RouteGuidanceConfig.projectionCandidateToleranceMetres

        func continuityCost(_ result: Result) -> Double {
            let step = result.distanceAlong - progressHighWaterMark
            return step >= 0 ? step : -step * RouteGuidanceConfig.projectionBacktrackPenalty
        }

        // min(by:) keeps the first of equal costs, so ties go to the earlier segment.
        return projections
            .filter { $0.distanceFromRoute <= maxCandidateDistance }
            .min { continuityCost($0) < continuityCost($1) }
    }

    /// Projects a point onto a line segment, returning the closest point and its fraction.
    ///
    /// Uses a planar approximation, with longitude scaled by cos(latitude) so the projection is
    /// computed in an isotropic (metric) space. Accurate for hiking-scale segments at non-polar
    /// latitudes; segments of many kilometres or near the poles would need a geodesic projection.
    ///
    /// - Parameters:
    ///   - point: The coordinate to project.
    ///   - segStart: The segment start coordinate.
    ///   - segEnd: The segment end coordinate.
    /// - Returns: The projected point and the fraction (0–1) along the segment.
    static func projectPointOntoSegment(
        point: CLLocationCoordinate2D,
        segStart: CLLocationCoordinate2D,
        segEnd: CLLocationCoordinate2D
    ) -> (point: CLLocationCoordinate2D, fraction: Double) {
        let lonScale = cos(segStart.latitude * .pi / 180)
        let dx = (segEnd.longitude - segStart.longitude) * lonScale
        let dy = segEnd.latitude - segStart.latitude
        let px = (point.longitude - segStart.longitude) * lonScale
        let py = point.latitude - segStart.latitude

        let segLengthSquared = dx * dx + dy * dy
        guard segLengthSquared > 0 else { return (point: segStart, fraction: 0) }

        let t = max(0, min(1, (px * dx + py * dy) / segLengthSquared))

        // Interpolate with the original (unscaled) coordinates; t is metric-agnostic.
        return (
            point: CLLocationCoordinate2D(
                latitude: segStart.latitude + t * (segEnd.latitude - segStart.latitude),
                longitude: segStart.longitude + t * (segEnd.longitude - segStart.longitude)
            ),
            fraction: t
        )
    }

    /// Haversine distance in metres between two coordinates.
    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        haversineDistance(lat1: a.latitude, lon1: a.longitude, lat2: b.latitude, lon2: b.longitude)
    }
}
