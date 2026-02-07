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

/// Navigation sections available in the iPad sidebar.
///
/// Each case maps directly to a tab in the iPhone ``ContentView`` ``TabView``.
/// The order matches the iPhone tab order for user familiarity.
enum SidebarSection: String, CaseIterable, Identifiable {
    /// Map region downloading and management.
    case regions = "Regions"
    /// Downloaded map regions list.
    case downloaded = "Downloaded"
    /// Saved hike history.
    case hikes = "Hikes"
    /// Planned routes list.
    case routes = "Routes"
    /// All waypoints across hikes.
    case waypoints = "Waypoints"
    /// Community route browser.
    case community = "Community"
    /// Apple Watch connection status and file transfer.
    case watch = "Watch"

    var id: String { rawValue }

    /// SF Symbol icon for this section.
    var iconName: String {
        switch self {
        case .regions: return "map"
        case .downloaded: return "arrow.down.circle"
        case .hikes: return "figure.hiking"
        case .routes: return "point.topleft.down.to.point.bottomright.curvepath"
        case .waypoints: return "mappin.and.ellipse"
        case .community: return "person.3"
        case .watch: return "applewatch"
        }
    }
}

/// iPad sidebar navigation for ``NavigationSplitView``.
///
/// Provides a persistent sidebar listing all app sections, replacing the bottom
/// tab bar used on iPhone. This is the standard iPad navigation pattern that
/// leverages the larger screen to show a sidebar + detail simultaneously.
///
/// ## Layout
/// The sidebar is only used in the ``NavigationSplitView`` variant of
/// ``ContentView`` on iPad. On iPhone, ``ContentView`` falls back to a ``TabView``.
///
/// ## Selection
/// The ``selection`` binding drives what appears in the detail column of the
/// ``NavigationSplitView``.
struct SidebarView: View {
    /// The currently selected sidebar section.
    @Binding var selection: SidebarSection?

    var body: some View {
        List(SidebarSection.allCases, selection: $selection) { section in
            Label(section.rawValue, systemImage: section.iconName)
                .tag(section)
        }
        .navigationTitle("OpenHiker")
        .listStyle(.sidebar)
    }
}
