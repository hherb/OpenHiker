// Copyright (C) 2024-2026 Dr Horst Herb
//
// This file is part of OpenHiker.
//
// OpenHiker is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// OpenHiker is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with OpenHiker. If not, see <https://www.gnu.org/licenses/>.

import Foundation
import CoreLocation
import Combine

// MARK: - Location Error

/// Errors that can occur during location tracking.
enum LocationError: Error, LocalizedError {
    /// The user denied location access permission.
    case accessDenied

    /// The device was unable to determine its location.
    case locationUnavailable

    /// A user-facing description of the error.
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Location access denied. Please enable in Settings."
        case .locationUnavailable:
            return "Unable to determine location."
        }
    }
}

/// Manages GPS location and heading tracking for the iOS hiking navigation feature.
///
/// Provides continuous location updates, track recording with distance/elevation
/// statistics, and compass heading for map orientation. Mirrors the watch
/// ``LocationManager`` capabilities so the iPhone can serve as a standalone
/// navigation device.
///
/// Three GPS accuracy modes are available:
/// - **High Accuracy**: Best GPS, 5m distance filter
/// - **Balanced**: 10m accuracy, 10m distance filter
/// - **Low Power**: 100m accuracy, 50m distance filter
final class iOSLocationManager: NSObject, ObservableObject {
    /// The underlying Core Location manager.
    private let locationManager = CLLocationManager()

    // MARK: - Published Properties

    /// The most recent location update from Core Location.
    @Published var currentLocation: CLLocation?

    /// The most recent compass heading from Core Location.
    @Published var heading: CLHeading?

    /// The current location authorization status.
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Whether a hike track is currently being recorded.
    @Published var isTracking = false

    /// Any error encountered during location tracking.
    @Published var trackingError: Error?

    /// Recorded GPS points during the current hike track.
    @Published var trackPoints: [CLLocation] = []

    /// Total distance of the current track in meters (incrementally updated).
    @Published private(set) var totalDistance: CLLocationDistance = 0

    /// Total cumulative elevation gain in meters (incrementally updated).
    @Published private(set) var elevationGain: Double = 0

    /// Total cumulative elevation loss in meters (incrementally updated, positive value).
    @Published private(set) var elevationLoss: Double = 0

    /// The current GPS signal quality based on horizontal accuracy.
    ///
    /// Updated with every location update. Views can observe this to show a
    /// warning when accuracy degrades (e.g., in dense forest or canyons).
    @Published private(set) var gpsSignalQuality: GPSSignalQuality = .unknown

    /// The current GPS accuracy mode.
    @Published var gpsMode: GPSMode = .highAccuracy {
        didSet {
            applyGPSSettings()
        }
    }

    // MARK: - GPS Modes

    /// Defines the GPS accuracy presets available for hiking navigation.
    ///
    /// Each mode configures `desiredAccuracy` and `distanceFilter` on the
    /// underlying `CLLocationManager`.
    enum GPSMode: String, CaseIterable {
        /// Best available GPS accuracy with 5m distance filter.
        case highAccuracy = "high"

        /// Nearest-ten-meters accuracy with 10m distance filter.
        case balanced = "balanced"

        /// Hundred-meter accuracy with 50m distance filter.
        case lowPower = "lowpower"

        /// The Core Location desired accuracy for this mode.
        var desiredAccuracy: CLLocationAccuracy {
            switch self {
            case .highAccuracy: return kCLLocationAccuracyBest
            case .balanced: return kCLLocationAccuracyNearestTenMeters
            case .lowPower: return kCLLocationAccuracyHundredMeters
            }
        }

        /// The minimum distance (in meters) a device must move before generating an update.
        var distanceFilter: CLLocationDistance {
            switch self {
            case .highAccuracy: return 5
            case .balanced: return 10
            case .lowPower: return 50
            }
        }

        /// A human-readable description of the mode.
        var description: String {
            switch self {
            case .highAccuracy: return "High Accuracy"
            case .balanced: return "Balanced"
            case .lowPower: return "Low Power"
            }
        }
    }

    /// Describes the current GPS signal quality derived from horizontal accuracy.
    ///
    /// Used by the navigation UI to show a warning indicator when the GPS signal
    /// degrades below usable thresholds.
    enum GPSSignalQuality: String {
        /// No location data received yet.
        case unknown = "Unknown"

        /// Horizontal accuracy <= 10m — excellent for trail navigation.
        case good = "Good"

        /// Horizontal accuracy 10–50m — acceptable but reduced precision.
        case fair = "Fair"

        /// Horizontal accuracy 50–200m — degraded signal, points still recorded
        /// but may be inaccurate. Common in dense forest or canyons.
        case poor = "Poor"

        /// Horizontal accuracy > 200m or negative — essentially no usable signal.
        case none = "No Signal"

