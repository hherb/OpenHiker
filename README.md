# OpenHiker

<p align="center">
  <img src="docs/images/app-icon.svg" alt="OpenHiker Logo" width="180" height="180">
</p>

<p align="center">
  <strong>Offline hiking navigation for Apple Watch, iPhone, Mac & Android</strong><br>
  <em>Using free OpenStreetMap cartographic data</em>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#platforms">Platforms</a> •
  <a href="#how-it-works">How It Works</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#roadmap">Roadmap</a> •
  <a href="#building">Building</a> •
  <a href="#license">License</a>
</p>

---

## Why OpenHiker?

Traditional hiking apps require cellular connectivity or expensive offline map subscriptions. OpenHiker brings truly **free, offline topographic maps** to your Apple Watch, iPhone, Mac, and Android phone — no internet required on the trail.

Perfect for:
- Backcountry hiking where there's no cell coverage
- Trail running without carrying a phone
- Quick glances at the map without stopping to dig out your phone
- Planning routes at home on your Mac and syncing to your devices

## Platforms

OpenHiker runs natively on four platforms:

| Platform | Status | Key Capability |
|----------|--------|---------------|
| **Apple Watch** (watchOS 10+) | Stable | Standalone offline navigation with SpriteKit map rendering |
| **iPhone/iPad** (iOS 17+) | Stable | Region downloading, route planning, turn-by-turn navigation, hike review |
| **Mac** (macOS 14+) | Stable | Full-featured planning hub with GPX import, keyboard shortcuts, iCloud sync |
| **Android** (API 26+) | In Development | MapLibre offline maps, A* routing, turn-by-turn navigation |

## Features

