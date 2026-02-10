# Trail Overlay Rendering — Android

## Context

watchOS now renders hiking trail overlays from the routing database (`routing_edges` table) as colored polylines on the map. If/when the Android app gains offline map support with a routing database, it should render trail overlays the same way.

## Prerequisites

- Android map rendering with offline MBTiles support
- Routing database (`.routing.db`) available on device
- SQLite access to `routing_edges` and `routing_nodes` tables

## What Needs to Be Done

1. **Port `getEdgesInBoundingBox` query** — same SQL spatial query joining edges with endpoint nodes, filtering by bounding box and non-null highway type. Reconstruct polylines from packed Float32 geometry blobs.

2. **Render trail polylines** — using the Android map library's polyline API (e.g., `MapLibre`'s `LineLayer` or Google Maps' `Polyline`). One polyline group per highway type.

3. **Color scheme** — match the existing convention:
   - `path`: red-orange (#E06040)
   - `footway`: orange (#FF8C00)
   - `track`: brown (#8B6914)
   - `steps`: magenta (#CC3399)
   - `cycleway`: dark cyan (#008B8B)
   - `bridleway`: olive (#6B8E23)
   - Other: gray (#888888)
   - All at 70% opacity, 2dp line width

4. **Viewport-based refresh** — query only edges visible on screen, re-query when viewport shifts >25% or zoom changes. Cache edges between minor pans.

## Notes

- The routing database schema and geometry packing format (Float32 lat/lon pairs) are documented in `Shared/Models/RoutingGraph.swift` (`EdgeGeometry.pack`/`unpack`).
- If using MapLibre, consider using a GeoJSON source with style layers for more efficient batch rendering.
