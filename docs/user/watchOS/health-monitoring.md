# Health Monitoring

OpenHiker integrates with Apple Health to provide real-time health data during your hikes.

## Available Health Metrics

| Metric | Source | Update Frequency |
|--------|--------|-----------------|
| **Heart Rate** | Apple Watch optical sensor | ~1 second during workout |
| **Blood Oxygen (SpO2)** | Apple Watch blood oxygen sensor | ~1 second during workout |
| **UV Index** | Apple WeatherKit (location-based) | Every 10 minutes |
| **Calories** | Computed from heart rate + movement | Continuous |

## Setting Up Health Access

1. Open OpenHiker on your watch
2. Swipe to the **Settings** tab
3. Under **Health**, tap **Authorize** if status shows "Not Authorized"
4. Grant permission for heart rate, blood oxygen, and workout data
5. Toggle **Record Workouts** on to save hikes as Apple Health workouts

## Viewing Health Data

### Stats Dashboard
Swipe up from the map to the **Stats Dashboard** tab. During an active recording:

- **Heart rate** — Large red number with heart icon
- **SpO2** — Cyan percentage with lungs icon
- **UV Index** — Color-coded with WHO danger levels and protection advice

### On the Map
The UV Index badge appears in the bottom-right of the map with color coding.

### On Your iPhone
During an active Apple Watch workout, health data is relayed to the iPhone's Navigate tab in real-time:
- Heart rate (BPM)
- Blood oxygen (SpO2 %)
- UV index

## Apple Health Workouts

When **Record Workouts** is enabled in Settings:

- Starting a GPS recording also starts an Apple Health workout (type: Hiking)
- The workout grants extended background runtime (better GPS tracking)
- After saving, the workout appears in the Apple Health app with:
  - Route map
  - Heart rate graph
  - Distance, duration, elevation
  - Estimated calories

## UV Index Guide

| UV Index | Level | Color | Protection |
|----------|-------|-------|------------|
| 1-2 | Low | Green | No protection needed |
| 3-5 | Moderate | Yellow | Wear sunscreen |
| 6-7 | High | Orange | Seek shade during midday |
| 8-10 | Very High | Red | Avoid sun exposure |
| 11+ | Extreme | Purple | Stay indoors if possible |

The UV index is fetched from Apple WeatherKit based on your current GPS location. It requires an internet connection for the initial reading but the last known value is cached.

## Tips

- **Enable workout recording** for the most accurate heart rate data — the watch increases sensor frequency during workouts
- **SpO2 readings at altitude** can indicate acclimatization issues — if your SpO2 drops below 90%, consider descending
- **Heart rate zones** help pace yourself:
  - < 120 BPM — Easy / conversational pace
  - 120-150 BPM — Moderate effort
  - > 150 BPM — High effort, consider slowing down
