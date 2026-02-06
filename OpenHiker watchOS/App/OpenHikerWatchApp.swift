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

/// The main entry point for the OpenHiker watchOS app.
///
/// This standalone watch app provides offline hiking navigation using pre-downloaded
/// map tiles rendered via SpriteKit. It receives map data from the iOS companion app
/// through WatchConnectivity.
///
/// Two environment objects are injected into the view hierarchy:
/// - ``LocationManager``: Provides GPS location, heading, and track recording
/// - ``WatchConnectivityReceiver``: Handles file reception from the iOS app
@main
struct OpenHikerWatchApp: App {
    /// GPS location and heading manager for the watch.
    @StateObject private var locationManager = LocationManager()

    /// Singleton receiver for files and messages from the iOS companion app.
    @StateObject private var connectivityManager = WatchConnectivityReceiver.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(locationManager)
                .environmentObject(connectivityManager)
        }
    }
}

// MARK: - Watch Connectivity Receiver

/// Receives files and messages from the iOS companion app via WatchConnectivity.
///
/// This singleton handles:
/// - Receiving MBTiles map databases transferred from the iPhone
/// - Receiving GPX route files
/// - Processing application context updates (available regions list)
/// - Persisting received region metadata as JSON in the Documents directory
///
/// ## File storage layout on watch
/// ```
/// Documents/
///   regions_metadata.json       ← JSON array of RegionMetadata
///   regions/
///     <uuid>.mbtiles            ← SQLite MBTiles databases
///   routes/
///     <name>.gpx                ← GPX route files
/// ```
final class WatchConnectivityReceiver: NSObject, ObservableObject {
    /// Shared singleton instance injected as an environment object.
    static let shared = WatchConnectivityReceiver()

    /// All regions available on the watch (locally saved + known from phone).
    @Published var availableRegions: [RegionMetadata] = []

    /// Whether a file transfer from the iPhone is currently in progress.
    @Published var isReceivingFile = false

    /// The name of the most recently received region (for UI feedback).
    @Published var lastReceivedRegion: String?

    /// The active WatchConnectivity session, or `nil` if not supported.
    private var session: WCSession?

    /// Private initializer enforcing singleton pattern. Sets up and activates the WCSession.
    private override init() {
        super.init()
        setupSession()
    }

