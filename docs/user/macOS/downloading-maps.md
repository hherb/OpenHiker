# Downloading Maps

The **Regions** section lets you browse the map, select an area, and download tiles for offline use.

## Browsing the Map

The interactive map supports three tile styles, switchable from the toolbar:

| Style | Best For |
|-------|----------|
| **Roads** | General orientation (Apple Maps) |
| **Trails** | Hiking — contour lines, trail markings, shelters (OpenTopoMap) |
| **Cycling** | Cycling infrastructure and routes (CyclOSM) |

### Map Controls

- **Scroll** to zoom in and out
- **Click and drag** to pan
- **Search** — Use the inline search field in the toolbar to find a location by name
- **Center on location** — Click the location button to jump to your current position

## Selecting a Region

1. Navigate to the area you want to download
2. Click **"Select Visible Area"** — a selection rectangle appears covering approximately 60% of the visible map
3. **Drag the handles** (8 handles: 4 corners + 4 edges) to adjust the selection precisely
4. Review the real-time estimate:
   - Tile count
   - Download size (MB/GB)
   - Area coverage (km²)

<!-- Screenshot: macOS region selection with handles -->
> **[Screenshot placeholder]** *macOS map with blue selection rectangle and 8 draggable handles, with download configuration panel on the right*

## Download Configuration

A **side panel** (300pt wide) appears with download options:

1. **Region name** — Enter a descriptive name
2. **Tile server** — OpenTopoMap (default), CyclOSM, or OpenStreetMap
3. **Zoom levels** — Adjust min/max with stepper controls (default: 8–18)
4. **Routing data** — Enable to include trail data for route planning

Click **Download** to begin. A progress overlay shows the percentage complete.

## After Download

The region appears in the **Downloaded** section. You can:

- Plan routes within the region (double-click, or right-click → "Plan Route")
- Send it to an iPhone via P2P transfer (right-click → "Send to iPhone")
- Rename or delete it

## Position Persistence

The map remembers your last viewed location and restores it on relaunch.
