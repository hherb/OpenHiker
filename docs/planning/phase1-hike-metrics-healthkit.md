# Phase 1: Live Hike Metrics & HealthKit

**Estimated effort:** ~2 weeks
**Dependencies:** None (first phase)
**Platform focus:** watchOS

## Overview

Surface the statistics the watch already computes (distance, elevation, duration) as an on-screen overlay during active tracking, and integrate HealthKit for real-time heart rate / SpO2 display plus workout recording.

---

## Feature 1.1: Display Distance Walked on Watch

**Size:** S (Small)

### What It Does

Shows a translucent overlay on the watch map during active hike tracking with:
- Distance walked (km or mi, locale-aware)
- Cumulative elevation gain (m or ft)
- Elapsed time (HH:MM:SS)

The overlay is only visible when `locationManager.isTracking == true`.

### Technical Approach

The `LocationManager` at `OpenHiker watchOS/Services/LocationManager.swift` already computes:
- `totalDistance: CLLocationDistance` (line 263)
- `elevationGain: Double` (line 277)
- `duration: TimeInterval?` (line 293)

These just need to be displayed. No new calculations required.

**Formatting:**
- Use `MeasurementFormatter` with locale-aware units (km/mi, m/ft)
- Add `@AppStorage("useMetricUnits")` preference (default: `true`)
- Format time as `HH:MM:SS` using a simple extension on `TimeInterval`

### Files to Create

#### `OpenHiker watchOS/Views/HikeStatsOverlay.swift`

```swift
// SwiftUI view with translucent capsule backgrounds
// Reads from @EnvironmentObject LocationManager
// Layout: horizontal strip at top or vertical stack at edge
// Shows: distance | elevation | time
// Only renders when locationManager.isTracking
```

Key design decisions:
- Use `.ultraThinMaterial` background (matches existing `topInfoBar` style in MapView.swift:176)
- Compact layout to not obscure the map (capsule badges, not full-width bars)
- Auto-hide after 5 seconds of no interaction, reappear on tap or new location update

### Files to Modify

#### `OpenHiker watchOS/Views/MapView.swift`
- Add `HikeStatsOverlay()` to the ZStack (between the map and existing controls)
- Conditionally visible when `locationManager.isTracking`

#### `OpenHiker watchOS/App/WatchContentView.swift`
- Add metric/imperial toggle to SettingsView:
  ```swift
  @AppStorage("useMetricUnits") var useMetricUnits = true
  // Toggle: "Units: Metric / Imperial"
  ```

### Testing

1. Build watchOS target
2. Start tracking on the watch simulator
3. Verify distance, elevation, and time update in real time
4. Toggle metric/imperial in settings, verify formatting changes
5. Stop tracking — overlay should disappear

---

## Feature 1.2: HealthKit — Read Vitals + Write Workouts

**Size:** M (Medium)

### What It Does

- **Read:** Real-time heart rate and blood oxygen (SpO2) from Apple Watch sensors during hikes
- **Write:** Save completed hikes as `HKWorkout` entries with GPS route, distance, elevation, and energy burned
- **Extended runtime:** Starting an `HKWorkoutSession` keeps the app running in the background on watchOS

### Technical Approach

#### Authorization

Request HealthKit permissions on first launch or when user enables tracking:
- **Read:** `HKQuantityType(.heartRate)`, `HKQuantityType(.oxygenSaturation)`
- **Write:** `HKWorkoutType.workoutType()`, `HKSeriesType.workoutRoute()`

#### Workout Session Lifecycle

1. When user taps "Start Tracking" → start `HKWorkoutSession` + `HKLiveWorkoutBuilder`
2. During hike → query heart rate via `HKAnchoredObjectQuery` (delivers new samples as they arrive)
3. When user taps "Stop Tracking" → end workout session, save workout with:
   - Activity type: `.hiking`
   - Distance: from `LocationManager.totalDistance`
   - Energy: estimated from MET values (hiking MET ≈ 6.0, adjusted by elevation)
   - Route: add GPS points via `HKWorkoutRouteBuilder`

#### Heart Rate Display

- Subscribe to heart rate updates via `HKAnchoredObjectQuery` with `HKQueryAnchor`
- Update `@Published var currentHeartRate: Double?` on the main thread
- Display in `HikeStatsOverlay` with heart icon and BPM value
- SpO2 is only available intermittently — display when a recent sample exists (< 5 minutes old)

#### Energy Estimation

