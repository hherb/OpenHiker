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
/// Presents a vertically-paged tab interface with three tabs:
/// - **Map**: The SpriteKit-based offline map with GPS overlay (``MapView``)
/// - **Regions**: List of available offline map regions (``RegionsListView``)
/// - **Settings**: GPS mode and display preferences (``SettingsView``)
struct WatchContentView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var connectivityManager: WatchConnectivityReceiver

    /// The currently selected tab index (0 = Map, 1 = Regions, 2 = Settings).
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Map View
            MapView()
                .tag(0)

            // Regions List
            RegionsListView()
                .tag(1)

            // Settings
            SettingsView()
                .tag(2)
        }
        .tabViewStyle(.verticalPage)
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
/// - **Display**: Toggle scale bar visibility
/// - **App info**: Version number
struct SettingsView: View {
    /// The GPS accuracy mode, persisted via `@AppStorage`.
    @AppStorage("gpsMode") private var gpsMode = "balanced"

    /// Whether to show the map scale bar, persisted via `@AppStorage`.
    @AppStorage("showScale") private var showScale = true

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

                Section("Display") {
                    Toggle("Show Scale", isOn: $showScale)
                }

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
}

#Preview {
    WatchContentView()
        .environmentObject(LocationManager())
        .environmentObject(WatchConnectivityReceiver.shared)
}
