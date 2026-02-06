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

/// Manages GPS location and heading tracking for the watchOS hiking app.
///
/// This class wraps Core Location to provide:
/// - Continuous location and compass heading updates
/// - Track recording with configurable GPS accuracy modes
/// - Track statistics (distance, elevation gain, duration)
/// - GPX export of recorded tracks
///
/// Three GPS modes are available, each trading accuracy for battery life:
/// - **High Accuracy**: Best GPS, 5m filter (6-12h battery)
/// - **Balanced**: 10m accuracy, 10m filter (12-18h battery)
/// - **Low Power**: 100m accuracy, 50m filter (35h+ battery)
final class LocationManager: NSObject, ObservableObject {
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

    /// The current GPS accuracy mode. Changing this updates the location manager settings.
    @Published var gpsMode: GPSMode = .balanced {
        didSet {
            updateLocationManagerSettings()
        }
    }

    // MARK: - GPS Modes

    /// Defines the GPS accuracy presets available for hiking.
    ///
    /// Each mode configures `desiredAccuracy` and `distanceFilter` on the
    /// underlying `CLLocationManager`, balancing position precision against
    /// Apple Watch battery consumption.
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

        /// A human-readable description including estimated battery life.
        var description: String {
            switch self {
            case .highAccuracy: return "High Accuracy (6-12h battery)"
            case .balanced: return "Balanced (12-18h battery)"
            case .lowPower: return "Low Power (35h+ battery)"
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
    ///
    /// Enables background location updates and fitness activity type.
    /// On iOS, also disables automatic pausing of location updates.
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        #if os(iOS)
        locationManager.pausesLocationUpdatesAutomatically = false
        #endif
        locationManager.activityType = .fitness
        updateLocationManagerSettings()
    }

    /// Applies the current GPS mode's accuracy and distance filter settings.
    private func updateLocationManagerSettings() {
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
    /// and sets ``isTracking`` to `true`. If location permission has not been
    /// granted, requests it first.
    func startTracking() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }

        trackPoints.removeAll()
        isTracking = true
        trackingError = nil

        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()

        print("Started GPS tracking in \(gpsMode.rawValue) mode")
    }

    /// Stops recording the current hike track.
    ///
    /// Sets ``isTracking`` to `false` and stops location/heading updates.
    /// The recorded ``trackPoints`` remain available for export.
    func stopTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()

        print("Stopped GPS tracking. Recorded \(trackPoints.count) points")
    }

    /// Starts continuous location and heading updates without recording a track.
    ///
    /// Used for displaying the user's position on the map when not actively
    /// recording a hike. If location permission has not been granted, requests it first.
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
    /// Does nothing if a hike is currently being tracked (``isTracking`` is `true`),
    /// to avoid interrupting the recording.
    func stopLocationUpdates() {
        guard !isTracking else { return }
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }

    /// Requests a single location update.
    ///
    /// Useful for getting the user's current position without starting continuous
    /// updates. If location permission has not been granted, requests it first.
    func requestSingleLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }

        locationManager.requestLocation()
    }

    /// Exports the recorded track as GPX (GPS Exchange Format) XML data.
    ///
    /// Creates a standard GPX 1.1 document with a single track segment containing
    /// all recorded points with latitude, longitude, elevation, and timestamp.
    ///
    /// - Returns: UTF-8 encoded GPX XML data, or `nil` if no track points exist.
    func exportTrackAsGPX() -> Data? {
        guard !trackPoints.isEmpty else { return nil }

        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="OpenHiker">
          <trk>
            <name>Hike - \(Date().ISO8601Format())</name>
            <trkseg>

        """

        for point in trackPoints {
            let timestamp = ISO8601DateFormatter().string(from: point.timestamp)
            gpx += """
              <trkpt lat="\(point.coordinate.latitude)" lon="\(point.coordinate.longitude)">
                <ele>\(point.altitude)</ele>
                <time>\(timestamp)</time>
              </trkpt>

            """
        }

        gpx += """
            </trkseg>
          </trk>
        </gpx>
        """

        return gpx.data(using: .utf8)
    }

    // MARK: - Track Statistics

    /// Total distance of the current track in meters.
    ///
    /// Calculated as the sum of distances between consecutive track points.
    var totalDistance: CLLocationDistance {
        guard trackPoints.count > 1 else { return 0 }

        var distance: CLLocationDistance = 0
        for i in 1..<trackPoints.count {
            distance += trackPoints[i].distance(from: trackPoints[i - 1])
        }
        return distance
    }

    /// Total cumulative elevation gain in meters.
    ///
    /// Only positive altitude changes between consecutive points are summed;
    /// descents are ignored.
    var elevationGain: Double {
        guard trackPoints.count > 1 else { return 0 }

        var gain: Double = 0
        for i in 1..<trackPoints.count {
            let diff = trackPoints[i].altitude - trackPoints[i - 1].altitude
            if diff > 0 {
                gain += diff
            }
        }
        return gain
    }

    /// Total cumulative elevation loss in meters (positive value).
    ///
    /// Only negative altitude changes between consecutive points are summed
    /// and returned as a positive value.
    var elevationLoss: Double {
        guard trackPoints.count > 1 else { return 0 }

        var loss: Double = 0
        for i in 1..<trackPoints.count {
            let diff = trackPoints[i].altitude - trackPoints[i - 1].altitude
            if diff < 0 {
                loss -= diff
            }
        }
        return loss
    }

    /// Duration of the track from first to last recorded point.
    ///
    /// - Returns: The time interval in seconds, or `nil` if fewer than 2 points exist.
    var duration: TimeInterval? {
        guard let first = trackPoints.first, let last = trackPoints.last else {
            return nil
        }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    /// Called when the user changes location authorization.
    ///
    /// Logs the new status and sets ``trackingError`` if access is denied.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location authorized")
        case .denied, .restricted:
            print("Location access denied")
            trackingError = LocationError.accessDenied
        case .notDetermined:
            print("Location authorization not determined")
        @unknown default:
            break
        }
    }

    /// Called when new locations are available from Core Location.
    ///
    /// Filters out readings with horizontal accuracy >= 100m or negative accuracy
    /// (indicating invalid data). When tracking, only appends points that exceed
    /// the current GPS mode's distance filter from the last recorded point.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Filter out inaccurate readings
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 100 else {
            return
        }

        currentLocation = location

        if isTracking {
            // Only add point if it's significantly different from the last one
            if let lastPoint = trackPoints.last {
                let distance = location.distance(from: lastPoint)
                if distance >= gpsMode.distanceFilter {
                    trackPoints.append(location)
                }
            } else {
                trackPoints.append(location)
            }
        }
    }

    /// Called when a new compass heading is available.
    ///
    /// Only accepts headings with non-negative accuracy (negative means invalid).
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Only use heading if it's accurate enough
        guard newHeading.headingAccuracy >= 0 else { return }
        heading = newHeading
    }

    /// Called when a location update fails.
    ///
    /// Handles specific Core Location error codes:
    /// - `.denied`: Sets ``trackingError`` to ``LocationError/accessDenied``
    /// - `.locationUnknown`: Temporary error, ignored (auto-retries)
    /// - Other errors: Stored in ``trackingError``
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")

        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                trackingError = LocationError.accessDenied
            case .locationUnknown:
                // Temporary error, will retry automatically
                break
            default:
                trackingError = error
            }
        } else {
            trackingError = error
        }
    }
}

// MARK: - Location Errors

/// Error types for location-related failures in the watch app.
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
