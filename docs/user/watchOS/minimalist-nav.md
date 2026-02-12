# Minimalist Navigation

Minimalist Navigation is a battery-saving mode that shows only turn-by-turn directions without rendering the map.

## Why Use It?

Map rendering with SpriteKit uses significant battery. Minimalist Navigation:

- **No map rendering** — Uses static SwiftUI instead of 60fps SpriteKit
- **Only redraws on GPS updates** — Not continuously
- **Can extend battery life by 50-75%** compared to full map mode
- Perfect for **long hikes** where you just need turn directions

## Enabling Minimalist Navigation

1. Swipe to **Settings**
2. Toggle **Minimalist Nav** on
3. Now when you start navigating a route, it opens in this view instead of the map

You can also swipe to the bottom tab to access it directly.

## What You See

<!-- Screenshot: Minimalist navigation view -->
> **[Screenshot placeholder]** *Minimalist navigation showing a large left-turn arrow, "Turn left onto Blue Ridge Trail", and "200m" distance, with heart rate and SpO2 at the bottom*

### Turn Direction
- **Large direction icon** — Clear arrow showing your next turn
- **Instruction text** — Trail/road name and action
- **Distance countdown** — Meters or feet to the next turn

### Health Bar
At the bottom, two compact readings:
- **Heart rate** with color-coded zone:
  - Green: < 120 BPM (easy)
  - Yellow: 120-150 BPM (moderate)
  - Red: > 150 BPM (hard)
- **SpO2** percentage

### Progress Section
- Thin progress bar showing route completion
- Remaining distance
- Completion percentage
- **"Show Map"** button — Tap to switch to the full map view if needed

## Off-Route Warning

If you stray more than 50m from the route:

- The entire screen turns **red**
- A **warning triangle** and **"OFF ROUTE"** text appear
- **"Return to trail"** message is displayed
- Haptic feedback alerts you

## When No Route Is Active

If you open Minimalist Navigation without an active route, it shows a placeholder message directing you to select a route from the Routes tab.

## Tips

- **Use this for well-marked trails** where you mainly need turn confirmations, not continuous map reference
- **Switch to full map** anytime by tapping "Show Map" — useful when the terrain is confusing
- **Combine with heading-up mode** — If you switch to the map briefly, heading-up mode helps orient the map to your walking direction
