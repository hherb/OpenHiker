# OpenHiker Privacy Policy

**Effective Date:** February 2026
**Last Updated:** February 2026

## Overview

OpenHiker is an open-source offline hiking navigation application licensed under the GNU Affero General Public License v3.0 (AGPL-3.0). This privacy policy explains what data the app collects, how it is used, and what information (if any) is shared with third parties.

OpenHiker is designed with privacy as a core principle. The app operates primarily offline, collects no personal data, and does not include any analytics, advertising, or tracking frameworks.

## Location Data

OpenHiker accesses your device's GPS location **solely for on-device map navigation and hike tracking**. Location data is used to:

- Display your current position on the map
- Record hike tracks when you choose to start a recording
- Provide turn-by-turn navigation guidance along routes
- Calculate distance, elevation gain, and other hike statistics

**No location data is ever transmitted to any server.** All GPS data remains on your device and is processed entirely locally. Recorded hike tracks are stored in a local SQLite database on your device and are never uploaded unless you explicitly choose to export or share them.

## Tile Downloads and Network Requests

When you download map regions for offline use, the app fetches map tile images from OpenTopoMap and/or OpenStreetMap tile servers. These requests are standard HTTPS requests and are subject to the privacy policies of those services:

- **OpenTopoMap:** [https://opentopomap.org](https://opentopomap.org)
- **OpenStreetMap:** [https://wiki.openstreetmap.org/wiki/Privacy_Policy](https://wiki.openstreetmap.org/wiki/Privacy_Policy)

These tile servers may log standard HTTP request information (such as your IP address and the tiles requested). OpenHiker has no control over these external services. Once tiles are downloaded, they are stored locally on your device and no further network requests are needed for map display.

## User Accounts and Authentication

OpenHiker does **not** require or support user accounts. There is no sign-up, login, or authentication of any kind. The app has no concept of user identity.

## Analytics, Advertising, and Tracking

OpenHiker contains:

- **No analytics SDKs** (no Google Analytics, Firebase Analytics, Crashlytics, or similar)
- **No advertising frameworks** (no AdMob, ad networks, or similar)
- **No user tracking** (no fingerprinting, usage telemetry, or behavioral analysis)
- **No third-party data collection SDKs** of any kind

## Personal Data Collection

OpenHiker collects **no personal data**. The app does not collect, store, or transmit:

- Names, email addresses, or contact information
- Device identifiers or advertising IDs
- Usage patterns or behavioral data
- Crash reports (unless you manually choose to share them)

## Data Stored Locally on Your Device

The following data is stored locally on your device and remains entirely under your control:

| Data Type | Storage Format | Purpose |
|---|---|---|
| Map tiles | MBTiles (SQLite) | Offline map display |
| Hike tracks | SQLite database | Recorded hike history and statistics |
| Waypoints | SQLite database | User-created points of interest |
| Routes | SQLite database | Planned and saved navigation routes |
| App preferences | Jetpack DataStore | User settings (units, tile sources, etc.) |

You can delete any of this data at any time through the app's interface or by clearing the app's storage in Android system settings.

## Cloud Sync (Opt-In)

OpenHiker offers an optional cloud sync feature that is **disabled by default**. If you choose to enable it, you select the storage destination yourself:

- **Google Drive:** Data is stored in your own Google Drive account, governed by Google's privacy policy.
- **Local folder (via Storage Access Framework):** Data is saved to a folder of your choosing on the device or connected storage.

Cloud sync transfers only your map regions, routes, waypoints, and hike tracks. No personal information or usage data is included in sync payloads. You can disable cloud sync at any time, and no data is retained on any server controlled by OpenHiker.

## Open Source Transparency

OpenHiker is licensed under the AGPL-3.0 license. The complete source code is publicly available, allowing anyone to independently verify the privacy claims made in this policy. You can inspect every network request, every database operation, and every permission usage in the source code.

**Source Code:** [https://github.com/hherb/OpenHiker](https://github.com/hherb/OpenHiker)

## Children's Privacy

OpenHiker does not knowingly collect any data from children or any other users. Since the app collects no personal data whatsoever, it does not pose any specific privacy concerns for users of any age.

## Changes to This Policy

If this privacy policy is updated, the changes will be reflected in the app's source code repository and the "Last Updated" date at the top of this document will be revised. Since OpenHiker collects no data, material changes to this policy are unlikely.

## Contact

If you have questions or concerns about this privacy policy, please open an issue on the project's GitHub repository:

**GitHub Issues:** [https://github.com/hherb/OpenHiker/issues](https://github.com/hherb/OpenHiker/issues)
