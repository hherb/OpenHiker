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

// MARK: - Route Planning Map View

/// A `UIViewRepresentable` wrapping `MKMapView` with offline topographic tile overlay support.
///
/// Used for route planning (interactive: tap to place pins) and route display (read-only).
/// Renders tiles from the locally downloaded MBTiles database via ``MBTilesTileOverlay``,
/// falling back to live OpenTopoMap tiles if no local database is available.
///
/// ## Features
/// - Offline topographic tile rendering from MBTiles SQLite database
/// - Route annotation pins (start/green, end/red, via/blue) with tap and long-press gestures
/// - Route polyline overlay (purple, 4pt)
/// - Tap gesture for coordinate-based pin placement
/// - Reposition mode visual feedback (yellow highlight on selected pin)
struct RoutePlanningMapView: UIViewRepresentable {

    // MARK: - Constants

    /// Route polyline stroke width in points.
    static let routePolylineWidth: CGFloat = 4

    /// Annotation pin diameter in points.
    static let pinDiameter: CGFloat = 28

    /// Border width for normal annotation pins.
    static let pinBorderWidth: CGFloat = 2

    /// Border width for the pin being repositioned.
    static let repositionBorderWidth: CGFloat = 3

    /// Scale factor applied to the pin being repositioned.
    static let repositionScale: CGFloat = 1.3

    /// Hit-test expansion radius (points) around annotation views for tap disambiguation.
    static let annotationHitTestExpansion: CGFloat = 10

    // MARK: - Properties

    /// Path to the region's `.mbtiles` SQLite file for offline tile rendering.
    /// When `nil`, falls back to live OpenTopoMap tiles from the internet.
    let mbtilesPath: String?

    /// Initial map center coordinate (typically from `region.boundingBox.center`).
    let initialCenter: CLLocationCoordinate2D

    /// Initial map span in degrees latitude (typically from the region's bounding box height).
    let initialSpan: Double

    /// Route annotations to display (start, end, via-points).
    let annotations: [RouteAnnotation]

    /// Coordinates of the computed route polyline.
    let routeCoordinates: [CLLocationCoordinate2D]

    /// ID of the annotation currently being repositioned, or `nil` if not in reposition mode.
    let repositioningAnnotationId: String?

    /// Called when the user taps an empty area of the map (not an annotation).
    var onMapTap: ((CLLocationCoordinate2D) -> Void)?

    /// Called when the user taps an existing annotation pin.
    var onAnnotationTap: ((RouteAnnotation) -> Void)?

    /// Called when the user long-presses an annotation pin (to enter reposition mode).
    var onAnnotationLongPress: ((RouteAnnotation) -> Void)?

    // MARK: - UIViewRepresentable

    /// Creates and configures the `MKMapView` with tile overlay, initial region, and tap gesture.
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true

        // Add tile overlay (offline MBTiles or online fallback)
        let overlay = createTileOverlay()
        mapView.addOverlay(overlay, level: .aboveLabels)
        context.coordinator.currentTileOverlay = overlay

        // Set initial region from the selected region's bounding box
        let region = MKCoordinateRegion(
            center: initialCenter,
            span: MKCoordinateSpan(latitudeDelta: initialSpan, longitudeDelta: initialSpan)
        )
        mapView.setRegion(region, animated: false)

