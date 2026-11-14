# GPS Fix Plausibility Check — Android

## Context

On iOS and watchOS, route guidance now holds back a GPS fix that puts the user further along the route than
they could have walked (`Shared/Models/FixPlausibilityGate.swift`, PR #45). Guidance never moves its turn
index backwards, so one wild fix far ahead used to skip turns for good.

Android has the same exposure in a different place. `RouteFollower` (`:core`) advances turns by the walked
distance it is given, and `LocationProvider.cumulativeDistance` adds the distance of every moving fix, with
no jump filter. A wild fix inflates the walked distance, and turns are skipped.

## Rule (match Apple)

- **Reachable distance:** planned speed × `MAX_SPEED_FACTOR` (1.8) × seconds since the last accepted fix,
  plus `CERTAINTY_RADIUS_METRES` (15). The planned speed is `totalDistance / estimatedDuration`, or the
  routing base speed for the mode when the duration is 0.
- **Suspect:** a fix whose forward progress exceeds the reachable distance. It is not used for guidance.
- **Recheck:** while a suspect is pending, switch the fused location provider to high accuracy with no
  minimum update distance, so rechecks arrive within a few seconds.
- **Confirm:** two rechecks, each within the certainty radius plus the distance reachable since the
  suspect, accept the jump.
- **Reject:** a recheck that disagrees drops the suspect, and that recheck is judged on its own.
- **Measured speed:** use the larger of the planned speed and the fix's Doppler-measured speed
  (`Location.speed`) when `speedAccuracyMetersPerSecond` is 2 m/s or better. Real fast travel then passes
  at once, and a position jump without a matching speed does not.
- **Cap:** a recheck lasts at most 10 s. The first fix at or after 10 s is accepted as it is. If no fix
  arrives for 10 s, a timer (restarted on every fix) abandons the recheck and ends the GPS burst.
- **Stale fixes:** a fix whose timestamp is not newer than the newest one seen is ignored, so a
  re-delivered suspect cannot confirm itself.
- **Old fixes:** a fix more than `MAX_FIX_AGE_SECONDS` (10) older than the current time is ignored before
  the gate sees it (Apple: `FixPlausibilityGate.isStale`, #47). A cached last-known location delivered
  when updates start would otherwise put the gate's clock minutes back and let the next wild fix pass.
- **Future-dated fixes:** a fix more than `MAX_FIX_LEAD_SECONDS` (10) after the current time is also ignored
  (#49). Stored as the newest fix, it would make every real fix look out of order until the clock caught
  up, and guidance would freeze. On Android, compare `Location.time` with `System.currentTimeMillis()`.
- **First fix:** on Apple a first fix more than 15 m along the route is rechecked. Android starts with a
  walked distance of 0, so the first fix is the reference and is accepted.

## What Needs to Be Done

1. Add the pure gate to `:core` (`com.openhiker.core.navigation`), with constants in `RouteGuidanceConfig`.
2. Gate the walked distance itself. `LocationProvider` adds each fix to `cumulativeDistance` before
   `NavigationService` sees it, so gating only in `NavigationService` would still let a held-back fix
   inflate the distance passed to `RouteFollower`. Either let the gate decide what `LocationProvider`
   accumulates, or have `NavigationService` keep its own walked distance built from accepted fixes only.
   The progress to judge is the distance from the last accepted fix, because Android does not project
   fixes onto the route.
3. Add a recheck mode to `LocationProvider` (a faster `LocationRequest`), toggled while a suspect is pending.
4. Port the iOS gate tests (`OpenHikerTests/iOSRouteGuidanceTests.swift`, section `FixPlausibilityGate`).
