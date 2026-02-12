# Settings & Sync

## Settings Window

Open Settings via **Cmd+,** or the app menu → Settings.

### General Tab

#### Units
- **Metric** — Distances in km, elevations in m
- **Imperial** — Distances in mi, elevations in ft

This preference applies throughout the app.

### Sync Tab

#### iCloud Sync
- **Status display** — Shows whether iCloud sync is active
- **"Sync Now" button** — Manually trigger a sync cycle

## iCloud Sync

OpenHiker syncs the following data across your Apple devices:

| Data Type | Syncs? |
|-----------|--------|
| Planned routes | Yes |
| Saved hikes | Yes |
| Waypoints | Yes |
| Map tiles (MBTiles) | No (too large) |
| Routing databases | No (too large) |

### How Sync Works

1. **On launch** — The app automatically syncs with iCloud
2. **On change** — When you create, edit, or delete data, changes push to iCloud
3. **From other devices** — Push notifications alert the Mac of changes made on iPhone or Watch

### Manual Sync Options

| Method | How |
|--------|-----|
| Sidebar "Sync now" | Click the refresh icon at the bottom of the sidebar |
| Settings | Open Settings → Sync tab → "Sync Now" |
| Keyboard | Press **Cmd+Shift+S** |
| Menu | File → Sync with iCloud |

### Sync for Routes to iPhone

To ensure a planned route reaches your iPhone:
- Press **Cmd+Shift+P** (File → Send Routes to iPhone)
- This triggers an iCloud sync push

From there, the iPhone can send the route to your Apple Watch.

## Keyboard Shortcuts Reference

| Shortcut | Action |
|----------|--------|
| **Cmd + I** | Import GPX file |
| **Cmd + Shift + S** | Sync with iCloud |
| **Cmd + Shift + P** | Send routes to iPhone |
| **Cmd + ,** | Open Settings |

## Map Region Storage

Map regions are stored locally on your Mac. They do NOT sync via iCloud due to their size. To get a region onto your iPhone:
- Use [Peer-to-Peer Sharing](peer-sharing.md) on a local network
- Or download the same region separately on each device
