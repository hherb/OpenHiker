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

- **Fully Offline Maps** — Download regions over WiFi, then navigate without any connection
- **Apple Watch Standalone** — Works independently without your iPhone nearby
- **Free Map Data** — Uses [OpenTopoMap](https://opentopomap.org/) tiles based on OpenStreetMap
- **Battery Optimized** — Configurable GPS modes to balance accuracy vs battery life
- **MBTiles Storage** — Efficient SQLite-based tile storage, compact and fast
- **SpriteKit Rendering** — Smooth, responsive map display optimized for watchOS

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

### GPS Modes

To preserve battery, OpenHiker offers configurable GPS accuracy:

| Mode | Update Interval | Best For |
|------|-----------------|----------|
| High | Continuous | Technical navigation, unfamiliar terrain |
| Standard | 10 seconds | General hiking |
| Low Power | 30 seconds | Long hikes, battery conservation |

## Architecture

```
OpenHiker/
├── Shared/                    # Cross-platform code
│   ├── Models/
│   │   ├── TileCoordinate.swift
│   │   └── Region.swift
│   └── Storage/
│       └── TileStore.swift    # MBTiles SQLite wrapper
│
├── OpenHiker iOS/             # iPhone companion app
│   ├── Views/
│   │   └── RegionSelectorView.swift
│   └── Services/
│       ├── TileDownloader.swift
│       └── WatchTransferManager.swift
│
└── OpenHiker watchOS/         # Apple Watch app
    ├── Views/
    │   └── MapView.swift
    └── Services/
        ├── MapRenderer.swift  # SpriteKit tile renderer
        └── LocationManager.swift
```

## Building

### Debug Build

```bash
xcodebuild -scheme "OpenHiker iOS" -destination "platform=iOS Simulator,name=iPhone 15 Pro"
xcodebuild -scheme "OpenHiker watchOS" -destination "platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)"
```

### Release Build

```bash
xcodebuild -scheme "OpenHiker iOS" -configuration Release archive
```

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
