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

import SwiftUI
import Charts

/// Renders an elevation profile chart for a hike using Swift Charts.
///
/// Displays an area chart with distance on the X axis and elevation on the Y axis.
/// The fill uses a green-to-red gradient (low-to-high). A separate ``LineMark``
/// draws the profile outline for clarity.
///
/// ## Data Source
/// The elevation data is extracted from compressed track data via
/// ``TrackCompression/extractElevationProfile(_:)``, which returns an array of
/// `(distance: Double, elevation: Double)` tuples.
///
/// ## Units
/// X axis: distance in km (metric) or miles (imperial)
/// Y axis: elevation in meters (metric) or feet (imperial)
struct ElevationProfileView: View {
    /// The elevation data points. Each point contains cumulative distance (meters)
    /// from the start and elevation (meters) at that point.
    let elevationData: [(distance: Double, elevation: Double)]

    /// Whether to use metric units (km, m) or imperial (mi, ft).
    let useMetric: Bool

    var body: some View {
        Chart {
            ForEach(chartData.indices, id: \.self) { index in
                let point = chartData[index]
                AreaMark(
                    x: .value("Distance", point.x),
                    y: .value("Elevation", point.y)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [.green.opacity(0.3), .red.opacity(0.3)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )

                LineMark(
                    x: .value("Distance", point.x),
                    y: .value("Elevation", point.y)
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartXAxisLabel(useMetric ? "Distance (km)" : "Distance (mi)")
        .chartYAxisLabel(useMetric ? "Elevation (m)" : "Elevation (ft)")
    }

    // MARK: - Data Conversion

    /// Chart-ready data points with converted units.
    ///
    /// Subsamples to a maximum of ``maxChartPoints`` points for rendering
    /// performance, and converts to the user's preferred unit system.
    private var chartData: [ChartPoint] {
        let subsampledData = subsample(elevationData, maxPoints: Self.maxChartPoints)

        return subsampledData.map { point in
            let x: Double
            let y: Double

            if useMetric {
                x = point.distance / 1000.0  // meters → km
                y = point.elevation            // meters
            } else {
                x = point.distance / HikeStatisticsConfig.metersPerMile  // meters → miles
                y = point.elevation * HikeStatisticsConfig.feetPerMeter  // meters → feet
            }

            return ChartPoint(x: x, y: y)
        }
    }

    /// Maximum number of data points to render in the chart.
    ///
    /// Large hikes may have thousands of track points. Rendering all of them in
    /// Swift Charts is unnecessary and slow. We subsample to this limit.
    private static let maxChartPoints = 200

    /// Subsamples an elevation data array to the given maximum number of points.
    ///
    /// Uses stride-based sampling to evenly distribute points across the full
    /// track length. Always includes the first and last points.
    ///
    /// - Parameters:
    ///   - data: The original elevation data.
    ///   - maxPoints: Maximum number of output points.
    /// - Returns: A subsampled array with at most `maxPoints` entries.
    private func subsample(
        _ data: [(distance: Double, elevation: Double)],
        maxPoints: Int
    ) -> [(distance: Double, elevation: Double)] {
        guard data.count > maxPoints else { return data }

        var result: [(distance: Double, elevation: Double)] = []
        let stride = Double(data.count - 1) / Double(maxPoints - 1)

        for i in 0..<maxPoints {
            let index = Int(Double(i) * stride)
            result.append(data[min(index, data.count - 1)])
        }

        return result
    }
}

// MARK: - Chart Data Point

/// A single point in the elevation chart with converted X (distance) and Y (elevation) values.
private struct ChartPoint {
    /// Distance value in display units (km or miles).
    let x: Double
    /// Elevation value in display units (m or ft).
    let y: Double
}
