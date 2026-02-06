import Foundation
import WatchConnectivity

/// Manages Watch Connectivity for transferring map data to Apple Watch
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    enum TransferStatus: Equatable {
        case queued
        case completed
        case failed(String)
    }

    @Published var isPaired = false
    @Published var isReachable = false
    @Published var pendingTransfers: [WCSessionFileTransfer] = []
    @Published var transferStatuses: [UUID: TransferStatus] = [:]

    private var session: WCSession?

    private override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        guard WCSession.isSupported() else {
            print("WatchConnectivity not supported on this device")
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    // MARK: - Public Methods

    /// Transfer an MBTiles file to the watch
    func transferMBTilesFile(at url: URL, metadata: RegionMetadata) {
        guard let session = session, session.activationState == .activated else {
            print("WCSession not activated")
            return
        }

        guard session.isPaired else {
            print("No watch paired")
            return
        }

        // Encode metadata to send with file
        let metadataDict: [String: Any] = [
            "type": "mbtiles",
            "regionId": metadata.id.uuidString,
            "name": metadata.name,
            "minZoom": metadata.minZoom,
            "maxZoom": metadata.maxZoom,
            "tileCount": metadata.tileCount,
            "north": metadata.boundingBox.north,
            "south": metadata.boundingBox.south,
            "east": metadata.boundingBox.east,
            "west": metadata.boundingBox.west
        ]

        let transfer = session.transferFile(url, metadata: metadataDict)
        DispatchQueue.main.async {
            self.pendingTransfers.append(transfer)
            self.transferStatuses[metadata.id] = .queued
        }

        print("Started transfer: \(url.lastPathComponent)")
        sendAvailableRegions()
    }

    /// Transfer all downloaded regions to the watch
    func syncAllRegionsToWatch() {
        guard let session = session, session.activationState == .activated, session.isPaired else {
            return
        }

        let storage = RegionStorage.shared
        storage.loadRegions()

        for region in storage.regions {
            let mbtilesURL = storage.mbtilesURL(for: region)
            guard FileManager.default.fileExists(atPath: mbtilesURL.path) else { continue }
            let metadata = storage.metadata(for: region)
            transferMBTilesFile(at: mbtilesURL, metadata: metadata)
        }
    }

    /// Transfer a GPX route file to the watch
    func transferGPXFile(at url: URL, routeName: String) {
        guard let session = session, session.activationState == .activated else {
            print("WCSession not activated")
            return
        }

        let metadataDict: [String: Any] = [
            "type": "gpx",
            "name": routeName
        ]

        let transfer = session.transferFile(url, metadata: metadataDict)
        DispatchQueue.main.async {
            self.pendingTransfers.append(transfer)
        }
    }

    /// Send a lightweight message (e.g., sync request)
    func sendMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
        guard let session = session, session.isReachable else {
            print("Watch not reachable")
            return
        }

        session.sendMessage(message, replyHandler: replyHandler) { error in
            print("Error sending message: \(error.localizedDescription)")
        }
    }

    /// Update app context with current state
    func updateApplicationContext(_ context: [String: Any]) {
        guard let session = session, session.activationState == .activated else {
            return
        }

        do {
            try session.updateApplicationContext(context)
        } catch {
            print("Error updating application context: \(error.localizedDescription)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isPaired = session.isPaired
            self.isReachable = session.isReachable
        }

        if let error = error {
            print("WCSession activation error: \(error.localizedDescription)")
        } else {
            print("WCSession activated: \(activationState.rawValue)")
            if session.isPaired {
                sendAvailableRegions()
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession became inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession deactivated")
        // Reactivate for switching watches
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPaired = session.isPaired
        }
        if session.isPaired {
            sendAvailableRegions()
        }
    }

    // MARK: - File Transfer Callbacks

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let regionIdString = fileTransfer.file.metadata?["regionId"] as? String
        let regionId = regionIdString.flatMap { UUID(uuidString: $0) }

        DispatchQueue.main.async {
            self.pendingTransfers.removeAll { $0 === fileTransfer }

            if let regionId = regionId {
                if let error = error {
                    self.transferStatuses[regionId] = .failed(error.localizedDescription)
                } else {
                    self.transferStatuses[regionId] = .completed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if self.transferStatuses[regionId] == .completed {
                            self.transferStatuses.removeValue(forKey: regionId)
                        }
                    }
                }
            }
        }

        if let error = error {
            print("File transfer failed: \(error.localizedDescription)")
        } else {
            print("File transfer completed: \(fileTransfer.file.fileURL.lastPathComponent)")
        }
    }

    // MARK: - Message Handling

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        print("Received message from watch: \(message)")

        // Handle messages from watch (e.g., sync requests)
        if let action = message["action"] as? String {
            switch action {
            case "requestRegions":
                // Send list of available regions
                sendAvailableRegions()
            default:
                break
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        print("Received message with reply handler: \(message)")

        if let action = message["action"] as? String {
            switch action {
            case "ping":
                replyHandler(["status": "ok", "timestamp": Date().timeIntervalSince1970])
            default:
                replyHandler(["status": "unknown_action"])
            }
        }
    }

    // MARK: - Private Helpers

    private func sendAvailableRegions() {
        let storage = RegionStorage.shared
        storage.loadRegions()

        let regionDicts: [[String: Any]] = storage.regions.map { region in
            let metadata = storage.metadata(for: region)
            return [
                "regionId": metadata.id.uuidString,
                "name": metadata.name,
                "minZoom": metadata.minZoom,
                "maxZoom": metadata.maxZoom,
                "tileCount": metadata.tileCount,
                "north": metadata.boundingBox.north,
                "south": metadata.boundingBox.south,
                "east": metadata.boundingBox.east,
                "west": metadata.boundingBox.west
            ]
        }

        updateApplicationContext(["availableRegions": regionDicts])
    }
}
