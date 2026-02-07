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

/// The sections available in the macOS sidebar.
///
/// Full feature parity with the iOS sidebar, including region downloading
/// and route planning that were previously iOS-only.
enum MacSidebarSection: String, CaseIterable, Identifiable {
    /// Interactive map for selecting and downloading regions.
    case regions = "Regions"
    /// List of downloaded offline map regions.
    case downloaded = "Downloaded"
    /// Saved hike history.
    case hikes = "Hikes"
    /// All waypoints across hikes.
    case waypoints = "Waypoints"
    /// Planned routes list and route planning.
    case routes = "Planned Routes"
    /// Community route browser.
    case community = "Community"

    var id: String { rawValue }

    /// SF Symbol icon for this section.
    var iconName: String {
        switch self {
        case .regions: return "map"
        case .downloaded: return "arrow.down.circle"
        case .hikes: return "figure.hiking"
        case .waypoints: return "mappin.and.ellipse"
        case .routes: return "point.topleft.down.to.point.bottomright.curvepath"
        case .community: return "person.3"
        }
    }
}

/// The root content view for the native macOS OpenHiker app.
///
/// Uses a ``NavigationSplitView`` with sidebar navigation, providing the
/// standard macOS multi-column layout. The sidebar lists Hikes, Waypoints,
/// Planned Routes, and Community sections.
///
/// ## iCloud Sync Status
/// A small sync status indicator appears at the bottom of the sidebar showing
/// the last sync time and a manual refresh button.
struct MacContentView: View {
    /// The currently selected sidebar section.
    @State private var selectedSection: MacSidebarSection? = .hikes

    /// User preference for metric (true) or imperial (false) units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
    }

    // MARK: - Sidebar

    /// The macOS sidebar with section list and sync status.
    private var sidebar: some View {
        List(MacSidebarSection.allCases, selection: $selectedSection) { section in
            Label(section.rawValue, systemImage: section.iconName)
                .tag(section)
        }
        .listStyle(.sidebar)
        .navigationTitle("OpenHiker")
        .safeAreaInset(edge: .bottom) {
            syncStatusBar
        }
    }

    /// Displays the iCloud sync status at the bottom of the sidebar.
    private var syncStatusBar: some View {
        HStack {
            Image(systemName: "icloud")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("iCloud Sync")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task {
                    await CloudSyncManager.shared.performSync()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Sync now")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Detail View

    /// Maps the selected sidebar section to the appropriate detail view.
    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .regions:
            MacRegionSelectorView()
        case .downloaded:
            MacRegionsListView()
        case .hikes:
            MacHikesView()
        case .waypoints:
            MacWaypointsView()
        case .routes:
            MacPlannedRoutesView()
        case .community:
            MacCommunityView()
        case nil:
            ContentUnavailableView(
                "Select a Section",
                systemImage: "sidebar.left",
                description: Text("Choose a section from the sidebar.")
            )
        }
    }
}
