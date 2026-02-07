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

#if os(macOS)
import SwiftUI
import MapKit

/// Available map display styles for the macOS region selector.
///
/// Controls both the map appearance during browsing and the default tile server
/// for downloads. "Roads" uses Apple's native MapKit, while "Trails" and "Cycling"
/// use tile overlays from OpenTopoMap and CyclOSM respectively.
enum MacMapViewStyle: String, CaseIterable {
    case standard = "Roads"
    case hiking = "Trails"
    case cycling = "Cycling"

    /// The tile URL template for the overlay, or `nil` for Apple Maps.
    var tileURLTemplate: String? {
        switch self {
        case .standard: return nil
        case .hiking: return "https://tile.opentopomap.org/{z}/{x}/{y}.png"
        case .cycling: return "https://a.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png"
        }
    }

    /// The default ``TileDownloader/TileServer`` for downloads when this style is active.
    var defaultDownloadServer: TileDownloader.TileServer {
        switch self {
        case .standard: return .osmTopo
        case .hiking: return .osmTopo
        case .cycling: return .cyclosm
        }
    }
}

/// An NSViewRepresentable wrapping `MKMapView` with custom tile overlay support for macOS.
///
/// Used to display OpenTopoMap (hiking trails, contour lines) or CyclOSM (cycling routes)
/// tiles in the macOS region selector. SwiftUI's `Map` does not support `MKTileOverlay`,
/// so this wrapper is required for custom tile server rendering.
///
/// Supports:
/// - Custom tile overlays that replace Apple Maps base tiles
/// - Selected region polygon overlay (blue, semi-transparent)
/// - Bidirectional camera position synchronisation with the parent view
struct MacTrailMapView: NSViewRepresentable {

    // MARK: - Tile Overlay Configuration

    /// Maximum zoom level supported by the tile servers (OpenTopoMap / CyclOSM).
    static let tileMaxZoom = 18

    /// Minimum zoom level supported by the tile servers.
    static let tileMinZoom = 1

    /// Standard web mercator tile size in points.
    static let tileSize = CGSize(width: 256, height: 256)

    /// Minimum coordinate change (in degrees) before programmatically repositioning the map.
    /// Prevents fighting with user gestures and triggering feedback loops.
    static let coordinateChangeThreshold: Double = 0.0001

    /// Minimum span change (in degrees latitude) before programmatically repositioning the map.
    static let spanChangeThreshold: Double = 0.01

    // MARK: - Overlay Styling

    /// Fill opacity for the selected region polygon overlay.
    static let selectionFillAlpha: CGFloat = 0.2

    /// Stroke width for the selected region polygon.
    static let selectionStrokeWidth: CGFloat = 2

    // MARK: - Properties

    /// The tile URL template with `{z}`, `{x}`, `{y}` placeholders, or `nil` for Apple Maps.
    let tileURLTemplate: String?

    /// The current map center coordinate (bidirectional binding).
    @Binding var center: CLLocationCoordinate2D

    /// The current map span in degrees latitude (bidirectional binding).
    @Binding var span: Double

    /// The selected region to highlight with a polygon overlay, or `nil` if none.
    let selectedRegion: MKCoordinateRegion?

    /// Called when the user pans or zooms the map.
    var onRegionChange: ((CLLocationCoordinate2D, Double) -> Void)?

    // MARK: - NSViewRepresentable

    /// Creates and configures the underlying `MKMapView` with initial region and optional tile overlay.
    ///
    /// - Parameter context: The NSViewRepresentable context providing the coordinator.
    /// - Returns: A configured `MKMapView`.
    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsZoomControls = true

        // Add tile overlay if we have a template
        if let template = tileURLTemplate {
            let overlay = MKTileOverlay(urlTemplate: template)
            overlay.canReplaceMapContent = true
            overlay.maximumZ = Self.tileMaxZoom
            overlay.minimumZ = Self.tileMinZoom
            overlay.tileSize = Self.tileSize
            mapView.addOverlay(overlay, level: .aboveLabels)
            context.coordinator.currentTileOverlay = overlay
            context.coordinator.lastTileTemplate = template
        }

        // Set initial region
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
        mapView.setRegion(region, animated: false)

