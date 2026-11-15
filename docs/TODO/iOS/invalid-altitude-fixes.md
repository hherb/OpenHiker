# Fixes Without a Valid Altitude — iOS

Tracked in #63.

## Context

Android (PR #62) no longer records 0 m for a GPS fix that has no altitude. Before the fix, such fixes showed
as a drop to sea level in the saved track and the elevation chart. On iOS a fix with
`CLLocation.verticalAccuracy < 0` has an invalid altitude. Before #63 it was still stored and still counted in
gain and loss: `OpenHiker iOS/Services/iOSLocationManager.swift` (`updateCachedStats`,
`locationManager(_:didUpdateLocations:)`).

## Rule (match Android)

- A fix with an invalid altitude adds nothing to elevation gain or loss.
- Its stored altitude reuses the last valid altitude.
- The first valid altitude of a hike also rewrites the earlier points (which all lacked one) to that value.
- Put the logic in a pure helper with unit tests (Android: `resolveTrackAltitude` in
  `HikeTrackingService.kt`).

## Status

Done (#63). Pure helper `TrackAltitude` in `Shared/Models/TrackAltitude.swift` (iOS, watchOS and macOS
targets), tested in `OpenHikerTests/TrackAltitudeTests.swift`. Used by `iOSLocationManager`
(`appendTrackPoint`, `updateCachedStats`). Points whose altitude was filled in keep their negative
`verticalAccuracy`. Gain and loss are measured from the last recorded high-accuracy (< 100 m) point with a
valid altitude, so a run of invalid fixes neither spikes the totals nor drops the climb across it.
