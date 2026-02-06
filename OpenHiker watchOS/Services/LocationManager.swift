import Foundation
import CoreLocation
import Combine

/// Manages GPS location tracking for the watch app
final class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()

    // MARK: - Published Properties

    @Published var currentLocation: CLLocation?
    @Published var heading: CLHeading?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking = false
    @Published var trackingError: Error?

    /// Recorded track points during a hike
    @Published var trackPoints: [CLLocation] = []

    /// Current GPS mode
    @Published var gpsMode: GPSMode = .balanced {
        didSet {
            updateLocationManagerSettings()
        }
    }

    // MARK: - GPS Modes

    enum GPSMode: String, CaseIterable {
        case highAccuracy = "high"
        case balanced = "balanced"
        case lowPower = "lowpower"

        var desiredAccuracy: CLLocationAccuracy {
            switch self {
            case .highAccuracy: return kCLLocationAccuracyBest
            case .balanced: return kCLLocationAccuracyNearestTenMeters
            case .lowPower: return kCLLocationAccuracyHundredMeters
            }
        }

        var distanceFilter: CLLocationDistance {
            switch self {
            case .highAccuracy: return 5
            case .balanced: return 10
            case .lowPower: return 50
            }
        }

        var description: String {
            switch self {
            case .highAccuracy: return "High Accuracy (6-12h battery)"
            case .balanced: return "Balanced (12-18h battery)"
            case .lowPower: return "Low Power (35h+ battery)"
            }
        }
    }

    // MARK: - Initialization

    override init() {
        super.init()
        setupLocationManager()
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        #if os(iOS)
        locationManager.pausesLocationUpdatesAutomatically = false
        #endif
        locationManager.activityType = .fitness
        updateLocationManagerSettings()
    }

    private func updateLocationManagerSettings() {
        locationManager.desiredAccuracy = gpsMode.desiredAccuracy
        locationManager.distanceFilter = gpsMode.distanceFilter
    }

    // MARK: - Public Methods

    /// Request location permissions
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Request always-on location permissions (for background tracking)
    func requestAlwaysPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    /// Start tracking location
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

    /// Stop tracking location
    func stopTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()

        print("Stopped GPS tracking. Recorded \(trackPoints.count) points")
    }

    /// Get a single location update
    func requestSingleLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }

        locationManager.requestLocation()
    }

    /// Export track as GPX data
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

    /// Total distance of the current track in meters
    var totalDistance: CLLocationDistance {
        guard trackPoints.count > 1 else { return 0 }

        var distance: CLLocationDistance = 0
        for i in 1..<trackPoints.count {
            distance += trackPoints[i].distance(from: trackPoints[i - 1])
        }
        return distance
    }

    /// Total elevation gain in meters
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

    /// Duration of the track
    var duration: TimeInterval? {
        guard let first = trackPoints.first, let last = trackPoints.last else {
            return nil
        }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
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

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Only use heading if it's accurate enough
        guard newHeading.headingAccuracy >= 0 else { return }
        heading = newHeading
    }

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

enum LocationError: Error, LocalizedError {
    case accessDenied
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Location access denied. Please enable in Settings."
        case .locationUnavailable:
            return "Unable to determine location."
        }
    }
}
