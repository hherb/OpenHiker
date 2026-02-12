# Map & Navigation

The Map tab is the primary screen on your Apple Watch, displaying offline topographic tiles with your GPS position.

## Map Display

The map renders OpenTopoMap tiles using SpriteKit for smooth performance on the watch. It shows:

- **Topographic contour lines** and elevation data
- **Trail markings** and paths
- **Your GPS position** as a cyan circle with heading indicator
- **Trail overlays** from the routing database (color-coded by trail type)
- **Waypoints** as category-specific icons

<!-- Screenshot: Watch map with GPS position and trails -->
> **[Screenshot placeholder]** *Apple Watch map showing topographic tiles with a cyan GPS dot, heading indicator, and trail overlay*

## Map Controls

### Digital Crown
- **Turn clockwise** → Zoom in (more detail)
- **Turn counter-clockwise** → Zoom out (wider view)
- Zoom range: level 12 (regional overview) to level 16 (trail detail)

### Drag Gesture
- **Drag the map** to pan in any direction
- Dragging temporarily disables auto-centering on your GPS position
- After 10 seconds of inactivity during tracking, the map re-centers automatically

### Toolbar Buttons

Four buttons appear in a toolbar below the map:

| Button | Icon | Action |
|--------|------|--------|
| **Center** | Location arrow | Center map on your GPS position |
| **Waypoint** | Orange pin | Drop a waypoint at your position |
| **Record** | Play/Stop | Start or stop GPS track recording |
| **Region** | Map | Open the region picker |

<!-- Screenshot: Watch map toolbar buttons -->
> **[Screenshot placeholder]** *Bottom toolbar showing four buttons: location arrow, orange pin, play button, and map icon*

## Center on User

Tap the **Center** button to cycle through three modes:

1. **Off** (gray) — Map stays where you left it
2. **Centered** (blue, unfilled) — Map follows your GPS position
3. **Centered + Heading Up** (blue, filled) — Map follows you AND rotates to match your walking direction

In heading-up mode, a compass rose appears in the top-right corner showing magnetic north.

## Map Overlays

### Hike Stats Overlay
When tracking, two small badges appear briefly on the map showing:
- **Distance** traveled
- **Duration** elapsed

These auto-hide after 5 seconds to keep the map uncluttered.

### UV Index Overlay
A small badge in the bottom-right shows the current UV index with WHO color coding:
- Green = Low (1-2)
- Yellow = Moderate (3-5)
- Orange = High (6-7)
- Red = Very High (8-10)
- Purple = Extreme (11+)

### Navigation Overlay
When following a planned route, a strip appears at the top showing:
- Turn direction icon
- Distance to next turn
- Instruction text

And at the bottom:
- Progress bar
- Remaining distance
- Completion percentage

The overlay turns **red** if you go off-route.

## Track-Only Mode

If you start recording a hike but have no map region loaded, the watch switches to **Track-Only Mode**:

- Black background (saves OLED battery)
- Your GPS trail shown as a purple line
- Current position marker
- Digital Crown controls view radius (100m to 3km)

This is useful if you forgot to download a map but still want to record your track.

## On-Demand Maps

If you need a different map area while on the trail:

1. Tap the **Region** button in the toolbar
2. Select **"Request Map from iPhone"**
3. Your watch asks the iPhone to download tiles for your current GPS location
4. Once transferred, the map updates automatically

Requirements:
- iPhone must be reachable (Bluetooth range or shared Wi-Fi)
- iPhone needs internet access to download tiles
- Rate limited to one request per 10 minutes
