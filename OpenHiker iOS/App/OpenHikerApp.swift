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
import WatchConnectivity

/// The main entry point for the OpenHiker iOS companion app.
///
/// This app serves as the companion to the watchOS hiking navigation app. It provides:
/// - Region selection and tile downloading from OpenTopoMap
/// - Management of downloaded offline map regions
/// - Syncing map data to Apple Watch via WatchConnectivity
///
/// The ``WatchConnectivityManager`` singleton is injected as an environment object
/// so all child views can access watch communication features.
@main
struct OpenHikerApp: App {
    /// Shared watch connectivity manager, injected into the view hierarchy as an environment object.
    @StateObject private var watchConnectivity = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(watchConnectivity)
                .onAppear {
                    initializeWaypointStore()
                    initializeRouteStore()
                    initializePlannedRouteStore()
                }
        }
    }

    /// Opens the shared ``WaypointStore`` database so it's ready for CRUD operations.
    ///
    /// Called once on app launch. Errors are logged but not fatal — the app can
    /// still function without waypoints.
    private func initializeWaypointStore() {
        do {
            try WaypointStore.shared.open()
        } catch {
            print("Error opening WaypointStore: \(error.localizedDescription)")
        }
    }

    /// Opens the shared ``RouteStore`` database so it's ready for CRUD operations.
    ///
    /// Called once on app launch. Errors are logged but not fatal — the app can
    /// still function without saved routes.
    private func initializeRouteStore() {
        do {
            try RouteStore.shared.open()
        } catch {
            print("Error opening RouteStore: \(error.localizedDescription)")
        }
    }

    /// Loads all saved planned routes into the ``PlannedRouteStore`` cache.
    ///
    /// Called once on app launch. Planned routes are stored as JSON files
    /// and loaded into memory for display in the Routes tab.
    private func initializePlannedRouteStore() {
        PlannedRouteStore.shared.loadAll()
    }
}