        // Add tap gesture recognizer for pin placement
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapTap(_:))
        )
        tapGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(tapGesture)

        return mapView
    }

    /// Updates the `MKMapView` when SwiftUI state changes (annotations, route, reposition state).
    func updateUIView(_ mapView: MKMapView, context: Context) {
        updateAnnotations(mapView, coordinator: context.coordinator)
        updateRoutePolyline(mapView, coordinator: context.coordinator)
        updateRepositionHighlight(mapView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Tile Overlay Setup

    /// Creates the appropriate tile overlay based on whether a local MBTiles path is available.
    ///
    /// - Returns: An `MBTilesTileOverlay` if a local database exists, otherwise a standard
    ///   `MKTileOverlay` pointing to the OpenTopoMap tile server.
    private func createTileOverlay() -> MKTileOverlay {
        if let path = mbtilesPath, FileManager.default.fileExists(atPath: path) {
            return MBTilesTileOverlay(mbtilesPath: path)
        }

        // Fallback to online OpenTopoMap
        let fallbackTemplate = MapViewStyle.hiking.tileURLTemplate
            ?? "https://tile.opentopomap.org/{z}/{x}/{y}.png"
        let overlay = MKTileOverlay(urlTemplate: fallbackTemplate)
        overlay.canReplaceMapContent = true
        overlay.maximumZ = TrailMapView.tileMaxZoom
        overlay.minimumZ = TrailMapView.tileMinZoom
        overlay.tileSize = TrailMapView.tileSize
        return overlay
    }

    // MARK: - Annotation Management

    /// Incrementally syncs `MKAnnotation` objects on the map with the current `annotations` array.
    ///
    /// Compares existing `RoutePointAnnotation` objects by ID, removing deleted ones,
    /// adding new ones, and updating moved ones.
    ///
    /// - Parameters:
    ///   - mapView: The `MKMapView` to update.
    ///   - coordinator: The coordinator holding state references.
    private func updateAnnotations(_ mapView: MKMapView, coordinator: Coordinator) {
        let existing = mapView.annotations.compactMap { $0 as? RoutePointAnnotation }
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.routeAnnotation.id, $0) })
        let desiredById = Dictionary(uniqueKeysWithValues: annotations.map { ($0.id, $0) })

        // Remove annotations that are no longer in the desired set
        for annotation in existing where desiredById[annotation.routeAnnotation.id] == nil {
            mapView.removeAnnotation(annotation)
        }

        // Add or update annotations
        for desired in annotations {
            if let existingAnnotation = existingById[desired.id] {
                // Check if coordinate changed (e.g., after repositioning)
                let latDiff = abs(existingAnnotation.coordinate.latitude - desired.coordinate.latitude)
                let lonDiff = abs(existingAnnotation.coordinate.longitude - desired.coordinate.longitude)
                if latDiff > 0.000001 || lonDiff > 0.000001 {
                    mapView.removeAnnotation(existingAnnotation)
                    mapView.addAnnotation(RoutePointAnnotation(routeAnnotation: desired))
                }
            } else {
                mapView.addAnnotation(RoutePointAnnotation(routeAnnotation: desired))
            }
        }
    }

    // MARK: - Route Polyline Management

    /// Replaces the route polyline overlay when the route coordinates change.
    ///
    /// - Parameters:
    ///   - mapView: The `MKMapView` to update.
    ///   - coordinator: The coordinator holding the current polyline reference.
    private func updateRoutePolyline(_ mapView: MKMapView, coordinator: Coordinator) {
        // Remove old polyline
        if let old = coordinator.routePolyline {
            mapView.removeOverlay(old)
            coordinator.routePolyline = nil
        }

        // Add new polyline if there are enough coordinates
        if routeCoordinates.count >= 2 {
            let polyline = MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
            mapView.addOverlay(polyline, level: .aboveLabels)
            coordinator.routePolyline = polyline
        }
    }

    // MARK: - Reposition Highlight

    /// Updates annotation view appearance to reflect the current reposition mode.
    ///
    /// The annotation being repositioned gets a yellow border and enlarged scale;
    /// all others revert to their normal appearance.
    ///
    /// - Parameters:
    ///   - mapView: The `MKMapView` whose annotation views to update.
    ///   - coordinator: The coordinator for state tracking.
    private func updateRepositionHighlight(_ mapView: MKMapView, coordinator: Coordinator) {
        let rpAnnotations = mapView.annotations.compactMap { $0 as? RoutePointAnnotation }

        for rpAnnotation in rpAnnotations {
            guard let view = mapView.view(for: rpAnnotation) else { continue }

            let isRepositioning = rpAnnotation.routeAnnotation.id == repositioningAnnotationId
            let diameter = isRepositioning
                ? Self.pinDiameter * Self.repositionScale
                : Self.pinDiameter

            view.image = Self.renderPinImage(
                color: rpAnnotation.routeAnnotation.uiColor,
                diameter: diameter,
                borderWidth: isRepositioning ? Self.repositionBorderWidth : Self.pinBorderWidth,
                borderColor: isRepositioning ? .systemYellow : .white
            )
            view.centerOffset = CGPoint(x: 0, y: -diameter / 2)
        }
    }

    // MARK: - Pin Rendering

    /// Renders a circular pin image for use as an `MKAnnotationView` image.
    ///
    /// - Parameters:
    ///   - color: Fill color of the circle.
    ///   - diameter: Diameter of the circle in points.
    ///   - borderWidth: Width of the border stroke.
    ///   - borderColor: Color of the border stroke.
    /// - Returns: A `UIImage` of the rendered pin.
    static func renderPinImage(
        color: UIColor,
        diameter: CGFloat,
        borderWidth: CGFloat,
        borderColor: UIColor
    ) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
            ctx.cgContext.setFillColor(color.cgColor)
            ctx.cgContext.fillEllipse(in: rect)
            ctx.cgContext.setStrokeColor(borderColor.cgColor)
            ctx.cgContext.setLineWidth(borderWidth)
            ctx.cgContext.strokeEllipse(in: rect)
        }
    }

    // MARK: - Coordinator

    /// Coordinator handling `MKMapViewDelegate` callbacks and gesture recognition.
    ///
    /// Manages overlay rendering, annotation views with gesture recognizers,
    /// tap-to-place interaction, and annotation selection.
    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        let parent: RoutePlanningMapView
        var currentTileOverlay: MKTileOverlay?
        var routePolyline: MKPolyline?

        /// Weak reference to the map view, set during annotation view creation.
        weak var mapView: MKMapView?

        init(parent: RoutePlanningMapView) {
            self.parent = parent
        }

        // MARK: - Overlay Rendering

        /// Returns the appropriate renderer for tile overlays and route polylines.
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(overlay: tileOverlay)
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemPurple
                renderer.lineWidth = RoutePlanningMapView.routePolylineWidth
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        // MARK: - Annotation Views

        /// Creates and configures annotation views for route point annotations.
        ///
        /// Returns `nil` for non-route annotations (e.g., user location) to use
        /// the system default view.
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let routePoint = annotation as? RoutePointAnnotation else { return nil }

            self.mapView = mapView

            let identifier = "RoutePin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)

            view.annotation = annotation
            view.canShowCallout = false

            let isRepositioning = routePoint.routeAnnotation.id == parent.repositioningAnnotationId
            let diameter = isRepositioning
                ? RoutePlanningMapView.pinDiameter * RoutePlanningMapView.repositionScale
                : RoutePlanningMapView.pinDiameter

            view.image = RoutePlanningMapView.renderPinImage(
                color: routePoint.routeAnnotation.uiColor,
                diameter: diameter,
                borderWidth: isRepositioning
                    ? RoutePlanningMapView.repositionBorderWidth
                    : RoutePlanningMapView.pinBorderWidth,
                borderColor: isRepositioning ? .systemYellow : .white
            )
            view.centerOffset = CGPoint(x: 0, y: -diameter / 2)

            // Add long-press gesture for reposition mode
            let existingLongPress = view.gestureRecognizers?.first { $0 is UILongPressGestureRecognizer }
            if existingLongPress == nil {
                let longPress = UILongPressGestureRecognizer(
                    target: self,
                    action: #selector(handleAnnotationLongPress(_:))
                )
                longPress.minimumPressDuration = 0.5
                view.addGestureRecognizer(longPress)
            }

            return view
        }

        /// Handles annotation selection (tap on a pin).
        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let routePoint = annotation as? RoutePointAnnotation else { return }
            mapView.deselectAnnotation(annotation, animated: false)
            parent.onAnnotationTap?(routePoint.routeAnnotation)
        }

        // MARK: - Gesture Handling

        /// Handles tap on the map for pin placement.
        ///
        /// Checks if the tap hit an annotation view first — if so, lets the delegate's
        /// `didSelect` handle it. Otherwise, converts the screen point to a geographic
        /// coordinate and calls `onMapTap`.
        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  let mapView = gesture.view as? MKMapView else { return }

            let point = gesture.location(in: mapView)

            // Check if tap hit an annotation view — if so, skip (didSelect handles it)
            for annotation in mapView.annotations {
                guard let view = mapView.view(for: annotation),
                      annotation is RoutePointAnnotation else { continue }

                let expandedFrame = view.frame.insetBy(
                    dx: -RoutePlanningMapView.annotationHitTestExpansion,
                    dy: -RoutePlanningMapView.annotationHitTestExpansion
                )
                if expandedFrame.contains(point) {
                    return
                }
            }

            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onMapTap?(coordinate)
        }

        /// Handles long-press on an annotation view for entering reposition mode.
        @objc func handleAnnotationLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  let annotationView = gesture.view as? MKAnnotationView,
                  let routePoint = annotationView.annotation as? RoutePointAnnotation else { return }

            parent.onAnnotationLongPress?(routePoint.routeAnnotation)
        }

        // MARK: - UIGestureRecognizerDelegate

        /// Allows the tap gesture to work alongside MKMapView's built-in gesture recognizers.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

