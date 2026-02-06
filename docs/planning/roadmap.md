# OpenHiker Feature Roadmap

**Last updated:** 2026-02-07
**License:** AGPL-3.0
**Target audience:** Worldwide — primarily European, Australian, and New Zealand hikers

## Vision

Transform OpenHiker from a basic offline map viewer into a complete hiking companion: live metrics, health vitals, waypoints with photos, saved routes with statistics, a fully offline routing engine, turn-by-turn guidance, route planning, multi-platform support, and exportable hike reports.

## Current State

| Feature | iOS | watchOS |
|---------|-----|---------|
| Offline map tiles (OpenTopoMap) | Download & manage | SpriteKit rendering |
| GPS tracking | Basic | 3 accuracy modes |
| Track recording | Basic polyline | Distance, elevation gain, duration |
| GPX export | — | Generates GPX 1.1 |
| Compass heading | — | True north indicator |
| WatchConnectivity | Transfers .mbtiles | Receives & stores |
| Digital Crown zoom | — | Zoom 12–16 |

## Phased Roadmap

```
Phase 1: Live Hike Metrics & HealthKit          [~2 weeks]
Phase 2: Waypoints & Pins                       [~3 weeks]
Phase 3: Save Routes & Review Past Hikes        [~3 weeks]
Phase 4: Custom Offline Routing Engine           [~5 weeks, parallel with 1–3]
Phase 5: Route Planning & Active Guidance        [~4 weeks]
Phase 6: Multi-Platform & Export                 [~8-11 weeks]
  6.3 Export (PDF/Markdown/Share)                 [~2 weeks]
  6.2 iPad Adaptive Layouts                      [~1-2 weeks]
  6.4 iCloud Sync                                [~2-3 weeks]
  6.1 Native macOS App                           [~3-4 weeks]
```

## Dependency Graph

```
Phase 1 (Quick Wins)
  1.1 Distance Display
  1.2 HealthKit                  ← 1.1

Phase 2 (Waypoints)              [parallel with Phase 1]
  2.1 Waypoint Model + Store
  2.2 Watch Pins                 ← 2.1
  2.3 iPhone Pins + Photos       ← 2.1, 2.2

Phase 3 (Routes)
  3.1 Route Model + Store        ← 1.2, 2.1
  3.2 Save Hike on Watch         ← 3.1
  3.3 Review Hikes on iPhone     ← 3.1, 2.1

Phase 4 (Routing Engine)          [parallel with Phases 1–3]
  4.1 OSM Pipeline + A*

Phase 5 (Planning + Guidance)
  5.1 Route Planning (iPhone)    ← 4.1
  5.2 Route Guidance (Watch)     ← 4.1, 5.1

Phase 6 (Platform + Export)
  6.3 Export (PDF/Markdown)      ← 3.3, 2.1
  6.2 iPad Adaptive Layouts      ← All phases
  6.4 iCloud Sync                ← 3.1, 2.1
  6.1 Native macOS App           ← 6.2, 6.3, 6.4
```

## Phase Summaries

### Phase 1: Live Hike Metrics & HealthKit
Quick wins that deliver immediate user value. The watch already computes distance, elevation, and duration — Phase 1 surfaces these on-screen and adds HealthKit for heart rate, SpO2, and workout recording.

**Details:** [phase1-hike-metrics-healthkit.md](phase1-hike-metrics-healthkit.md)

### Phase 2: Waypoints & Pins
Cross-platform waypoint infrastructure. Watch gets a quick "mark this spot" button with category presets and voice dictation. iPhone gets full pin+photo+annotation with camera/photo library. Bidirectional sync via WatchConnectivity.

**Details:** [phase2-waypoints-pins.md](phase2-waypoints-pins.md)

