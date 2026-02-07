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

#if os(iOS)
import SwiftUI
import MapKit

/// Available map display styles for the region selector.
///
/// Controls both the map appearance during browsing and the default tile server
/// for downloads. "Roads" uses Apple's native MapKit, while "Trails" and "Cycling"
/// use tile overlays from OpenTopoMap and CyclOSM respectively.
enum MapViewStyle: String, CaseIterable {
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

/// A UIViewRepresentable wrapping `MKMapView` with custom tile overlay support.
///
/// Used to display OpenTopoMap (hiking trails, contour lines) or CyclOSM (cycling routes)
/// tiles in the region selector. SwiftUI's `Map` does not support `MKTileOverlay`, so this
/// wrapper is required for custom tile server rendering.
///
/// Supports:
/// - Custom tile overlays that replace Apple Maps base tiles
/// - Waypoint annotations with orange markers matching the SwiftUI map style
/// - Selected region polygon overlay (blue, semi-transparent)
/// - Track recording breadcrumb polyline (orange)
/// - Bidirectional camera position synchronisation with the parent view
struct TrailMapView: UIViewRepresentable {
    /// The tile URL template with `{z}`, `{x}`, `{y}` placeholders.
    let tileURLTemplate: String

    /// The current map center coordinate (bidirectional binding).
    @Binding var center: CLLocationCoordinate2D

    /// The current map span in degrees latitude (bidirectional binding).
    @Binding var span: Double

    /// Waypoints to display as map annotations.
    let waypoints: [Waypoint]

    /// The selected region to highlight with a polygon overlay, or `nil` if none.
    let selectedRegion: MKCoordinateRegion?

    /// Track recording coordinates to display as an orange polyline.
    let trackCoordinates: [CLLocationCoordinate2D]

    /// Called when the user pans or zooms the map.
    var onRegionChange: ((CLLocationCoordinate2D, Double) -> Void)?

    /// Called when the user taps a waypoint annotation.
    var onWaypointTapped: ((Waypoint) -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true

        // Add the tile overlay that replaces Apple Maps base tiles
        let overlay = MKTileOverlay(urlTemplate: tileURLTemplate)
        overlay.canReplaceMapContent = true
        overlay.maximumZ = 18
        overlay.minimumZ = 1
        overlay.tileSize = CGSize(width: 256, height: 256)
        mapView.addOverlay(overlay, level: .aboveLabels)
        context.coordinator.currentTileOverlay = overlay
        context.coordinator.lastTileTemplate = tileURLTemplate

        // Set initial region
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
        mapView.setRegion(region, animated: false)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator

        // Swap tile overlay when the URL template changes (e.g. switching Trails ↔ Cycling)
        if coordinator.lastTileTemplate != tileURLTemplate {
            if let old = coordinator.currentTileOverlay {
                mapView.removeOverlay(old)
            }
            let overlay = MKTileOverlay(urlTemplate: tileURLTemplate)
            overlay.canReplaceMapContent = true
            overlay.maximumZ = 18
            overlay.minimumZ = 1
            overlay.tileSize = CGSize(width: 256, height: 256)
            mapView.addOverlay(overlay, level: .aboveLabels)
            coordinator.currentTileOverlay = overlay
            coordinator.lastTileTemplate = tileURLTemplate
        }

        // Only reposition the map programmatically when the centre has moved significantly,
        // to avoid fighting with user gestures and triggering feedback loops.
        let latDiff = abs(mapView.centerCoordinate.latitude - center.latitude)
        let lonDiff = abs(mapView.centerCoordinate.longitude - center.longitude)
        let spanDiff = abs(mapView.region.span.latitudeDelta - span)
        if (latDiff > 0.0001 || lonDiff > 0.0001 || spanDiff > 0.01)
            && !coordinator.isUpdatingFromMap
        {
            let region = MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            )
            mapView.setRegion(region, animated: true)
        }

        // Sync annotations
        updateAnnotations(mapView)

        // Sync overlays (selected region polygon + track polyline)
        updateShapeOverlays(mapView, coordinator: coordinator)
    }

    // MARK: - Annotation Management

    /// Incrementally adds and removes waypoint annotations to match the current `waypoints` array.
    private func updateAnnotations(_ mapView: MKMapView) {
        let existing = mapView.annotations.compactMap { $0 as? WaypointAnnotation }
        let existingIDs = Set(existing.map { $0.waypoint.id })
        let desiredIDs = Set(waypoints.map { $0.id })

        for annotation in existing where !desiredIDs.contains(annotation.waypoint.id) {
            mapView.removeAnnotation(annotation)
        }
        for waypoint in waypoints where !existingIDs.contains(waypoint.id) {
            mapView.addAnnotation(WaypointAnnotation(waypoint: waypoint))
        }
    }

    // MARK: - Shape Overlay Management

    /// Replaces the selected region polygon and track polyline overlays.
    private func updateShapeOverlays(_ mapView: MKMapView, coordinator: Coordinator) {
        // Remove previous shape overlays
        if let old = coordinator.selectionPolygon {
            mapView.removeOverlay(old)
            coordinator.selectionPolygon = nil
        }
        if let old = coordinator.trackPolyline {
            mapView.removeOverlay(old)
            coordinator.trackPolyline = nil
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

        // Add track breadcrumb polyline
        if trackCoordinates.count >= 2 {
            let polyline = MKPolyline(coordinates: trackCoordinates, count: trackCoordinates.count)
            mapView.addOverlay(polyline, level: .aboveLabels)
            coordinator.trackPolyline = polyline
        }
    }

    // MARK: - Coordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Coordinator handling `MKMapViewDelegate` callbacks for the trail map.
    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: TrailMapView
        var currentTileOverlay: MKTileOverlay?
        var lastTileTemplate: String
        var selectionPolygon: MKPolygon?
        var trackPolyline: MKPolyline?

        /// Flag to prevent feedback loops when the map reports a region change
        /// that was triggered by the binding update.
        var isUpdatingFromMap = false

        init(parent: TrailMapView) {
            self.parent = parent
            self.lastTileTemplate = parent.tileURLTemplate
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(overlay: tileOverlay)
            }
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.2)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 2
                return renderer
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemOrange
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

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

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let waypointAnnotation = annotation as? WaypointAnnotation else { return nil }

            let identifier = "WaypointPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)

            view.annotation = annotation
            view.markerTintColor = .systemOrange
            view.glyphImage = UIImage(systemName: waypointAnnotation.waypoint.category.iconName)
            view.titleVisibility = .adaptive
            view.canShowCallout = true
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let waypointAnnotation = annotation as? WaypointAnnotation else { return }
            parent.onWaypointTapped?(waypointAnnotation.waypoint)
            mapView.deselectAnnotation(annotation, animated: false)
        }
    }
}

// MARK: - Waypoint Annotation

/// An `MKAnnotation` subclass for displaying waypoints on the `MKMapView`.
///
/// Wraps a ``Waypoint`` value and exposes its coordinate and label as MKAnnotation properties.
class WaypointAnnotation: NSObject, MKAnnotation {
    /// The underlying waypoint model.
    let waypoint: Waypoint

    /// The waypoint's geographic coordinate.
    var coordinate: CLLocationCoordinate2D {
        waypoint.coordinate
    }

    /// The annotation title, using the waypoint label or category name.
    var title: String? {
        waypoint.label.isEmpty ? waypoint.category.displayName : waypoint.label
    }

    /// Creates an annotation from a waypoint.
    ///
    /// - Parameter waypoint: The waypoint to display.
    init(waypoint: Waypoint) {
        self.waypoint = waypoint
    }
}

#endif