### Offline Maps & Navigation
- **Fully Offline Maps** — Download regions over WiFi, then navigate without any connection
- **Apple Watch Standalone** — Works independently without your iPhone nearby
- **iPhone Turn-by-Turn** — Full navigation with route recording and health data relay
- **Free Map Data** — Uses [OpenTopoMap](https://opentopomap.org/) tiles based on OpenStreetMap
- **Multiple Map Styles** — OpenTopoMap, CyclOSM, and OpenStreetMap Standard
- **Battery Optimized** — Configurable GPS modes to balance accuracy vs battery life
- **MBTiles Storage** — Efficient SQLite-based tile storage, compact and fast
- **SpriteKit Rendering** — Smooth, responsive map display optimized for watchOS
- **Apple Maps Integration** — Registered as a routing app for pedestrian and cycling directions

### Offline Routing Engine
- **A\* Pathfinding** — Fully offline route computation using OSM trail data from Geofabrik
- **Elevation-Aware** — Copernicus DEM GLO-30 elevation data with hiking cost function based on Naismith's rule
- **Compact Routing Graphs** — SQLite-based routing database (~5-20 MB per 50x50 km region)
- **OSM PBF Parsing** — Direct Protocol Buffer parsing of OpenStreetMap extracts
- **Hiking & Cycling Modes** — Activity-specific routing with appropriate cost functions

### Route Planning & Turn-by-Turn Guidance
- **Route Planning on iPhone & Mac** — Tap start/end/via-points, compute optimal paths, view route stats
- **Turn-by-Turn on Watch** — Route polyline overlay, upcoming turn instructions, haptic feedback
- **Turn-by-Turn on iPhone** — Full navigation UI with route recording and live stats
- **Off-Route Detection** — Automatic re-routing when you leave the planned path
- **Heading-Up Mode** — Map rotation aligned with walking direction on watchOS

### Live Hike Metrics & HealthKit
- **Real-Time Stats Overlay** — Distance, elevation gain, duration displayed on the watch during hikes
- **Stats Dashboard** — Dedicated dashboard view with comprehensive hike statistics
- **HealthKit Integration** — Records heart rate, calories burned, and workout sessions
- **Workout Recording** — Automatic HealthKit workout tracking while hiking
- **UV Index Monitoring** — Real-time UV exposure data with sun safety overlay
- **Watch Health Relay** — Health data forwarded from watch to iPhone during navigation

### Waypoints & Pins
- **Quick Mark on Watch** — Drop pins at points of interest with category presets
- **Full Annotations on iPhone** — Add photos, notes, and categories to waypoints
- **Bidirectional Sync** — Waypoints sync between iPhone and Apple Watch via WatchConnectivity

### Saved Routes & Hike Review
- **Save Completed Hikes** — Persist routes with comprehensive auto-computed statistics (distance, elevation gain/loss, duration)
- **Watch Track Recording** — GPS tracking with low-battery mode and crash recovery (auto-save every 5 minutes)
- **Hike History on iPhone** — Browse past hikes with track overlays and elevation profiles (Swift Charts)
- **Track Compression** — Efficient storage of recorded tracks using the Ramer-Douglas-Peucker algorithm
- **Rename Support** — Rename regions, hikes, and planned routes with iCloud sync

### Multi-Platform & Export
- **iPad Adaptive Layout** — `NavigationSplitView` with sidebar on iPad for a desktop-class experience
- **Native macOS App** — Full-featured planning hub with region selection, tile downloading, route planning, hike review, keyboard shortcuts, and iCloud sync
- **GPX Import** — Import GPX tracks on macOS for review and conversion
- **PDF & Markdown Export** — Generate hike reports with map snapshots and elevation profiles
- **GPX Export** — Standard GPX 1.1 track export from the watch

### Peer-to-Peer Sharing
- **Device-to-Device Transfer** — Share downloaded regions directly between iPhones or from Mac to iPhone, no internet required
- **Complete Bundle** — Automatically includes all associated saved routes, planned routes, and waypoints
- **Hiking Group Ready** — Perfect for sharing maps at the trailhead before heading into areas without coverage
- **VPN Detection** — Warns when an active VPN may interfere with local peer discovery

### Community Route Sharing & iCloud Sync
- **Browse Shared Routes** — Discover routes shared by the community
- **Upload Your Routes** — Share your planned routes with other hikers
- **iCloud Sync** — Routes, waypoints, and regions sync across your Apple devices via CloudKit

### Android (In Development)
- **MapLibre Native** — GPU-accelerated offline map rendering with native MBTiles support
- **Jetpack Compose UI** — Modern Material 3 interface with bottom navigation
- **A\* Routing Engine** — Same algorithms as iOS, ported to a pure Kotlin core library
- **Turn-by-Turn Navigation** — Route following with haptic feedback and off-route detection
- **Foreground GPS Service** — Background location tracking during active hikes
- **Room Databases** — Type-safe SQLite storage with same schemas as iOS

## How It Works

```
┌──────────────────┐          ┌──────────────────┐          ┌──────────────────┐
│   iPhone App     │   ───►   │  Apple Watch     │          │   Mac App        │
│                  │  Watch   │                  │          │                  │
│ • Select region  │ Connect  │ • View map       │          │ • Select region  │
│ • Download tiles │  ivity   │ • GPS tracking   │  iCloud  │ • Download tiles │
│ • Plan routes    │          │ • Turn-by-turn   │ ◄──────► │ • Plan routes    │
│ • Navigate       │          │ • Live stats     │          │ • Review hikes   │
│ • Review hikes   │          │ • Offline nav    │          │ • Community      │
│ • Community      │          │ • HealthKit      │          │ • GPX import     │
└──────┬───────────┘          └──────────────────┘          └──────┬───────────┘
       │                                                          │
       │◄─── Peer-to-Peer (MultipeerConnectivity) ──────────────►│
       │     Share regions, routes & waypoints directly           │
       │     between devices — no internet required               │
       │◄──────────────────────────────────────────────────────►  │
       │         iPhone ◄──► iPhone (P2P)                         │
       └──────────────────────────────────────────────────────────┘

┌──────────────────┐
│  Android App     │  (In Development)
│                  │
│ • MapLibre maps  │  Same offline tile + routing
│ • Download tiles │  format as Apple platforms
│ • A* routing     │  (MBTiles, SQLite routing DB,
│ • Turn-by-turn   │   compressed track format)
│ • GPS tracking   │
└──────────────────┘
```

1. **Select** — Use the iOS, macOS, or Android app to browse and select a hiking region
2. **Download** — Tiles and optional routing data are fetched and stored in MBTiles/SQLite format
3. **Transfer** — Maps and planned routes are sent to your Apple Watch via Watch Connectivity (iOS) or iCloud sync
4. **Share** — Share downloaded regions with nearby devices via peer-to-peer transfer (no internet needed)
5. **Plan** — Create routes on iPhone, Mac, or Android with A* pathfinding, then send to watch
6. **Hike** — Navigate offline with real-time GPS, turn-by-turn guidance, and live stats
7. **Review** — Browse past hikes on iPhone, iPad, or Mac with track overlays and elevation profiles

## Installation

### Requirements

**Apple platforms:**
- iOS 17.0+ (iPhone/iPad companion app)
- watchOS 10.0+ (Apple Watch app)
- macOS 14.0+ (Mac app)
- Xcode 15.0+

**Android:**
- Android 8.0+ (API 26)
- Android Studio Hedgehog or later

### From Source

**Apple platforms:**
```bash
git clone https://github.com/hherb/OpenHiker.git
cd OpenHiker
open OpenHiker.xcodeproj
```

**Android:**
```bash
git clone https://github.com/hherb/OpenHiker.git
cd OpenHiker/OpenHikerAndroid
# Open in Android Studio, or:
./gradlew :app:assembleDebug
```

## Usage

### Downloading a Region

1. Open OpenHiker on your iPhone
2. Navigate to the **Regions** tab and browse the map
3. Tap **Select Area** and draw a rectangle around your hiking region
4. Optionally enable routing data download for offline route planning
5. Review the estimated download size and tile count
6. Tap **Download** and wait for completion
7. The region will automatically transfer to your paired Apple Watch

### Planning a Route

1. Navigate to the **Routes** tab on your iPhone
2. Tap **+** and select a downloaded region with routing data
3. Tap on the map to set start, end, and via-points
4. The routing engine computes the optimal path with distance and elevation stats
5. Send the planned route to your Apple Watch

### On the Trail

1. Open OpenHiker on your Apple Watch
2. Select your downloaded region from the **Regions** tab
3. Your current position is shown with a pulsing blue dot
4. Use the Digital Crown to zoom in/out
5. Pan by swiping on the display
6. If following a planned route, turn-by-turn guidance appears with haptic alerts
7. View live stats (distance, elevation, duration) on the overlay
8. Tap to drop waypoint pins at points of interest
9. Save your hike when finished to review later

### iPhone Navigation

1. Open a planned route and tap **Navigate**
2. Turn-by-turn instructions display with the route overlaid on the map
3. GPS tracks your position with live stats (distance, elevation, duration)
4. Choose from three map styles: Roads, Trails, or Cycling
5. Health data relays to your Apple Watch during the hike

### GPS Modes

To preserve battery, OpenHiker offers configurable GPS accuracy:

| Mode | Update Interval | Best For |
|------|-----------------|----------|
| High | Continuous | Technical navigation, unfamiliar terrain |
| Balanced | 10 seconds | General hiking |
| Low Power | 30 seconds | Long hikes, battery conservation |

### Sharing with Nearby Devices

Share your downloaded regions (with all routes and waypoints) directly with another iPhone or from your Mac — no internet needed:

1. **Sender:** Long-press a region in **Downloaded Regions** → tap **"Share with nearby device"**
2. **Receiver:** Tap the download-arrow button in the toolbar → tap the sender's device name
3. Transfer starts automatically — progress bar shows each step
4. When complete, the region and all routes appear on the receiver's device

See [Peer-to-Peer Sharing Guide](docs/user/peer-to-peer-sharing.md) for detailed instructions and troubleshooting.

### Reviewing Past Hikes

1. Open OpenHiker on your iPhone, iPad, or Mac
2. Navigate to the **Hikes** tab (or section)
3. Browse your saved hikes with distance, duration, and elevation stats
4. Tap a hike to see the track overlaid on a map with elevation profile
5. Export hikes as PDF or Markdown reports

## Architecture

```
OpenHiker/
├── Shared/                    # Cross-platform code (iOS, watchOS, macOS)
│   ├── Models/                # Data types
│   │   ├── TileCoordinate.swift
│   │   ├── Region.swift
│   │   ├── Waypoint.swift
│   │   ├── SavedRoute.swift
│   │   ├── HikeStatistics.swift
│   │   ├── PlannedRoute.swift
│   │   ├── RoutingGraph.swift
│   │   ├── TurnInstruction.swift
│   │   ├── ActivityType.swift
│   │   └── SharedRoute.swift
│   ├── Storage/               # SQLite data stores
│   │   ├── TileStore.swift
│   │   ├── WaypointStore.swift
│   │   ├── RouteStore.swift
│   │   └── RoutingStore.swift
│   ├── Services/              # Shared business logic
│   │   ├── RoutingEngine.swift
│   │   ├── CloudKitStore.swift
│   │   ├── CloudSyncManager.swift
│   │   ├── PeerTransferService.swift  # P2P region & route sharing via MultipeerConnectivity
│   │   ├── GitHubRouteService.swift
│   │   └── HikeSummaryExporter.swift
│   └── Utilities/
│       ├── TrackCompression.swift
│       ├── RouteExporter.swift
│       └── PhotoCompressor.swift
│
├── OpenHiker iOS/             # iPhone & iPad companion app
│   ├── App/                   # Entry point, adaptive layout (TabView / NavigationSplitView)
│   ├── Views/
│   │   ├── RegionSelectorView.swift     # MapKit region selection & download
│   │   ├── TrailMapView.swift           # Trail overlay map display
│   │   ├── HikesListView.swift          # Saved hike history
│   │   ├── HikeDetailView.swift         # Hike detail with track overlay
│   │   ├── ElevationProfileView.swift   # Swift Charts elevation profile
│   │   ├── RoutePlanningView.swift      # A* route planning UI
│   │   ├── RoutePlanningMapView.swift   # MapKit view for route planning
│   │   ├── RouteDetailView.swift        # Planned route detail & transfer
│   │   ├── iOSNavigationView.swift      # iPhone turn-by-turn navigation
│   │   ├── iOSNavigationOverlay.swift   # Navigation instruction overlay
│   │   ├── AddWaypointView.swift        # Waypoint creation with photos
│   │   ├── WaypointDetailView.swift     # Waypoint detail & editing
│   │   ├── WaypointsListView.swift      # All waypoints browser
│   │   ├── CommunityBrowseView.swift    # Browse shared routes
│   │   ├── CommunityRouteDetailView.swift
│   │   ├── RouteUploadView.swift        # Share routes with community
│   │   ├── PeerSendView.swift           # P2P sender sheet
│   │   ├── PeerReceiveView.swift        # P2P receiver sheet
│   │   ├── ExportSheet.swift            # PDF/Markdown export
│   │   └── SidebarView.swift            # iPad sidebar sections
│   └── Services/
│       ├── TileDownloader.swift         # Actor-based tile fetcher with subdomain rotation
│       ├── WatchTransferManager.swift   # WatchConnectivity file sender
│       ├── RegionStorage.swift          # Downloaded region management
│       ├── iOSLocationManager.swift     # iPhone GPS tracking
│       ├── iOSRouteGuidance.swift       # iPhone route-following logic
│       ├── WatchHealthRelay.swift       # Health data forwarding from watch
│       ├── OSMDataDownloader.swift      # OSM PBF trail data download
│       ├── PBFParser.swift              # Protocol Buffer parser
│       ├── ProtobufReader.swift         # Low-level protobuf reader
│       ├── RoutingGraphBuilder.swift    # Builds routing graphs from OSM data
│       ├── ElevationDataManager.swift   # Copernicus DEM elevation data
│       └── PDFExporter.swift            # PDF report generation
│
├── OpenHiker watchOS/         # Apple Watch standalone app
│   ├── App/                   # Entry point, 4-tab vertically-paged interface
│   ├── Views/
│   │   ├── MapView.swift                # SpriteKit offline map display
│   │   ├── HikeStatsOverlay.swift       # Live stats during hike
│   │   ├── HikeStatsDashboardView.swift # Comprehensive stats dashboard
│   │   ├── NavigationOverlay.swift      # Turn-by-turn guidance overlay
│   │   ├── UVIndexOverlay.swift         # UV exposure sun safety overlay
│   │   ├── AddWaypointSheet.swift       # Quick waypoint creation
│   │   └── SaveHikeSheet.swift          # Save completed hike
│   └── Services/
│       ├── MapRenderer.swift            # SpriteKit tile renderer
│       ├── LocationManager.swift        # GPS tracking & track recording
│       ├── HealthKitManager.swift       # Heart rate, workouts, SpO2
│       ├── UVIndexManager.swift         # Real-time UV index monitoring
│       └── RouteGuidance.swift          # Turn-by-turn navigation engine
│
├── OpenHiker macOS/           # Native macOS planning & review app
│   ├── App/                   # Entry point, NavigationSplitView sidebar
│   │   └── OpenHikerCommands.swift      # Keyboard shortcuts & menu commands
│   ├── Views/
│   │   ├── MacRegionSelectorView.swift  # Region selection & tile downloading
│   │   ├── MacTrailMapView.swift        # MapKit trail overlay display
│   │   ├── MacRegionsListView.swift     # Downloaded regions management
│   │   ├── MacRoutePlanningView.swift   # Route planning with A* pathfinding
│   │   ├── MacHikesView.swift           # Hike history browser
│   │   ├── MacHikeDetailView.swift      # Hike detail with map & profile
│   │   ├── MacWaypointsView.swift       # Waypoints table view
│   │   ├── MacAddWaypointView.swift     # Waypoint creation
│   │   ├── MacPlannedRoutesView.swift   # Planned routes list
│   │   ├── MacCommunityView.swift       # Community route browser
│   │   ├── MacPeerSendView.swift        # P2P sender sheet (send region to iPhone)
│   │   ├── MacSettingsView.swift        # App preferences
│   │   └── GPXImportHandler.swift       # GPX file import support
│   └── Services/
│       └── MacPDFExporter.swift         # macOS-specific PDF generation
│
└── OpenHikerAndroid/          # Android app (in development)
    ├── core/                  # Pure Kotlin library (no Android deps)
    │   └── src/main/kotlin/com/openhiker/core/
    │       ├── geo/           # TileCoordinate, BoundingBox, Haversine, TileRange
    │       ├── routing/       # A* pathfinding, cost functions, turn detection
    │       ├── elevation/     # HGT parsing, bilinear interpolation, elevation profiles
    │       ├── compression/   # Track compression (cross-platform compatible)
    │       ├── navigation/    # Route following, off-route detection
    │       ├── overpass/      # Overpass API query building, OSM XML parsing
    │       ├── community/     # Route index, shared route models
    │       ├── formats/       # MBTiles schema, routing DB schema, sync manifest
    │       └── model/         # All shared data classes
    └── app/                   # Android application (Jetpack Compose + Room + Hilt)
        └── src/main/java/com/openhiker/android/
            ├── di/            # Hilt dependency injection modules
            ├── data/          # Room databases, repositories
            ├── service/       # Tile download, location, OSM, routing graph builder
            └── ui/            # Compose screens (regions, map, routing, navigation, settings)
```

## Building

### Apple Platforms — Debug Build

```bash
# iOS (iPhone/iPad simulator)
xcodebuild -scheme "OpenHiker" -destination "platform=iOS Simulator,name=iPhone 16 Pro"

# watchOS (Apple Watch simulator)
xcodebuild -scheme "OpenHiker Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)"

# macOS
xcodebuild -scheme "OpenHiker macOS" build
```

### Apple Platforms — Release Build

```bash
xcodebuild -scheme "OpenHiker" -configuration Release archive
```

### Android

```bash
cd OpenHikerAndroid

# Debug build
./gradlew :app:assembleDebug

# Run core library tests
./gradlew :core:test

# Run Android tests
./gradlew :app:testDebugUnitTest
```

## Roadmap

OpenHiker is under active development. Here's what's been completed and what's coming next:

### Apple Platforms (iOS, watchOS, macOS)

| Phase | Feature | Status |
|-------|---------|--------|
| 1 | Live Hike Metrics & HealthKit | Done |
| 2 | Waypoints & Pins | Done |
| 3 | Save Routes & Review Past Hikes | Done |
| 4 | Custom Offline Routing Engine | Done |
| 5 | Route Planning & Active Guidance | Done |
| 6.1 | Native macOS App | Done |
| 6.2 | iPad Adaptive Layouts | Done |
| 6.3 | Export (PDF/Markdown) | Done |
| 6.4 | iCloud Sync | Done |
| — | Community Route Sharing | Done |
| — | Peer-to-Peer Region & Route Sharing | Done |
| — | iPhone Turn-by-Turn Navigation | Done |
| — | Apple Maps Routing Integration | Done |
| — | Watch Track Recording & Crash Recovery | Done |

### Android

| Phase | Feature | Status |
|-------|---------|--------|
| 1 | Foundation & Offline Maps (project scaffolding, core library, MapLibre, tile downloading, region management) | Done |
| 2 | Navigation & Routing (GPS tracking, elevation data, OSM download, routing graph, A* routing, turn-by-turn) | Done |
| 3 | History, Waypoints & Export (hike recording/review, waypoint management, PDF/GPX export) | In Progress |
| 4 | Community & Cloud Sync (community route sharing, cloud drive sync) | Planned |

### What's Next

- Complete Android Phase 3 (hike recording, waypoints, export)
- Android Phase 4 (community features, cloud sync)
- Polish and bug fixes across all platforms
- Expanded test coverage
- App Store and Google Play release preparation

See [docs/planning/roadmap.md](docs/planning/roadmap.md) for the full roadmap with technical details.

## Data Sources

All map and routing data is free and globally available:

| Data | Source | License |
|------|--------|---------|
| Map tiles | [OpenTopoMap](https://opentopomap.org/) | CC-BY-SA |
| Trail data | [Geofabrik](https://download.geofabrik.de/) OSM extracts | ODbL |
| Elevation | [Copernicus DEM GLO-30](https://spacedata.copernicus.eu/) | CC-BY-4.0 |

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- [OpenStreetMap](https://www.openstreetmap.org/) — Map data contributors
- [OpenTopoMap](https://opentopomap.org/) — Topographic tile rendering
- [MBTiles Specification](https://github.com/mapbox/mbtiles-spec) — Tile storage format
- [MapLibre](https://maplibre.org/) — Open-source map rendering for Android

## License

This project is licensed under the **GNU Affero General Public License v3.0** (AGPL-3.0).

See [LICENSE](LICENSE) for the full license text.

---

<p align="center">
  <sub>Built with SwiftUI, SpriteKit, Jetpack Compose, and a love for the outdoors.</sub>
</p>
