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

/// A compact translucent UV index badge displayed on the watch map.
///
/// Shows the UV index value with a color-coded icon following the WHO/WMO
/// standard color scheme (green/yellow/orange/red/purple). Positioned at the
/// bottom-right of the map view.
///
/// Full UV details (category name, protection advice) are available on the
/// dedicated ``HikeStatsDashboardView`` accessible by swiping down from the map.
///
/// ## Visibility Rules
/// - Only visible when ``UVIndexManager/currentUVIndex`` is not `nil`
/// - Hidden when the user has disabled UV display via `@AppStorage("showUVIndex")`
///
/// ## Data Source
/// Uses WeatherKit (Apple Weather service) via ``UVIndexManager`` — not a
/// hardware UV sensor. Data is location-based and refreshed every 10 minutes.
struct UVIndexOverlay: View {
    @EnvironmentObject var uvIndexManager: UVIndexManager

    /// User preference for showing the UV index overlay.
    @AppStorage("showUVIndex") private var showUVIndex = true

    var body: some View {
        if showUVIndex, uvIndexManager.isReadingCurrent,
           let uvIndex = uvIndexManager.currentUVIndex,
           let category = uvIndexManager.currentCategory {
            VStack {
                Spacer()

                // Compact UV badge
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
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 8)
            .padding(.bottom, 52)
        }
    }
}
