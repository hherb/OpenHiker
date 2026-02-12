# Downloading Maps

The **Regions** tab lets you browse the map, select an area, and download tiles for offline use.

## Browsing the Map

The interactive map supports three tile styles — switch between them using the segmented control at the top:

| Style | Icon | Best For |
|-------|------|----------|
| **Roads** | Standard map | General orientation |
| **Trails** | Topographic | Hiking — shows contour lines, trail markings, shelters |
| **Cycling** | Bike routes | Cycling — shows cycling infrastructure and surface quality |

### Map Controls

- **Pinch to zoom** in and out
- **Drag** to pan the map
- **Search** — Tap the search icon to find a location by name
- **Center on GPS** — Tap the location button to jump to your current position

<!-- Screenshot: Region selector map view with map style picker -->
> **[Screenshot placeholder]** *Region selector map with Trails style selected, showing topographic contours*

## Selecting a Region

1. **Navigate to the area** you want to download
2. **Tap "Select Region"** — a blue rectangle appears on the map
3. **Adjust the rectangle** by dragging the edges to cover exactly the area you need
4. **Review the estimate** displayed below the selection:
   - Area coverage (km²)
   - Estimated tile count
   - Estimated download size

<!-- Screenshot: Region selection rectangle on map with size estimate -->
> **[Screenshot placeholder]** *Blue selection rectangle over a mountainous area with "~2,400 tiles, ~45 MB" estimate shown*

## Download Configuration

After selecting your region:

1. **Region name** — Enter a descriptive name (e.g., "Yosemite Valley", "Blue Mountains")
2. **Tile server** — Choose your preferred map style:
   - **OpenTopoMap** (recommended for hiking)
   - **CyclOSM** (recommended for cycling)
   - **OpenStreetMap** (general purpose)
3. **Zoom levels** — Adjust the min/max zoom (default: 8–18)
   - Lower zoom = wider overview (less detail, fewer tiles)
   - Higher zoom = close-up detail (more tiles, larger download)
4. **Contour lines** — Toggle on/off (included by default)
5. **Routing data** — Enable to download trail data for route planning

> **Tip:** Including routing data adds a small amount to the download but enables offline route planning with turn-by-turn directions within this region.

6. **Tap "Download"** to begin

## During Download

- A progress bar shows the download status
- Tiles are downloaded at a polite rate (100ms between tiles) to respect the tile server's usage policy
- You can continue using the app while downloading
- Downloads can be cancelled if needed

## After Download

Your region appears in the **Downloaded** tab. From there you can:

- Transfer it to your Apple Watch
- Plan routes within the region
- Share it with nearby devices via peer-to-peer transfer

## Quick Download from Navigation

While in the **Navigate** tab, you can tap the download button to save the currently visible area as a new region — useful for quickly caching the map around your current location.

## Storage Tips

- A typical hiking region (50 km², zoom 8–16) is about 30–80 MB
- Higher max zoom levels significantly increase download size
- Zoom 16 is usually sufficient for trail navigation
- Zoom 18 provides street-level detail but takes more storage
- Delete regions you no longer need from the Downloaded tab to free space
