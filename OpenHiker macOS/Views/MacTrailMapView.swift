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
/// - Selected region polygon overlay (blue, semi-transparent) with interactive drag handles
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

    /// The selected region to highlight with a polygon overlay and drag handles, or `nil` if none.
    @Binding var selectedRegion: MKCoordinateRegion?

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

        // Add the handle overlay NSView on top of the map
        let handleOverlay = SelectionHandleOverlayView()
        handleOverlay.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(handleOverlay)
        NSLayoutConstraint.activate([
            handleOverlay.leadingAnchor.constraint(equalTo: mapView.leadingAnchor),
            handleOverlay.trailingAnchor.constraint(equalTo: mapView.trailingAnchor),
            handleOverlay.topAnchor.constraint(equalTo: mapView.topAnchor),
            handleOverlay.bottomAnchor.constraint(equalTo: mapView.bottomAnchor),
        ])
        context.coordinator.handleOverlay = handleOverlay
        let coordinator = context.coordinator
        handleOverlay.onRegionChanged = { [weak coordinator] newRegion in
            coordinator?.parent.selectedRegion = newRegion
        }

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

        // Sync overlays (selected region polygon + handle overlay)
        updateShapeOverlays(mapView, coordinator: coordinator)
        coordinator.handleOverlay?.update(
            mapView: mapView,
            selectedRegion: selectedRegion
        )
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
        var parent: MacTrailMapView
        var currentTileOverlay: MKTileOverlay?
        var lastTileTemplate: String?
        var selectionPolygon: MKPolygon?

        /// The AppKit overlay view that draws and handles drag on selection handles.
        var handleOverlay: SelectionHandleOverlayView?

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

            // Refresh handle overlay positions after map movement
            handleOverlay?.update(mapView: mapView, selectedRegion: parent.selectedRegion)

            // Reset flag on next run-loop pass, after SwiftUI has processed the binding update.
            DispatchQueue.main.async { [weak self] in
                self?.isUpdatingFromMap = false
            }
        }
    }
}

// MARK: - Selection Handle Overlay (AppKit)

/// An `NSView` overlay that draws interactive drag handles on top of `MKMapView`.
///
/// This view is added as a subview of the `MKMapView`. It overrides `hitTest(_:)` to
/// return itself only when the mouse is over a drag handle, letting all other events
/// pass through to the map. This solves the gesture conflict where SwiftUI gestures
/// on top of `NSViewRepresentable`-hosted `MKMapView` are swallowed by the underlying
/// `NSScrollView` gesture recognizers.
///
/// Draws 8 handles (4 corners + 4 edge midpoints) and supports dragging to resize
/// the selected region.
class SelectionHandleOverlayView: NSView {

    // MARK: - Constants

    /// Size of the visible handle squares.
    private static let handleSize: CGFloat = 10

    /// Hit target radius around each handle center. Mouse events within this distance
    /// of a handle center are intercepted; everything else passes to the map.
    private static let handleHitRadius: CGFloat = 15

    /// Minimum selection size in degrees to prevent collapsing the rectangle.
    private static let minimumSpanDegrees: Double = 0.005

    // MARK: - State

    /// The current handle screen rects, computed from the selected region.
    private var handleRects: [HandlePosition: CGRect] = [:]

    /// The screen rect of the selection rectangle (for drawing the outline).
    private var selectionScreenRect: CGRect = .zero

    /// The handle currently being dragged, or `nil` if no drag in progress.
    private var activeHandle: HandlePosition?

    /// The geographic region at the start of the current drag.
    private var dragStartRegion: MKCoordinateRegion?

    /// The mouse position at the start of the current drag (in view coordinates).
    private var dragStartPoint: CGPoint = .zero

    /// Weak reference to the map view for coordinate conversion.
    private weak var mapView: MKMapView?

    /// The current selected region in geographic coordinates.
    private var selectedRegion: MKCoordinateRegion?

    /// Callback invoked when a handle drag changes the selected region.
    var onRegionChanged: ((MKCoordinateRegion) -> Void)?

    /// Which handle of the selection rectangle.
    private enum HandlePosition: CaseIterable {
        case topLeft, top, topRight
        case left, right
        case bottomLeft, bottom, bottomRight
    }

    // MARK: - Initialisation

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    // MARK: - Public API

    /// Updates the overlay with the current map state and selected region.
    ///
    /// Recomputes handle screen positions from the geographic region using the
    /// map view's coordinate conversion.
    ///
    /// - Parameters:
    ///   - mapView: The `MKMapView` used for coordinate conversion.
    ///   - selectedRegion: The geographic region to show handles for, or `nil` to hide.
    func update(mapView: MKMapView, selectedRegion: MKCoordinateRegion?) {
        self.mapView = mapView
        self.selectedRegion = selectedRegion
        recomputeHandleRects()
        needsDisplay = true
    }

