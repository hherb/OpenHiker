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

/// A translucent overlay displaying the current UV index on the watch map.
///
/// Shows the UV index value with a color-coded badge following the WHO/WMO
/// standard color scheme (green/yellow/orange/red/purple). Positioned at the
/// top-right of the map view alongside the GPS status indicator.
///
/// ## Visibility Rules
/// - Only visible when ``UVIndexManager/currentUVIndex`` is not `nil`
/// - Hidden when the user has disabled UV display via `@AppStorage("showUVIndex")`
/// - Tapping the badge shows a brief detail popup with the category name and
///   protection advice
///
/// ## Data Source
/// Uses WeatherKit (Apple Weather service) via ``UVIndexManager`` — not a
/// hardware UV sensor. Data is location-based and refreshed every 10 minutes.
struct UVIndexOverlay: View {
    @EnvironmentObject var uvIndexManager: UVIndexManager

    /// User preference for showing the UV index overlay.
    @AppStorage("showUVIndex") private var showUVIndex = true

    /// Whether the expanded detail popup is currently displayed.
    @State private var showingDetail = false

    /// Timer that auto-hides the detail popup after a few seconds.
    @State private var detailTimer: Timer?

    /// Number of seconds before the detail popup auto-hides.
    private static let detailAutoHideSec: TimeInterval = 4.0

    var body: some View {
        if showUVIndex, uvIndexManager.isReadingCurrent,
           let uvIndex = uvIndexManager.currentUVIndex,
           let category = uvIndexManager.currentCategory {
            VStack(alignment: .trailing, spacing: 4) {
                Spacer()

                // Expanded detail card (shown on tap)
                if showingDetail {
                    detailCard(uvIndex: uvIndex, category: category)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottomTrailing)))
                }

                // Compact UV badge
                uvBadge(uvIndex: uvIndex, category: category)
                    .onTapGesture {
                        toggleDetail()
                    }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 8)
            .padding(.bottom, 52)
            .animation(.easeInOut(duration: 0.25), value: showingDetail)
            .onDisappear {
                detailTimer?.invalidate()
                detailTimer = nil
            }
        }
    }

    // MARK: - Subviews

    /// A compact capsule badge showing the UV index value with a color-coded icon.
    ///
    /// - Parameters:
    ///   - uvIndex: The current UV index value.
    ///   - category: The UV exposure category for color coding.
    /// - Returns: A styled capsule view.
    private func uvBadge(uvIndex: Int, category: UVCategory) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 10))
                .foregroundStyle(category.displayColor)
            Text("UV \(uvIndex)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// An expanded detail card showing the UV category, protection advice, and data source.
    ///
    /// - Parameters:
    ///   - uvIndex: The current UV index value.
    ///   - category: The UV exposure category.
    /// - Returns: A styled card view with UV details.
    private func detailCard(uvIndex: Int, category: UVCategory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Category header with color bar
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(category.displayColor)
                    .frame(width: 4, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text("UV Index \(uvIndex)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(category.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(category.displayColor)
                }
            }

            // Protection advice
            Text(category.protectionAdvice)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            // Data source attribution (required by WeatherKit terms)
            Text("Apple Weather")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    /// Toggles the detail popup visibility and manages the auto-hide timer.
    private func toggleDetail() {
        if showingDetail {
            showingDetail = false
            detailTimer?.invalidate()
            detailTimer = nil
        } else {
            showingDetail = true
            detailTimer?.invalidate()
            detailTimer = Timer.scheduledTimer(
                withTimeInterval: Self.detailAutoHideSec,
                repeats: false
            ) { _ in
                DispatchQueue.main.async {
                    withAnimation {
                        showingDetail = false
                    }
                }
            }
        }
    }
}
