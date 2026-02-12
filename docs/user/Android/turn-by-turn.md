# Turn-by-Turn Navigation

Follow a planned route with live GPS tracking, turn instructions, and off-route warnings.

## Starting Navigation

1. Open a saved route from the **Routes** tab
2. Tap **Start Navigation**
3. The navigation screen opens with full-screen map and guidance overlay

## Navigation Display

<!-- Screenshot: Turn-by-turn navigation screen -->
> **[Screenshot placeholder]** *Full-screen navigation showing map with route line, GPS dot, turn instruction card at top reading "Turn left — Ridge Trail — 200m", and progress bar at bottom*

### Turn Instruction Card (Top)
- **Turn direction** — Verb describing the action (e.g., "Turn left")
- **Trail/road name** — Where the turn occurs
- **Distance** — Large, easy-to-read countdown to the next turn (meters or kilometers)

### Progress Bar (Bottom)
- Visual route completion indicator (0–100%)

### Live Statistics
- Distance walked
- Remaining distance
- Elapsed time

## Haptic Feedback

Your phone vibrates at key navigation moments:

| Event | When | Vibration |
|-------|------|-----------|
| **Approaching turn** | ~100m before | Gentle pulse |
| **At turn** | ~30m | Stronger pulse |
| **Off route** | >50m from route | Alert pattern |
| **Arrived** | At destination | Success pattern |

Haptic feedback can be toggled on/off in Settings.

## Off-Route Warning

If you stray more than **50 meters** from the planned route:

- A **red banner** slides in from the top
- Shows distance from the route
- Haptic alert vibrates your phone
- The warning clears automatically when you return within **30 meters** of the route

The hysteresis (different trigger and clear distances) prevents the warning from flapping on and off when you're near the route edge.

## Arrival

When you reach the destination:
- A **green "Arrived" banner** appears
- Success haptic feedback

## Stopping Navigation

1. Tap the **Stop** button
2. A confirmation dialog appears
3. Confirm to end navigation

## Audio Cues

For accessibility, OpenHiker supports audio cues as an alternative to haptic feedback. Enable in **Settings → Navigation → Audio cues**.

## Tips

- **Keep the screen on** — Enable "Keep screen on during navigation" in Settings to prevent the display from turning off
- **Use heading-up mode** — Tap the compass button so the map rotates with your walking direction
- **Watch your battery** — GPS navigation uses significant power; bring a portable charger for long hikes
