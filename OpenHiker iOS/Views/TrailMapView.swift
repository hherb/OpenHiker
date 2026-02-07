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

    /// Stroke width for the track recording polyline.
    static let trackStrokeWidth: CGFloat = 4

    // MARK: - Properties

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

    // MARK: - UIViewRepresentable

    /// Creates and configures the underlying `MKMapView` with a tile overlay and initial region.
    ///
    /// - Parameter context: The UIViewRepresentable context providing the coordinator.
    /// - Returns: A configured `MKMapView` displaying the tile overlay.
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true

        // Add the tile overlay that replaces Apple Maps base tiles
        let overlay = MKTileOverlay(urlTemplate: tileURLTemplate)
        overlay.canReplaceMapContent = true
        overlay.maximumZ = Self.tileMaxZoom
        overlay.minimumZ = Self.tileMinZoom
        overlay.tileSize = Self.tileSize
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

    /// Updates the `MKMapView` when SwiftUI state changes (tile template, position, annotations, overlays).
    ///
    /// Swaps the tile overlay if the URL template changed, repositions the map if the center/span
    /// moved significantly, and incrementally syncs annotations and shape overlays.
    ///
    /// - Parameters:
    ///   - mapView: The existing `MKMapView` to update.
    ///   - context: The UIViewRepresentable context providing the coordinator.
    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator

        // Swap tile overlay when the URL template changes (e.g. switching Trails ↔ Cycling)
        if coordinator.lastTileTemplate != tileURLTemplate {
            if let old = coordinator.currentTileOverlay {
                mapView.removeOverlay(old)
            }
            let overlay = MKTileOverlay(urlTemplate: tileURLTemplate)
            overlay.canReplaceMapContent = true
            overlay.maximumZ = Self.tileMaxZoom
            overlay.minimumZ = Self.tileMinZoom
            overlay.tileSize = Self.tileSize
            mapView.addOverlay(overlay, level: .aboveLabels)
            coordinator.currentTileOverlay = overlay
            coordinator.lastTileTemplate = tileURLTemplate
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

        // Sync annotations
        updateAnnotations(mapView)

        // Sync overlays (selected region polygon + track polyline)
        updateShapeOverlays(mapView, coordinator: coordinator)
    }

    // MARK: - Annotation Management

    /// Incrementally adds, removes, and updates waypoint annotations to match the current `waypoints` array.
    ///
    /// Compares existing annotations against the desired waypoint list by ID, then checks
    /// for property changes (label, category) on annotations that remain. This ensures the
    /// map reflects edits to existing waypoints without removing all annotations each frame.
    ///
    /// - Parameter mapView: The `MKMapView` whose annotations should be synchronised.
    private func updateAnnotations(_ mapView: MKMapView) {
        let existing = mapView.annotations.compactMap { $0 as? WaypointAnnotation }
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.waypoint.id, $0) })
        let desiredByID = Dictionary(uniqueKeysWithValues: waypoints.map { ($0.id, $0) })

        // Remove annotations whose waypoint was deleted
        for annotation in existing where desiredByID[annotation.waypoint.id] == nil {
            mapView.removeAnnotation(annotation)
        }

        for waypoint in waypoints {
            if let existingAnnotation = existingByID[waypoint.id] {
                // Update in-place if the waypoint's properties changed
                if existingAnnotation.waypoint != waypoint {
                    mapView.removeAnnotation(existingAnnotation)
                    mapView.addAnnotation(WaypointAnnotation(waypoint: waypoint))
                }
            } else {
                // Add new annotation
                mapView.addAnnotation(WaypointAnnotation(waypoint: waypoint))
            }
        }
    }

    // MARK: - Shape Overlay Management

    /// Replaces the selected region polygon and track polyline overlays.
    ///
    /// Removes any previously added shape overlays (polygon and polyline) from the map,
    /// then re-adds them if the current state warrants it. The tile overlay is left untouched.
    ///
    /// - Parameters:
    ///   - mapView: The `MKMapView` to update.
    ///   - coordinator: The coordinator holding references to current shape overlays.
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

    /// Creates the coordinator that acts as the `MKMapViewDelegate` for this view.
    ///
    /// - Returns: A new ``Coordinator`` linked to this `TrailMapView`.
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Coordinator handling `MKMapViewDelegate` callbacks for the trail map.
    ///
    /// Manages overlay rendering, region change reporting, annotation views,
    /// and waypoint tap handling. Holds strong references to the current tile overlay
    /// and shape overlays so they can be swapped or removed on updates.
    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: TrailMapView
        var currentTileOverlay: MKTileOverlay?
        var lastTileTemplate: String
        var selectionPolygon: MKPolygon?
        var trackPolyline: MKPolyline?

        /// Flag to prevent feedback loops when the map reports a region change
        /// that was triggered by the binding update.
        var isUpdatingFromMap = false

        /// Initialises the coordinator with a reference to the parent `TrailMapView`.
        ///
        /// - Parameter parent: The owning `TrailMapView` instance.
        init(parent: TrailMapView) {
            self.parent = parent
            self.lastTileTemplate = parent.tileURLTemplate
        }

        /// Returns the appropriate overlay renderer for tile overlays, selection polygons, and track polylines.
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
                renderer.fillColor = UIColor.systemBlue.withAlphaComponent(TrailMapView.selectionFillAlpha)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = TrailMapView.selectionStrokeWidth
                return renderer
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemOrange
                renderer.lineWidth = TrailMapView.trackStrokeWidth
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

        /// Returns a styled annotation view for waypoint annotations.
        ///
        /// Uses `MKMarkerAnnotationView` with an orange tint and the waypoint's category
        /// icon. Non-waypoint annotations (e.g. user location) return `nil` to use the default.
        ///
        /// - Parameters:
        ///   - mapView: The map view requesting the annotation view.
        ///   - annotation: The annotation to display.
        /// - Returns: A configured `MKMarkerAnnotationView`, or `nil` for non-waypoint annotations.
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

        /// Handles waypoint annotation selection by invoking the parent's `onWaypointTapped` callback.
        ///
        /// Immediately deselects the annotation so the callout does not linger.
        ///
        /// - Parameters:
        ///   - mapView: The map view where the annotation was selected.
        ///   - annotation: The selected annotation.
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
