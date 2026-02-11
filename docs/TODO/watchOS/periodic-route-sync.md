# Periodic Route Sync to Phone (watchOS)

## Status: IMPLEMENTED

## Summary
During active trail recording, the watch periodically sends partial route data to the phone every 5 minutes, piggybacking on the existing auto-save timer. Uses a stable UUID so the phone can upsert (replace) the in-progress route rather than creating duplicates.

## Implementation
- **Modified**: `OpenHiker watchOS/Views/MapView.swift` — added `syncPartialRouteToPhone()` and `liveRouteId` state
- **Modified**: `OpenHiker watchOS/App/OpenHikerWatchApp.swift` — added `syncLiveRoute()` to WatchConnectivityReceiver
- **Modified**: `OpenHiker iOS/Services/WatchTransferManager.swift` — added `isLiveSync` metadata handling

## Features
- Automatic sync every 5 minutes during recording (piggybacks on auto-save timer)
- Only sends when phone is reachable (no queued transfers during recording)
- Stable UUID ensures phone upserts rather than creating duplicate routes
- Route named "Recording — <date>" with "In-progress recording" comment
- Final save replaces the partial route with complete data

## Technical Details
- Uses `WCSession.transferFile()` with `isLiveSync: "true"` metadata flag
- RouteStore already uses `INSERT OR REPLACE` so upsert is automatic
- Track data compressed via TrackCompression.encode() before transfer
