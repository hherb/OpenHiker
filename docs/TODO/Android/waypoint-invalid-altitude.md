# Waypoints Without a Valid Altitude — Android

Tracked in #65.

## Context

On iOS, watchOS and macOS, `Waypoint.fromLocation` stores no altitude (`nil`) when Core Location marks it
invalid (`verticalAccuracy < 0`), and keeps valid altitudes below sea level (PR #64). On Android,
`AddWaypointScreen.kt` saves `currentLocation?.altitude` from `android.location.Location`, which is 0.0 when
`hasAltitude()` is false. The waypoint then shows 0 m and exports `<ele>0</ele>`.

## Rule (match Apple)

- Store the fix's altitude only when `location.hasAltitude()` is true, otherwise `null`.
- Put the choice in a pure function with a unit test, not in the Composable.

## Status

Not started.
