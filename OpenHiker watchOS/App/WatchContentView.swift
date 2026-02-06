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

/// The root content view of the watchOS app.
///
/// Presents a vertically-paged tab interface with four tabs:
/// - **Map**: The SpriteKit-based offline map with GPS overlay (``MapView``)
/// - **Routes**: List of planned routes for turn-by-turn navigation (``WatchPlannedRoutesView``)
/// - **Regions**: List of available offline map regions (``RegionsListView``)
/// - **Settings**: GPS mode and display preferences (``SettingsView``)
struct WatchContentView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var connectivityManager: WatchConnectivityReceiver
    @EnvironmentObject var routeGuidance: RouteGuidance

    /// The currently selected tab index (0 = Map, 1 = Routes, 2 = Regions, 3 = Settings).
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Map View
            MapView()
                .tag(0)

            // Planned Routes
            WatchPlannedRoutesView(onStartNavigation: { route in
                routeGuidance.start(route: route)
                selectedTab = 0 // Switch to map view for guidance
            })
            .tag(1)

            // Regions List
            RegionsListView()
                .tag(2)

            // Settings
            SettingsView()
                .tag(3)
        }
        .tabViewStyle(.verticalPage)
    }
}

// MARK: - Watch Planned Routes View

/// Displays a list of planned routes received from the iPhone.
///
/// Each route shows its name, distance, and estimated duration. Tapping a route
/// starts active turn-by-turn navigation and switches to the map tab. Routes
/// can be deleted with swipe-to-delete.
struct WatchPlannedRoutesView: View {
    @ObservedObject private var routeStore = PlannedRouteStore.shared
    @EnvironmentObject var routeGuidance: RouteGuidance

    /// Callback invoked when the user taps a route to start navigation.
    let onStartNavigation: (PlannedRoute) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if routeStore.routes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No Routes")
                            .font(.headline)
                        Text("Plan routes on your iPhone and send them here")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    routesList
                }
            }
            .navigationTitle("Routes")
            .onAppear {
                routeStore.loadAll()
            }
        }
    }

    /// The scrollable list of planned routes.
    private var routesList: some View {
        List {
            // Active navigation stop button
            if routeGuidance.isNavigating {
                Button(role: .destructive) {
                    routeGuidance.stop()
                } label: {
                    Label("Stop Navigation", systemImage: "xmark.circle.fill")
                }
            }

            ForEach(routeStore.routes) { route in
                Button {
                    onStartNavigation(route)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route.name)
                            .font(.headline)
                            .lineLimit(1)

                        HStack {
                            Label(formatDistance(route.totalDistance), systemImage: "ruler")
                            Spacer()
                            Label(route.formattedDuration, systemImage: "clock")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: deleteRoutes)
        }
    }

    /// Deletes planned routes at the given index offsets.
    ///
    /// - Parameter offsets: The index positions of the routes to delete.
    private func deleteRoutes(at offsets: IndexSet) {
        for index in offsets {
            let route = routeStore.routes[index]
            try? PlannedRouteStore.shared.delete(id: route.id)
        }
    }

    /// Formats a distance in metres for compact display on the watch.
    ///
    /// - Parameter metres: Distance in metres.
    /// - Returns: Formatted string like "12.4 km" or "800 m".
    private func formatDistance(_ metres: Double) -> String {
        if metres >= 1000 {
            return String(format: "%.1f km", metres / 1000)
        }
        return "\(Int(metres)) m"
    }
}

// MARK: - Regions List View

/// Displays a list of offline map regions available on the watch.
///
/// Shows regions received from the iOS companion app via WatchConnectivity.
/// On appear, loads locally saved region metadata and merges it with
/// the regions already known from application context updates.
struct RegionsListView: View {
    @EnvironmentObject var connectivityManager: WatchConnectivityReceiver

    var body: some View {
        NavigationStack {
            List {
                if connectivityManager.availableRegions.isEmpty {
                    Text("No offline maps")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(connectivityManager.availableRegions) { region in
                        VStack(alignment: .leading) {
                            Text(region.name)
                                .font(.headline)
                            Text("\(region.tileCount) tiles")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Regions")
        }
        .onAppear {
            // Load saved regions
            let savedRegions = connectivityManager.loadAllRegionMetadata()
            if connectivityManager.availableRegions.isEmpty && !savedRegions.isEmpty {
                connectivityManager.availableRegions = savedRegions
            }
        }
    }
}

// MARK: - Settings View

/// Provides user-configurable settings for the watch app.
///
/// Currently supports:
/// - **GPS Accuracy**: High / Balanced / Low Power modes affecting battery life
/// - **Units**: Metric (km, m) or Imperial (mi, ft) for distance and elevation
/// - **Display**: Toggle scale bar visibility
/// - **HealthKit**: Authorization status, authorize button, workout recording toggle
/// - **App info**: Version number
struct SettingsView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager

    /// The GPS accuracy mode, persisted via `@AppStorage`.
    @AppStorage("gpsMode") private var gpsMode = "balanced"

    /// Whether to show the map scale bar, persisted via `@AppStorage`.
    @AppStorage("showScale") private var showScale = true

    /// Whether to use metric units (km, m) or imperial (mi, ft).
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    /// Whether to record hikes as workouts in Apple Health.
    @AppStorage("recordWorkouts") private var recordWorkouts = true

    /// Whether a HealthKit authorization request is in flight.
    @State private var isRequestingAuth = false

    var body: some View {
        NavigationStack {
            List {
                Section("GPS") {
                    Picker("Accuracy", selection: $gpsMode) {
                        Text("High").tag("high")
                        Text("Balanced").tag("balanced")
                        Text("Low Power").tag("lowpower")
                    }
                }

                Section("Units") {
                    Picker("System", selection: $useMetricUnits) {
                        Text("Metric").tag(true)
                        Text("Imperial").tag(false)
                    }
                }

                Section("Display") {
                    Toggle("Show Scale", isOn: $showScale)
                }

                healthKitSection

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - HealthKit Settings Section

    /// The HealthKit settings section showing authorization status and controls.
    ///
    /// Displays:
    /// - Authorization status (Authorized / Not Authorized)
    /// - An "Authorize" button when not yet authorized
    /// - A toggle for recording workouts to Apple Health
    /// - Any HealthKit errors
    private var healthKitSection: some View {
        Section("Health") {
            // Authorization status
            HStack {
                Text("HealthKit")
                Spacer()
                if healthKitManager.isAuthorized {
                    Text("Authorized")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text("Not Authorized")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Authorize button (only when not yet authorized)
            if !healthKitManager.isAuthorized {
                Button {
                    isRequestingAuth = true
                    Task {
                        do {
                            try await healthKitManager.requestAuthorization()
                        } catch {
                            print("HealthKit auth error: \(error.localizedDescription)")
                        }
                        isRequestingAuth = false
                    }
                } label: {
                    if isRequestingAuth {
                        ProgressView()
                    } else {
                        Text("Authorize HealthKit")
                    }
                }
                .disabled(isRequestingAuth)
            }

            // Workout recording toggle
            Toggle("Record Workouts", isOn: $recordWorkouts)

            // Error display
            if let error = healthKitManager.healthKitError {
                Text(error.localizedDescription)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }
}

#Preview {
    WatchContentView()
        .environmentObject(LocationManager())
        .environmentObject(WatchConnectivityReceiver.shared)
        .environmentObject(HealthKitManager())
        .environmentObject(RouteGuidance())
}
