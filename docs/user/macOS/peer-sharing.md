# Peer-to-Peer Sharing

Send map regions from your Mac directly to a nearby iPhone — no internet required.

## How It Works

OpenHiker uses MultipeerConnectivity to transfer data over Bluetooth and Wi-Fi between your Mac and nearby Apple devices.

## Sending a Region to iPhone

1. Go to the **Downloaded** section
2. Right-click the region you want to send
3. Select **"Send to iPhone"**
4. A transfer sheet opens:
   - Shows the region name and file size
   - Displays "Waiting for iPhone..." while advertising
   - Shows transfer progress with a percentage bar
   - Confirms completion with a green checkmark

<!-- Screenshot: Mac P2P send sheet -->
> **[Screenshot placeholder]** *P2P send dialog showing "Ridge Mountains Region — 48 MB" with a progress bar at 67%*

## What Gets Transferred

A complete transfer includes:
- **Map tiles** (MBTiles file)
- **Routing database** (if available)
- **Planned routes** for that region
- **Saved routes/hikes** for that region
- **Waypoints** for that region

## On the iPhone

1. Open OpenHiker on your iPhone
2. Go to the **Downloaded** tab
3. Tap the **receive** button (download icon) in the toolbar
4. Tap your Mac when it appears in the device list
5. The transfer completes automatically

## Troubleshooting

| Issue | Solution |
|-------|----------|
| iPhone doesn't see Mac | Ensure both are on the same Wi-Fi network, or have Bluetooth enabled |
| VPN warning | Disconnect VPN — it can interfere with local network discovery |
| Transfer is slow | Move devices closer; Wi-Fi transfer is faster than Bluetooth |
| Transfer fails | Cancel and retry; ensure OpenHiker is open on both devices |

## Network Requirements

P2P sharing uses Apple's Bonjour protocol (`_openhiker-xfer._tcp`). It works:
- Over Wi-Fi (same network)
- Over Bluetooth
- Without internet access

All data stays on the local network — nothing goes through external servers.
