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
import MapKit
import CoreLocation

// MARK: - Directions Request Handler

/// Handles incoming direction requests from Apple Maps when OpenHiker is
/// registered as a routing app for pedestrian navigation.
///
/// When a user asks for walking/hiking directions in Apple Maps and OpenHiker
/// is listed as an option, iOS sends an ``MKDirectionsRequest`` encoded as a URL.
/// This handler decodes the request, finds a matching downloaded region with
/// routing data, computes the route using ``RoutingEngine``, and creates a
/// ``PlannedRoute`` ready for display and watch transfer.
///
/// ## Apple Maps Integration Flow
/// 1. User taps "Directions" in Apple Maps → selects OpenHiker
/// 2. iOS launches OpenHiker via URL scheme with ``MKDirectionsRequest``
/// 3. ``handle(url:)`` decodes source/destination from the URL
/// 4. ``findCoveringRegion(for:and:)`` locates a downloaded region
/// 5. ``RoutingEngine`` computes the offline route
/// 6. Result is saved as a ``PlannedRoute`` in ``PlannedRouteStore``
///
/// ## Requirements
/// The app must declare the following in `Info.plist`:
/// - `MKDirectionsApplicationSupportedModes`: `[MKDirectionsModePedestrian]`
/// - Document type: `com.apple.maps.directionsrequest`
/// - A `directions_coverage.geojson` uploaded to App Store Connect
final class DirectionsRequestHandler: ObservableObject {

    /// Shared singleton instance.
    static let shared = DirectionsRequestHandler()

    // MARK: - Published State

    /// The most recently computed route from an Apple Maps directions request.
    ///
    /// Views observe this to present the route detail UI when the app is opened
    /// from Apple Maps.
    @Published var pendingRoute: PlannedRoute?

    /// Whether a directions request is currently being processed.
    @Published var isProcessing: Bool = false

    /// A user-facing error message if the directions request failed.
    @Published var errorMessage: String?

    // MARK: - Notification

    /// Posted when a new route has been computed from an Apple Maps directions request.
    ///
    /// The notification's `object` is the ``PlannedRoute`` that was created.
    /// UI layers can observe this to navigate to the route detail view.
    static let routeComputedNotification = Notification.Name("DirectionsRequestRouteComputed")

    // MARK: - Public API

