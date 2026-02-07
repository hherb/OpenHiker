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
import MultipeerConnectivity
import Combine

/// Manages peer-to-peer transfer of map regions between macOS and iOS via MultipeerConnectivity.
///
/// On **macOS** the service acts as an advertiser/sender: it makes itself discoverable on the
/// local network and sends MBTiles files (and optional routing databases) to a connected iPhone.
///
/// On **iOS** the service acts as a browser/receiver: it discovers a nearby Mac, connects,
/// receives the region files, and saves them into ``RegionStorage``.
///
/// ## Transfer Protocol
/// 1. Mac advertises with service type `"openhiker-xfer"`.
/// 2. iPhone browses, discovers the Mac, and sends an invitation.
/// 3. Mac auto-accepts the invitation and a session is established.
/// 4. Mac sends three resources in order:
///    - `manifest:<uuid>` — a JSON-encoded ``Region`` manifest
///    - `mbtiles:<uuid>` — the MBTiles database file
///    - `routing:<uuid>` — the routing graph database (only if `hasRoutingData`)
/// 5. iPhone receives each resource, copies it to the regions directory, and saves the metadata.
///
/// ## Thread Safety
/// All `@Published` properties are updated on the main thread. The MPC delegate callbacks
/// are dispatched to `DispatchQueue.main` before mutating state.
class PeerTransferService: NSObject, ObservableObject {

    // MARK: - Constants

    /// Bonjour service type for region transfer (max 15 chars, lowercase + hyphens).
    static let serviceType = "openhiker-xfer"

    /// Timeout in seconds for peer invitations.
    static let invitationTimeout: TimeInterval = 30

    // MARK: - Transfer State

    /// The possible states of a region transfer.
    enum TransferState: Equatable {
        /// Idle — no transfer in progress.
        case idle
        /// Waiting for a peer to connect.
        case waitingForPeer
        /// A peer has connected and is ready to send/receive.
        case connected
        /// Sending/receiving the manifest file.
        case sendingManifest
        /// Sending/receiving the MBTiles file.
        case sendingMBTiles
        /// Sending/receiving the routing database.
        case sendingRouting
        /// Transfer completed successfully.
        case completed
        /// Transfer failed with an error message.
        case failed(String)

        /// Human-readable description for display in the UI.
        var description: String {
            switch self {
            case .idle: return "Ready"
            case .waitingForPeer: return "Waiting for connection…"
            case .connected: return "Connected"
            case .sendingManifest: return "Sending manifest…"
            case .sendingMBTiles: return "Sending map tiles…"
            case .sendingRouting: return "Sending routing data…"
            case .completed: return "Transfer complete"
            case .failed(let msg): return "Failed: \(msg)"
            }
        }
    }

    // MARK: - Published State

    /// Current state of the transfer.
    @Published var transferState: TransferState = .idle

    /// Peers discovered by the browser (iOS side).
    @Published var discoveredPeers: [MCPeerID] = []

    /// Currently connected peers.
    @Published var connectedPeers: [MCPeerID] = []

    /// Transfer progress as a fraction from 0.0 to 1.0.
    @Published var progress: Double = 0

    // MARK: - Private Properties

    /// The local peer identity, derived from the device name.
    private let myPeerID: MCPeerID

    /// The active MPC session.
    private let session: MCSession

    /// Advertiser for the macOS sender side.
    private var advertiser: MCNearbyServiceAdvertiser?

    /// Browser for the iOS receiver side.
    private var browser: MCNearbyServiceBrowser?

    /// KVO observation token for tracking resource transfer progress.
    private var progressObservation: NSKeyValueObservation?

    /// The region currently being sent (macOS side).
    private var regionToSend: Region?

    /// Temporary storage for received manifest data (iOS side).
    private var receivedManifest: Region?

    // MARK: - Singleton

    /// Shared singleton instance.
    static let shared = PeerTransferService()

    // MARK: - Initialization

    /// Creates a new peer transfer service with a local peer identity.
    override init() {
        #if os(macOS)
        self.myPeerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
        #else
        self.myPeerID = MCPeerID(displayName: UIDevice.current.name)
        #endif

        self.session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )

