# OpenHikerRoutes

Community-shared hiking, cycling, and outdoor routes for the [OpenHiker](https://github.com/hherb/OpenHiker) app.

## How It Works

1. **Record** a hike or ride on your Apple Watch with OpenHiker
2. **Share** it from the iOS app with a single tap ("Share to Community")
3. **Browse** and download community routes directly in the app
4. **Navigate** offline using downloaded routes on your Apple Watch

## Repository Structure

```
routes/
  <country>/
    <route-slug>/
      route.json      # Canonical route data (track, waypoints, stats, photos)
      route.gpx       # Auto-generated GPX for interoperability
      README.md       # Auto-generated human-readable summary
      photos/         # Compressed photos (640x400 JPEG)

waypoints/
  <country>/
    <waypoint-slug>/
      waypoints.json  # Standalone waypoints (not part of a route)
      photos/

index.json            # Master index with all route summaries (auto-rebuilt)
```

## Route Data Format

Each route is stored as a `route.json` file following this schema:

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `version` | Int | Schema version (currently 1) |
| `name` | String | Route name |
| `activityType` | Enum | `hiking`, `cycling`, `running`, `skiTouring`, `other` |
| `author` | String | Display name of the contributor |
| `description` | String | Route description and tips |
| `createdAt` | ISO8601 | When the route was recorded |
| `region` | Object | `{ country: "US", area: "California" }` |
| `stats` | Object | Distance, elevation gain/loss, duration |
| `boundingBox` | Object | `{ north, south, east, west }` |
| `track` | Array | GPS points: `[{ lat, lon, ele, time }]` |
| `waypoints` | Array | Points of interest along the route |
| `photos` | Array | Photo references with GPS coordinates |

## Contributing

### Via the App (Recommended)
Open a saved hike in the OpenHiker iOS app and tap the share button. Fill in the details and submit. Your route will be submitted as a pull request for review.

### Manually
1. Fork this repository
2. Create a directory under `routes/<country>/<route-slug>/`
3. Add a `route.json` following the schema above
4. Submit a pull request

The CI workflow will validate your `route.json` and auto-generate the GPX and README files.

## License

Route data contributed to this repository is shared under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) — you are free to share and adapt the data as long as you give credit and share alike.

The OpenHiker app itself is licensed under [AGPL-3.0](https://github.com/hherb/OpenHiker/blob/main/LICENSE).
