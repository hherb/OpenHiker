# HANDOVER

Working notes for picking up in-flight work. Each section is one self-contained slice: what's known, where to
start, and how to verify. Remove a section once its slice has landed. Add a new section when handing off new
work. Planned work that has not started lives in `ROADMAP.md`.

Last updated: 2026-11-14.

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
  2026-11-14 (`RouteFollower` arrival gated on the last instruction, #44).
- **Last PRs:** #43 (2026-11-14, #41: Apple guidance advances a turn only once passed, single arrival haptic);
  #42 (2026-11-14, Android `RouteFollower` turn advance, `:core` tests green). This branch fixes #44: Apple
  guidance places each fix with the shared `RouteProjection` (`Shared/Models/RouteProjection.swift`, iOS and
  watchOS targets only). Among segments within 20 m of the nearest one, it picks the one that best fits the
  session's high-water mark of progress, so loop and out-and-back routes no longer jump to the wrong leg. Android
  `RouteFollower` reports arrival only on the last instruction, so a loop does not arrive at the trailhead.
  The same branch adds `FixPlausibilityGate` (`Shared/Models/FixPlausibilityGate.swift`). A fix further ahead
  than planned speed × 1.8 × elapsed time + 15 m is held back. The GPS switches to a best-accuracy burst
  until two agreeing rechecks confirm the jump, or one disagreeing recheck drops it. A trusted measured
  (Doppler) speed raises the limit, so car or bus travel is not held back. A recheck lasts at most 10 s, with
  a timer for when no fixes arrive, so guidance cannot freeze. Android port:
  `docs/TODO/Android/gps-fix-plausibility.md`.
- **User manuals** for all four platforms are in `docs/user/` (commit `0913fe4`).

## Baseline (checked 2026-11-14, Xcode 27.2)

| Gate | Command (see `.claude/skills/nextsession/SKILL.md`) | Result |
|---|---|---|
| iOS tests (`OpenHikerTests`) | `xcodebuild test … -scheme OpenHiker` on `iPhone 17,OS=27.0` | **49/49 pass** |
| watchOS build | `… -scheme 'OpenHiker Watch App'` on `Apple Watch Ultra 3 (49mm),OS=26.5` | builds |
| macOS build | `… -scheme 'OpenHiker macOS' -destination 'platform=macOS'` | builds |
| Android tests | `cd OpenHikerAndroid && ./gradlew test --continue` | all pass (`:core` 320/320, `:app` green) |

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
  with a loop route and an out-and-back route (#44): no arrival at the start, arrival back at the trailhead. Watch
  the GPS indicator for the recheck burst. Check that it ends within a few seconds and does not get stuck
  on, which would drain the battery. Also log `speed` and `speedAccuracy` on the watch in low-power mode: the
  measured-speed safeguard needs `speedAccuracy` ≤ 2 m/s to apply.

### CI

- `ios.yml` builds and tests scheme `OpenHiker`. It is pinned to `macos-15` (PR #40): `macos-latest`
  (Xcode 26.6) had no iOS simulator runtime, so no destination matched.
- `codeql.yml` is disabled for inactivity (last run 2026-04-14). Re-enable it with
  `gh workflow enable codeql.yml` if code scanning is wanted.
- `swift.yml` was deleted in PR #40: it ran `swift build` with no `Package.swift` and failed on every run.
- No CI job runs Android, watchOS or macOS.

## Open GitHub issues

- #23: Android service and ViewModel test coverage.
- #30: missing unit tests for public functions from PR #26 (Android phase 3).

## Known stubs

- **Community route upload** needs a real GitHub bot token on both platforms
  (`Shared/Services/GitHubRouteService.swift:175`, placeholder bytes;
  `OpenHikerAndroid/.../community/GitHubRouteService.kt:544`, empty `OBFUSCATED_TOKEN`).
- **Android cloud sync** skips saved routes and waypoints (`CloudDriveSyncEngine.kt:176`, `:183`, both TODO).
- **README is stale for Android:** its phase table says phase 3 is "In Progress" and phase 4 "Planned", but
  both are merged.
