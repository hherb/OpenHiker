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

## Status

Todo.
