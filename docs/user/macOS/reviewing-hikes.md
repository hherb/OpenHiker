# Reviewing Hikes

The **Hikes** section displays all your recorded hikes synced from your Apple Watch and iPhone via iCloud.

## Hikes List

The left column shows all hikes with:
- Hike name
- Distance, duration, elevation gain
- Date and time

Click a hike to see its full detail in the right panel.

### Searching
Use the search bar to filter hikes by name.

### Managing
- **Right-click** → Rename
- **Right-click** → Delete

<!-- Screenshot: Hikes list-detail view on macOS -->
> **[Screenshot placeholder]** *macOS split view: hike list on the left, detailed hike view on the right with map, elevation chart, and stats*

## Hike Detail View

### Map Section
- Your track as an **orange polyline** (3pt stroke)
- **Green flag** at the start
- **Red/checkered flag** at the end
- 3D terrain rendering
- Auto-fitted to your track bounds

### Elevation Profile
An interactive chart showing distance vs. elevation across the entire hike. Units respect your metric/imperial preference.

### Statistics Grid

| Statistic | Description |
|-----------|-------------|
| Distance | Total distance walked |
| Elevation gain | Cumulative uphill |
| Elevation loss | Cumulative downhill |
| Duration | Total elapsed time |
| Walking time | Time spent moving |
| Resting time | Time spent stationary |
| Avg heart rate | From Apple Watch (if available) |
| Max heart rate | From Apple Watch (if available) |
| Calories | Estimated energy burn (if available) |

### Waypoints Table

A native macOS table showing waypoints linked to the hike:

| Column | Content |
|--------|---------|
| Category | Icon with color coding |
| Label | Waypoint name |
| Coordinates | Lat/lon in monospaced font |
| Notes | Truncated notes text |

The table is scrollable for hikes with many waypoints.

### Comments

An editable text area where you can add or update notes about your hike. Changes are saved automatically.

## Exporting

From the toolbar menu, choose an export format:

| Format | File Type | Contents |
|--------|-----------|----------|
| Quick Summary | .md | Stats, waypoints, comments as markdown |
| GPS Track | .gpx | Track points for import into other apps |
| Detailed Report | .pdf | Multi-page report with stats and waypoints |

A **macOS save dialog** (NSSavePanel) lets you choose where to save the file.

> **Note:** The macOS PDF export includes statistics and waypoints. Map snapshots and elevation charts in the PDF are a planned enhancement.

## iCloud Sync

Hikes recorded on your Apple Watch or iPhone sync automatically via iCloud. If you don't see your latest hike:

1. Click the **refresh** button in the toolbar
2. Or click **"Sync now"** in the sidebar iCloud bar
3. Or press **Cmd+Shift+S**