        super.init()
        session.delegate = self
    }

    // MARK: - Advertiser (macOS Sender)

    /// Starts advertising this device as available for region transfer.
    ///
    /// Called on macOS when the user initiates "Send to iPhone" for a region.
    /// The service advertises using Bonjour so that nearby iOS devices can discover it.
    ///
    /// - Parameter region: The ``Region`` to send once a peer connects.
    func startAdvertising(region: Region) {
        regionToSend = region
        transferState = .waitingForPeer
        progress = 0

        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: ["region": region.name],
            serviceType: Self.serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }

    /// Stops advertising and tears down the advertiser.
    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
    }

    // MARK: - Browser (iOS Receiver)

    /// Starts browsing for nearby macOS peers advertising region transfers.
    ///
    /// Called on iOS when the user opens the "Receive from Mac" sheet.
    func startBrowsing() {
        discoveredPeers = []
        transferState = .waitingForPeer
        progress = 0

        browser = MCNearbyServiceBrowser(
            peer: myPeerID,
            serviceType: Self.serviceType
        )
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    /// Stops browsing and tears down the browser.
    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
    }

    /// Sends an invitation to the specified peer to join the session.
    ///
    /// Called on iOS when the user taps a discovered Mac in the peer list.
    ///
    /// - Parameter peer: The ``MCPeerID`` of the Mac to connect to.
    func invitePeer(_ peer: MCPeerID) {
        browser?.invitePeer(
            peer,
            to: session,
            withContext: nil,
            timeout: Self.invitationTimeout
        )
    }

    // MARK: - Send Region (macOS)

    /// Sends the queued region to all connected peers.
    ///
    /// Sends three resources in sequence: manifest JSON, MBTiles file, and
    /// optionally the routing database. Each resource name is prefixed with
    /// its type (`manifest:`, `mbtiles:`, `routing:`) followed by the region UUID.
    ///
    /// - Parameter peer: The connected peer to send to.
    private func sendRegion(to peer: MCPeerID) {
        guard let region = regionToSend else {
            DispatchQueue.main.async {
                self.transferState = .failed("No region selected")
            }
            return
        }

        Task { @MainActor in
            do {
                // Step 1: Send manifest
                transferState = .sendingManifest
                progress = 0
                let manifestData = try JSONEncoder().encode(region)
                let manifestURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("manifest_\(region.id.uuidString).json")
                try manifestData.write(to: manifestURL)

                try await sendResource(
                    at: manifestURL,
                    withName: "manifest:\(region.id.uuidString)",
                    toPeer: peer
                )
                try? FileManager.default.removeItem(at: manifestURL)

                // Step 2: Send MBTiles
                transferState = .sendingMBTiles
                progress = 0
                let mbtilesURL = RegionStorage.shared.mbtilesURL(for: region)
                guard FileManager.default.fileExists(atPath: mbtilesURL.path) else {
                    transferState = .failed("MBTiles file not found")
                    return
                }

                try await sendResource(
                    at: mbtilesURL,
                    withName: "mbtiles:\(region.id.uuidString)",
                    toPeer: peer
                )

                // Step 3: Send routing database (if available)
                if region.hasRoutingData {
                    transferState = .sendingRouting
                    progress = 0
                    let routingURL = RegionStorage.shared.routingDbURL(for: region)
                    if FileManager.default.fileExists(atPath: routingURL.path) {
                        try await sendResource(
                            at: routingURL,
                            withName: "routing:\(region.id.uuidString)",
                            toPeer: peer
                        )
                    }
                }

                transferState = .completed
                progress = 1.0
            } catch {
                transferState = .failed(error.localizedDescription)
            }
        }
    }

    /// Sends a single resource file to a peer and awaits completion.
    ///
    /// Wraps `MCSession.sendResource(at:withName:toPeer:withCompletionHandler:)` in
    /// an async/await interface and observes the returned `Progress` to update
    /// the published ``progress`` property.
    ///
    /// - Parameters:
    ///   - url: The local file URL to send.
    ///   - name: The resource name (includes type prefix and UUID).
    ///   - peer: The target peer.
    /// - Throws: If the send operation fails.
    private func sendResource(at url: URL, withName name: String, toPeer peer: MCPeerID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let sendProgress = session.sendResource(
                at: url,
                withName: name,
                toPeer: peer
            ) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }

            if let sendProgress = sendProgress {
                self.progressObservation = sendProgress.observe(\.fractionCompleted) { [weak self] prog, _ in
                    DispatchQueue.main.async {
                        self?.progress = prog.fractionCompleted
                    }
                }
            }
        }
    }

    // MARK: - Disconnect

    /// Disconnects from all peers and resets state.
    func disconnect() {
        session.disconnect()
        stopAdvertising()
        stopBrowsing()
        progressObservation = nil
        regionToSend = nil
        receivedManifest = nil

        DispatchQueue.main.async {
            self.transferState = .idle
            self.discoveredPeers = []
            self.connectedPeers = []
            self.progress = 0
        }
    }
}

// MARK: - MCSessionDelegate

extension PeerTransferService: MCSessionDelegate {

    /// Called when a peer's connection state changes.
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                self.transferState = .connected
                // On macOS, auto-start sending once connected
                #if os(macOS)
                self.sendRegion(to: peerID)
                #endif

            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
                if self.connectedPeers.isEmpty {
                    // Only mark failed if we were mid-transfer
                    if case .sendingManifest = self.transferState { self.transferState = .failed("Peer disconnected") }
                    else if case .sendingMBTiles = self.transferState { self.transferState = .failed("Peer disconnected") }
                    else if case .sendingRouting = self.transferState { self.transferState = .failed("Peer disconnected") }
                }

