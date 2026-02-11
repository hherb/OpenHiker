# On-Demand Tile Request from Watch (iOS)

## Status: IMPLEMENTED

## Summary
The iPhone handles tile download requests from the Apple Watch. When the watch sends a `requestTilesForLocation` message, the phone downloads tiles for zoom 12-15 around the requested GPS coordinate and transfers the resulting MBTiles file to the watch.

## Implementation
- **Modified**: `OpenHiker iOS/Services/WatchTransferManager.swift` — added `handleTileRequest()` in `didReceiveMessage` reply handler

## Features
- Receives `requestTilesForLocation` messages from watch with lat, lon, radiusKm
- Downloads tiles at zoom 12-15 using TileDownloader
- Radius clamped to 10km max for safety
- Creates and saves region via RegionStorage
- Transfers MBTiles to watch via existing transferMBTilesFile mechanism
- Fully async — no UI blocking on the phone

## Technical Details
- Triggered from `session(_:didReceiveMessage:replyHandler:)` delegate method
- Immediately replies with `["status": "downloading"]` before async work
- Uses same TileDownloader and RegionStorage as manual region download
- Region named "Watch — <date>" for identification