    // MARK: - Hit Testing

    /// Returns `self` if the point is inside a handle hit area, `nil` otherwise.
    ///
    /// This is the key mechanism: by returning `nil` for non-handle areas, mouse
    /// events pass through to the `MKMapView` underneath for normal map panning.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard selectedRegion != nil else { return nil }
        let localPoint = convert(point, from: superview)
        for (_, rect) in handleRects {
            let hitRect = rect.insetBy(
                dx: -(Self.handleHitRadius - Self.handleSize / 2),
                dy: -(Self.handleHitRadius - Self.handleSize / 2)
            )
            if hitRect.contains(localPoint) {
                return self
            }
        }
        return nil
    }

    // MARK: - Mouse Event Handling

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        activeHandle = handleAt(point)
        if activeHandle != nil {
            dragStartPoint = point
            dragStartRegion = selectedRegion
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let handle = activeHandle,
              let startRegion = dragStartRegion,
              let mapView = mapView else { return }

        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - dragStartPoint.x
        // NSView Y is flipped vs screen (0 at bottom), but MKMapView.convert
        // handles this. We compute delta in view coordinates.
        let dy = point.y - dragStartPoint.y

        let newRegion = applyHandleDrag(
            handle: handle,
            startRegion: startRegion,
            dx: dx,
            dy: dy,
            mapView: mapView
        )
        selectedRegion = newRegion
        onRegionChanged?(newRegion)
        recomputeHandleRects()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        activeHandle = nil
        dragStartRegion = nil
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        discardCursorRects()
        for (position, rect) in handleRects {
            let hitRect = rect.insetBy(
                dx: -(Self.handleHitRadius - Self.handleSize / 2),
                dy: -(Self.handleHitRadius - Self.handleSize / 2)
            )
            let cursor = cursorForHandle(position)
            addCursorRect(hitRect, cursor: cursor)
        }
    }

    /// Returns the appropriate resize cursor for a given handle position.
    private func cursorForHandle(_ position: HandlePosition) -> NSCursor {
        switch position {
        case .topLeft, .bottomRight:
            return NSCursor(image: NSCursor.arrow.image, hotSpot: NSCursor.arrow.hotSpot)
        case .topRight, .bottomLeft:
            return NSCursor(image: NSCursor.arrow.image, hotSpot: NSCursor.arrow.hotSpot)
        case .top, .bottom:
            return .resizeUpDown
        case .left, .right:
            return .resizeLeftRight
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard selectedRegion != nil else { return }

        // Draw handle squares
        for (position, rect) in handleRects {
            let isActive = (position == activeHandle)

            // White fill
            NSColor.white.setFill()
            let path = NSBezierPath(rect: rect)
            path.fill()

            // Blue stroke (thicker when active)
            NSColor.systemBlue.setStroke()
            path.lineWidth = isActive ? 2.5 : 1.5
            path.stroke()
        }
    }

    // MARK: - Internal

    /// Finds which handle (if any) is at the given point in view coordinates.
    private func handleAt(_ point: CGPoint) -> HandlePosition? {
        for (position, rect) in handleRects {
            let hitRect = rect.insetBy(
                dx: -(Self.handleHitRadius - Self.handleSize / 2),
                dy: -(Self.handleHitRadius - Self.handleSize / 2)
            )
            if hitRect.contains(point) {
                return position
            }
        }
        return nil
    }

    /// Recomputes the screen rects for all 8 handles from the geographic region.
    private func recomputeHandleRects() {
        handleRects.removeAll()
        guard let region = selectedRegion, let mapView = mapView else { return }

        let halfLat = region.span.latitudeDelta / 2
        let halfLon = region.span.longitudeDelta / 2
        let c = region.center

        let nw = CLLocationCoordinate2D(latitude: c.latitude + halfLat, longitude: c.longitude - halfLon)
        let ne = CLLocationCoordinate2D(latitude: c.latitude + halfLat, longitude: c.longitude + halfLon)
        let sw = CLLocationCoordinate2D(latitude: c.latitude - halfLat, longitude: c.longitude - halfLon)
        let se = CLLocationCoordinate2D(latitude: c.latitude - halfLat, longitude: c.longitude + halfLon)
        let n  = CLLocationCoordinate2D(latitude: c.latitude + halfLat, longitude: c.longitude)
        let s  = CLLocationCoordinate2D(latitude: c.latitude - halfLat, longitude: c.longitude)
        let w  = CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude - halfLon)
        let e  = CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude + halfLon)

        let pairs: [(HandlePosition, CLLocationCoordinate2D)] = [
            (.topLeft, nw), (.top, n), (.topRight, ne),
            (.left, w), (.right, e),
            (.bottomLeft, sw), (.bottom, s), (.bottomRight, se),
        ]

        let hs = Self.handleSize
        for (pos, coord) in pairs {
            let pt = mapView.convert(coord, toPointTo: self)
            handleRects[pos] = CGRect(x: pt.x - hs / 2, y: pt.y - hs / 2, width: hs, height: hs)
        }

        // Compute selection screen rect for cursor rects
        let nwPt = mapView.convert(nw, toPointTo: self)
        let sePt = mapView.convert(se, toPointTo: self)
        selectionScreenRect = CGRect(
            x: min(nwPt.x, sePt.x),
            y: min(nwPt.y, sePt.y),
            width: abs(sePt.x - nwPt.x),
            height: abs(sePt.y - nwPt.y)
        )

        // Update cursor rects when handle positions change
        window?.invalidateCursorRects(for: self)
    }

    /// Applies a handle drag delta to the start region and returns the new region.
    ///
    /// Converts the screen-space mouse delta to geographic coordinates using the
    /// map view's coordinate conversion, then adjusts the appropriate edge(s).
    ///
    /// - Parameters:
    ///   - handle: Which handle is being dragged.
    ///   - startRegion: The geographic region when the drag began.
    ///   - dx: Horizontal mouse delta in view points (positive = right/east).
    ///   - dy: Vertical mouse delta in view points (positive = up in NSView = north).
    ///   - mapView: The map view for coordinate conversion.
    /// - Returns: The adjusted geographic region.
    private func applyHandleDrag(
        handle: HandlePosition,
        startRegion: MKCoordinateRegion,
        dx: CGFloat,
        dy: CGFloat,
        mapView: MKMapView
    ) -> MKCoordinateRegion {
        let halfLat = startRegion.span.latitudeDelta / 2
        let halfLon = startRegion.span.longitudeDelta / 2
        let c = startRegion.center

        var north = c.latitude + halfLat
        var south = c.latitude - halfLat
        var east = c.longitude + halfLon
        var west = c.longitude - halfLon

        // Convert original edges to screen points, apply delta, convert back
        // This is more accurate than linear degree-per-pixel estimates because
        // it accounts for the Mercator projection.
        let geoDelta = screenDeltaToGeoDelta(dx: dx, dy: dy, mapView: mapView)
        let dLat = geoDelta.dLat
        let dLon = geoDelta.dLon

        switch handle {
        case .topLeft:     north += dLat; west += dLon
        case .top:         north += dLat
        case .topRight:    north += dLat; east += dLon
        case .left:        west += dLon
        case .right:       east += dLon
        case .bottomLeft:  south += dLat; west += dLon
        case .bottom:      south += dLat
        case .bottomRight: south += dLat; east += dLon
        }

        return clampedRegion(north: north, south: south, east: east, west: west)
    }

    /// Converts a screen-space delta to a geographic delta.
    ///
    /// Uses the map view's center point as a reference: maps the center to a screen point,
    /// offsets it by (dx, dy), and converts back to get the geographic difference.
    private func screenDeltaToGeoDelta(dx: CGFloat, dy: CGFloat, mapView: MKMapView) -> (dLat: Double, dLon: Double) {
        let centerCoord = mapView.centerCoordinate
        let centerPt = mapView.convert(centerCoord, toPointTo: self)
        let offsetPt = CGPoint(x: centerPt.x + dx, y: centerPt.y + dy)
        let offsetCoord = mapView.convert(offsetPt, toCoordinateFrom: self)
        return (dLat: offsetCoord.latitude - centerCoord.latitude, dLon: offsetCoord.longitude - centerCoord.longitude)
    }

    /// Clamps the given bounds to a valid region with minimum span.
    private func clampedRegion(north: Double, south: Double, east: Double, west: Double) -> MKCoordinateRegion {
        let minSpan = Self.minimumSpanDegrees
        let clampedNorth = max(north, south + minSpan)
        let clampedSouth = min(south, north - minSpan)
        let clampedEast = max(east, west + minSpan)
        let clampedWest = min(west, east - minSpan)

        let latSpan = clampedNorth - clampedSouth
        let lonSpan = clampedEast - clampedWest
        let centerLat = (clampedNorth + clampedSouth) / 2
        let centerLon = (clampedEast + clampedWest) / 2

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )
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
