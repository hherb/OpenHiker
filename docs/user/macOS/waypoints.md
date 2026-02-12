# Waypoints

The **Waypoints** section provides a sortable spreadsheet view of all your waypoints.

## Waypoints Table

A native macOS table with sortable columns:

| Column | Content | Sortable |
|--------|---------|----------|
| Category | Icon with color coding | Yes |
| Label | Waypoint name | Yes |
| Coordinate | Lat/lon in monospaced font | Yes |
| Altitude | Elevation in m or ft | Yes |
| Date | When the waypoint was created | Yes |
| Note | Truncated notes text | Yes |
| Photo | Blue camera icon if photo attached | — |

Click any column header to sort by that column.

<!-- Screenshot: Waypoints table on macOS -->
> **[Screenshot placeholder]** *macOS table view showing 8 waypoints with category icons, labels, coordinates, and altitude columns*

## Managing Waypoints

### Selecting
- Click a row to select it
- Cmd+Click to select multiple rows
- The row count is shown in the navigation title (e.g., "Waypoints (42)")

### Deleting
- Select one or more waypoints
- Click the **trash icon** in the toolbar
- Confirm deletion

## Adding Waypoints (from Mac)

While waypoints are typically created on the trail (from your watch or phone), you can add them on the Mac:

1. The Add Waypoint dialog opens as a form:
   - **Coordinates** — Latitude and longitude (read-only, set from context)
   - **Label** — Name for the waypoint
   - **Category** — Pick from the full category list with icons
   - **Notes** — Multi-line text field
   - **Photo** — Drag and drop an image, or click "Choose Photo..." to use the file picker
2. Click **Save**

Photos are automatically compressed for efficient storage.

## Syncing

Waypoints sync across all your Apple devices via iCloud:
- Created on iPhone → appears on Mac and Watch
- Created on Watch → appears on Mac and iPhone
- Deleted on any device → removed everywhere

If waypoints aren't appearing, click "Sync now" in the sidebar.