        /// Classifies a horizontal accuracy value into a signal quality level.
        ///
        /// - Parameter accuracy: The `CLLocation.horizontalAccuracy` value.
        /// - Returns: The corresponding signal quality.
        static func from(accuracy: CLLocationAccuracy) -> GPSSignalQuality {
            if accuracy < 0 { return .none }
            if accuracy <= 10 { return .good }
            if accuracy <= 50 { return .fair }
            if accuracy <= 200 { return .poor }
            return .none
        }
    }

    // MARK: - Tracking State Persistence

    /// UserDefaults key for the persisted tracking state flag.
    private static let isTrackingKey = "iOSLocationManager.isTracking"

    /// File URL for persisted track points (JSON array of lat/lon/alt/timestamp).
    private static var trackPointsFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("active_track_points.json")
    }

    /// File URL for persisted tracking statistics.
    private static var trackStatsFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("active_track_stats.json")
    }

    // MARK: - Initialization

    /// Initializes the location manager and configures it for hiking use.
    ///
    /// If a tracking session was active when the app was previously terminated,
    /// the track points and statistics are restored and tracking resumes automatically.
    override init() {
        super.init()
        setupLocationManager()
        restoreTrackingStateIfNeeded()
    }

    /// Configures the underlying CLLocationManager with hiking-optimized settings.
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .fitness
        locationManager.showsBackgroundLocationIndicator = true
        applyGPSSettings()
    }

    /// Applies the current GPS mode's accuracy and distance filter settings.
    private func applyGPSSettings() {
        locationManager.desiredAccuracy = gpsMode.desiredAccuracy
        locationManager.distanceFilter = gpsMode.distanceFilter
    }

    // MARK: - Public Methods

    /// Requests "when in use" location authorization from the user.
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Requests "always" location authorization for background tracking.
    func requestAlwaysPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    /// Starts recording a hike track.
    ///
    /// Clears any previous track points, begins location and heading updates,
    /// and sets ``isTracking`` to `true`. The tracking state is persisted to disk
    /// so it can be restored if the app is terminated by iOS.
    ///
    /// If "Always" authorization hasn't been granted yet, it's requested here.
    /// "Always" ensures iOS delivers location updates reliably even when the app
    /// is backgrounded or suspended during a long hike.
    func startTracking() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }

        // Upgrade to "Always" if still on "When In Use" — needed for reliable
        // background tracking during long hikes where the app may be backgrounded
        if authorizationStatus == .authorizedWhenInUse {
            requestAlwaysPermission()
        }

        trackPoints.removeAll()
        totalDistance = 0
        elevationGain = 0
        elevationLoss = 0
        isTracking = true
        trackingError = nil

        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        persistTrackingState()

        print("Started iOS GPS tracking in \(gpsMode.rawValue) mode")
    }

    /// Stops recording the current hike track.
    ///
    /// The recorded ``trackPoints`` remain available for saving.
    /// Clears persisted tracking state since the session is intentionally ended.
    func stopTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        clearPersistedTrackingState()

        print("Stopped iOS GPS tracking. Recorded \(trackPoints.count) points")
    }

    /// Starts continuous location and heading updates without recording a track.
    ///
    /// Used for displaying the user's position on the map without recording.
    func startLocationUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }

        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }

    /// Stops continuous location and heading updates.
    ///
    /// Does nothing if a hike is currently being tracked.
    func stopLocationUpdates() {
        guard !isTracking else { return }
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }

    // MARK: - Track Statistics

    /// Duration of the track from first to last recorded point.
    ///
    /// - Returns: The time interval in seconds, or `nil` if fewer than 2 points exist.
    var duration: TimeInterval? {
        guard let first = trackPoints.first, let last = trackPoints.last else {
            return nil
        }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }

    /// Incrementally updates cached distance and elevation stats when a new point is appended.
    ///
    /// - Parameters:
    ///   - previous: The last recorded track point.
    ///   - current: The new track point being appended.
    private func updateCachedStats(from previous: CLLocation, to current: CLLocation) {
        totalDistance += current.distance(from: previous)

        let elevationDiff = current.altitude - previous.altitude
        if elevationDiff > 0 {
            elevationGain += elevationDiff
        } else if elevationDiff < 0 {
            elevationLoss -= elevationDiff
        }
    }

    // MARK: - State Persistence

    /// Persists the current tracking state (flag + stats) to disk.
    ///
    /// Called when tracking starts and periodically as new points are recorded.
    /// Track points are saved to a JSON file so the session can be recovered
    /// if iOS terminates the app in the background.
    private func persistTrackingState() {
        UserDefaults.standard.set(isTracking, forKey: Self.isTrackingKey)

        // Persist stats
        let stats: [String: Double] = [
            "totalDistance": totalDistance,
            "elevationGain": elevationGain,
            "elevationLoss": elevationLoss
        ]
        if let data = try? JSONSerialization.data(withJSONObject: stats) {
            try? data.write(to: Self.trackStatsFileURL, options: .atomic)
        }
    }

    /// Persists the current track points to disk.
    ///
    /// Called periodically (every 10 points) to avoid excessive I/O while still
    /// ensuring most of the track survives app termination.
    private func persistTrackPoints() {
        let points = trackPoints.map { location -> [String: Double] in
            [
                "lat": location.coordinate.latitude,
                "lon": location.coordinate.longitude,
                "alt": location.altitude,
                "ts": location.timestamp.timeIntervalSince1970,
                "hacc": location.horizontalAccuracy,
                "vacc": location.verticalAccuracy
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: points) else { return }
        try? data.write(to: Self.trackPointsFileURL, options: .atomic)

        // Also update stats
        persistTrackingState()
    }

    /// Restores tracking state after app relaunch if a session was active.
    ///
    /// Reads the persisted flag, track points, and statistics from disk,
    /// then resumes location updates so recording continues seamlessly.
    private func restoreTrackingStateIfNeeded() {
        guard UserDefaults.standard.bool(forKey: Self.isTrackingKey) else { return }

        // Restore track points
        if let data = try? Data(contentsOf: Self.trackPointsFileURL),
           let points = try? JSONSerialization.jsonObject(with: data) as? [[String: Double]] {
            trackPoints = points.compactMap { dict in
                guard let lat = dict["lat"], let lon = dict["lon"],
                      let alt = dict["alt"], let ts = dict["ts"],
                      let hacc = dict["hacc"], let vacc = dict["vacc"] else { return nil }
                return CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    altitude: alt,
                    horizontalAccuracy: hacc,
                    verticalAccuracy: vacc,
                    timestamp: Date(timeIntervalSince1970: ts)
                )
            }
        }

        // Restore stats
        if let data = try? Data(contentsOf: Self.trackStatsFileURL),
           let stats = try? JSONSerialization.jsonObject(with: data) as? [String: Double] {
            totalDistance = stats["totalDistance"] ?? 0
            elevationGain = stats["elevationGain"] ?? 0
            elevationLoss = stats["elevationLoss"] ?? 0
        }

        // Resume tracking
        isTracking = true
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()

        print("Restored iOS tracking session with \(trackPoints.count) points")
    }

    /// Removes all persisted tracking state files from disk.
    ///
    /// Called when the user intentionally stops tracking.
    private func clearPersistedTrackingState() {
        UserDefaults.standard.set(false, forKey: Self.isTrackingKey)
        try? FileManager.default.removeItem(at: Self.trackPointsFileURL)
        try? FileManager.default.removeItem(at: Self.trackStatsFileURL)
    }
}

