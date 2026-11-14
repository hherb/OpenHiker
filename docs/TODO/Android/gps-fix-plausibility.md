# GPS Fix Plausibility Check — Android

## Context

On iOS and watchOS, route guidance now holds back a GPS fix that puts the user further along the route than
they could have walked (`Shared/Models/FixPlausibilityGate.swift`, PR #45). Guidance never moves its turn
index backwards, so one wild fix far ahead used to skip turns for good.

Android has the same exposure in a different place. `RouteFollower` (`:core`) advances turns by the walked
distance it is given, and `LocationProvider.cumulativeDistance` adds the full distance to every fix. A wild
fix inflates the walked distance, and turns are skipped.

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
  arrives, a timer abandons the recheck and ends the GPS burst.
- **First fix:** the first fix after navigation starts has no reference, so a first fix more than 15 m
  along the route is rechecked like any other jump.

## What Needs to Be Done

1. Add the pure gate to `:core` (`com.openhiker.core.navigation`), with constants in `RouteGuidanceConfig`.
2. Apply it in `NavigationService` before `RouteFollower.update`. The progress to judge is the walked
   distance since the last accepted fix, because Android does not project fixes onto the route.
3. Add a recheck mode to `LocationProvider` (a faster `LocationRequest`), toggled while a suspect is pending.
4. Port the iOS gate tests (`OpenHikerTests/iOSRouteGuidanceTests.swift`, section `FixPlausibilityGate`).
