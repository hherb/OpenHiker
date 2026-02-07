# Sharing Regions & Routes with Nearby Devices

OpenHiker lets you share downloaded map regions — along with all associated saved routes, planned routes, and waypoints — directly between devices using peer-to-peer wireless transfer. No internet connection is required.

This is ideal for hiking groups meeting at a trailhead: one person who prepared the maps and routes at home can share everything with the group before heading into areas without cellular coverage.

---

## What Gets Shared

When you share a region, OpenHiker automatically bundles everything associated with it:

| Data | Description |
|------|-------------|
| **Map tiles** | The full offline MBTiles database for the region |
| **Routing data** | The offline routing graph (if downloaded), enabling turn-by-turn navigation |
| **Saved routes** | Any recorded hikes you've completed in that region |
| **Planned routes** | Routes you've planned for the region |
| **Waypoints** | All waypoint pins from your saved routes (with notes and categories) |

The receiver gets a complete, ready-to-use copy — they can immediately view the map, follow planned routes, or start their own hike.

---

## Supported Transfer Directions

| From | To | How |
|------|----|-----|
| iPhone | iPhone | Both devices use OpenHiker for iOS |
| Mac | iPhone | Mac sends via "Send to iPhone", iPhone receives via "Receive" |

<!-- TODO: Screenshot showing supported transfer directions diagram -->

---

## Sharing a Region from iPhone

### Step 1: Open the Send Sheet

1. Go to the **Downloaded Regions** tab
2. **Long-press** (press and hold) on the region you want to share
3. Tap **"Share with nearby device"** from the context menu

<!-- TODO: Screenshot of context menu on region row with "Share with nearby device" option -->

### Step 2: Wait for Connection

The send sheet opens and your iPhone begins advertising on the local network. You'll see a spinning indicator and the message "Waiting for connection..."

<!-- TODO: Screenshot of PeerSendView in waiting state showing region name and "Waiting for connection..." -->

### Step 3: Transfer Happens Automatically

Once the receiving device connects (see "Receiving" below), the transfer starts automatically. A progress bar shows the current step:

- Sending manifest...
- Sending map tiles...
- Sending routing data...
- Sending recorded hikes...
- Sending planned routes...
- Sending waypoints...

<!-- TODO: Screenshot of PeerSendView showing progress bar during transfer -->

### Step 4: Done

A green checkmark confirms the transfer is complete. Tap **Done** to close the sheet.

<!-- TODO: Screenshot of PeerSendView showing "Transfer Complete" with green checkmark -->

---

## Sharing a Region from Mac

1. In the **Downloaded Regions** list, **right-click** (or Control-click) on the region
2. Select **"Send to iPhone"**
3. The send sheet opens — wait for the iPhone to connect
4. Transfer proceeds automatically with a progress bar

<!-- TODO: Screenshot of MacPeerSendView showing "Send to iPhone" dialog -->

---

## Receiving a Region on iPhone

### Step 1: Open the Receive Sheet

1. Go to the **Downloaded Regions** tab
2. Tap the **download arrow** button in the toolbar (top-right)

<!-- TODO: Screenshot of toolbar with receive button highlighted -->

### Step 2: Select the Sender

OpenHiker scans for nearby devices. When the sender appears in the **Nearby Devices** list, tap their device name to connect.

<!-- TODO: Screenshot of PeerReceiveView showing discovered peers list -->

> **Tip:** If no devices appear, make sure the sender has already opened the share sheet on their end. Both devices need to be in range (typically within 10 metres / 30 feet).

### Step 3: Watch the Transfer

The transfer begins automatically after connecting. A progress bar tracks each stage.

<!-- TODO: Screenshot of PeerReceiveView showing progress during transfer -->

### Step 4: Done

Once complete, the region appears in your **Downloaded Regions** list — ready to use offline. Any associated routes and waypoints are also imported and visible in the Routes and Hikes sections.

Tap **Done** to close the sheet.

<!-- TODO: Screenshot of PeerReceiveView showing "Transfer Complete" -->

---

## Troubleshooting

### No devices appear in the list

- **Both devices must have the share/receive sheets open.** The sender opens "Share with nearby device" first, then the receiver opens "Receive".
- **Stay close together.** Peer-to-peer wireless has a range of about 10 metres (30 feet).
- **Check WiFi is enabled.** WiFi must be turned on (but you don't need to be connected to a network). Bluetooth should also be enabled.
- **Disable VPN.** VPN software can block the local network communication that peer-to-peer uses. If connections keep timing out, try disabling your VPN temporarily.

### Connection times out

- Move the devices closer together.
- Disable VPN on both devices.
- Tap **"Try Again"** to retry the connection with a fresh session.
- If on the same WiFi network, make sure it allows device-to-device communication (some public/corporate WiFi networks block this).

### Transfer fails midway

If the transfer is interrupted (device went to sleep, moved out of range, etc.):

1. Tap **"Try Again"** on the sender
2. Re-open the "Receive" sheet on the receiver
3. Reconnect and the transfer restarts from the beginning

Partially received data is cleaned up automatically — you won't end up with corrupted regions.

### Region transferred but routes are missing

Routes and waypoints are only included if they exist on the sender's device. If the sender hasn't recorded any hikes or planned any routes for that region, only the map tiles and routing data are transferred.

---

## Privacy & Security

- **No internet required.** All data is transferred directly between devices over Apple's peer-to-peer wireless protocol (AWDL / Bluetooth). Nothing is uploaded to a server.
- **Encrypted connection.** The wireless session uses TLS encryption to prevent eavesdropping.
- **Manual acceptance only.** The receiver must explicitly choose to connect by tapping the sender's device name. No data is sent without the receiver's action.
- **Local network only.** Transfers only work between devices in close physical proximity.
