# LostBuddy: Cross-Platform Proximity Sharing Feasibility Study

**Last updated:** 2026-02-09
**Status:** Research / Planning — no implementation yet
**Scope:** Evaluate approaches for proximity-based data sharing between OpenHiker users on iOS and Android devices, without requiring internet connectivity.

---

## Motivation

OpenHiker already supports device-to-device sharing via Apple's MultipeerConnectivity framework (`PeerTransferService`). This works well for iPhone-to-iPhone and Mac-to-iPhone transfers at trailheads.

However, **MultipeerConnectivity is Apple-only**. It uses Bonjour (mDNS) over Wi-Fi and Apple's proprietary BLE service discovery, making it impossible to communicate with Android devices. Hiking groups are often mixed-platform, and a cross-platform proximity sharing feature ("LostBuddy") would enable:

1. **Region/route sharing** — Transfer downloaded map regions and planned routes to Android hiking companions before heading into areas without connectivity.
2. **Group location awareness** — Share live GPS positions between nearby devices so hiking buddies can see each other on the map (especially useful when the group splits up).
3. **Emergency beacon** — A lost or injured hiker could broadcast their position to any nearby OpenHiker user, regardless of platform.

---

## Technology Options

### Option 1: Bluetooth Low Energy (BLE) — Custom GATT Service

Both iOS (Core Bluetooth) and Android (android.bluetooth.le) expose BLE APIs. A custom GATT service would allow cross-platform discovery and data exchange.

#### BLE Version Landscape (iPhones)

| iPhone | Bluetooth Version | Notable BLE Features |
|--------|------------------|----------------------|
| iPhone 13 series | 5.0 | 2x speed, 4x range vs 4.2, LE 2M PHY |
| iPhone 14 series | 5.3 | Connection Subrating, power efficiency |
| iPhone 15 series | 5.3 | Same + Thread radio (U1 improvements) |
| iPhone 16 series | 5.3 | Same capabilities |

**Critical limitation:** Apple does **not** expose BLE 5.0 Long Range (Coded PHY) in Core Bluetooth. Despite the hardware supporting it, the API only provides 1M and 2M PHY modes. This caps practical range to standard BLE levels.

#### BLE Range in Hiking Environments

| Environment | BLE 4.2 | BLE 5.0 (1M/2M PHY) | BLE 5.0 Long Range (Coded PHY) |
|-------------|---------|----------------------|--------------------------------|
| Open field / ridgeline | 30-50m | 60-100m | 200-400m |
| Light forest / scrub | 15-30m | 30-60m | 100-200m |
| Dense forest / rainforest | 5-15m | 10-30m | 50-100m |
| Urban canyon / deep valley | 10-20m | 20-40m | 80-150m |

**Note:** Long Range (Coded PHY) figures are theoretical only on Apple devices since Apple does not expose this PHY. Android devices with BLE 5.0+ *can* use Coded PHY if the chipset supports it.

#### Pros

- Works with zero infrastructure (no Wi-Fi network, no internet, no hotspot)
- Low power consumption — viable for all-day background operation
- Universal: every modern smartphone has BLE
- Well-suited for small payloads (GPS coordinates, status updates)
- Background operation possible on both iOS (with caveats) and Android

#### Cons

- **Range is severely limited** — 10-30m in dense forest is essentially useless for tracking separated hiking buddies
- **Apple blocks Long Range PHY** — the one BLE feature that would make forest range acceptable is not available on iOS
- **Slow throughput** — practical BLE transfer speeds are ~100-200 KB/s; transferring a 20 MB MBTiles region would take 2-3 minutes minimum
- **iOS background BLE restrictions** — Apple aggressively throttles BLE advertising and scanning in background mode (slower intervals, limited advertisement data)
- **Connection management complexity** — BLE GATT requires careful handling of MTU negotiation, connection intervals, service discovery, and reconnection logic
- **File transfer requires custom chunking** — BLE has no built-in concept of "file transfer"; must implement chunking, reassembly, checksums, and retry logic from scratch
- **Platform behavioral differences** — iOS and Android handle BLE connection parameters, background state, and scanning behavior very differently, requiring extensive platform-specific tuning

#### Suitability Verdict

- **GPS coordinate sharing:** Feasible but range-limited. Only useful when hikers are already close together.
- **Region/route file transfer:** Technically possible but painfully slow and complex to implement reliably.
- **Emergency beacon:** Impractical — 10-30m range in forest means the "beacon" only works if someone is already almost on top of you.

---

### Option 2: Wi-Fi Direct / Peer-to-Peer Wi-Fi

#### Status

- **Android:** Fully supports Wi-Fi Direct (peer-to-peer connections without an access point). Well-documented API.
- **iOS:** Apple does **not** expose Wi-Fi Direct APIs publicly. Apple's peer-to-peer Wi-Fi is only available through MultipeerConnectivity (Apple-to-Apple only). There is no public API to create or join a Wi-Fi Direct group from an iOS app.

#### Verdict: Dead end for cross-platform use

