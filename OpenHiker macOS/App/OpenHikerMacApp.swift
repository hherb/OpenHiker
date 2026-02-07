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
/// This app provides a full-featured macOS interface including region downloading,
/// route planning, hike review, waypoint management, and community route browsing.
/// Route sync to iPhone/Watch works via iCloud (Mac → iCloud → iPhone → Watch).
///
/// ## Window Structure
/// Uses a ``NavigationSplitView`` with:
/// - **Sidebar**: Section navigation (Regions, Downloaded, Hikes, Waypoints, Routes, Community)
/// - **Detail**: Full detail for the selected section
///
/// ## Commands
/// Adds macOS-specific menu commands via ``OpenHikerCommands``:
/// - File > Import GPX... (Cmd+I)
/// - File > Sync with iCloud (Cmd+Shift+S)
/// - File > Send Routes to iPhone (Cmd+Shift+P)
@main
struct OpenHikerMacApp: App {

    var body: some Scene {
        WindowGroup {
            MacContentView()
                .frame(minWidth: 900, minHeight: 600)
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
