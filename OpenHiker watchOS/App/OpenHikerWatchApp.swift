import SwiftUI
import WatchConnectivity

@main
struct OpenHikerWatchApp: App {
    @StateObject private var locationManager = LocationManager()
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

/// Receives files and messages from the iOS companion app
final class WatchConnectivityReceiver: NSObject, ObservableObject {
    static let shared = WatchConnectivityReceiver()

    @Published var availableRegions: [RegionMetadata] = []
    @Published var isReceivingFile = false
    @Published var lastReceivedRegion: String?

    private var session: WCSession?

    private override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        guard WCSession.isSupported() else { return }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    /// Request the iOS app to send available regions
    func requestRegionsFromPhone() {
        guard let session = session, session.isReachable else { return }

        session.sendMessage(["action": "requestRegions"], replyHandler: nil) { error in
            print("Error requesting regions: \(error.localizedDescription)")
        }
    }
}

extension WatchConnectivityReceiver: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation error: \(error.localizedDescription)")
        }
    }

    // MARK: - File Receiving

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

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // Handle updated context from iOS app
        print("Received application context update")
    }
}
