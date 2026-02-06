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

/// macOS Settings window (Preferences) for the OpenHiker app.
///
/// Provides a tabbed settings interface following macOS conventions:
/// - **General**: Unit preferences (metric/imperial)
/// - **Sync**: iCloud sync status and manual sync button
struct MacSettingsView: View {
    /// User preference for metric (true) or imperial (false) units.
    @AppStorage("useMetricUnits") private var useMetricUnits = true

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            syncTab
                .tabItem {
                    Label("Sync", systemImage: "icloud")
                }
        }
        .frame(width: 400, height: 200)
    }

    // MARK: - General Tab

    /// General settings tab with unit preferences.
    private var generalTab: some View {
        Form {
            Toggle("Use Metric Units (km, m)", isOn: $useMetricUnits)
                .toggleStyle(.switch)

            Text(useMetricUnits
                 ? "Distances in kilometers, elevation in meters"
                 : "Distances in miles, elevation in feet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Sync Tab

    /// iCloud sync settings tab.
    private var syncTab: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "icloud")
                    .font(.title)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading) {
                    Text("iCloud Sync")
                        .font(.headline)
                    Text("Routes, waypoints, and planned routes sync automatically via iCloud.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Sync Now") {
                Task {
                    await CloudSyncManager.shared.performSync()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
