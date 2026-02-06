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

/// The main entry point for the native macOS OpenHiker app.
///
/// This app provides the macOS-specific interface for reviewing hikes, browsing
/// waypoints, managing planned routes, and exporting data. It does not include
/// watch connectivity or region downloading (those are iOS-only features).
///
/// The macOS app relies on iCloud sync (``CloudSyncManager``) to receive hike
/// data from the iOS/watchOS companion apps.
///
/// ## Window Structure
/// Uses a three-column ``NavigationSplitView`` with:
/// - **Sidebar**: Section navigation (Hikes, Waypoints, Routes, Community)
/// - **List**: Items within the selected section
/// - **Detail**: Full detail for the selected item
///
/// ## Commands
/// Adds macOS-specific menu commands via ``OpenHikerCommands``:
/// - File > Export Hike... (Cmd+E)
/// - File > Sync with iCloud (Cmd+Shift+S)
@main
struct OpenHikerMacApp: App {

    var body: some Scene {
        WindowGroup {
            MacContentView()
                .frame(minWidth: 800, minHeight: 500)
                .onAppear {
                    initializeStores()
                    initializeCloudSync()
                }
        }
        .commands {
            OpenHikerCommands()
        }

        #if os(macOS)
        Settings {
            MacSettingsView()
        }
        #endif
    }

    /// Opens all local data stores (RouteStore, WaypointStore, PlannedRouteStore).
    ///
    /// Called once on app launch. Errors are logged but not fatal.
    private func initializeStores() {
        do {
            try RouteStore.shared.open()
        } catch {
            print("Error opening RouteStore: \(error.localizedDescription)")
        }

        do {
            try WaypointStore.shared.open()
        } catch {
            print("Error opening WaypointStore: \(error.localizedDescription)")
        }

        PlannedRouteStore.shared.loadAll()
    }

    /// Initializes iCloud sync via ``CloudSyncManager``.
    ///
    /// Runs asynchronously so it doesn't block app launch.
    private func initializeCloudSync() {
        Task {
            await CloudSyncManager.shared.syncOnLaunch()
        }
    }
}
