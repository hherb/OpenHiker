# ROADMAP

Planned work that is not started yet. Where to start on an item is in `HANDOVER.md`. Remove an item here once
it has landed. The original phased plan (phases 1–6, all done on Apple platforms) is kept for history in
`docs/planning/roadmap.md`.

---

## Health of the codebase (do first)

| Item | What | Where |
|---|---|---|
| **Android test coverage** | Service and ViewModel tests; tests for phase 3's public functions | #23, #30 |
| **Turn haptics (Apple)** | Fix the early instruction advance; share a tested pure function | #41 |
| **CI coverage** | Add jobs that build watchOS and macOS; add a `./gradlew test` job for Android | `.github/workflows/` |
| **README** | Bring the Android status table and "What's Next" up to date | `README.md` |

## Feature parity

| Feature | iOS | watchOS | macOS | Android | Spec |
|---|---|---|---|---|---|
| Trail overlay rendering from the routing DB (`routing_edges`) | todo | **done** | todo | todo | `docs/TODO/<platform>/trail-overlay-rendering.md` |
| Cloud sync of saved routes and waypoints | done | n/a (via iPhone) | done | todo (TODO stubs in `CloudDriveSyncEngine.kt`) | — |

## Release blockers

- **Community route upload:** provision a GitHub bot token and embed it, obfuscated, on Apple and Android
  (`GitHubRouteService`, both platforms). Until then, uploads cannot work.
