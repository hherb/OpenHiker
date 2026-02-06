# Hike Metrics & HealthKit — Developer Guide

This document covers the Phase 1 implementation: live hike statistics overlay and HealthKit integration on watchOS. It is written so that a developer unfamiliar with the codebase can modify, expand, or debug this feature.

## Architecture Overview

```
OpenHikerWatchApp (entry point)
  |
  +-- LocationManager (GPS, heading, track points)
  +-- HealthKitManager (workout sessions, heart rate, SpO2)
  +-- WatchConnectivityReceiver (file transfers from iOS)
  |
  +-- WatchContentView (TabView)
        |
        +-- MapView (SpriteKit map + overlays)
        |     +-- HikeStatsOverlay (distance, elevation, time, vitals)
        |
        +-- RegionsListView
        +-- SettingsView (GPS mode, units, HealthKit settings)
```

All three managers are injected as `@EnvironmentObject` from `OpenHikerWatchApp.swift`.

---

## Files Reference

### New Files

| File | Target | Purpose |
|------|--------|---------|
| `Shared/Models/HikeStatistics.swift` | iOS + watchOS | `HikeStatistics` value type, `HikeStatsFormatter`, `CalorieEstimator`, `HikeStatisticsConfig` |
| `OpenHiker watchOS/Views/HikeStatsOverlay.swift` | watchOS | SwiftUI overlay showing live stats on the map |
| `OpenHiker watchOS/Services/HealthKitManager.swift` | watchOS | `HKWorkoutSession`, heart rate/SpO2 queries, route builder |
| `OpenHiker watchOS/OpenHiker watchOS.entitlements` | watchOS | HealthKit entitlement |

### Modified Files

| File | What Changed |
|------|-------------|
| `OpenHiker watchOS/Services/LocationManager.swift` | Added `elevationLoss` computed property |
| `OpenHiker watchOS/Views/MapView.swift` | Added `HikeStatsOverlay` to ZStack; integrated HealthKit start/stop into `toggleTracking()`; feeds route points on location updates |
| `OpenHiker watchOS/App/WatchContentView.swift` | Added metric/imperial toggle and HealthKit settings section to `SettingsView` |
| `OpenHiker watchOS/App/OpenHikerWatchApp.swift` | Injected `HealthKitManager` as `@StateObject` + `@EnvironmentObject` |
| `OpenHiker watchOS/Resources/Info.plist` | Added `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` |
| `OpenHiker.xcodeproj/project.pbxproj` | Registered new files, added `HealthKit.framework`, set `CODE_SIGN_ENTITLEMENTS` |

---

## Data Flow

### Tracking Lifecycle

```
User taps Play button
  -> MapView.toggleTracking()
      -> LocationManager.startTracking()       // GPS recording
      -> HealthKitManager.startWorkout()        // HKWorkoutSession (if enabled)
          -> setupHeartRateQuery()              // HKAnchoredObjectQuery
          -> setupSpO2Query()                   // HKAnchoredObjectQuery

Location updates arrive
  -> MapView.updateUserPosition()
      -> mapScene.updatePositionMarker()
      -> mapScene.updateTrackTrail()
      -> HealthKitManager.addRoutePoints()      // HKWorkoutRouteBuilder

User taps Stop button
  -> MapView.toggleTracking()
      -> LocationManager.stopTracking()         // GPS stops
      -> HealthKitManager.stopWorkout()         // async
          -> CalorieEstimator.estimateCalories()
          -> workoutBuilder.addSamples()        // distance + calories
          -> workoutBuilder.finishWorkout()
          -> routeBuilder.finishRoute()         // GPS route on Apple Health map
```

### Stats Overlay Data Sources

The `HikeStatsOverlay` reads from two environment objects:

| Metric | Source | Property |
|--------|--------|----------|
| Distance | `LocationManager` | `.totalDistance` (computed from `trackPoints`) |
| Elevation | `LocationManager` | `.elevationGain` (computed) |
| Duration | `LocationManager` | `.duration` (computed) |
| Heart rate | `HealthKitManager` | `.currentHeartRate` (from `HKAnchoredObjectQuery`) |
| SpO2 | `HealthKitManager` | `.currentSpO2` (from `HKAnchoredObjectQuery`, max 5 min old) |

### Unit Formatting

All raw values are in SI units (meters, seconds, m/s). The `HikeStatsFormatter` enum handles conversion to metric or imperial based on the `@AppStorage("useMetricUnits")` preference.

---

## Key Design Decisions

### Why `ObservableObject` instead of Swift Actor for HealthKitManager?

`HKHealthStore` is documented as thread-safe by Apple. Using `ObservableObject` allows `@Published` properties to drive SwiftUI updates directly. An Actor would add unnecessary complexity for async access to properties that are already safe.

### Why `HKAnchoredObjectQuery` instead of `HKObserverQuery`?

`HKAnchoredObjectQuery` with an `updateHandler` delivers new samples incrementally and maintains an anchor for efficient delta processing. `HKObserverQuery` only notifies that data changed — you'd still need a separate query to fetch the samples. Anchored queries are the recommended approach for live workout data.

### Why not use `HKLiveWorkoutBuilder` for heart rate?

The workout builder collects heart rate automatically, but exposes it through `HKStatistics` aggregates (average, max) rather than individual samples. We need individual samples to display the current BPM in real time, so we use a dedicated `HKAnchoredObjectQuery`.

### Calorie Estimation Formula

```
calories = MET * bodyMassKg * durationHours
```

- Base hiking MET: 6.0 (Compendium of Physical Activities)
- Grade adjustment: +1.0 MET per 10% average grade
- Body mass: read from HealthKit if available, otherwise defaults to 70 kg

