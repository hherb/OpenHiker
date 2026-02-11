# On-Demand Tile Request from Phone (watchOS)

## Status: IMPLEMENTED

## Summary
The watch can request map tiles from the phone when no region is loaded. A "Request Map from iPhone" button appears in the no-map placeholder view. The phone downloads tiles for zoom 12-15 around the watch's GPS location and transfers them as an MBTiles region.

## Implementation
- **Modified**: `OpenHiker watchOS/App/OpenHikerWatchApp.swift` — added `requestTilesFromPhone()` and `isTileRequestPending` to WatchConnectivityReceiver
- **Modified**: `OpenHiker watchOS/Views/MapView.swift` — added request button in noMapView
- **Modified**: `OpenHiker iOS/Services/WatchTransferManager.swift` — added `handleTileRequest()` message handler

## Features
- "Request Map from iPhone" button shown when phone is reachable and no map loaded
- Rate limited: one request per 10 minutes
- Phone downloads zoom 12-15 tiles for a 5km radius (configurable)
- Radius clamped to 10km max on phone side
- Progress indicator on watch while request is pending
- Region auto-appears in watch's region list when transfer completes

## Technical Details
- Watch sends `sendMessage` with reply handler: `["action": "requestTilesForLocation", "lat": ..., "lon": ..., "radiusKm": ...]`
- Phone creates RegionSelectionRequest, downloads via TileDownloader, saves via RegionStorage
- Transfer uses existing `transferMBTilesFile()` mechanism
- `isTileRequestPending` reset when MBTiles file received on watch
