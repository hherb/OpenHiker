import SwiftUI
import WatchConnectivity

@main
struct OpenHikerApp: App {
    @StateObject private var watchConnectivity = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(watchConnectivity)
        }
    }
}