    /// Configures and activates the WatchConnectivity session with this receiver as delegate.
    private func setupSession() {
        guard WCSession.isSupported() else { return }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    /// Sends a message to the iOS app requesting the list of available regions.
    ///
    /// The iOS app responds by updating the application context with region metadata.
    /// Requires the watch to be reachable (iOS app in foreground).
    func requestRegionsFromPhone() {
        guard let session = session, session.isReachable else { return }

        session.sendMessage(["action": "requestRegions"], replyHandler: nil) { error in
            print("Error requesting regions: \(error.localizedDescription)")
        }
    }
}

extension WatchConnectivityReceiver: WCSessionDelegate {
    /// Called when the WCSession activation completes on the watch.
    ///
    /// Processes any application context that was received while the app wasn't running.
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation error: \(error.localizedDescription)")
        } else {
            // Process any application context sent while the app wasn't running
            let context = session.receivedApplicationContext
            if !context.isEmpty {
                self.session(session, didReceiveApplicationContext: context)
            }
        }
    }

    // MARK: - File Receiving

    /// Called when a file transfer from the iOS app completes.
    ///
    /// Routes the file to the appropriate handler based on the `type` field in metadata:
    /// - `"mbtiles"`: Saves the MBTiles database and updates region metadata
    /// - `"gpx"`: Saves the GPX route file
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        DispatchQueue.main.async {
            self.isReceivingFile = true
        }

        guard let metadata = file.metadata else {
            print("Received file without metadata")
            return
        }

        let fileType = metadata["type"] as? String ?? "unknown"

        switch fileType {
        case "mbtiles":
            handleReceivedMBTiles(file: file, metadata: metadata)
        case "gpx":
            handleReceivedGPX(file: file, metadata: metadata)
        default:
            print("Unknown file type: \(fileType)")
        }

        DispatchQueue.main.async {
            self.isReceivingFile = false
        }
    }

    /// Processes a received MBTiles file from the iOS companion app.
    ///
    /// Moves the file to the `Documents/regions/` directory, creates a ``RegionMetadata``
    /// object from the transfer metadata, and persists it to the JSON metadata file.
    ///
    /// - Parameters:
    ///   - file: The received WCSession file containing the MBTiles database.
    ///   - metadata: The transfer metadata dictionary with region details.
    private func handleReceivedMBTiles(file: WCSessionFile, metadata: [String: Any]) {
        guard let regionIdString = metadata["regionId"] as? String,
              let regionId = UUID(uuidString: regionIdString),
              let name = metadata["name"] as? String,
              let minZoom = metadata["minZoom"] as? Int,
              let maxZoom = metadata["maxZoom"] as? Int,
              let tileCount = metadata["tileCount"] as? Int,
              let north = metadata["north"] as? Double,
              let south = metadata["south"] as? Double,
              let east = metadata["east"] as? Double,
              let west = metadata["west"] as? Double else {
            print("Invalid MBTiles metadata")
            return
        }

        // Move file to documents directory
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let regionsDir = documentsDir.appendingPathComponent("regions", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: regionsDir, withIntermediateDirectories: true)

            let destinationURL = regionsDir.appendingPathComponent("\(regionId.uuidString).mbtiles")

            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.moveItem(at: file.fileURL, to: destinationURL)

            // Create metadata object
            let regionMetadata = RegionMetadata(
                id: regionId,
                name: name,
                boundingBox: BoundingBox(north: north, south: south, east: east, west: west),
                minZoom: minZoom,
                maxZoom: maxZoom,
                tileCount: tileCount
            )

            // Save metadata
            saveRegionMetadata(regionMetadata)

            DispatchQueue.main.async {
                self.availableRegions.append(regionMetadata)
                self.lastReceivedRegion = name
            }

            print("Successfully received and saved region: \(name)")

        } catch {
            print("Error saving received MBTiles: \(error.localizedDescription)")
        }
    }

    /// Processes a received GPX route file from the iOS companion app.
    ///
    /// Moves the file to the `Documents/routes/` directory.
    ///
    /// - Parameters:
    ///   - file: The received WCSession file containing GPX data.
    ///   - metadata: The transfer metadata dictionary with the route name.
    private func handleReceivedGPX(file: WCSessionFile, metadata: [String: Any]) {
        guard let name = metadata["name"] as? String else {
            print("Invalid GPX metadata")
            return
        }

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let routesDir = documentsDir.appendingPathComponent("routes", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: routesDir, withIntermediateDirectories: true)

            let destinationURL = routesDir.appendingPathComponent("\(name).gpx")

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.moveItem(at: file.fileURL, to: destinationURL)

            print("Successfully received GPX route: \(name)")

        } catch {
            print("Error saving received GPX: \(error.localizedDescription)")
        }
    }

    /// Persists a ``RegionMetadata`` object to the JSON metadata file.
    ///
    /// If a region with the same ID already exists, it is replaced. The full
    /// metadata array is then re-encoded and written to disk.
    ///
    /// - Parameter metadata: The ``RegionMetadata`` to save.
    private func saveRegionMetadata(_ metadata: RegionMetadata) {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let metadataURL = documentsDir.appendingPathComponent("regions_metadata.json")

        var allMetadata = loadAllRegionMetadata()
        allMetadata.removeAll { $0.id == metadata.id }
        allMetadata.append(metadata)

        do {
            let data = try JSONEncoder().encode(allMetadata)
            try data.write(to: metadataURL)
        } catch {
            print("Error saving region metadata: \(error.localizedDescription)")
        }
    }

    /// Loads all saved region metadata from the JSON file on disk.
    ///
    /// - Returns: An array of ``RegionMetadata`` objects, or an empty array if
    ///   the file doesn't exist or can't be decoded.
    func loadAllRegionMetadata() -> [RegionMetadata] {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let metadataURL = documentsDir.appendingPathComponent("regions_metadata.json")

        guard FileManager.default.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode([RegionMetadata].self, from: data) else {
            return []
        }

        return metadata
    }

    // MARK: - Application Context

    /// Processes an application context update from the iOS app.
    ///
    /// The context contains an `"availableRegions"` key with an array of region
    /// dictionaries. This is merged with locally saved regions: local regions take
    /// priority, and any new regions from the phone are appended.
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("Received application context update")

        guard let regionDicts = applicationContext["availableRegions"] as? [[String: Any]] else { return }

        var phoneRegions: [RegionMetadata] = []
        for dict in regionDicts {
            guard let idString = dict["regionId"] as? String,
                  let id = UUID(uuidString: idString),
                  let name = dict["name"] as? String,
                  let minZoom = dict["minZoom"] as? Int,
                  let maxZoom = dict["maxZoom"] as? Int,
                  let tileCount = dict["tileCount"] as? Int,
                  let north = dict["north"] as? Double,
                  let south = dict["south"] as? Double,
                  let east = dict["east"] as? Double,
                  let west = dict["west"] as? Double else {
                continue
            }

            phoneRegions.append(RegionMetadata(
                id: id,
                name: name,
                boundingBox: BoundingBox(north: north, south: south, east: east, west: west),
                minZoom: minZoom,
                maxZoom: maxZoom,
                tileCount: tileCount
            ))
        }

        DispatchQueue.main.async {
            // Merge: keep local regions, add any from phone we don't have locally yet
            let localRegions = self.loadAllRegionMetadata()
            let localIds = Set(localRegions.map { $0.id })
            let newFromPhone = phoneRegions.filter { !localIds.contains($0.id) }
            self.availableRegions = localRegions + newFromPhone
        }
    }
}
