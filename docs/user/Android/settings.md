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
- **Last sync timestamp** — Shows when the last sync completed
- **Progress indicator** — Shown during active sync

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
