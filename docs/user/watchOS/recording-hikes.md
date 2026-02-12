# Recording Hikes

Record your GPS track, distance, elevation, and health data while hiking.

## Starting a Recording

Tap the **Play** button in the map toolbar. The button turns red (Stop) to indicate recording is active.

Your GPS track appears as a **purple trail** on the map as you walk.

## During Your Hike

While recording, OpenHiker captures:

- **GPS coordinates** at regular intervals (based on your accuracy setting)
- **Altitude** readings
- **Walking vs resting time** (based on movement speed)
- **Total distance** via cumulative GPS points
- **Health data** — heart rate, SpO2, and calories (if HealthKit is authorized)

### Viewing Live Stats

Swipe up to the **Stats Dashboard** tab to see real-time metrics:

- Heart rate (BPM)
- Blood oxygen (SpO2 %)
- Distance walked
- Elevation gain
- Duration
- Average speed
- UV index

<!-- Screenshot: Stats dashboard during active hike -->
> **[Screenshot placeholder]** *Stats dashboard showing heart rate 132 BPM, SpO2 96%, distance 4.2 km, elevation gain 320m, duration 1:45:12*

## Auto-Save Protection

Your track is automatically saved every **5 minutes** as a recovery file. This protects against:

- App crashes
- System termination (low memory)
- Battery death

### Crash Recovery

If the app closes unexpectedly during a hike, the next time you launch it:

1. A recovery alert appears showing:
   - Date of the interrupted hike
   - Distance recorded
   - Number of track points
2. Choose **"Recover & Save"** to restore your hike
3. Or **"Discard"** if you don't need it

## Stopping and Saving

1. Tap the **Stop** button (red) in the toolbar
2. The **Save Hike** sheet appears:
   - Pre-filled name based on the date
   - Editable name field (tap to edit, use dictation)
   - Optional comment field (dictation)
   - Statistics summary (distance, elevation, duration, walking/resting time, heart rate)
3. Tap **Save** to store the hike

<!-- Screenshot: Save hike sheet -->
> **[Screenshot placeholder]** *Save Hike sheet with "Morning Hike" name, distance 6.8 km, elevation +450m, duration 2:15:30*

## What Happens on Save

- Track points are compressed and stored in the local database
- A GPX file is generated
- The hike is transferred to your iPhone when reachable
- Health data (heart rate samples, calories) are included if available

## Live iPhone Sync

During an active recording, your track is synced to your iPhone every **5 minutes** as a partial route. This means:

- Your iPhone shows your progress in near-real-time
- If your watch runs out of battery, the iPhone has most of your track
- Health data (heart rate, SpO2, UV) is relayed continuously (~4 times per second)