// MARK: - CLLocationManagerDelegate

extension iOSLocationManager: CLLocationManagerDelegate {
    /// Called when the user changes location authorization.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("iOS location authorized")
        case .denied, .restricted:
            print("iOS location access denied")
            trackingError = LocationError.accessDenied
        case .notDetermined:
            print("iOS location authorization not determined")
        @unknown default:
            break
        }
    }

    /// Called when new locations are available from Core Location.
    ///
    /// Updates ``gpsSignalQuality`` on every update so the UI can warn the user
    /// about degraded GPS. Only truly invalid readings (negative accuracy) are
    /// discarded. Low-accuracy points (> 100m) are still recorded during tracking
    /// so that gaps don't appear in the track — the slightly inaccurate path is
    /// preferable to a missing segment. Elevation stats are skipped for low-accuracy
    /// points to avoid altitude noise.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Update signal quality for every update (including poor ones)
        gpsSignalQuality = GPSSignalQuality.from(accuracy: location.horizontalAccuracy)

        // Discard only truly invalid readings (negative accuracy = no fix at all)
        guard location.horizontalAccuracy >= 0 else { return }

        currentLocation = location

        if isTracking {
            let isHighAccuracy = location.horizontalAccuracy < 100

            if let lastPoint = trackPoints.last {
                let distance = location.distance(from: lastPoint)
                if distance >= gpsMode.distanceFilter {
                    // Only update elevation stats for high-accuracy points to avoid
                    // barometric altitude noise from degraded GPS readings
                    if isHighAccuracy {
                        updateCachedStats(from: lastPoint, to: location)
                    } else {
                        // Still count distance even for low-accuracy points
                        totalDistance += distance
                    }
                    trackPoints.append(location)

                    // Persist track to disk every 10 points for crash recovery
                    if trackPoints.count % 10 == 0 {
                        persistTrackPoints()
                    }
                }
            } else {
                trackPoints.append(location)
            }
        }
    }

    /// Called when a new compass heading is available.
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        heading = newHeading
    }

    /// Called when a location update fails.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("iOS location error: \(error.localizedDescription)")

        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                trackingError = LocationError.accessDenied
            case .locationUnknown:
                break
            default:
                trackingError = error
            }
        } else {
            trackingError = error
        }
    }
}
