# OpenHiker

<p align="center">
  <img src="docs/images/app-icon.svg" alt="OpenHiker Logo" width="180" height="180">
</p>

<p align="center">
  <strong>Offline hiking navigation for Apple Watch</strong><br>
  <em>Using free OpenStreetMap cartographic data</em>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#how-it-works">How It Works</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#roadmap">Roadmap</a> •
  <a href="#building">Building</a> •
  <a href="#license">License</a>
</p>

---

## Why OpenHiker?

Traditional hiking apps require cellular connectivity or expensive offline map subscriptions. OpenHiker brings truly **free, offline topographic maps** directly to your Apple Watch — no phone required on the trail.

Perfect for:
- Backcountry hiking where there's no cell coverage
- Trail running without carrying a phone
- Quick glances at the map without stopping to dig out your phone

## Features

### Offline Maps & Navigation
- **Fully Offline Maps** — Download regions over WiFi, then navigate without any connection
- **Apple Watch Standalone** — Works independently without your iPhone nearby
- **Free Map Data** — Uses [OpenTopoMap](https://opentopomap.org/) tiles based on OpenStreetMap
- **Battery Optimized** — Configurable GPS modes to balance accuracy vs battery life
- **MBTiles Storage** — Efficient SQLite-based tile storage, compact and fast
- **SpriteKit Rendering** — Smooth, responsive map display optimized for watchOS

### Live Hike Metrics & HealthKit
- **Real-Time Stats Overlay** — Distance, elevation gain, duration displayed on the watch during hikes
- **HealthKit Integration** — Records heart rate, calories burned, and workout sessions
- **Workout Recording** — Automatic HealthKit workout tracking while hiking

### Waypoints & Pins
- **Quick Mark on Watch** — Drop pins at points of interest with category presets
- **Full Annotations on iPhone** — Add photos, notes, and categories to waypoints
- **Bidirectional Sync** — Waypoints sync between iPhone and Apple Watch via WatchConnectivity

### Saved Routes & Hike Review
- **Save Completed Hikes** — Persist routes with comprehensive auto-computed statistics (distance, elevation gain/loss, duration)
- **Hike History on iPhone** — Browse past hikes with track overlays and elevation profiles (Swift Charts)
- **Track Compression** — Efficient storage of recorded tracks using the Ramer-Douglas-Peucker algorithm

## How It Works

```
┌─────────────────┐          ┌─────────────────┐
│   iOS App       │   ───►   │  Apple Watch    │
│                 │  WiFi    │                 │
│ • Select region │ Transfer │ • View map      │
│ • Download tiles│          │ • GPS tracking  │
│ • Manage maps   │          │ • Offline nav   │
└─────────────────┘          └─────────────────┘
```

1. **Select** — Use the iOS companion app to browse and select a hiking region
2. **Download** — Tiles are fetched from OpenTopoMap and stored in MBTiles format
3. **Transfer** — Maps are sent to your Apple Watch via Watch Connectivity
4. **Hike** — Navigate offline with real-time GPS position on your watch

## Installation

### Requirements

- iOS 17.0+ (iPhone companion app)
- watchOS 10.0+ (Apple Watch app)
- Xcode 15.0+

### From Source

```bash
git clone https://github.com/hherb/OpenHiker.git
cd OpenHiker
open OpenHiker.xcodeproj
```

Build and run on your devices using Xcode.

## Usage

### Downloading a Region

1. Open OpenHiker on your iPhone
2. Navigate to the area you want to hike
3. Tap **Select Area** and draw a rectangle around your hiking region
4. Review the estimated download size and tile count
5. Tap **Download** and wait for completion
6. The region will automatically transfer to your paired Apple Watch

### On the Trail

1. Open OpenHiker on your Apple Watch
2. Select your downloaded region
3. Your current position is shown with a pulsing blue dot
4. Use the Digital Crown to zoom in/out
5. Pan by swiping on the display
6. View live stats (distance, elevation, duration) on the overlay
7. Tap to drop waypoint pins at points of interest
8. Save your hike when finished to review later

### GPS Modes

To preserve battery, OpenHiker offers configurable GPS accuracy:

| Mode | Update Interval | Best For |
|------|-----------------|----------|
| High | Continuous | Technical navigation, unfamiliar terrain |
| Standard | 10 seconds | General hiking |
| Low Power | 30 seconds | Long hikes, battery conservation |

### Reviewing Past Hikes

1. Open OpenHiker on your iPhone
2. Navigate to the **Hikes** tab
3. Browse your saved hikes with distance, duration, and elevation stats
4. Tap a hike to see the track overlaid on a map with elevation profile
5. View associated waypoints and photos from the trail

## Architecture

```
OpenHiker/
├── Shared/                    # Cross-platform code
│   ├── Models/
│   │   ├── TileCoordinate.swift
│   │   ├── Region.swift
│   │   ├── Waypoint.swift
│   │   ├── SavedRoute.swift
│   │   └── HikeStatistics.swift
│   ├── Storage/
│   │   ├── TileStore.swift    # MBTiles SQLite wrapper
│   │   ├── WaypointStore.swift
│   │   └── RouteStore.swift
│   └── Utilities/
│       └── TrackCompression.swift
│
├── OpenHiker iOS/             # iPhone companion app
│   ├── Views/
│   │   ├── RegionSelectorView.swift
│   │   ├── AddWaypointView.swift
│   │   ├── WaypointDetailView.swift
│   │   ├── HikesListView.swift
│   │   ├── HikeDetailView.swift
│   │   └── ElevationProfileView.swift
│   └── Services/
│       ├── TileDownloader.swift
│       └── WatchTransferManager.swift
│
└── OpenHiker watchOS/         # Apple Watch app
    ├── Views/
    │   ├── MapView.swift
    │   ├── HikeStatsOverlay.swift
    │   ├── AddWaypointSheet.swift
    │   └── SaveHikeSheet.swift
    └── Services/
        ├── MapRenderer.swift  # SpriteKit tile renderer
        ├── LocationManager.swift
        └── HealthKitManager.swift
```

## Building

### Debug Build

```bash
xcodebuild -scheme "OpenHiker" -destination "platform=iOS Simulator,name=iPhone 15 Pro"
xcodebuild -scheme "OpenHiker Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)"
```

### Release Build

```bash
xcodebuild -scheme "OpenHiker" -configuration Release archive
```

## Roadmap

OpenHiker is under active development. Here's what's been completed and what's coming next:

| Phase | Feature | Status |
|-------|---------|--------|
| 1 | Live Hike Metrics & HealthKit | Done |
| 2 | Waypoints & Pins | Done |
| 3 | Save Routes & Review Past Hikes | Done |
| 4 | Custom Offline Routing Engine | Planned |
| 5 | Route Planning & Active Guidance | Planned |
| 6 | Multi-Platform & Export | Planned |

### Upcoming Highlights

- **Offline Routing Engine** — A* pathfinding using OSM trail data from Geofabrik and Copernicus DEM elevation data, with a hiking cost function based on Naismith's rule
- **Route Planning & Turn-by-Turn Guidance** — Plan routes on iPhone, get haptic-guided navigation on the watch with off-route detection and re-routing
- **Multi-Platform** — Adaptive layouts for iPad and Mac as a planning & review hub
- **Export** — Generate PDF and Markdown hike reports with map snapshots, elevation profiles, and photo galleries

See [docs/planning/roadmap.md](docs/planning/roadmap.md) for the full roadmap with technical details.

## Data Sources

All map and routing data is free and globally available:

| Data | Source | License |
|------|--------|---------|
| Map tiles | [OpenTopoMap](https://opentopomap.org/) | CC-BY-SA |
| Trail data (planned) | [Geofabrik](https://download.geofabrik.de/) OSM extracts | ODbL |
| Elevation (planned) | [Copernicus DEM GLO-30](https://spacedata.copernicus.eu/) | CC-BY-4.0 |

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- [OpenStreetMap](https://www.openstreetmap.org/) — Map data contributors
- [OpenTopoMap](https://opentopomap.org/) — Topographic tile rendering
- [MBTiles Specification](https://github.com/mapbox/mbtiles-spec) — Tile storage format

## License

This project is licensed under the **GNU Affero General Public License v3.0** (AGPL-3.0).

See [LICENSE](LICENSE) for the full license text.

---

<p align="center">
  <sub>Built with SwiftUI, SpriteKit, and a love for the outdoors.</sub>
</p>
