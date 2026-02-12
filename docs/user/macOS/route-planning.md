# Route Planning

OpenHiker for Mac provides interactive route planning with offline map tiles, automatic pathfinding, and turn-by-turn directions.

## Prerequisites

Route planning requires a downloaded region **with routing data**. Regions with routing data show a green diamond icon in the Downloaded list.

## Opening the Route Planner

### From the Routes Section
1. Click **Routes** in the sidebar
2. Click **Plan Route** in the toolbar
3. Select a region from the dropdown (only regions with routing data appear)

### From the Downloaded Section
- Double-click a region with routing data, or
- Right-click → **Plan Route**

## The Route Planning Interface

The planner uses a split-view layout:

```
┌──────────────────────────┬────────────────┐
│                          │                │
│     Map (offline tiles)  │  Side Panel    │
│                          │  - Stats       │
│     Click to add pins    │  - Directions  │
│                          │  - Save        │
│                          │                │
└──────────────────────────┴────────────────┘
```

<!-- Screenshot: Route planning split view -->
> **[Screenshot placeholder]** *Route planning view with offline topo map on the left showing green start, blue via-points, and red end connected by a purple route line; side panel on the right showing stats and directions*

## Placing Waypoints

Click the map to place waypoints:

| Click | Pin Color | Meaning |
|-------|-----------|---------|
| First click | Green | Start point |
| Second click | Red | End point (route auto-computes) |
| Additional clicks | Blue (numbered) | Via-points |
| Click existing pin | — | Remove it |

After placing at least a start and end point, the route is computed automatically.

## Routing Modes

Use the toolbar segmented picker to choose:

- **Hiking** — Prefers trails, paths, footways
- **Cycling** — Prefers cycleways and rideable tracks

## Route Results

After computation, the side panel shows:

### Statistics
- Total distance (km or mi)
- Estimated time (Naismith's rule, accounting for elevation)
- Elevation gain / loss

### Turn-by-Turn Directions
An expandable list of every turn:
- Direction icon (arrow, continue straight, arrive, etc.)
- Instruction text ("Turn left onto Blue Ridge Trail")
- Distance from the previous turn

## Saving Your Route

1. Enter a **route name** in the text field at the bottom of the side panel
2. Click **Save & Sync**
3. The route is saved locally and synced to iCloud
4. A confirmation dialog offers to **Sync to iPhone**

## Toolbar Controls

| Button | Action |
|--------|--------|
| **Clear All** | Remove all pins and the computed route |
| **Back** | Return to the routes list |
| Hiking/Cycling picker | Switch routing mode |

## Managing Saved Routes

In the Routes list:

- **Click** a route to see its detail (map, stats, elevation profile, directions)
- **Right-click** → Rename
- **Right-click** → Send to iPhone via iCloud
- **Right-click** → Delete
- **Swipe left** to delete

## Importing GPX Files

You can import routes from other apps:

### Via Menu
**File → Import GPX...** (or press **Cmd+I**)

### Import Process
1. A file picker opens (supports .gpx and .xml files)
2. Select one or more files
3. Routes are parsed and saved to your planned routes list
4. A success message shows how many routes were imported

Imported routes include:
- Track name (from GPX metadata)
- All track points with coordinates and elevation
- Distance, elevation gain/loss, and estimated time are computed automatically
