# Fixes Without a Valid Altitude — watchOS

Tracked in #63.

## Context

Android (PR #62) no longer records 0 m for a GPS fix that has no altitude. Before the fix, such fixes showed
as a drop to sea level in the saved track and the elevation chart. On watchOS a fix with
`CLLocation.verticalAccuracy < 0` has an invalid altitude. It is still stored and still counted in gain
and loss: `OpenHiker watchOS/Services/LocationManager.swift` (elevation diff and track point recording).

## Rule (match Android)

- A fix with an invalid altitude adds nothing to elevation gain or loss.
- Its stored altitude reuses the last valid altitude.
- The first valid altitude of a hike also rewrites the earlier points (which all lacked one) to that value.
- Put the logic in a pure helper with unit tests (Android: `resolveTrackAltitude` in
  `HikeTrackingService.kt`).

## Status

Not started.
