# Map & Navigation

The **Navigate** tab is your primary map view for browsing, GPS tracking, and downloading offline regions.

## Map Display

OpenHiker uses MapLibre for map rendering with support for both online and offline tiles.

### Online Tile Sources

When connected to the internet, choose between:

| Source | Best For |
|--------|----------|
| **OpenTopoMap** | Hiking — contour lines, trails, shelters |
| **CyclOSM** | Cycling — bike routes, surface quality |
| **OSM Standard** | General — roads, POIs |

Switch tile sources using the dropdown in the map toolbar.

### Offline Maps

Once you download a region, tiles are served from the local MBTiles database — no internet needed. The map seamlessly blends online and offline tiles.

## Map Controls

- **Pinch to zoom** — Two-finger zoom in/out
- **Drag** — Pan the map
- **My Location button** — Center the map on your GPS position
- **Compass toggle** — Switch between north-up and heading-up (map rotates with your direction)

### GPS Position

Your position appears as a **blue dot with an arrow** showing your heading direction.

<!-- Screenshot: Android map with GPS position -->
> **[Screenshot placeholder]** *Android map showing OpenTopoMap tiles with blue GPS dot, heading arrow, and region boundary overlay*

## Region Boundaries

Downloaded regions are shown as **blue-outlined polygons** on the map, so you can see which areas you have available offline.

## Downloading a Region

### Quick Download

1. Navigate to the area you want to save
2. Tap the **download button** (floating action button)
3. A **bottom sheet** appears with configuration:
   - **Region name** — Enter a descriptive name
   - **Tile server** — OpenTopoMap, CyclOSM, or OSM Standard
   - **Min/Max zoom** — Adjust with sliders (default: 12-16)
   - **Estimated tile count** — Updates as you adjust settings
4. Tap **Download**

### During Download

- A progress bar shows tiles downloaded and percentage
- You can cancel the download at any time
- Downloads run in the background — you can use other parts of the app

<!-- Screenshot: Download bottom sheet -->
> **[Screenshot placeholder]** *Bottom sheet showing region name "Blue Ridge", tile server OpenTopoMap, zoom 12-16, estimated 3,200 tiles, with a Download button*

## Managing Regions

Go to the **Regions** tab to see all downloaded regions:

Each region card shows:
- Name
- Area coverage
- Tile count and file size
- Zoom range

Actions:
- **"View on map"** — Centers the map on that region
- **Swipe to delete** — With confirmation dialog
- **Storage summary** — Total storage used shown at the top

## Camera Position Persistence

The map remembers your last viewed position and zoom level, restoring it when you relaunch the app.
