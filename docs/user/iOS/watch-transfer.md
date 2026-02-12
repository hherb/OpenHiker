# Apple Watch Transfer

The **Watch** tab manages map and route transfers between your iPhone and Apple Watch.

## Prerequisites

- Apple Watch paired with your iPhone
- OpenHiker installed on both devices
- Bluetooth connection active

## Connection Status

The Watch tab shows the current connection state:

| Status | Description |
|--------|-------------|
| **Watch Ready** | Watch is connected and ready for transfers |
| **No Watch Paired** | No Apple Watch detected — check Bluetooth |
| **Watch App Not Installed** | Install OpenHiker on your watch from the Watch app |

<!-- Screenshot: Watch sync tab showing connection status -->
> **[Screenshot placeholder]** *Watch tab showing "Watch Ready" status with green indicator and a list of regions with transfer status icons*

## Transferring a Map Region

### From the Watch Tab
1. Tap **Send All Regions to Watch** to transfer everything at once

### From the Downloaded Tab
1. Find the region you want to transfer
2. Tap the **send to watch** button (arrow icon) on that region

### Transfer Status

Each region shows a transfer status icon:

| Icon | Status |
|------|--------|
| Clock | Queued — waiting to send |
| Checkmark | Completed — successfully on watch |
| Warning | Failed — try again |

## Transferring Routes

To send a planned route to your watch:

1. Go to the **Routes** tab
2. Open the route detail
3. Tap **Send to Watch** in the toolbar

The route appears in the watch's Routes tab for on-wrist navigation.

## What Gets Transferred

When you send a region, the following data is included:

- **Map tiles** (MBTiles file)
- **Routing database** (if the region includes routing data)
- **Region metadata** (name, bounds, zoom levels)

Waypoints and routes sync separately via the WatchConnectivity framework.

## Transfer Tips

- Transfers happen via Bluetooth/Wi-Fi — keep both devices nearby
- Large regions (>100 MB) may take several minutes
- The watch must have enough free storage
- Transfers continue in the background while you use other apps
- If a transfer fails, simply re-send the region

## On-Demand Download

If you're on the trail with your watch and realize you need a different map area, the watch can request a map download from your iPhone — see the [watchOS On-Demand Maps](../watchOS/map-navigation.md#on-demand-maps) section.
