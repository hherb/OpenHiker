# Trail Overlay Rendering — iOS

## Context

watchOS now renders hiking trail overlays from the routing database (`routing_edges` table) as colored polylines on the SpriteKit map. iOS needs the same feature on its MapKit-based views (`RoutePlanningMapView`, `TrailMapView`, `iOSNavigationView`).

## What Exists

- `RoutingStore.getEdgesInBoundingBox(_:)` (Shared) — spatial query returning `TrailEdgeData` (highway type + coordinates) for a viewport. Ready to use.
- `RoutingStore` is already opened in `RoutePlanningView` for route computation.
- iOS maps use `MKMapView` with `MKTileOverlay` for base tiles and `MKPolyline` for route rendering.

## What Needs to Be Done

1. **Query trails for the visible region** — use `getEdgesInBoundingBox(_:)` with the `MKMapView`'s visible `MKCoordinateRegion` converted to a `BoundingBox`.

2. **Render as MKPolyline overlays** — create one `MKPolyline` per trail edge (or batch by highway type using `MKMultiPolyline`). Add with `.aboveLabels` level, below the route polyline.

3. **Style by highway type** — in the `MKMapViewDelegate.rendererFor(overlay:)` method, return `MKPolylineRenderer` with colors matching watchOS (red-orange for path, orange for footway, brown for track, etc.), 2pt line width, 0.7 alpha.

4. **Refresh on viewport change** — implement `mapView(_:regionDidChangeAnimated:)` delegate callback to re-query when the user pans/zooms. Use the same 25% shift threshold from watchOS to avoid excessive queries.

5. **Apply to all map views** — `RoutePlanningMapView`, `TrailMapView`, and `iOSNavigationView` all display maps that would benefit from trail overlays.

## Key Differences from watchOS

- MapKit handles projection and rendering — no manual `projectToMapLocal()` needed
- Use `MKMultiPolyline` (iOS 13+) to batch all edges of one type into a single overlay for better performance
- `MKMapView` already manages viewport lifecycle — hook into `regionDidChangeAnimated` instead of manual refresh calls
