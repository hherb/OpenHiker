# Peer-to-Peer Region & Route Sharing — Developer Guide

This document covers the implementation of peer-to-peer region and route sharing via Apple's MultipeerConnectivity framework. Read this before modifying, expanding, or debugging any P2P transfer features.

---

## Feature Overview

Peer-to-peer sharing allows any two devices (Mac-to-iPhone, iPhone-to-iPhone) to transfer downloaded map regions and all associated data — saved routes, planned routes, and waypoints — without requiring internet access.

Typical use case: a hiking group at a trailhead shares a pre-downloaded region and routes between phones before heading into an area without connectivity.

---

## Architecture Diagram

```
Device A (Sender)                    Device B (Receiver)
┌──────────────────────┐            ┌──────────────────────┐
│ PeerSendView (iOS)   │            │ PeerReceiveView (iOS)│
│ MacPeerSendView (Mac)│            │                      │
│                      │            │                      │
│  onAppear:           │            │  onAppear:           │
│  startAdvertising()  │            │  startBrowsing()     │
│  role = .sender      │            │  role = .receiver    │
└──────────┬───────────┘            └──────────┬───────────┘
           │                                   │
           ▼                                   ▼
┌──────────────────────────────────────────────────────────┐
│                   PeerTransferService                    │
│                   (Shared singleton)                     │
│                                                          │
│  MCNearbyServiceAdvertiser ◄──── MCNearbyServiceBrowser  │
│         (sender)                      (receiver)         │
│                                                          │
│          MCSession (encrypted, recreated per transfer)   │
│                                                          │
│  TransferRole: .sender / .receiver                       │
│  TransferState: idle → waitingForPeer → connected →      │
│    sendingManifest → sendingMBTiles → sendingRouting →   │
│    sendingSavedRoutes → sendingPlannedRoutes →            │
│    sendingWaypoints → completed                          │
└──────────────────────────────────────────────────────────┘
```

---

## File Map

### Shared (iOS + macOS targets)

| File | Purpose |
|------|---------|
| `Shared/Services/PeerTransferService.swift` | Core MPC service: advertising, browsing, session management, sequential resource transfer, resource reception and import |

### iOS-Only

| File | Purpose |
|------|---------|
| `OpenHiker iOS/Views/PeerSendView.swift` | Sender sheet — presented from context menu on region rows |
| `OpenHiker iOS/Views/PeerReceiveView.swift` | Receiver sheet — presented from toolbar button on Downloaded Regions tab |

### macOS-Only

| File | Purpose |
|------|---------|
| `OpenHiker macOS/Views/MacPeerSendView.swift` | Sender sheet — presented from context menu on Mac region rows |

### Modified Files (for P2P context menu integration)

| File | Change |
|------|--------|
| `OpenHiker iOS/App/ContentView.swift` | Added `regionToSend` state, `.contextMenu` on region rows with "Share with nearby device", `.sheet` presenting `PeerSendView` |
| `Shared/Storage/RouteStore.swift` | Added `fetchForRegion(_ regionId:)` method |
| `Shared/Models/PlannedRoute.swift` | Added `fetchForRegion(_ regionId:)` to `PlannedRouteStore` |

---

## Transfer Protocol

The transfer protocol sends resources sequentially over an MCSession using `sendResource(at:withName:toPeer:)`. Each resource name is prefixed with a type tag followed by the region UUID:

```
manifest:<uuid>        →  JSON-encoded Region metadata
mbtiles:<uuid>         →  The MBTiles tile database file
routing:<uuid>         →  The routing graph database (if hasRoutingData)
savedroutes:<uuid>     →  JSON array of SavedRoute objects
plannedroutes:<uuid>   →  JSON array of PlannedRoute objects
waypoints:<uuid>       →  JSON array of Waypoint objects (from saved routes)
done:<uuid>            →  Sentinel — signals all resources have been sent
```

### Sequencing

Resources are sent one at a time using `async/await`. Each `sendResource` call wraps the MPC completion handler in a `CheckedContinuation`:

```swift
private func sendResource(at url: URL, withName name: String, toPeer peer: MCPeerID) async throws {
    try await withCheckedThrowingContinuation { continuation in
        session.sendResource(at: url, withName: name, toPeer: peer) { error in
            if let error { continuation.resume(throwing: error) }
            else { continuation.resume() }
        }
    }
}
```

