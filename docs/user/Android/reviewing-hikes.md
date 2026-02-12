# Reviewing Hikes

The **Hikes** tab displays all your recorded hikes with detailed statistics and export options.

## Hikes List

All recorded hikes sorted by date (newest first). Each card shows:
- Hike name and date
- Distance, elevation gain, duration
- Optional map thumbnail

### Searching and Sorting

- **Search bar** — Filter by hike name
- **Sort options** — Date, distance, elevation, or duration

### Managing
- **Swipe to delete** — With confirmation dialog

<!-- Screenshot: Hikes list on Android -->
> **[Screenshot placeholder]** *Hikes list showing three recorded hikes with distance, elevation, and duration on each card*

## Hike Detail View

Tap a hike to see the complete detail:

### Map Section
- Your track as an **orange polyline**
- Start and end markers
- Associated waypoints on the map

### Statistics Table

| Statistic | Description |
|-----------|-------------|
| Distance | Total distance walked |
| Elevation gain | Cumulative uphill |
| Elevation loss | Cumulative downhill |
| Walking time | Time spent moving |
| Resting time | Time spent stationary |
| Average speed | Overall pace |
| Max speed | Peak pace recorded |
| Calories | Estimated energy burn |

### Elevation Profile

An interactive chart (powered by Vico library) showing:
- Distance vs. elevation across the entire hike
- Grid lines and axis labels
- Min/max elevation annotations

<!-- Screenshot: Hike detail with elevation profile -->
> **[Screenshot placeholder]** *Hike detail showing orange track on map, statistics grid, and elevation profile chart with a mountain-shaped curve*

### Waypoints
Any waypoints created during the hike are shown on the map and listed below.

### Actions
- **Rename** — Edit the hike name
- **Export** — GPX or PDF format
- **Delete** — Remove the hike

## Exporting

From the detail view, tap **Export**:

| Format | Contents |
|--------|----------|
| **GPX** | Standard GPS track for other apps |
| **PDF** | Two-page report with stats and elevation chart |

See [Exporting Data](exporting-data.md) for details.
