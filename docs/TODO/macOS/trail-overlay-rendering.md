# Trail Overlay Rendering — macOS

## Context

watchOS now renders hiking trail overlays from the routing database as colored polylines on the map. macOS needs the same feature on its MapKit-based views (`MacTrailMapView`, `MacRoutePlanningView`).

## What Exists

- `RoutingStore.getEdgesInBoundingBox(_:)` (Shared) — spatial query returning `TrailEdgeData`. Ready to use.
- `RoutingStore` is already opened in `MacRoutePlanningView` for route computation.
- macOS maps use `MKMapView` (via `NSViewRepresentable`) with `MKTileOverlay` for base tiles.

## What Needs to Be Done

1. **Query trails for the visible region** — use `getEdgesInBoundingBox(_:)` with the `MKMapView`'s visible region converted to `BoundingBox`.

2. **Render as MKPolyline overlays** — batch by highway type using `MKMultiPolyline`. Style with `MKPolylineRenderer` using the same color scheme as watchOS.

3. **Refresh on viewport change** — implement `mapViewDidChangeVisibleRegion` delegate callback with 25% shift threshold.

4. **Apply to map views** — `MacTrailMapView` and `MacRoutePlanningView`.

## Notes

- Implementation is nearly identical to iOS — both use MapKit with `NSViewRepresentable`/`UIViewRepresentable` wrappers. Consider extracting shared trail overlay logic into a helper in `Shared/` that both platforms can call.