// MARK: - MBTiles Tile Overlay

/// A custom `MKTileOverlay` that reads tile data from a local MBTiles SQLite database.
///
/// Provides offline topographic map rendering by loading tiles from the MBTiles file
/// that was downloaded when the user saved a map region. Uses the existing ``TileStore``
/// for thread-safe SQLite access with TMS y-coordinate flipping handled internally.
///
/// Tiles outside the downloaded region return empty (transparent) data so that the
/// underlying Apple Maps base tiles are fully replaced.
class MBTilesTileOverlay: MKTileOverlay {

    /// The tile store providing read access to the MBTiles SQLite database.
    private let tileStore: TileStore

    /// Whether the tile store was successfully opened.
    private let isOpen: Bool

    /// Creates a tile overlay backed by a local MBTiles database.
    ///
    /// Opens the database immediately. If opening fails, tiles will fall back to empty data.
    ///
    /// - Parameter mbtilesPath: File system path to the `.mbtiles` SQLite database.
    init(mbtilesPath: String) {
        self.tileStore = TileStore(path: mbtilesPath)

        var opened = false
        do {
            try tileStore.open()
            opened = true
        } catch {
            print("MBTilesTileOverlay: Failed to open MBTiles at \(mbtilesPath): \(error.localizedDescription)")
        }
        self.isOpen = opened

        super.init(urlTemplate: nil)

        self.canReplaceMapContent = true
        self.maximumZ = tileStore.metadata?.maxZoom ?? TrailMapView.tileMaxZoom
        self.minimumZ = tileStore.metadata?.minZoom ?? TrailMapView.tileMinZoom
        self.tileSize = TrailMapView.tileSize
    }

