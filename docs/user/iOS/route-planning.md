# Route Planning

The **Routes** tab lets you plan hiking and cycling routes with automatic pathfinding and turn-by-turn directions.

## Prerequisites

Route planning requires a downloaded region **with routing data**. When downloading a region, make sure the "Routing data" option is enabled. Regions with routing data show a green icon in the Downloaded list.

## Creating a New Route

1. Tap the **+** button in the Routes tab
2. **Select a region** from the list — only regions with routing data are available
3. The **route planning map** opens, showing your offline topo tiles

<!-- Screenshot: Route planning map with waypoints -->
> **[Screenshot placeholder]** *Route planning map showing green start pin, blue via-points, and red end pin connected by a purple route line*

## Placing Waypoints

- **Tap the map** to place waypoints in order:
  - First tap → **green start pin** (WP 1)
  - Last tap → **red end pin**
  - Taps between → **blue via-points** (numbered)
- **Long-press a waypoint** to drag it to a new position
- **Tap an existing waypoint** to remove it

## Computing the Route

Choose a routing mode in the toolbar:

| Mode | Description |
|------|-------------|
| **Hiking** | Prefers trails, paths, and footways |
| **Cycling** | Prefers cycleways and rideable tracks |

Then choose a computation option:

- **Start → End** — Computes a one-way route through your waypoints
- **Back to Start** — Computes a loop route that returns to your starting point

The computed route appears as a **purple line** on the map.

## Route Statistics

After computing, you'll see:

- **Total distance** (km or mi)
- **Estimated time** (calculated using Naismith's rule, accounting for elevation)
- **Elevation gain / loss** (m or ft)

## Turn-by-Turn Directions

Expand the directions panel to see each turn listed with:

- Direction icon (left turn, right turn, continue straight, etc.)
- Instruction text ("Turn left onto Blue Ridge Trail")
- Distance from the previous turn

## Saving Your Route

1. Enter a **route name**
2. Tap **Save**
3. The route appears in your Routes list and syncs to iCloud

## Viewing a Saved Route

Tap any route in the Routes list to see:

- Map with route polyline and start/end markers
- Statistics grid (distance, time, elevation)
- Elevation profile chart
- Full turn-by-turn direction list
- **Send to Watch** button — transfers the route for on-wrist navigation

## Importing Routes from Apple Maps

OpenHiker registers as a directions provider with Apple Maps:

1. Open **Apple Maps** and search for a destination
2. Tap **Directions** → select **OpenHiker** as the routing app
3. The route is automatically imported and appears in your Routes tab

## Managing Routes

- **Swipe left** on a route to delete it
- **Context menu** (long-press) → Rename
- Routes sync across your devices via iCloud