Progress for each resource is tracked via KVO on the `Progress` object returned by `sendResource`.

### Receiver Handling

On the receiver side, `session(_:didFinishReceivingResourceWithName:fromPeer:at:withError:)` dispatches based on the name prefix:

| Prefix | Action |
|--------|--------|
| `manifest:` | Decode `Region` JSON, store as `receivedManifest` |
| `mbtiles:` | Move file to `RegionStorage.mbtilesURL(for:)`, save region metadata |
| `routing:` | Move file to `RegionStorage.routingDbURL(for:)` |
| `savedroutes:` | Decode `[SavedRoute]`, insert each via `RouteStore.shared.insert()` |
| `plannedroutes:` | Decode `[PlannedRoute]`, save each via `PlannedRouteStore.shared.save()` |
| `waypoints:` | Decode `[Waypoint]`, insert each via `WaypointStore.shared.insert()` |
| `done:` | Set `transferState = .completed` |

---

## Role-Based Architecture

Prior to iPhone-to-iPhone support, the auto-send logic was gated with `#if os(macOS)`. This was replaced with a runtime role system:

```swift
enum TransferRole {
    case sender
    case receiver
}
private var currentRole: TransferRole?
```

- `startAdvertising(region:)` sets `currentRole = .sender`
- `startBrowsing()` sets `currentRole = .receiver`
- `disconnect()` clears `currentRole = nil`

When a peer connects, the session delegate checks the role:

```swift
case .connected:
    self.transferState = .connected
    if self.currentRole == .sender {
        self.sendRegion(to: peerID)
    }
```

This allows any device (Mac or iPhone) to be either the sender or receiver.

---

## MCSession Management

### Session Recreation

MCSession objects become unreliable after `disconnect()`. The service creates a fresh session for each transfer cycle:

```swift
private func createSession() {
    session?.disconnect()
    session = MCSession(
        peer: myPeerID,
        securityIdentity: nil,
        encryptionPreference: .optional
    )
    session.delegate = self
}
```

Both `startAdvertising()` and `startBrowsing()` call `createSession()` before configuring the advertiser or browser.

### Encryption Preference

The session uses `.optional` (not `.none`). Using `.none` caused AWDL (Apple Wireless Direct Link) connection timeouts. `.optional` lets TLS negotiate without requiring certificates while maintaining compatibility with AWDL transport.

### Peer Identity

`MCPeerID` equality is based on **object identity**, not `displayName`. To prevent duplicate entries in the discovered peers list, the browser delegate filters by `displayName`:

```swift
func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, ...) {
    if !self.discoveredPeers.contains(where: { $0.displayName == peerID.displayName }) {
        self.discoveredPeers.append(peerID)
    }
}
```

### Invitation Guard

An `isInviting` flag prevents flooding the connection with duplicate invitations when a user taps a peer multiple times:

```swift
func invitePeer(_ peer: MCPeerID) {
    guard !isInviting else { return }
    isInviting = true
    browser?.invitePeer(peer, to: session, withContext: nil, timeout: 60)
}
```

`isInviting` is reset on disconnect or when the peer transitions to `.notConnected`.

---

## UI Layer

### iOS Sender (`PeerSendView`)

- Presented via `.sheet(item: $regionToSend)` from a `.contextMenu` on each region row
- Shows region name and file size in the header
- Status section switches on `transferState`: waiting → connected → progress → complete/failed
- "Try Again" button on failure calls `disconnect()` then `startAdvertising(region:)`
- `onAppear` → `startAdvertising(region:)`, `onDisappear` → `stopAdvertising()`

### iOS Receiver (`PeerReceiveView`)

- Presented via `.sheet(isPresented: $showingPeerReceive)` from a toolbar button
- Shows a scanning indicator until peers are discovered
- Discovered peers listed with tap-to-connect
- Progress bar during transfer, checkmark on completion
- `onAppear` → `startBrowsing()`, `onDisappear` → `stopBrowsing()`

### macOS Sender (`MacPeerSendView`)

- Same logic as iOS sender but with macOS styling (no NavigationStack, fixed frame, keyboard shortcuts)
- Uses `HStack` for Cancel/Done buttons instead of toolbar items

All three views observe `PeerTransferService.shared` as an `@ObservedObject`.

---