    deinit {
        tileStore.close()
    }

    /// Loads tile data from the local MBTiles database.
    ///
    /// Called by MapKit for each visible tile. Reads the tile from SQLite via ``TileStore``.
    /// Returns empty PNG data for tiles that don't exist in the database (areas outside the
    /// downloaded region).
    ///
    /// - Parameters:
    ///   - path: The tile path containing x, y, z coordinates.
    ///   - result: Completion handler to call with the tile data or an error.
    override func loadTile(
        at path: MKTileOverlayPath,
        result: @escaping (Data?, Error?) -> Void
    ) {
        guard isOpen else {
            result(Self.emptyTileData, nil)
            return
        }

        let coordinate = TileCoordinate(x: path.x, y: path.y, z: path.z)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                result(Self.emptyTileData, nil)
                return
            }

            do {
                let data = try self.tileStore.getTile(coordinate)
                result(data, nil)
            } catch {
                // Tile not found — return empty (transparent) tile
                result(Self.emptyTileData, nil)
            }
        }
    }

    /// Minimal 1x1 transparent PNG used for tiles outside the downloaded region.
    ///
    /// Returning empty data instead of an error prevents MapKit from showing Apple Maps
    /// base tiles underneath the overlay.
    private static let emptyTileData: Data = {
        // 1x1 transparent PNG (67 bytes)
        let bytes: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,  // PNG signature
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,  // IHDR chunk
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,  // 1x1
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,  // RGBA
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,  // IDAT chunk
            0x54, 0x78, 0x9C, 0x62, 0x00, 0x00, 0x00, 0x02,
            0x00, 0x01, 0xE5, 0x27, 0xDE, 0xFC, 0x00, 0x00,
            0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,  // IEND chunk
            0x60, 0x82
        ]
        return Data(bytes)
    }()
}

// MARK: - Route Point Annotation

/// An `MKAnnotation` subclass wrapping a ``RouteAnnotation`` for display on `MKMapView`.
///
/// Bridges the SwiftUI `RouteAnnotation` model to the UIKit `MKAnnotation` protocol,
/// exposing the coordinate and label as MKAnnotation properties.
class RoutePointAnnotation: NSObject, MKAnnotation {
    /// The underlying route annotation model.
    let routeAnnotation: RouteAnnotation

    /// The annotation's geographic coordinate.
    var coordinate: CLLocationCoordinate2D {
        routeAnnotation.coordinate
    }

    /// The annotation title (start/end/via label).
    var title: String? {
        routeAnnotation.label
    }

    /// Creates a route point annotation from a route annotation.
    ///
    /// - Parameter routeAnnotation: The route annotation to wrap.
    init(routeAnnotation: RouteAnnotation) {
        self.routeAnnotation = routeAnnotation
    }
}

// MARK: - RouteAnnotation UIColor Extension

extension RouteAnnotation {
    /// The UIKit color for this annotation type, matching the SwiftUI `Color` values.
    var uiColor: UIColor {
        switch type {
        case .start: return .systemGreen
        case .end:   return .systemRed
        case .via:   return .systemBlue
        }
    }
}

#endif