Use MET (Metabolic Equivalent of Task) values:
- Base hiking MET: 6.0 (moderate hiking)
- Adjust for grade: +1.0 MET per 10% average grade
- Formula: `calories = MET × weight_kg × duration_hours`
- Weight can be read from HealthKit `HKQuantityType(.bodyMass)` if authorized

### Files to Create

#### `OpenHiker watchOS/Services/HealthKitManager.swift`

```swift
// ObservableObject class (not Actor — HKHealthStore is thread-safe)
//
// Properties:
//   @Published var currentHeartRate: Double?
//   @Published var currentSpO2: Double?
//   @Published var isAuthorized: Bool
//   @Published var workoutActive: Bool
//
// Methods:
//   requestAuthorization() async throws
//   startWorkout() — creates HKWorkoutSession + builder
//   stopWorkout() async throws -> HKWorkout — ends session, saves workout
//   addRoutePoints(_ locations: [CLLocation]) — feeds GPS to HKWorkoutRouteBuilder
//
// Internal:
//   setupHeartRateQuery() — HKAnchoredObjectQuery for live HR
//   setupSpO2Query() — HKAnchoredObjectQuery for SpO2
```

#### `Shared/Models/HikeStatistics.swift`

```swift
// Value type aggregating all hike stats
// Used by: stats overlay, save route, HealthKit, export
//
// struct HikeStatistics: Codable, Sendable {
//     let totalDistance: Double          // meters
//     let elevationGain: Double          // meters
//     let elevationLoss: Double          // meters
//     let duration: TimeInterval
//     let walkingTime: TimeInterval
//     let restingTime: TimeInterval
//     let averageHeartRate: Double?
//     let maxHeartRate: Double?
//     let averageSpO2: Double?
//     let estimatedCalories: Double?
//     let averageSpeed: Double           // m/s
//     let maxSpeed: Double               // m/s
// }
```

### Files to Modify

#### `OpenHiker watchOS/Views/MapView.swift`
- In `toggleTracking()` (line 301):
  - When starting: also call `healthKitManager.startWorkout()`
  - When stopping: also call `healthKitManager.stopWorkout()`
- Pass `healthKitManager` as `@EnvironmentObject` or `@StateObject`

#### `OpenHiker watchOS/Views/HikeStatsOverlay.swift`
- Add heart rate display: `♥ 142 bpm` (red heart icon)
- Add SpO2 display when available: `O₂ 97%`
- Conditionally show only when HealthKit is authorized and data is available

#### `OpenHiker watchOS/App/WatchContentView.swift`
- Add HealthKit section to SettingsView:
  - Authorization status indicator
  - "Authorize HealthKit" button
  - Toggle for "Record workouts to Health"

#### `OpenHiker watchOS/App/OpenHikerWatchApp.swift`
- Inject `HealthKitManager` as `@StateObject` into the environment

### Xcode Project Changes

- Add `HealthKit.framework` to the watchOS target's "Frameworks, Libraries, and Embedded Content"
- Create `OpenHiker watchOS/OpenHiker watchOS.entitlements`:
  ```xml
  <key>com.apple.developer.healthkit</key>
  <true/>
  <key>com.apple.developer.healthkit.access</key>
  <array>
      <string>health-records</string>
  </array>
  ```
- Add to watchOS `Info.plist`:
  ```xml
  <key>NSHealthShareUsageDescription</key>
  <string>OpenHiker reads your heart rate and blood oxygen during hikes to display live vitals and record workout data.</string>
  <key>NSHealthUpdateUsageDescription</key>
  <string>OpenHiker saves your hikes as workouts in Apple Health with distance, elevation, route, and calorie data.</string>
  ```

### Testing

1. Build watchOS target — verify it compiles with HealthKit framework
2. Launch on simulator — verify HealthKit authorization dialog appears
3. Start tracking — verify HKWorkoutSession starts (check Health app for active workout)
4. On real device: verify heart rate appears in overlay during active hike
5. Stop tracking — verify HKWorkout saved to Health with correct distance and route
6. Open Apple Health app — verify hiking workout appears with GPS route on map

### Edge Cases

- HealthKit not available (older devices, restricted MDM): gracefully degrade, hide vitals section
- User denies HealthKit authorization: tracking still works, just no vitals or workout recording
- SpO2 not available on all watch models (Series 6+): check `HKHealthStore.isHealthDataAvailable()` and sensor availability
- Background runtime: the `HKWorkoutSession` provides extended background execution — ensure it's started before the app goes to the wrist-down state
