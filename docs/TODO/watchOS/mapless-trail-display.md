# Mapless Trail Display (watchOS)

## Status: IMPLEMENTED

## Summary
When recording a trail without a loaded map region, the watch now displays a lightweight SpriteKit scene (`TrackOnlyScene`) with the GPS trail rendered as a purple polyline on a black OLED-optimized background.

## Implementation
- **New file**: `OpenHiker watchOS/Views/TrackOnlyScene.swift`
- **Modified**: `OpenHiker watchOS/Views/MapView.swift` — integrates TrackOnlyScene as fallback when no map is loaded

## Features
- Purple trail polyline on black background (OLED battery optimization)
- Cyan GPS position marker with heading cone
- Compass indicator (same as MapScene)
- Digital Crown controls visible radius: 100m, 250m, 500m, 1km, 2km, 3km
- Heading-up mode with map rotation
- Automatic transition to tile map when a region is loaded

## Technical Details
- Uses simple geographic distance projection (meters-to-screen) instead of Web Mercator
- Scene created when recording starts without a map; destroyed when recording stops or a region loads
- Reuses same SpriteKit rendering patterns as MapScene (SKShapeNode polylines, position marker, compass)
