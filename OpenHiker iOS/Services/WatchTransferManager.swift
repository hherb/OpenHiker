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

import Foundation
import WatchConnectivity

/// Manages WatchConnectivity on the iOS side for transferring map data to Apple Watch.
///
/// This singleton handles:
/// - Activating and monitoring the ``WCSession``
/// - Transferring MBTiles and GPX files to the watch
/// - Tracking transfer status (queued, completed, failed)
/// - Sending lightweight messages and application context updates
/// - Receiving and responding to messages from the watch app
///
/// Transfer statuses are automatically cleaned up 5 seconds after successful completion.
final class WatchConnectivityManager: NSObject, ObservableObject {
    /// Shared singleton instance injected as an environment object throughout the app.
    static let shared = WatchConnectivityManager()

    /// Represents the lifecycle state of a file transfer to the watch.
    enum TransferStatus: Equatable {
        /// The transfer has been queued but not yet started by the system.
        case queued
        /// The transfer completed successfully.
        case completed
        /// The transfer failed with the given error message.
        case failed(String)
    }

    /// Whether an Apple Watch is currently paired with this iPhone.
    @Published var isPaired = false

    /// Whether the OpenHiker watch app is installed on the paired watch.
    @Published var isWatchAppInstalled = false

    /// Whether the watch app is currently reachable for live messaging.
    @Published var isReachable = false

    /// Currently active (in-progress) file transfers to the watch.
    @Published var pendingTransfers: [WCSessionFileTransfer] = []

    /// Transfer status for each region, keyed by region UUID.
    @Published var transferStatuses: [UUID: TransferStatus] = [:]

    /// The active WatchConnectivity session, or `nil` if not supported.
    private var session: WCSession?

    /// Private initializer enforcing singleton pattern. Sets up and activates the WCSession.
    private override init() {
        super.init()
        setupSession()
    }

    /// Configures and activates the WatchConnectivity session.
    ///
    /// Sets this manager as the session delegate and activates it.
    /// Does nothing if WatchConnectivity is not supported on the current device.
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

    /// Transfers an MBTiles file to the Apple Watch.
    ///
    /// The file is sent via `WCSession.transferFile()` with metadata containing the
    /// region ID, name, zoom levels, tile count, and bounding box. The transfer is
    /// marked as `.queued` immediately.
    ///
    /// After successful transfer, ``sendAvailableRegions()`` is called to update
    /// the watch's application context with the current list of available regions.
    ///
    /// - Parameters:
    ///   - url: The local file URL of the MBTiles database to transfer.
    ///   - metadata: The ``RegionMetadata`` describing the region being transferred.
    func transferMBTilesFile(at url: URL, metadata: RegionMetadata) {
        guard let session = session, session.activationState == .activated else {
            print("WCSession not activated")
            return
        }

        guard session.isPaired && session.isWatchAppInstalled else {
            print("No watch paired or watch app not installed (paired=\(session.isPaired) appInstalled=\(session.isWatchAppInstalled))")
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

    /// Transfers all downloaded regions to the Apple Watch.
    ///
    /// Loads all regions from ``RegionStorage``, then initiates a file transfer
    /// for each one whose MBTiles file exists on disk.
    func syncAllRegionsToWatch() {
        guard let session = session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else {
            print("Cannot sync: session not ready, no watch paired, or watch app not installed")
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

    /// Transfers a GPX route file to the Apple Watch.
    ///
    /// - Parameters:
    ///   - url: The local file URL of the GPX file.
    ///   - routeName: A human-readable name for the route.
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

    /// Sends a lightweight dictionary message to the watch app.
    ///
    /// The watch must be reachable (app running in foreground) for this to succeed.
    /// For background communication, use ``updateApplicationContext(_:)`` instead.
    ///
    /// - Parameters:
    ///   - message: The message dictionary to send.
    ///   - replyHandler: Optional callback for the watch's reply.
    func sendMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
        guard let session = session, session.isReachable else {
            print("Watch not reachable")
            return
        }

        session.sendMessage(message, replyHandler: replyHandler) { error in
            print("Error sending message: \(error.localizedDescription)")
        }
    }

    /// Updates the watch's application context with the provided dictionary.
    ///
    /// Application context is delivered to the watch the next time it wakes,
    /// even if the watch app is not currently running. Only the most recent
    /// context is delivered (previous updates are replaced).
    ///
    /// - Parameter context: The context dictionary to send.
    func updateApplicationContext(_ context: [String: Any]) {
        guard let session = session, session.activationState == .activated,
              session.isWatchAppInstalled else {
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
    /// Called when the WCSession activation completes.
    ///
    /// Updates published properties with the current watch state and recovers
    /// any outstanding file transfers from previous sessions. If a watch is
    /// paired with the app installed, sends the available regions context.
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable
        }

        if let error = error {
            print("WCSession activation error: \(error.localizedDescription)")
        } else {
            print("WCSession activated: state=\(activationState.rawValue) paired=\(session.isPaired) appInstalled=\(session.isWatchAppInstalled) reachable=\(session.isReachable)")
            // Recover any outstanding transfers from previous sessions
            let outstanding = session.outstandingFileTransfers
            if !outstanding.isEmpty {
                print("Found \(outstanding.count) outstanding file transfers")
                DispatchQueue.main.async {
                    self.pendingTransfers = outstanding
                }
            }
            if session.isPaired && session.isWatchAppInstalled {
                sendAvailableRegions()
            }
        }
    }

    /// Called when the session becomes inactive (e.g., during watch switching).
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession became inactive")
    }

    /// Called when the session deactivates. Re-activates to support watch switching.
    func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession deactivated")
        // Reactivate for switching watches
        session.activate()
    }

    /// Called when watch reachability changes (watch app enters/exits foreground).
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    /// Called when watch pairing or app installation state changes.
    ///
    /// Updates published properties and sends available regions if the watch
    /// is newly paired with the app installed.
    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
        print("Watch state changed: paired=\(session.isPaired) appInstalled=\(session.isWatchAppInstalled)")
        if session.isPaired && session.isWatchAppInstalled {
            sendAvailableRegions()
        }
    }

