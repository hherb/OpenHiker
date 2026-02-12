# Peer-to-Peer Sharing

OpenHiker can transfer map regions, routes, and waypoints directly between devices on the same local network — no internet required.

## How It Works

Peer-to-peer (P2P) sharing uses Apple's MultipeerConnectivity framework to transfer data over Bluetooth and Wi-Fi between nearby devices. This works between:

- iPhone ↔ iPhone
- iPhone ↔ Mac
- Mac ↔ Mac

## Sending a Region

1. Go to the **Downloaded** tab
2. Long-press (or right-click on iPad) on the region you want to share
3. Select **Share with nearby device** from the context menu
4. The send screen appears and begins advertising your device

<!-- Screenshot: Peer send view -->
> **[Screenshot placeholder]** *P2P send screen showing "Waiting for iPhone..." with the region name and file size*

### What Gets Sent

A P2P transfer includes everything associated with the region:

- Map tiles (MBTiles file)
- Routing database (if available)
- Planned routes for that region
- Saved routes (hikes) for that region
- Waypoints for that region

## Receiving a Region

1. Go to the **Downloaded** tab
2. Tap the **receive** button (download icon) in the toolbar
3. The receive screen appears and scans for nearby devices
4. Tap the sending device when it appears
5. Wait for the transfer to complete

The region and all associated data are automatically imported.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Devices can't find each other | Ensure both are on the same Wi-Fi, or have Bluetooth enabled |
| Transfer is slow | Move devices closer together; Wi-Fi is faster than Bluetooth |
| VPN warning | P2P may not work with some VPN configurations — try disconnecting |
| Transfer fails | Cancel and try again; ensure both devices have OpenHiker open |

## Privacy

P2P transfers happen directly between devices without going through any server. Your data stays on the local network.