### Auto-Hide Overlay

The stats overlay auto-hides after 5 seconds to avoid obscuring the map. It reappears on:
- Tap anywhere on the overlay area
- New GPS location update
- Start of tracking

---

## Configuration Constants

All tunable constants are in `HikeStatisticsConfig` (inside `Shared/Models/HikeStatistics.swift`):

| Constant | Value | Purpose |
|----------|-------|---------|
| `restingSpeedThreshold` | 0.3 m/s | Below this = resting (for walking/resting time split) |
| `baseHikingMET` | 6.0 | Base metabolic equivalent for hiking |
| `metPerTenPercentGrade` | 1.0 | MET added per 10% grade |
| `defaultBodyMassKg` | 70.0 | Fallback weight when HealthKit has no data |
| `spO2MaxAgeSec` | 300.0 | Max age (5 min) for SpO2 readings to be displayed |

To change any of these, edit the constants in `HikeStatisticsConfig`. No other code needs to change.

---

## User Preferences

| Key | Type | Default | Location |
|-----|------|---------|----------|
| `useMetricUnits` | Bool | `true` | `SettingsView`, `HikeStatsOverlay` |
| `recordWorkouts` | Bool | `true` | `SettingsView`, `MapView.toggleTracking()` |
| `gpsMode` | String | `"balanced"` | `SettingsView` (pre-existing) |
| `showScale` | Bool | `true` | `SettingsView` (pre-existing) |

---

## Graceful Degradation

HealthKit integration degrades gracefully at multiple levels:

1. **HealthKit not available** (simulator, older device, MDM): `HealthKitManager.healthStore` is `nil`, all methods are no-ops. Stats overlay shows only GPS metrics.

2. **User denies authorization**: `isAuthorized` stays `false`. Workout recording is skipped. Heart rate / SpO2 badges are hidden from the overlay.

3. **SpO2 sensor not available** (pre-Series 6): The SpO2 query runs but never delivers samples. `currentSpO2` stays `nil` and the badge is hidden.

4. **"Record Workouts" disabled in Settings**: `MapView.toggleTracking()` checks `recordWorkouts` before calling `startWorkout()`. GPS tracking works normally without HealthKit.

---

## How to Extend

### Adding a new metric to the overlay

1. Add the data source (property on `LocationManager` or `HealthKitManager`)
2. Add a formatter method to `HikeStatsFormatter`
3. Add a `statBadge()` call in `HikeStatsOverlay.body`
4. Add the field to `HikeStatistics` if it should be persisted

### Adding a new HealthKit data type

1. Add the `HKQuantityType` to `HealthKitManager.readTypes` or `writeTypes`
2. Create a setup query method (follow `setupHeartRateQuery()` pattern)
3. Create a process samples method (follow `processHeartRateSamples()` pattern)
4. Add a `@Published` property for the latest value
5. Call setup in `startWorkout()`, stop in `stopQueries()`
6. Update the entitlements if needed

### Changing the overlay layout

Edit `HikeStatsOverlay.swift`. The layout uses `VStack` of `HStack` rows, each containing `statBadge()` capsules. The auto-hide delay is `autoHideDelaySec`.

---

## Debugging

### HealthKit on Simulator

The watchOS simulator supports HealthKit but has no real sensors. To test:
- Authorization dialogs appear normally
- Heart rate and SpO2 queries run but produce no samples
- Workouts are saved to the simulator's Health data store
- Use the Health app on the iOS simulator (paired) to verify saved workouts

### Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| No heart rate in overlay | HealthKit not authorized | Check `SettingsView` > Health > Authorize |
| Overlay never appears | Not tracking | Tap Play button to start tracking |
| Overlay appears then vanishes | Auto-hide timer (5s) | Tap the map to bring it back |
| Workout not saved | `recordWorkouts` is `false` | Check Settings > Health > Record Workouts |
| "HealthKit is not available" | Running on simulator or restricted device | Expected behavior, GPS tracking still works |
| App suspends on wrist-down | Workout session not started | Ensure `recordWorkouts` is enabled; `HKWorkoutSession` provides extended runtime |

### Logging

All HealthKit operations print to the console with descriptive messages. Filter the console output for:
- `"HealthKit"` — authorization, availability
- `"workout"` — session start/stop/state changes
- `"heart rate"` / `"SpO2"` / `"body mass"` — query results
- `"Error"` — any failures

---

## Testing Checklist

### Feature 1.1 — Stats Display

- [ ] Start tracking: overlay appears with distance (0.0 km), elevation (0 m), time (00:00:00)
- [ ] Walk: distance and time update in real time
- [ ] Elevation changes: gain counter increases on uphill segments
- [ ] Toggle metric/imperial in Settings: overlay switches between km/mi and m/ft
- [ ] Stop tracking: overlay disappears
- [ ] Auto-hide: overlay fades after 5 seconds, reappears on tap

### Feature 1.2 — HealthKit

- [ ] Build watchOS target: compiles with HealthKit framework
- [ ] First launch: HealthKit authorization dialog appears (from Settings > Authorize)
- [ ] Start tracking with recordWorkouts=true: HKWorkoutSession starts
- [ ] Heart rate appears in overlay (real device only)
- [ ] SpO2 appears when recent reading exists (Series 6+ only)
- [ ] Stop tracking: workout saved to Health with correct distance
- [ ] Apple Health app: hiking workout appears with GPS route on map
- [ ] recordWorkouts=false: tracking works without HealthKit workout
- [ ] HealthKit denied: tracking works, vitals section hidden