### Phase 3: Save Routes & Review Past Hikes
Route persistence with comprehensive statistics. Save completed hikes on watch with auto-computed stats (distance, elevation gain/loss, walking/resting time, heart rate, calories). Review past hikes on iPhone with MapKit track overlay, Swift Charts elevation profile, photos, and waypoints.

**Details:** [phase3-save-routes-review.md](phase3-save-routes-review.md)

### Phase 4: Custom Offline Routing Engine
The most ambitious feature. Build a fully offline A* routing engine in pure Swift using:
- OSM PBF data from Geofabrik (global coverage, ODbL license)
- Copernicus DEM GLO-30 elevation data (global 90°N–90°S, CC-BY-4.0)
- Hiking cost function based on Naismith's rule with surface/difficulty penalties
- SQLite routing graph database (~5–20 MB per 50×50 km region)

**Details:** [phase4-routing-engine.md](phase4-routing-engine.md)

### Phase 5: Route Planning & Active Guidance
Route planning UI on iPhone (tap start/end/via-points, compute path, view stats). Turn-by-turn guidance on watch (route polyline, upcoming turn overlay, haptic feedback, off-route detection with re-routing).

**Details:** [phase5-route-planning-guidance.md](phase5-route-planning-guidance.md)

### Phase 6: Multi-Platform & Export (Revised)
Four sub-features in recommended order: (6.3) Export completed hikes as personal Markdown summaries and multi-page PDF reports with map snapshots and elevation profiles. (6.2) Adaptive NavigationSplitView layouts for iPad. (6.4) iCloud sync for routes, waypoints, and regions between devices. (6.1) First-class native macOS app (separate Xcode target, NOT Mac Catalyst) as a full planning/review hub with menu bar, keyboard shortcuts, drag-and-drop GPX import, and table-style views.

**Details:** [phase6-multiplatform-export.md](phase6-multiplatform-export.md)

## Shared Infrastructure

These components are used across multiple phases and should be built early:

| Component | Used By | Phase |
|-----------|---------|-------|
| `HikeStatistics` value type | Stats overlay, HealthKit, saved routes, export | 1.2 |
| `Waypoint` model + `WaypointStore` | Pins, saved routes, route planning, export | 2.1 |
| `SavedRoute` model + `RouteStore` | Save/review hikes, export | 3.1 |
| `TrackCompression` utility | Save routes, transfer routes, export | 3.1 |
| `RoutingStore` + `RoutingEngine` | Route planning, guidance, re-routing | 4.1 |

## Key Existing Code to Reuse

| File | Pattern to Reuse |
|------|-----------------|
| `Shared/Storage/TileStore.swift` | SQLite pattern: serial queue, SQLite3 API, open/close lifecycle, `@unchecked Sendable` |
| `Shared/Models/Region.swift` | `Codable + Sendable + Identifiable` model convention |
| `OpenHiker watchOS/Services/LocationManager.swift` | Extend (not rewrite) — already has `totalDistance`, `elevationGain`, `duration` |
| `OpenHiker watchOS/Services/MapRenderer.swift` | Extend for waypoint markers, route polylines, navigation overlays |
| `OpenHiker iOS/Services/WatchTransferManager.swift` | Extend for new file types (.routing.db, waypoints, routes) |
| `OpenHiker iOS/Services/TileDownloader.swift` | Actor pattern to replicate for OSMDataDownloader |

## Data Sources (Global Coverage)

| Data | Source | Coverage | License |
|------|--------|----------|---------|
| Map tiles | OpenTopoMap | Worldwide | CC-BY-SA (existing) |
| OSM trail data | Geofabrik regional extracts (.osm.pbf) | Every continent | ODbL |
| Elevation (primary) | Copernicus DEM GLO-30 (ESA) | 90°N–90°S (global) | CC-BY-4.0 |
| Elevation (fallback) | SRTM 1-arc-second (NASA/USGS) | 60°N–56°S | Public domain |

All data sources are compatible with AGPL-3.0 licensing and provide non-US-centric global coverage.