            case .connecting:
                break

            @unknown default:
                break
            }
        }
    }

    /// Called when data is received (not used — we use resource transfer instead).
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Not used for region transfer
    }

    /// Called when a stream is received (not used).
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used for region transfer
    }

    /// Called when a resource transfer begins on the receiver side.
    ///
    /// Observes the `Progress` object to update the UI with transfer progress.
    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with transferProgress: Progress
    ) {
        DispatchQueue.main.async {
            if resourceName.hasPrefix("manifest:") {
                self.transferState = .sendingManifest
            } else if resourceName.hasPrefix("mbtiles:") {
                self.transferState = .sendingMBTiles
            } else if resourceName.hasPrefix("routing:") {
                self.transferState = .sendingRouting
            }
            self.progress = 0
        }

        progressObservation = transferProgress.observe(\.fractionCompleted) { [weak self] prog, _ in
            DispatchQueue.main.async {
                self?.progress = prog.fractionCompleted
            }
        }
    }

    /// Called when a resource transfer completes on the receiver side.
    ///
    /// Parses the resource name prefix to determine the file type, then copies it
    /// to the appropriate location in ``RegionStorage``.
    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        DispatchQueue.main.async {
            if let error = error {
                self.transferState = .failed(error.localizedDescription)
                return
            }

            guard let localURL = localURL else {
                self.transferState = .failed("No file received")
                return
            }

            self.handleReceivedResource(name: resourceName, at: localURL)
        }
    }

    /// Processes a received resource file based on its name prefix.
    ///
    /// - Parameters:
    ///   - name: The resource name (e.g., `"manifest:<uuid>"`, `"mbtiles:<uuid>"`).
    ///   - localURL: The temporary file URL where the resource was saved.
    private func handleReceivedResource(name: String, at localURL: URL) {
        let components = name.split(separator: ":", maxSplits: 1)
        guard components.count == 2 else {
            transferState = .failed("Invalid resource name: \(name)")
            return
        }

        let prefix = String(components[0])
        let uuidString = String(components[1])

        switch prefix {
        case "manifest":
            do {
                let data = try Data(contentsOf: localURL)
                let region = try JSONDecoder().decode(Region.self, from: data)
                receivedManifest = region
                print("PeerTransferService: Received manifest for '\(region.name)'")
            } catch {
                transferState = .failed("Failed to decode manifest: \(error.localizedDescription)")
            }
            try? FileManager.default.removeItem(at: localURL)

        case "mbtiles":
            guard let region = receivedManifest, region.id.uuidString == uuidString else {
                transferState = .failed("Received MBTiles without matching manifest")
                return
            }
            let destURL = RegionStorage.shared.mbtilesURL(for: region)
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: localURL, to: destURL)
                print("PeerTransferService: Saved MBTiles to \(destURL.lastPathComponent)")

                // If the region has no routing data, save it now
                if !region.hasRoutingData {
                    RegionStorage.shared.saveRegion(region)
                    transferState = .completed
                    progress = 1.0
                    receivedManifest = nil
                    print("PeerTransferService: Region '\(region.name)' saved (no routing data)")
                }
            } catch {
                transferState = .failed("Failed to save MBTiles: \(error.localizedDescription)")
            }

        case "routing":
            guard let region = receivedManifest, region.id.uuidString == uuidString else {
                transferState = .failed("Received routing DB without matching manifest")
                return
            }
            let destURL = RegionStorage.shared.routingDbURL(for: region)
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: localURL, to: destURL)
                RegionStorage.shared.saveRegion(region)
                transferState = .completed
                progress = 1.0
                receivedManifest = nil
                print("PeerTransferService: Region '\(region.name)' saved with routing data")
            } catch {
                transferState = .failed("Failed to save routing DB: \(error.localizedDescription)")
            }

        default:
            transferState = .failed("Unknown resource type: \(prefix)")
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate (macOS sender)

extension PeerTransferService: MCNearbyServiceAdvertiserDelegate {

    /// Auto-accepts incoming invitations from iOS devices.
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        print("PeerTransferService: Received invitation from \(peerID.displayName)")
        invitationHandler(true, session)
    }

    /// Logs advertiser errors.
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("PeerTransferService: Failed to advertise: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.transferState = .failed("Failed to advertise: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate (iOS receiver)

extension PeerTransferService: MCNearbyServiceBrowserDelegate {

    /// Called when a nearby Mac is discovered.
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            if !self.discoveredPeers.contains(peerID) {
                self.discoveredPeers.append(peerID)
            }
        }
    }

    /// Called when a previously discovered Mac is no longer available.
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0 == peerID }
        }
    }

    /// Logs browser errors.
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("PeerTransferService: Failed to browse: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.transferState = .failed("Failed to browse: \(error.localizedDescription)")
        }
    }
}