    /// Attempts to handle an incoming URL as an Apple Maps directions request.
    ///
    /// Call this from the SwiftUI `.onOpenURL` modifier. If the URL is not a
    /// valid ``MKDirectionsRequest``, this method returns `false` without side
    /// effects so other URL handlers can try.
    ///
    /// - Parameter url: The URL received by the app.
    /// - Returns: `true` if the URL was a directions request and processing began,
    ///   `false` otherwise.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard MKDirections.Request.isDirectionsRequest(url) else {
            return false
        }

        let request = MKDirections.Request(contentsOf: url)

        guard let source = request.source,
              let destination = request.destination else {
            errorMessage = "Apple Maps did not provide both a start and end point."
            print("[DirectionsRequestHandler] Missing source or destination in MKDirectionsRequest")
            return true
        }

        let sourceCoord = source.placemark.coordinate
        let destCoord = destination.placemark.coordinate

        // Build a descriptive route name from placemark info
        let routeName = buildRouteName(source: source, destination: destination)

        print("[DirectionsRequestHandler] Received directions request: "
              + "\(sourceCoord.latitude),\(sourceCoord.longitude) → "
              + "\(destCoord.latitude),\(destCoord.longitude)")

        processDirectionsRequest(
            from: sourceCoord,
            to: destCoord,
            name: routeName
        )

        return true
    }

    // MARK: - Private Implementation

    /// Processes the directions request asynchronously: finds a region, computes
    /// the route, and saves the result.
    ///
    /// - Parameters:
    ///   - from: Start coordinate from Apple Maps.
    ///   - to: End coordinate from Apple Maps.
    ///   - name: Human-readable route name.
    private func processDirectionsRequest(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        name: String
    ) {
        DispatchQueue.main.async {
            self.isProcessing = true
            self.errorMessage = nil
            self.pendingRoute = nil
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                // 1. Find a downloaded region that covers both endpoints
                guard let (region, routingDbURL) = self.findCoveringRegion(
                    for: from,
                    and: to
                ) else {
                    throw DirectionsError.noRegionCoverage(from: from, to: to)
                }

                // 2. Open the routing store for that region
                let routingStore = RoutingStore(path: routingDbURL.path)
                try routingStore.open()
                defer { routingStore.close() }

                // 3. Compute the route using the offline routing engine
                let engine = RoutingEngine(store: routingStore)
                let computedRoute = try engine.findRoute(
                    from: from,
                    to: to,
                    mode: .hiking
                )

                // 4. Convert to a PlannedRoute and save
                let plannedRoute = PlannedRoute.from(
                    computedRoute: computedRoute,
                    name: name,
                    mode: .hiking,
                    regionId: region.id
                )

                try PlannedRouteStore.shared.save(plannedRoute)

                DispatchQueue.main.async {
                    self.pendingRoute = plannedRoute
                    self.isProcessing = false
                    print("[DirectionsRequestHandler] Route computed: "
                          + "\(plannedRoute.formattedDistance), "
                          + "\(plannedRoute.formattedDuration)")

                    NotificationCenter.default.post(
                        name: DirectionsRequestHandler.routeComputedNotification,
                        object: plannedRoute
                    )
                }
            } catch let error as DirectionsError {
                DispatchQueue.main.async {
                    self.errorMessage = error.userMessage
                    self.isProcessing = false
                    print("[DirectionsRequestHandler] Error: \(error.userMessage)")
                }
            } catch let error as RoutingError {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                    print("[DirectionsRequestHandler] Routing error: \(error)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to compute route: \(error.localizedDescription)"
                    self.isProcessing = false
                    print("[DirectionsRequestHandler] Unexpected error: \(error)")
                }
            }
        }
    }

    /// Searches downloaded regions for one that contains both the start and end
    /// coordinates and has routing data available.
    ///
    /// Prefers regions with routing data. If multiple regions match, the first
    /// one found is returned (regions are sorted newest-first by ``RegionStorage``).
    ///
    /// - Parameters:
    ///   - start: The route start coordinate.
    ///   - end: The route end coordinate.
    /// - Returns: A tuple of the matching ``Region`` and its routing database URL,
    ///   or `nil` if no suitable region is found.
    private func findCoveringRegion(
        for start: CLLocationCoordinate2D,
        and end: CLLocationCoordinate2D
    ) -> (Region, URL)? {
        let storage = RegionStorage.shared
        let regions = storage.regions

        for region in regions {
            // Must have routing data
            guard region.hasRoutingData else { continue }

            // Must contain both endpoints
            guard region.boundingBox.contains(start),
                  region.boundingBox.contains(end) else { continue }

            // Verify the routing database file actually exists
            let routingURL = storage.routingDbURL(for: region)
            guard FileManager.default.fileExists(atPath: routingURL.path) else { continue }

            return (region, routingURL)
        }

        return nil
    }

    /// Builds a human-readable route name from Apple Maps placemarks.
    ///
    /// Uses the placemark name if available, falling back to a coordinate-based
    /// description.
    ///
    /// - Parameters:
    ///   - source: The start map item from Apple Maps.
    ///   - destination: The end map item from Apple Maps.
    /// - Returns: A descriptive route name like "Trailhead → Summit Peak".
    private func buildRouteName(source: MKMapItem, destination: MKMapItem) -> String {
        let sourceName = source.name
            ?? formatCoordinate(source.placemark.coordinate)
        let destName = destination.name
            ?? formatCoordinate(destination.placemark.coordinate)

        return "\(sourceName) → \(destName)"
    }

    /// Formats a coordinate as a short string for use in route names when no
    /// placemark name is available.
    ///
    /// - Parameter coordinate: The coordinate to format.
    /// - Returns: A string like "47.42°N 10.99°E".
    private func formatCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        let latDir = coordinate.latitude >= 0 ? "N" : "S"
        let lonDir = coordinate.longitude >= 0 ? "E" : "W"
        return String(format: "%.2f°%@ %.2f°%@",
                      abs(coordinate.latitude), latDir,
                      abs(coordinate.longitude), lonDir)
    }
}

// MARK: - Directions Error

/// Errors specific to handling Apple Maps directions requests.
///
/// These are translated to user-facing messages for display in an alert.
enum DirectionsError: Error {
    /// Neither the start nor end coordinate falls within any downloaded region
    /// that has routing data.
    case noRegionCoverage(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D)

    /// A user-friendly error message explaining what went wrong and what the
    /// user can do to fix it.
    var userMessage: String {
        switch self {
        case .noRegionCoverage:
            return "No downloaded region covers both the start and end of this route. "
                + "Please download a map region that includes both locations, "
                + "with routing data enabled, then try again from Apple Maps."
        }
    }
}
