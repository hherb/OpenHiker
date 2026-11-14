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
    the gate starts afresh as for a first fix (#51, this branch). `iOSRouteGuidance.currentDate` is the
    clock seam the tests use for this.
  - Android port of the gate: `docs/TODO/Android/gps-fix-plausibility.md`. Android does not project fixes
    onto the route, so the leg choice does not apply there.
- **Last PRs:** #50 (2026-11-14, #49, future-dated fixes), #48 (#46 and #47, guidance start), #45 (#44
  and the plausibility gate).
- **User manuals** for all four platforms are in `docs/user/` (commit `0913fe4`).

## Baseline (checked 2026-11-14, Xcode 27.2)

| Gate | Command (see `.claude/skills/nextsession/SKILL.md`) | Result |
|---|---|---|
| iOS tests (`OpenHikerTests`) | `xcodebuild test … -scheme OpenHiker` on `iPhone 17,OS=27.0` | **65/65 pass** |
| watchOS build | `… -scheme 'OpenHiker Watch App'` on `Apple Watch Ultra 3 (49mm),OS=26.5` | builds |
| macOS build | `… -scheme 'OpenHiker macOS' -destination 'platform=macOS'` | builds |
| Android tests | `cd OpenHikerAndroid && ./gradlew test --continue` | all pass (`:core` 321/321, `:app` green) |

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