## Thread Safety

`PeerTransferService` is an `NSObject` subclass marked `@unchecked Sendable`. All `@Published` properties (`transferState`, `progress`, `discoveredPeers`, `connectedPeers`) are updated on `DispatchQueue.main` from delegate callbacks. The `sendRegion(to:)` method runs in a `Task { @MainActor in ... }` block.

---

## Network Requirements

MultipeerConnectivity uses:
- **AWDL** (Apple Wireless Direct Link) — peer-to-peer WiFi, no router needed
- **Infrastructure WiFi** — if both devices are on the same network
- **Bluetooth LE** — for initial discovery (AWDL handles data transfer)

**Important:** VPNs can block MPC connections. If connections time out, check whether a VPN is active on either device.

The iOS entitlements file does **not** require `com.apple.developer.networking.multicast` — MPC works without it. The macOS entitlements require `com.apple.security.network.client` and `com.apple.security.network.server` (already present for iCloud networking).

---

## Extending the Transfer Protocol

### Adding a new resource type

1. Add a new `TransferState` case (e.g., `.sendingPhotos`) in `PeerTransferService.swift`
2. Update `TransferState.description` with a human-readable string
3. In `sendRegion(to:)`, add a step that encodes and sends the new resource with a prefix (e.g., `photos:<uuid>`)
4. In `handleReceivedResource(name:at:)`, add a `case "photos":` handler to decode and import
5. Update all three views (`PeerSendView`, `PeerReceiveView`, `MacPeerSendView`) to include the new state in their `switch` statements for progress display
6. Ensure the `done:` sentinel remains the last resource sent

### Supporting selective transfer

Currently all routes and waypoints associated with a region are transferred automatically. To add user selection:

1. Add a `@Published var selectedRoutes: Set<UUID>` to the service
2. Filter routes in `sendRegion(to:)` before encoding
3. Add a selection UI in `PeerSendView` between the header and status sections

---

## Testing

### Manual Testing Checklist

1. **iPhone → iPhone:** Long-press region → "Share with nearby device" → second iPhone opens "Receive" → taps first phone → transfer completes
2. **Mac → iPhone:** Right-click region on Mac → "Send to iPhone" → iPhone opens "Receive" → taps Mac → transfer completes
3. **Routes included:** After transfer, verify saved routes, planned routes, and waypoints appear on the receiver
4. **Retry on failure:** Disconnect mid-transfer → "Try Again" button works → fresh session and successful retransfer
5. **Cancel:** Cancel on either side → both devices return to idle state cleanly
6. **Duplicate peers:** Same device does not appear twice in the peer list
7. **VPN interference:** With VPN active, connection should still time out gracefully with a user-visible error (not hang)

### Build Verification

```bash
# iOS target (includes PeerSendView, PeerReceiveView, PeerTransferService)
xcodebuild -scheme "OpenHiker" -destination "platform=iOS Simulator,name=iPhone 16 Pro"

# macOS target (includes MacPeerSendView, PeerTransferService)
xcodebuild -scheme "OpenHiker macOS" build
```

---

## Common Issues & Debugging

### Connection times out

1. Check both devices are on the same WiFi network or within Bluetooth range
2. Disable VPN on both devices
3. Ensure the sender is advertising (`startAdvertising` logged) and receiver is browsing (`startBrowsing` logged)
4. Check console for `PeerTransferService:` log messages — the service logs all state transitions

### Duplicate peers in list

Should not happen after the `displayName`-based dedup fix. If it recurs, check that `foundPeer` is being called with the same `displayName` from multiple `MCPeerID` instances.

### Transfer fails with "Peer disconnected"

The MCSession dropped. This typically happens if:
- One device goes to sleep or backgrounds the app
- WiFi or Bluetooth drops momentarily
- The session was reused from a previous transfer (should not happen — `createSession()` prevents this)

User action: tap "Try Again" to create a fresh session and re-advertise/re-browse.

### "No region selected" error

The `regionToSend` property was nil when `sendRegion(to:)` was called. This can happen if `disconnect()` was called between `startAdvertising` and connection establishment.

### `@unchecked Sendable` warning

`PeerTransferService` uses `@unchecked Sendable` because KVO closures capture `self` in `@Sendable` contexts. The service is safe because all mutable state is accessed on `DispatchQueue.main`.
