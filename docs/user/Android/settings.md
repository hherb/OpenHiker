# Settings

Tap the **gear icon** in the top app bar to open Settings.

## Map Settings

### Default Tile Server
Choose your preferred online map source:
- **OpenTopoMap** — Hiking trails, contour lines, shelters (default)
- **CyclOSM** — Cycling routes, surface quality
- **OSM Standard** — General road map

This sets the default when browsing the map. You can switch sources on the fly from the map toolbar.

## GPS Settings

### Accuracy Mode

| Mode | Interval | Displacement | Best For |
|------|----------|-------------|----------|
| **High Accuracy** | 2 seconds | 5 meters | Technical terrain, precise tracking |
| **Balanced** | 5 seconds | 10 meters | Most day hikes (recommended) |
| **Low Power** | 10 seconds | 50 meters | Long hikes, battery conservation |

## Navigation Settings

### Unit System
- **Metric** — Distances in km, elevations in m
- **Imperial** — Distances in mi, elevations in ft

Applied throughout the app.

### Haptic Feedback
Toggle vibration feedback during turn-by-turn navigation on or off.

### Audio Cues
Enable audio feedback for navigation events — useful for accessibility or when you can't feel vibrations (e.g., thick gloves).

### Keep Screen On
When enabled, the screen stays on during active navigation. Useful on the trail but increases battery consumption.

## Download Settings

### Default Zoom Levels
- **Minimum zoom** — Slider (1-18), default: 12
- **Maximum zoom** — Slider (1-18), default: 16

### Concurrent Downloads
- Slider (2-12) — How many tiles download simultaneously
- Higher values are faster but use more bandwidth

## Cloud Sync

Sync copies planned routes, recorded hikes, and waypoints (with their photos) to and from the folder, so
several Android devices can share them. Deleting an item on one device deletes it on the others once both
have synced. A device that has not synced for more than 30 days keeps its copy. If the same item was changed on
two devices, the most recent change wins.

### Auto-Sync
Toggle automatic synchronization every 15 minutes.

### Sync Folder
Choose a sync folder using Android's Storage Access Framework. Works with:
- **Google Drive**
- **Dropbox**
- **OneDrive**
- **Local storage**
- Any other SAF-compatible storage provider

Tap to select or change the sync folder. The current folder path is displayed below.

### Manual Sync
- **"Sync Now" button** — Trigger an immediate sync
- **Last sync timestamp** — Shows when the last sync without errors completed
- **Progress indicator** — Shown during any sync, including automatic ones

### Sync Errors
If a sync fails, automatic or manual, a red banner above every screen lists what failed. Tap **Retry** to
sync again, or the close button to hide the banner until a later sync fails. If the banner says the sync
folder is unavailable, the app lost access to it: choose it again under **Sync Folder**. If the folder
cannot be reached, it was removed or its storage provider is offline; sync tries again later. If the app's own sync records were damaged, the banner says so: items you deleted shortly
before may come back, and you can delete them again.

<!-- Screenshot: Settings screen -->
> **[Screenshot placeholder]** *Android settings screen showing GPS accuracy (Balanced selected), Units (Metric), and Cloud Sync section with Google Drive folder selected*

## Storage Management

### Storage Overview
- **Total storage used** — Sum of all OpenHiker data
- **Map regions** — Size of downloaded tile databases
- **Elevation cache** — Cached elevation data with **Clear** button
- **OSM data cache** — Cached routing data with **Clear** button

Use the Clear buttons to free up space without deleting your downloaded regions.

## About

- **App version** — 1.0.0
- **License** — GNU AGPL-3.0
- **Copyright** — OpenHiker contributors
- **Source code** — Link to GitHub repository

### Map Data Attributions
- OpenStreetMap contributors
- OpenTopoMap (CC-BY-SA)
- CyclOSM
- Elevation data: SRTM / Mapzen Skadi
