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

    // MARK: - Initialization

    /// Initializes the location manager and configures it for hiking use.
    override init() {
        super.init()
        setupLocationManager()
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
    /// and sets ``isTracking`` to `true`.
    func startTracking() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }

        trackPoints.removeAll()
        totalDistance = 0
        elevationGain = 0
        elevationLoss = 0
        isTracking = true
        trackingError = nil

        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()

        print("Started iOS GPS tracking in \(gpsMode.rawValue) mode")
    }

    /// Stops recording the current hike track.
    ///
    /// The recorded ``trackPoints`` remain available for saving.
    func stopTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()

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
    /// Filters out readings with horizontal accuracy >= 100m or negative accuracy.
    /// When tracking, only appends points that exceed the GPS mode's distance filter.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 100 else {
            return
        }

        currentLocation = location

        if isTracking {
            if let lastPoint = trackPoints.last {
                let distance = location.distance(from: lastPoint)
                if distance >= gpsMode.distanceFilter {
                    updateCachedStats(from: lastPoint, to: location)
                    trackPoints.append(location)
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
