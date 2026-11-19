# HANDOVER

Working notes for picking up in-flight work. Each section is one self-contained slice: what's known, where to
start, and how to verify. Remove a section once its slice has landed. Add a new section when handing off new
work. Planned work that has not started lives in `ROADMAP.md`.

Last updated: 2026-11-17.

---

## State of the project

Four platforms. Apple (iOS, watchOS, macOS) share `Shared/` in one Xcode project. Android is a separate Gradle
project in `OpenHikerAndroid/` with modules `core` (pure Kotlin) and `app`.

- **iOS, watchOS, macOS:** feature-complete for the original roadmap (`docs/planning/roadmap.md`, phases 1–6:
  metrics and HealthKit, waypoints, saved hikes, offline A* routing, planning and guidance, export, iCloud
  sync, the native macOS app). Since then: P2P sharing, mapless trail display, on-demand tile requests from the
  watch, periodic route sync, and a watchOS toolbar below the map.
- **Android:** phases 1–5 merged (PRs #14, #20, #26, #33, #34). MapLibre offline maps, A* routing, navigation,
  history, waypoints, export, community routes, cloud-drive sync, settings. Last Android change:
  2026-11-15 (cloud sync of saved routes and waypoints; waypoint category raw values, #61).
- **Android cloud-drive sync** (`service/sync/`) covers planned routes, saved routes (track Base64) and
  waypoints (photo and thumbnail Base64), one `SyncChannel` per type. `SyncStateStore`
  (`data/sync/`) keeps this device's last-sync time and the deletions not yet in the manifest. The
  repositories record a tombstone on every delete. The manifest's own timestamp is informational only.
  Decisions are pure functions in `SyncRules.kt`: when an item exists both locally and in the cloud, the
  newer copy wins (`reconcile`), so an old last-sync time never overwrites a newer edit (#69). A manifest
  that exists but cannot be read stops the sync, so other devices' tombstones are never lost. A mutex
  serialises "Sync now" and the worker. `SyncWorker` reads the folder URI from
  `UserPreferencesRepository`. Before this fix it read an unused SharedPreferences file, so background
  sync never ran. Only Android reads this folder; Apple platforms sync through iCloud.
- **Android `PlannedRouteRepository.save` and `delete` throw** on a failed write or delete and then leave the
  in-memory list unchanged, as Apple's `PlannedRouteStore` does. `save` writes a temp file and renames it, so
  a failed write keeps the old copy. Callers show the error; the route detail screen closes only after a
  successful delete; the sync engine counts the item as failed (#68).
- **Android planned-route reads** tell "missing" from "broken" (#74). `getById` returns null only for a
  missing file and throws `IOException` for an unreadable one. `loadAll` throws if the directory cannot be
  created or listed (the list is then left unchanged, so sync never treats every route as missing). It
  returns one "file: reason" entry per skipped file, which sync reports as an error; a cloud copy of the
  route replaces the broken file in the same sync. The navigation screen now shows a load error instead
  of staying blank.
- **Apple planned-route reads** (#75) match Android. `PlannedRouteStore.loadAllFromDisk()` throws when the
  folder exists but cannot be listed, so the planned-route part of the iCloud sync stops instead of
  overwriting local edits. It returns the skipped files as "file: reason" entries, which
  sync logs; a pull replaces a broken `<id>.json` with the cloud copy of route `<id>`, if there is one.
  Other broken files stay and the app cannot delete them (#80, like Android #77). `loadAll()` leaves
  `routes` unchanged on a folder error and publishes `loadErrors`. The iOS Routes tab, the iOS Navigate
  route picker, macOS and watchOS show them and hide the "No Planned Routes" empty state.
  `fetchForRegion` throws on a folder error and calls `loadAll()` when it skipped files, so transfers
  report them too. Unused `fetch(id:)` is gone. The store takes its folder in `init(storageDirectory:)`
  for tests (`PlannedRouteStoreTests`).
- **Apple iCloud sync errors reach the user** (#78, #81). `CloudSyncManager` runs the upload and the download
  of saved hikes, waypoints and planned routes as six separate steps (`runSteps`), so one failing step no
  longer stops the others. Each sync,
  launch error and push-notification pull is recorded in `CloudSyncStatus.shared` (`@MainActor`, last clean
  sync time plus "part: reason" errors), which replaced the unobserved `cloudSyncCompleted` notification.
  iOS shows a red banner above every tab (Retry, dismiss); macOS shows "Sync failed" in the sidebar and the
  errors or last sync time in Settings → Sync. watchOS does not sync with iCloud. Tests:
  `CloudSyncManagerTests`. When the launch account check failed, Sync Now and Retry rerun it. An unavailable
  iCloud account is still not shown, nor is a sync in progress (#84). Subscription errors are swallowed and
  non-recoverable CloudKit errors are retried (#86).
  Android counterpart: `docs/TODO/Android/sync-error-reporting.md` (#72).
- **Apple iCloud pulls read every record** (#85). `CloudKitStore.fetchAll(recordType:decode:)` follows the
  query cursor to the last page (`collectPages`). A record that fails to load or decode is logged and kept as
  a "record: reason" entry in `FetchResult.skipped`; the pull merges the readable records, then throws
  `unreadableRecords`, so the banner reads "Saved hikes (download): 2 records could not be read: …". The
  decoders are static and throwing; a waypoint without coordinates or a record with a broken `hikeId` or
  `regionId` counts as unreadable. The error names at most 3 records and counts the rest. A query error
  "is not marked queryable" (missing `recordName` index) is now reported, not read as an empty result. Tests:
  `CloudKitStoreTests`. Deferred: #89 (deletions never reach iCloud), #90 (unreadable records never heal,
  merge write errors).
- **Apple route guidance** (iOS `iOSRouteGuidance`, watchOS `RouteGuidance`; shared helpers in
  `Shared/Models/`, compiled into the iOS and watchOS targets only):
  - `RouteProjection` places each fix on the route. Among segments within 20 m of the nearest one or within
    the 50 m off-route threshold, it picks the one that best fits the session's high-water mark of progress,
    so loop and out-and-back routes do not jump to the wrong leg (#44, PR #45). When the fix has a trusted
    course (`courseAccuracy` ≤ 30°), candidates pointing more than 90° away from it are skipped first, so
    guidance started on an out-and-back's return leg follows that leg (#46, PR #48). The course
    picks the leg only until the first fix with a trusted course is accepted, so a short turn-back later
    cannot jump guidance to the other leg.
  - `FixPlausibilityGate` holds back a fix further ahead than planned speed × 1.8 × elapsed time + 15 m,
    with a best-accuracy GPS burst until two agreeing rechecks confirm it. A trusted Doppler speed raises
    the limit, and a recheck lasts at most 10 s (PR #45). Guidance drops fixes older than 10 s, such as
    CoreLocation's cached first fix (#47, PR #48), and fixes more than 10 s in the future, which would
    freeze the gate until the clock caught up (#49, PR #50). If the device clock jumps back mid-session,
    the gate starts afresh as for a first fix (#51, PR #52). It does the same after a forward jump, which
    it spots when fix timestamps outrun a monotonic clock by more than 20 s (#53, PR #54). The 10 s
    recheck cap runs on the same monotonic clock, so a smaller clock step cannot shorten it (#55, PR #56).
    `iOSRouteGuidance.currentDate` and `currentMonotonicTime` are the clock seams the tests use.
  - Android port of the gate: `docs/TODO/Android/gps-fix-plausibility.md`. Android does not project fixes
    onto the route, so the leg choice does not apply there.
- **Fixes without a valid altitude** are handled the same way on all three recording platforms. A fix
  without one stores the last valid altitude, the first valid altitude backfills the points before it, and
  such fixes add nothing to gain or loss. Android: `resolveTrackAltitude` (#59, PR #62). iOS and watchOS:
  `Shared/Models/TrackAltitude.swift` (`verticalAccuracy < 0`; #63, PR #64). Waypoints store no altitude
  for such a fix: Apple `Waypoint.fromLocation`, Android `waypointAltitude` (#65, PR #67).
- **Waypoint categories** are stored as the shared raw value (`waterSource`) on all platforms. Android's
  Room DB v2 migrates v1 rows that held the enum name. Read stored strings with
  `WaypointCategory.fromStored`, which accepts both forms (#61).
- **Last PRs:** #88 (Apple #85), #83 (Apple #78, #81), #79 (Apple #75), #76 (Android #74), #73 (Android
  #68), #70 (#61 plus Android sync of saved routes and waypoints; fixes #69), #67 (Android waypoint
  altitude, #65), #64 (Apple invalid altitudes, #63).
- **User manuals** for all four platforms are in `docs/user/` (commit `0913fe4`).

## Baseline (checked 2026-11-15; Xcode 27.2)

| Gate | Command (see `.claude/skills/nextsession/SKILL.md`) | Result |
|---|---|---|
| iOS tests (`OpenHikerTests`) | `xcodebuild test … -scheme OpenHiker` on `iPhone 17,OS=27.0` | **111/111 pass** (2026-11-17) |
| watchOS build | `… -scheme 'OpenHiker Watch App'` on `Apple Watch Ultra 3 (49mm),OS=26.5` | builds |
| macOS build | `… -scheme 'OpenHiker macOS' -destination 'platform=macOS'` | builds |
| Android tests | `cd OpenHikerAndroid && ./gradlew test --continue` | all pass (`:core` 340/340, `:app` 178/178 per variant; 2026-11-16) |

The older destinations (iPhone 16 Pro, Apple Watch Ultra 2) only have old runtimes installed (iOS 18.4, watchOS
11.x), and the iPhone 16 Pro run failed to find a destination (exit 70). CLAUDE.md and the skills now pin current
runtimes: `iPhone 17,OS=27.0` and `Apple Watch Ultra 3 (49mm),OS=26.5` (watchOS 27.0 has only an Ultra 4).

## In flight

### Device check after PR #40 (merged 2026-11-13)

PR #40 moved the Info.plist usage strings into `INFOPLIST_KEY_*` build settings, dropped the unused iOS
background modes (`processing`, `fetch`) and the watchOS HealthKit background-delivery entitlement, and shared
all three Apple schemes. Add those capabilities back only together with code that uses them. The HealthKit
and WeatherKit framework build files kept Xcode-generated IDs (`6F81…`), not the `1B…` convention; harmless.

- **Still to do:** run the iOS app once on a device to confirm the location and HealthKit permission prompts
  still appear. On the same run, check #41 on device: simulate a route with an Xcode GPX file on iPhone and
  watch, and feel for the direction haptic about 30 m before each turn and a single arrival haptic. Repeat
  with a loop route and an out-and-back route (#44): no arrival at the start, arrival back at the trailhead.
  Start guidance while walking the return leg of an out-and-back (#46): it should follow the return leg.
  Then, on the outbound leg, turn back for 20 m: guidance should stay on the outbound leg. Watch
  the GPS indicator for the recheck burst. Check that it ends within a few seconds and does not get stuck
  on, which would drain the battery. Also log `speed` and `speedAccuracy` on the watch in low-power mode: the
  measured-speed safeguard needs `speedAccuracy` ≤ 2 m/s to apply.

### CI

- `ios.yml` (workflow "Apple") builds and tests scheme `OpenHiker`, and builds the watchOS app (generic
  simulator destination) and the macOS app, both with `CODE_SIGNING_ALLOWED=NO`. The iOS job was pinned to
  `macos-15` in PR #40 (`macos-latest`, Xcode 26.6, had no iOS simulator runtime); the watchOS and macOS
  jobs use the same runner. CI's Xcode (16.4) is older than the local one.
- `android.yml` runs `./gradlew test --continue` on `ubuntu-latest` with Temurin JDK 21 (`:core` needs a
  21 toolchain).
- `codeql.yml` is disabled for inactivity (last run 2026-04-14). Re-enable it with
  `gh workflow enable codeql.yml` if code scanning is wanted.
- `swift.yml` was deleted in PR #40: it ran `swift build` with no `Package.swift` and failed on every run.

## Open GitHub issues

- #23: Android service and ViewModel test coverage.
- #71: Android `WaypointDatabase.MIGRATION_1_2` has no `MigrationTestHelper` test (needs `room-testing`).
- #72: Android background sync errors are only logged, never shown to the user.
- #77: Android sync never clears the error for a broken local planned-route file that has a tombstone
  or no cloud copy, and the app cannot delete it.
- #80: Apple cannot delete a broken planned-route file, and a one-off read failure lets an iCloud pull
  overwrite an unsynced edit with the older cloud copy.
- #82: Apple planned-route `try?` save/delete, and watch-requested transfers that skip routes silently.
- #84: Apple iCloud shows nothing when the account is unavailable or a sync is already running.
- #86: Apple iCloud subscription errors are logged at debug level; non-recoverable CloudKit errors are
  retried.
- #66: watchOS `TrackCompression.decode` resets `verticalAccuracy` to 0, so restored placeholder altitudes
  look valid. Latent: `LocationManager.restoreTrackState` has no callers.
- Android pure functions under test sit top-level and `internal` next to their callers (for example
  `calculateAverageSpeed` in `PDFExporter.kt`, `pausedMsAfterResume` in `HikeTrackingService.kt`).

## Known stubs

- **Community route upload** needs a real GitHub bot token on both platforms
  (`Shared/Services/GitHubRouteService.swift:175`, placeholder bytes;
  `OpenHikerAndroid/.../community/GitHubRouteService.kt:544`, empty `OBFUSCATED_TOKEN`).
