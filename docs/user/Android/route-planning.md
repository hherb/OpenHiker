# Route Planning

The **Routes** tab lets you plan hiking and cycling routes with automatic pathfinding and turn-by-turn directions.

## Prerequisites

Route planning requires a downloaded region with routing data. When downloading a region, the routing database is built automatically from OpenStreetMap trail data.

## Creating a New Route

1. Go to the **Routes** tab
2. Tap the **+** button or **Plan Route**
3. Select a **region** from the dropdown (only regions with routing data appear)
4. Choose your **routing mode**:
   - **Hiking** — Prefers trails, paths, and footways
   - **Cycling** — Prefers cycleways and rideable tracks

## Placing Waypoints

Tap the map to add waypoints:

| Tap | Marker | Meaning |
|-----|--------|---------|
| First tap | Green (numbered) | Start point |
| Last tap | Red (numbered) | End point |
| Middle taps | Blue (numbered) | Via-points |

Waypoints are numbered in order (1, 2, 3...) and listed below the map with their coordinates.

<!-- Screenshot: Route planning with waypoints on map -->
> **[Screenshot placeholder]** *Route planning screen showing three numbered waypoints on the map connected by an orange route line, with hiking/cycling filter chips at the top*

## Computing the Route

Choose a computation option:

| Option | Description |
|--------|-------------|
| **Start → End** | One-way route: 1→2→3→4→5 |
| **Back to Start** | Loop route: 1→2→3→4→5→1 |

The computed route appears as an **orange polyline** on the map.

## Route Results

After computation:

### Statistics
- Total distance (km or mi)
- Elevation gain / loss (m or ft)
- Estimated duration (accounting for terrain)

### Turn-by-Turn Directions
A scrollable list of every turn with:
- Direction and instruction text
- Distance from the previous turn

## Saving Your Route

1. Tap **Save**
2. Enter a **route name**
3. The route is stored locally and available for navigation

## Route Detail View

Tap any saved route to see:
- **Map** with route polyline
- **Elevation profile** chart
- **Complete statistics**
- **Turn-by-turn directions** (scrollable list)
- **Start Navigation** button
- **Export** button (GPX/PDF)

Options: Rename, Delete, Export

## Clearing

Tap **Clear Route** to remove all waypoints and start over.