    // MARK: - File Transfer Callbacks

    /// Called when a file transfer to the watch finishes (either successfully or with an error).
    ///
    /// Removes the transfer from ``pendingTransfers`` and updates ``transferStatuses``.
    /// Successful transfers are automatically removed from the status dictionary after 5 seconds.
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

    // MARK: - File Reception (from Watch)

    /// Called when a file is received from the watch via `WCSession.transferFile()`.
    ///
    /// Routes the file to the appropriate handler based on the `type` field in metadata:
    /// - `"savedRoute"`: Decodes the JSON route data and inserts it into ``RouteStore``
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let metadata = file.metadata else {
            print("Received file from watch without metadata")
            return
        }

        let fileType = metadata["type"] as? String ?? "unknown"

        switch fileType {
        case "savedRoute":
            handleReceivedRoute(file: file, metadata: metadata)
        default:
            print("Received unknown file type from watch: \(fileType)")
        }
    }

    /// Processes a received saved route file from the Apple Watch.
    ///
    /// The file contains a JSON-encoded ``SavedRoute`` (including compressed track data).
    /// Decodes it and inserts into the local ``RouteStore``.
    ///
    /// - Parameters:
    ///   - file: The received WCSession file containing JSON route data.
    ///   - metadata: The transfer metadata dictionary with the route ID.
    private func handleReceivedRoute(file: WCSessionFile, metadata: [String: Any]) {
        let routeIdString = metadata["routeId"] as? String ?? "unknown"

        do {
            let jsonData = try Data(contentsOf: file.fileURL)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let route = try decoder.decode(SavedRoute.self, from: jsonData)

            try RouteStore.shared.insert(route)
            print("Received and saved route from watch: \(routeIdString) — \(route.name)")
        } catch {
            print("Error processing received route \(routeIdString): \(error.localizedDescription)")
        }
    }

    // MARK: - Message Handling

    /// Handles incoming messages from the watch (no reply expected).
    ///
    /// Currently supports:
    /// - `"requestRegions"`: Responds by sending the available regions via application context.
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

    /// Handles incoming messages from the watch that expect a reply.
    ///
    /// Currently supports:
    /// - `"ping"`: Replies with `["status": "ok", "timestamp": <current_time>]`.
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

    // MARK: - Waypoint Sync

    /// Sends a waypoint to the Apple Watch via `transferUserInfo`.
    ///
    /// Uses queued delivery which is reliable even when the watch app is not
    /// running. The waypoint's dictionary representation includes a `"type": "waypoint"`
    /// key for routing on the receiving side. If a thumbnail is provided, it is
    /// included as `"thumbnailData"` in the transfer.
    ///
    /// - Parameters:
    ///   - waypoint: The ``Waypoint`` to sync to the watch.
    ///   - thumbnail: Optional 100x100 JPEG thumbnail data.
    func sendWaypointToWatch(_ waypoint: Waypoint, thumbnail: Data?) {
        guard let session = session, session.activationState == .activated else {
            print("WCSession not activated, cannot sync waypoint to watch")
            return
        }

        guard session.isPaired && session.isWatchAppInstalled else {
            print("No watch paired or app not installed, skipping waypoint sync")
            return
        }

        var userInfo = waypoint.toDictionary()
        userInfo["type"] = "waypoint"
        if let thumbnail = thumbnail {
            userInfo["thumbnailData"] = thumbnail
        }

        session.transferUserInfo(userInfo)
        print("Queued waypoint sync to watch: \(waypoint.id.uuidString)")
    }

    // MARK: - User Info Reception (Waypoint Sync from Watch)

    /// Called when the watch sends userInfo (used for waypoint sync).
    ///
    /// Checks for `"type": "waypoint"` and decodes the waypoint dictionary.
    /// Inserts the waypoint into the local ``WaypointStore`` so it appears on
    /// the iPhone map.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let type = userInfo["type"] as? String, type == "waypoint" else {
            print("Received unknown userInfo type from watch")
            return
        }

        guard let waypoint = Waypoint.fromDictionary(userInfo) else {
            print("Failed to decode waypoint from watch userInfo")
            return
        }

        do {
            try WaypointStore.shared.insert(waypoint)
            print("Received and saved waypoint from watch: \(waypoint.id.uuidString)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .waypointSyncReceived, object: nil)
            }
        } catch {
            print("Error saving received waypoint: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    /// Sends the list of all downloaded regions to the watch via application context.
    ///
    /// Loads all regions from ``RegionStorage``, converts each to a dictionary
    /// representation, and updates the application context so the watch can display
    /// available regions even when the iOS app is not running.
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
