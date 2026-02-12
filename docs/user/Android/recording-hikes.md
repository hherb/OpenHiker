# Recording Hikes

OpenHiker records your GPS track in the background with full statistics and crash recovery.

## Starting a Recording

From the **Navigate** tab, tap the **Record** button to start GPS tracking. A **foreground service notification** appears in your notification shade showing:

- Current distance
- Elapsed time
- **Pause/Resume** button
- **Stop** button

<!-- Screenshot: Recording notification -->
> **[Screenshot placeholder]** *Android notification showing "OpenHiker — Recording: 3.2 km, 45:12" with Pause and Stop buttons*

## During Your Hike

While recording, OpenHiker captures:

- **GPS coordinates** at regular intervals (based on your accuracy setting)
- **Altitude** readings
- **Walking vs resting time** (movement threshold: 0.3 m/s)
- **Total distance** via Haversine calculations between GPS points
- **Elevation gain/loss** with 3-meter noise filtering
- **Average and max speed**

### Background Tracking

Recording continues when:
- The screen is off
- You switch to another app
- The phone is locked

The foreground service notification keeps the tracking alive.

### Pause and Resume

From the notification or the app:
- **Pause** — Stops accumulating distance and time; GPS remains on
- **Resume** — Continues tracking from where you left off

## Auto-Save Protection

Your track is automatically saved as a **draft every 5 minutes** using compressed binary format. This protects against:

- App crashes
- System killing the service (low memory)
- Battery death

If the app closes unexpectedly, your track data is preserved and can be recovered.

## Stopping and Saving

1. Tap **Stop** (from the notification or the app)
2. Enter a **hike name**
3. Tap **Save**

The hike appears in your **Hikes** tab with full statistics.

## What Gets Saved

- Compressed GPS track (zlib binary format)
- All computed statistics
- Associated waypoints
- Track point count
