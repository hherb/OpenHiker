import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var connectivityManager: WatchConnectivityReceiver

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

struct SettingsView: View {
    @AppStorage("gpsMode") private var gpsMode = "balanced"
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
