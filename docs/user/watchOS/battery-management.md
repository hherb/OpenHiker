# Battery Management

Battery life is critical for hiking. OpenHiker provides multiple ways to extend your watch's runtime.

## GPS Accuracy Modes

Choose your GPS accuracy in **Settings** based on your hike:

| Mode | GPS Accuracy | Distance Filter | Expected Battery Life |
|------|-------------|----------------|----------------------|
| **High** | Best (5m) | 5m | 6-12 hours |
| **Balanced** | Good (10m) | 10m | 12-18 hours |
| **Low Power** | Basic (100m) | 50m | 35+ hours |

### Which Mode to Choose?

- **High** — Technical terrain, narrow switchbacks, dense trail junctions. Use when you need precise positioning.
- **Balanced** — Most day hikes. Good accuracy with reasonable battery life. This is the recommended default.
- **Low Power** — Multi-day hikes, thru-hiking, or when you just need basic tracking. Position updates are less frequent but battery lasts much longer.

## Battery-Saving Tips

### Use Minimalist Navigation
Switch to [Minimalist Navigation](minimalist-nav.md) mode to avoid continuous map rendering. This can extend battery life by **50-75%** compared to full map mode.

### Lower GPS Accuracy
Switch from High to Balanced or Low Power mode. The difference in track quality is minimal for most hikes, but the battery savings are significant.

### Disable UV Index
In Settings, toggle off **Show UV Index** to prevent periodic weather data fetches.

### Turn Off Always-On Display
In watchOS Settings > Display & Brightness, disable Always On. The watch screen turns off when your wrist is down, saving significant power.

## Low Battery Mode

When your watch reaches **5% battery**, OpenHiker automatically activates emergency mode:

### What Happens
1. The full UI is replaced with a **minimal black screen** (OLED power saving)
2. Your current track is **saved immediately** as an emergency recovery file
3. GPS switches to **low-power mode** automatically
4. Only essential information is displayed

### What You See
- **Distance** traveled
- **Heart rate** (if available)
- **SpO2** (if available)
- **Battery percentage** with yellow warning banner
- **Elapsed time**
- **"Stop Hike"** button

<!-- Screenshot: Low battery tracking view -->
> **[Screenshot placeholder]** *Black screen with yellow "Battery 5%" banner, showing distance 12.4 km, heart rate 118 BPM, SpO2 95%, and a red "Stop Hike" button*

### Emergency Save

Your track data is automatically saved, so even if the battery dies completely:
- Your GPS track is preserved
- It can be recovered on the next launch (or from the iPhone sync)
- No data is lost

## Battery Life Estimates

These are approximate for a continuous hike with GPS tracking:

| Configuration | Estimate |
|---------------|----------|
| High GPS + Full Map + Health | 6-8 hours |
| High GPS + Minimalist Nav + Health | 10-14 hours |
| Balanced GPS + Full Map + Health | 12-16 hours |
| Balanced GPS + Minimalist Nav + Health | 18-24 hours |
| Low Power GPS + Minimalist Nav | 35+ hours |

Actual battery life depends on your Apple Watch model, age, temperature, and cellular/Wi-Fi activity.