This option is not viable because iOS cannot participate in Wi-Fi Direct connections initiated by Android devices. Apple has chosen to keep peer-to-peer Wi-Fi locked behind MultipeerConnectivity.

---

### Option 3: Local Wi-Fi Hotspot + TCP/Bonjour

One device creates a Wi-Fi hotspot, the other connects. Once on the same network, devices discover each other via mDNS/Bonjour (iOS `NWBrowser` / Android `NsdManager`) and transfer data over TCP sockets.

#### Pros

- **Fast transfers** — Wi-Fi speeds (10+ MB/s), a 20 MB MBTiles region transfers in ~2 seconds
- **Good range** — Wi-Fi hotspot range is 30-50m+, significantly better than BLE in forest
- **Mature networking stack** — TCP handles reliability, ordering, flow control; no need for custom chunking
- **Cross-platform** — Both iOS and Android can create hotspots and connect to them
- **Proven pattern** — Many file-sharing apps (SHAREit, Snapdrop clones) use this approach
- **Works anywhere** — No infrastructure required beyond the devices themselves

#### Cons

- **Manual setup required** — User must go to Settings, enable Personal Hotspot, share the password; other user must manually join. This is a clunky UX compared to MultipeerConnectivity's automatic discovery
- **iOS hotspot restrictions** — iOS Personal Hotspot requires a cellular data plan on the hosting device (it's technically "Internet Sharing"). On devices without cellular, this option may not be available
- **Breaks existing Wi-Fi** — The connecting device disconnects from any existing Wi-Fi network to join the hotspot
- **Battery intensive** — Running a Wi-Fi hotspot drains battery significantly faster than BLE
- **Single direction at a time** — One device must be the hotspot, the other the client; roles must be coordinated manually
- **No background discovery** — Can't scan for nearby OpenHiker users passively; requires deliberate user action

#### Suitability Verdict

- **Region/route file transfer:** Excellent. Fast, reliable, good range. Best option for large file transfers.
- **GPS coordinate sharing:** Overkill and impractical for continuous sharing due to battery drain and manual setup.
- **Emergency beacon:** Not suitable — requires manual connection setup, which defeats the purpose.

---

### Option 4: BLE for Discovery + Wi-Fi Hotspot for Transfer (Hybrid)

Use BLE for passive background discovery and presence awareness (small payloads: device name, GPS coordinates). When users want to transfer files, automatically coordinate a Wi-Fi hotspot connection for high-speed transfer.

#### Pros

- Best of both worlds: passive BLE discovery + fast Wi-Fi transfer
- BLE runs in background for location awareness while Wi-Fi is only used on-demand
- Can show "nearby hikers" list even before initiating a transfer
- Graceful degradation: if Wi-Fi fails, BLE can still share coordinates (slowly)

#### Cons

- **Full complexity of both stacks** — Must implement and maintain both BLE GATT and Wi-Fi/TCP networking
- **Hotspot coordination is fragile** — Negotiating which device creates the hotspot and automating the connection is unreliable on iOS (no programmatic hotspot join API)
- **iOS background BLE limitations still apply** — Nearby hiker detection will be delayed/unreliable when the app is backgrounded
- **BLE range limitation still applies** — Discovery only works within ~10-30m in forest

#### Suitability Verdict

Technically the most capable option but also the most complex to implement. The BLE range limitation means "nearby hiker" discovery still only works at close range.

---

### Option 5: Server Relay (Cloud-Based)

Upload GPS positions / files to a cloud server. Other users in the same "hiking group" receive updates. Could use WebSockets for real-time position sharing.

#### Pros

- **Unlimited range** — works as long as any cellular signal exists
- **Simple implementation** — standard HTTP/WebSocket client code on both platforms
- **No Bluetooth/Wi-Fi complexity** — just REST APIs
- **Group management** — easy to implement invite codes, group membership
- **Works across arbitrary distances** — hikers on different trails or continents

#### Cons

- **Requires internet connectivity** — fundamentally incompatible with OpenHiker's offline-first ethos
- **Server infrastructure costs** — hosting, scaling, maintenance
- **Privacy concerns** — user GPS data on a server, even temporarily
- **Latency** — depends on cell signal quality, which is poor in remote hiking areas
- **AGPL compliance** — server code would need to be open source under AGPL

#### Suitability Verdict

Viable as a complement to offline options but cannot be the primary approach for a hiking app focused on areas without connectivity.

---

### Option 6: Google Nearby Connections API

Google's cross-platform proximity library. Android-native, with an iOS SDK.

#### Status: Deprecated

Google discontinued the iOS Nearby Connections SDK. The Android API still exists but has no cross-platform iOS counterpart. Not viable.

---

## Comparison Matrix

| Criterion | BLE Only | Wi-Fi Hotspot | Hybrid (BLE+Wi-Fi) | Server Relay |
|-----------|----------|---------------|---------------------|--------------|
| Cross-platform | Yes | Yes | Yes | Yes |
| No internet required | Yes | Yes | Yes | No |
| Range (forest) | 10-30m | 30-50m+ | 10-30m (discovery) / 30-50m+ (transfer) | Unlimited (with signal) |
| File transfer speed | Slow (~100 KB/s) | Fast (~10 MB/s) | Fast (~10 MB/s) | Variable |
| Background operation | Limited (iOS) | No | Limited (BLE portion) | Yes |
| User setup required | Minimal | Manual hotspot | Manual hotspot for transfers | Account/group creation |
| Battery impact | Low | High (hotspot) | Medium | Low |
| Implementation effort | High | Medium | Very High | Medium |
| Passive discovery | Yes (short range) | No | Yes (short range) | Yes |
| Emergency beacon | Impractical (range) | No | Impractical (range) | Yes (if signal) |

---

## Key Findings

### 1. No silver bullet for cross-platform offline proximity sharing

Every option has significant trade-offs. Apple's refusal to expose Wi-Fi Direct and BLE Long Range PHY creates a fundamental platform gap that cannot be worked around elegantly.

### 2. BLE range in forest is the critical bottleneck

The 10-30m practical range in dense forest makes BLE-based buddy tracking largely impractical for the primary use case (separated hiking companions). BLE is only useful when hikers are already within shouting distance.

### 3. Wi-Fi hotspot is the most practical option for file sharing

For the trailhead use case (share a downloaded region with your group before setting off), Wi-Fi hotspot + TCP is fast, reliable, and cross-platform. The manual setup UX is acceptable because file sharing is an intentional, infrequent action.

### 4. Continuous cross-platform location sharing without internet is essentially unsolved

No existing technology provides reliable, long-range (>100m), cross-platform, infrastructure-free location sharing on consumer smartphones. This is a hardware/platform limitation, not a software one.

### 5. Server relay fills the gap where connectivity exists

For areas with cell signal, a lightweight server relay could complement the offline options. A simple WebSocket-based group position sharing service would cover the "where is my buddy on the other trail" use case — but only where there's signal.

---

## Recommended Approach (if proceeding)

### Phase A: Cross-Platform File Transfer via Wi-Fi Hotspot (~3-4 weeks)

The highest-value, most achievable feature. Allows mixed iOS/Android groups to share regions and routes at the trailhead.

**Scope:**
- Define a simple JSON-based transfer protocol over TCP (compatible with existing `PeerTransferService` resource sequence: manifest → mbtiles → routing → routes → waypoints)
- iOS: `NWListener` + `NWConnection` (Network.framework) for TCP server/client
- Android: Standard `ServerSocket` / `Socket` + `NsdManager` for mDNS discovery
- UI: "Share via Wi-Fi" button alongside existing "Share via AirDrop/Peer" option
- Manual hotspot setup with clear in-app instructions

**Dependencies:** Requires an Android companion app (or at minimum a protocol spec for third-party Android clients).

### Phase B: BLE Presence Awareness (~2-3 weeks, optional)

Low-priority addition for short-range "who's nearby" awareness.

**Scope:**
- Custom BLE GATT service broadcasting: device name, truncated GPS coordinate, hiking status
- iOS: Core Bluetooth peripheral/central
- Android: android.bluetooth.le advertiser/scanner
- UI: "Nearby Hikers" badge/count in navigation view
- Explicitly document the range limitation to users

**Caveat:** Given the 10-30m forest range, this feature's practical value is questionable. It may not be worth the implementation complexity.

### Phase C: Server Relay for Connected Areas (~2-3 weeks, optional)

Only if there's demand for real-time group tracking.

**Scope:**
- Lightweight WebSocket relay server (open source, AGPL)
- Group creation with invite codes (no accounts required)
- Ephemeral position sharing (positions stored in memory only, discarded when group ends)
- Client-side encryption of GPS coordinates
- Graceful degradation when signal is lost

**Caveat:** Conflicts with OpenHiker's offline-first philosophy. Server hosting costs. Privacy considerations.

---

## Open Questions

1. **Android app scope** — Is an Android version of OpenHiker planned? Without one, cross-platform sharing has no counterpart. Alternatively, could we publish a protocol spec and let third-party Android hiking apps implement compatibility?

2. **LoRa / Meshtastic integration** — Some hikers carry LoRa devices (Meshtastic, goTenna) with 1-5 km forest range. Could OpenHiker integrate with these via BLE as a relay? This would solve the range problem but adds hardware dependency.

3. **Apple Satellite SOS (iPhone 14+)** — Apple's satellite connectivity is for emergencies only and not available to third-party apps. However, if Apple ever opens an API for satellite messaging, this could be transformative for hiker-to-hiker communication.

4. **Offline Maps Interop** — If sharing regions cross-platform, the MBTiles format is universal. But Android apps use different tile storage conventions. Should OpenHiker standardize on MBTiles as the interchange format?

5. **Legal/liability** — An "emergency beacon" feature implies a safety promise. What are the liability implications if the beacon fails due to range limitations? How prominently must limitations be disclosed?
