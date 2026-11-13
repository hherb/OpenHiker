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
  history, waypoints, export, community routes, cloud-drive sync, settings. Last Android change: `9cb9251`
  (2026-02-12).
- **Last code PR overall:** #39 (2026-06-16), Apple and `Shared/` bug fixes from review (crashes, GPS and SpO2
  accuracy, throttling, rate limiting).
- **User manuals** for all four platforms are in `docs/user/` (commit `0913fe4`).

## Baseline (checked 2026-11-14, Xcode 27.2)

| Gate | Command (see `.claude/skills/nextsession/SKILL.md`) | Result |
|---|---|---|
| iOS tests (`OpenHikerTests`) | `xcodebuild test … -scheme OpenHiker` on `iPhone 17,OS=27.0` | **25/25 pass** |
| watchOS build | `… -scheme 'OpenHiker Watch App'` on `Apple Watch Ultra 3 (49mm),OS=26.5` | builds |
| macOS build | `… -scheme 'OpenHiker macOS' -destination 'platform=macOS'` | builds |
| Android tests | `cd OpenHikerAndroid && ./gradlew test --continue` | `:app` passes; **`:core` 318 run, 4 fail** |

The older destinations (iPhone 16 Pro, Apple Watch Ultra 2) only have old runtimes installed (iOS 18.4, watchOS
11.x), and the iPhone 16 Pro run failed to find a destination (exit 70). CLAUDE.md and the skills now pin current
runtimes: `iPhone 17,OS=27.0` and `Apple Watch Ultra 3 (49mm),OS=26.5` (watchOS 27.0 has only an Ultra 4).

## In flight

### Project config changes (PR from `chore/session-skills-handover`)

These were staged before the 2026-11-14 session, never committed, and are now in that PR's second commit:

- **Info.plist keys moved to build settings.** Location and HealthKit usage strings,
  `LSSupportsOpeningDocumentsInPlace` and `WKWatchOnly` went from `Info.plist` into `INFOPLIST_KEY_*` in
  `project.pbxproj`. Most of the watchOS `Info.plist` is gone. The HealthKit and WeatherKit framework build
  files got Xcode-generated IDs (`6F81…`), which breaks the `1B…` convention in CLAUDE.md. That is harmless
  but inconsistent.
- **Removed in finalcheck:** iOS background modes `processing` and `fetch`, and the watchOS entitlement
  `com.apple.developer.healthkit.background-delivery`. Nothing used them: no BGTaskScheduler code, no
  `BGTaskSchedulerPermittedIdentifiers` (an App Store upload fails without it), no `enableBackgroundDelivery`.
  Add them back together with the code that needs them.
- **Shared schemes** `OpenHiker`, `OpenHiker Watch App` and (added in finalcheck) `OpenHiker macOS`.
- `Screenshots/` (9 iPhone PNGs, about 14 MB) and `report.md` (code statistics, 2026-02-10).
- **Verify:** all three Apple gates above pass with these changes staged (checked 2026-11-14). Also run the iOS
  app once on a device to confirm the location and HealthKit permission prompts still appear.

### Android `:core` test failures (pre-existing)

Found 2026-11-14. These are not tracked in an issue yet:

- `TileCoordinateTest` › *fromLatLon converts Innsbruck … zoom 14*: expected x ≈ 8725, got 8710. The code
  is right: floor((11.39 + 180) / 360 · 2^14) = 8710. Fix the test's expectation.
- `RouteFollowerTest` › *approaching turn …* (line 158) and *isAtTurn …* (line 184): the thresholds and the
  test geometry disagree.
- `OsmXmlParserTest` › *parse handles long way with many nodes* (line 266): `SAXParseException` "processing
  instruction target matching [xX][mM][lL] is not allowed". The test builds XML with leading whitespace before
  `<?xml`. Most likely a `trimIndent()` or raw-string problem in the test, not in the parser.

**Verify:** `cd OpenHikerAndroid && ./gradlew :core:test --rerun-tasks`.

### CI

- `ios.yml` (build and test scheme `OpenHiker`) was green on `main` in June. On PR #40 (2026-11-13) it failed:
  the `macos-latest` runner (Xcode 26.6) had no iOS simulator runtime, so no destination matched.
- `codeql.yml` is disabled for inactivity (last run 2026-04-14). Re-enable it with
  `gh workflow enable codeql.yml` if code scanning is wanted.
- **`swift.yml` has failed on every run:** it calls `swift build`, but there is no `Package.swift`. Delete
  the workflow or replace it with watchOS and macOS `xcodebuild` jobs (ROADMAP: CI coverage).
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