        return mapView
    }

    /// Updates the `MKMapView` when SwiftUI state changes (tile template, position, overlays).
    ///
    /// Swaps the tile overlay if the URL template changed, repositions the map if the center/span
    /// moved significantly, and syncs shape overlays.
    ///
    /// - Parameters:
    ///   - mapView: The existing `MKMapView` to update.
    ///   - context: The NSViewRepresentable context providing the coordinator.
    func updateNSView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator

        // Swap tile overlay when the URL template changes
        let newTemplate = tileURLTemplate
        if coordinator.lastTileTemplate != newTemplate {
            // Remove existing tile overlay
            if let old = coordinator.currentTileOverlay {
                mapView.removeOverlay(old)
                coordinator.currentTileOverlay = nil
            }

            // Add new tile overlay if template is provided
            if let template = newTemplate {
                let overlay = MKTileOverlay(urlTemplate: template)
                overlay.canReplaceMapContent = true
                overlay.maximumZ = Self.tileMaxZoom
                overlay.minimumZ = Self.tileMinZoom
                overlay.tileSize = Self.tileSize
                mapView.addOverlay(overlay, level: .aboveLabels)
                coordinator.currentTileOverlay = overlay
            }
            coordinator.lastTileTemplate = newTemplate
        }

        // Only reposition the map programmatically when the centre has moved significantly,
        // to avoid fighting with user gestures and triggering feedback loops.
        let latDiff = abs(mapView.centerCoordinate.latitude - center.latitude)
        let lonDiff = abs(mapView.centerCoordinate.longitude - center.longitude)
        let spanDiff = abs(mapView.region.span.latitudeDelta - span)
        if (latDiff > Self.coordinateChangeThreshold || lonDiff > Self.coordinateChangeThreshold || spanDiff > Self.spanChangeThreshold)
            && !coordinator.isUpdatingFromMap
        {
            let region = MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            )
            mapView.setRegion(region, animated: true)
        }

        // Sync overlays (selected region polygon)
        updateShapeOverlays(mapView, coordinator: coordinator)
    }

    // MARK: - Shape Overlay Management

    /// Replaces the selected region polygon overlay.
    ///
    /// Removes any previously added polygon from the map, then re-adds it if a region
    /// is currently selected. The tile overlay is left untouched.
    ///
    /// - Parameters:
    ///   - mapView: The `MKMapView` to update.
    ///   - coordinator: The coordinator holding references to current shape overlays.
    private func updateShapeOverlays(_ mapView: MKMapView, coordinator: Coordinator) {
        // Remove previous selection polygon
        if let old = coordinator.selectionPolygon {
            mapView.removeOverlay(old)
            coordinator.selectionPolygon = nil
        }

        // Add selected region polygon
        if let region = selectedRegion {
            let latDelta = region.span.latitudeDelta / 2
            let lonDelta = region.span.longitudeDelta / 2
            let c = region.center
            let coords = [
                CLLocationCoordinate2D(latitude: c.latitude + latDelta, longitude: c.longitude - lonDelta),
                CLLocationCoordinate2D(latitude: c.latitude + latDelta, longitude: c.longitude + lonDelta),
                CLLocationCoordinate2D(latitude: c.latitude - latDelta, longitude: c.longitude + lonDelta),
                CLLocationCoordinate2D(latitude: c.latitude - latDelta, longitude: c.longitude - lonDelta),
            ]
            let polygon = MKPolygon(coordinates: coords, count: coords.count)
            mapView.addOverlay(polygon, level: .aboveLabels)
            coordinator.selectionPolygon = polygon
        }
    }

    // MARK: - Coordinator

    /// Creates the coordinator that acts as the `MKMapViewDelegate` for this view.
    ///
    /// - Returns: A new ``Coordinator`` linked to this `MacTrailMapView`.
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Coordinator handling `MKMapViewDelegate` callbacks for the macOS trail map.
    ///
    /// Manages overlay rendering, region change reporting, and holds strong references
    /// to the current tile overlay and shape overlays so they can be swapped on updates.
    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: MacTrailMapView
        var currentTileOverlay: MKTileOverlay?
        var lastTileTemplate: String?
        var selectionPolygon: MKPolygon?

        /// Flag to prevent feedback loops when the map reports a region change
        /// that was triggered by the binding update.
        var isUpdatingFromMap = false

        /// Initialises the coordinator with a reference to the parent `MacTrailMapView`.
        ///
        /// - Parameter parent: The owning `MacTrailMapView` instance.
        init(parent: MacTrailMapView) {
            self.parent = parent
            self.lastTileTemplate = parent.tileURLTemplate
        }

        /// Returns the appropriate overlay renderer for tile overlays and selection polygons.
        ///
        /// - Parameters:
        ///   - mapView: The map view requesting the renderer.
        ///   - overlay: The overlay to render.
        /// - Returns: A configured `MKOverlayRenderer` for the overlay type.
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(overlay: tileOverlay)
            }
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = NSColor.systemBlue.withAlphaComponent(MacTrailMapView.selectionFillAlpha)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = MacTrailMapView.selectionStrokeWidth
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        /// Called when the map's visible region changes (pan, zoom, or rotation).
        ///
        /// Updates the parent's center/span bindings and invokes the `onRegionChange` callback.
        /// Sets `isUpdatingFromMap` to prevent the resulting SwiftUI update from repositioning
        /// the map again (feedback loop prevention).
        ///
        /// - Parameters:
        ///   - mapView: The map view whose region changed.
        ///   - animated: Whether the change was animated.
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            isUpdatingFromMap = true
            let newCenter = mapView.centerCoordinate
            let newSpan = mapView.region.span.latitudeDelta
            parent.center = newCenter
            parent.span = newSpan
            parent.onRegionChange?(newCenter, newSpan)
            // Reset flag on next run-loop pass, after SwiftUI has processed the binding update.
            DispatchQueue.main.async { [weak self] in
                self?.isUpdatingFromMap = false
            }
        }
    }
}

// MARK: - macOS Location Manager

/// A Core Location manager for the macOS companion app.
///
/// Provides current location and authorization handling for centering the map
/// on the user's position. macOS requires explicit authorization via Info.plist
/// and the `CLLocationManager.requestWhenInUseAuthorization()` call.
class LocationManagerMac: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// The underlying Core Location manager.
    private let manager = CLLocationManager()

    /// The most recent location update from Core Location.
    @Published var currentLocation: CLLocation?

    /// The current location authorization status.
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Flag indicating the map should center on the next location update.
    var shouldCenterOnNextUpdate = false

    /// Initializes the location manager with standard accuracy settings.
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    /// Requests location permission and starts location updates if already authorized.
    ///
    /// If authorization has not been determined, requests "when in use" permission.
    /// If already authorized, immediately starts updating location.
    func requestLocationPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorized:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    /// Called by Core Location when new locations are available.
    ///
    /// Updates ``currentLocation`` with the most recent location.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
    }

    /// Called by Core Location when a location update fails.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("macOS Location error: \(error.localizedDescription)")
    }

    /// Called when the user changes location authorization.
    ///
    /// Automatically starts location updates when permission is granted.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorized {
            manager.startUpdatingLocation()
        }
    }
}

#endif
