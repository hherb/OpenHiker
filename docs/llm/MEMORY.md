# OpenHiker Project Memory

## Project Structure
- Dual-platform: iOS companion + standalone watchOS app
- `Shared/` compiled into both targets (models, storage)
- watchOS uses SpriteKit for map rendering (not SwiftUI)
- No third-party dependencies; Apple frameworks + SQLite3 only
- AGPL-3.0 license; all files need copyright header

## Key Patterns
- Models: `Codable + Sendable + Identifiable` convention
- Singletons: `WatchConnectivityReceiver.shared` with `@StateObject` injection
- Environment objects injected at `OpenHikerWatchApp` level
- `@AppStorage` for user preferences
- Thread safety: serial DispatchQueues for SQLite, HKHealthStore is thread-safe

## Xcode Project (pbxproj)
- ID format: `2A...` for iOS file refs, `2B...` for watchOS, `1A...` for iOS build files, `1B...` for watchOS
- Shared files need build file entries in BOTH targets (different IDs, same file ref)
- Groups: `5A...` iOS, `5B...` watchOS, `5C...` Shared
- watchOS target: `6B0000010000000000000001`
- iOS target: `6A0000010000000000000001`

## Phase 1 Complete
- `HikeStatistics` shared model, `HikeStatsFormatter`, `CalorieEstimator`
- `HikeStatsOverlay` view with auto-hide
- `HealthKitManager` with workout session, HR/SpO2 queries, route builder
- HealthKit entitlements, Info.plist entries, framework linked
- Developer docs at `docs/developer/hike-metrics-healthkit.md`

## Dev Rules (from docs/llm/general_golden_rules.md)
1. Clean separation of concerns
2. Prefer reusable pure functions
3. Doc strings for everything (junior-friendly)
4. No magic numbers (use config constants)
5. Unit tests for public functions
6. Never truncate data
7. Network calls need retry + exponential backoff
8. All errors must be handled, logged, reported
9. Research unfamiliar APIs first
10. Keep cross-platform compatibility in mind
