# Cloud Sync Errors Reach the User — Android

Tracked in #72. Apple counterpart: #78 and #81.

## Context

On iOS and macOS, `CloudSyncManager` records every iCloud sync in `CloudSyncStatus` (`Shared/Services/`):
the time of the last clean sync and one "part: reason" entry per failed part. The iOS app shows a red banner
above every tab while the last sync failed, with "Retry" and a close button. macOS shows "Sync failed" in the
sidebar (the tooltip lists the errors) and the errors or the last sync time in Settings → Sync. The upload
and the download of saved hikes, waypoints and planned routes are separate steps, so one failing step does
not stop the others (#81).

On Android, `CloudDriveSyncEngine` already syncs each `SyncChannel` on its own and returns `SyncResult.errors`.
"Sync now" in Settings shows the result, but `SyncWorker` (background sync) only logs it.

## Rule (match Apple)

- Keep the last sync result (time of the last clean sync, error list) where the UI can observe it, for both
  "Sync now" and `SyncWorker`.
- Show the errors outside Settings while the last sync failed (for example a banner), with retry and dismiss.
- Show that a sync is running, so retry and "Sync now" do not seem to do nothing (Apple #84: the retry button
  turns into a spinner).
- Tell a sync folder that is not set up from a failed sync: Apple shows a grey, dismissible "iCloud off"
  notice when no account is signed in, not an error (#84). Apple checks the account at the start of every
  sync, so signing in or out while the app runs is noticed at the next sync.
- Retry only failures that can clear up by themselves, and report the others at once (Apple #86,
  `CloudKitStore.retryAdvice(for:)`). Apple honours a server-requested delay only up to 30 s
  (`CloudSyncManager.maxServerRetryDelay`) and fails the step at once beyond that.

## Status

Done (#72), except for two rules that do not carry over as they stand:

- `SyncStateStore` keeps the last sync's errors (`lastErrors`) and the last clean sync time on disk, so a
  background failure shows the next time the app opens. `CloudDriveSyncEngine.sync` records them and
  publishes `isSyncing`.
- `SyncStatusBanner` (`ui/sync/`) shows them above every tab except full-screen pages, with Retry (a
  spinner while any sync runs) and Dismiss. Settings shows the last clean sync time and the spinner for
  background syncs too.
- A corrupt `sync_state.json` sets `stateWasReset`, which the banner shows until dismissed. It is not a
  sync error, so it does not hold back the last-sync time.
- A revoked folder permission is reported as "Sync folder unavailable", a folder that cannot be found as
  unreachable (the pure `folderErrorResult`). Like Apple's `retryAdvice`, the engine sorts errors into
  ones that may clear by themselves (`isTransient`: an I/O failure not caused by a parse error) and the
  rest. `SyncWorker` returns `Result.retry()` only when every error is transient
  (`SyncResult.retryable`); otherwise, and for both folder errors, it returns `Result.failure()` and waits
  for the next period, so a broken file does not re-upload everything on each backoff retry (#100).
- Choosing the sync folder starts a sync at once, so a stale "choose the folder again" error clears.
  Turning sync off clears the errors, and Retry shows only while sync is on.
- There is no grey "not set up" notice: sync on Android is opt-in, so having no folder is not a problem to
  report.
