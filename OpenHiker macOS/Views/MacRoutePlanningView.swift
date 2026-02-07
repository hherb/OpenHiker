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

import SwiftUI
import MapKit
import CoreLocation

// MARK: - MBTiles Tile Overlay

/// A custom `MKTileOverlay` that reads tile images from a local MBTiles (SQLite) database.
///
/// Used by ``MacRoutePlanningView`` to display downloaded OpenTopoMap tiles offline
/// instead of fetching from the network. Opens a ``TileStore`` for the region's
/// `.mbtiles` file and converts each `MKTileOverlayPath` to a ``TileCoordinate``
/// for lookup.
private final class MBTilesTileOverlay: MKTileOverlay {
    /// The read-only tile store backed by the MBTiles SQLite database.
    private let tileStore: TileStore

    /// Creates an overlay that reads tiles from the given MBTiles file path.
    ///
    /// - Parameters:
    ///   - mbtilesPath: Absolute path to the `.mbtiles` SQLite database.
    ///   - minZoom: Minimum zoom level available in the database.
    ///   - maxZoom: Maximum zoom level available in the database.
    /// - Throws: `TileStoreError` if the database cannot be opened.
    init(mbtilesPath: String, minZoom: Int, maxZoom: Int) throws {
        self.tileStore = TileStore(path: mbtilesPath)
        try tileStore.open()
        super.init(urlTemplate: nil)
        self.canReplaceMapContent = true
        self.minimumZ = minZoom
        self.maximumZ = maxZoom
        self.tileSize = CGSize(width: 256, height: 256)
    }

    /// Loads a tile from the MBTiles database for the given path.
    ///
    /// MapKit calls this for every visible tile. The `MKTileOverlayPath` z/x/y
    /// values use the standard web mercator (slippy map) convention; ``TileStore``
    /// handles the TMS y-flip internally.
    ///
    /// - Parameters:
    ///   - path: The tile path (z, x, y) requested by MapKit.
    ///   - result: Completion handler receiving the tile data or an error.
    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let coordinate = TileCoordinate(x: path.x, y: path.y, z: path.z)
        do {
            let data = try tileStore.getTile(coordinate)
            result(data, nil)
        } catch TileStoreError.tileNotFound {
            // Expected for tiles outside the downloaded region — return empty data
            // so MapKit shows a blank tile instead of logging an error.
            result(nil, nil)
        } catch {
            result(nil, error)
        }
    }
}

// MARK: - Pin Annotation

/// A lightweight annotation for start, end, and via-point pins on the route planning map.
///
/// Each pin has a ``pinType`` that determines its colour and icon in the annotation view.
private final class RoutePinAnnotation: MKPointAnnotation {
    /// The semantic type of this pin (start, end, or via-point).
    enum PinType {
        case start
        case end
        case via(Int)
    }

    /// What kind of pin this annotation represents.
    let pinType: PinType

    /// Creates a pin annotation at the given coordinate.
    ///
    /// - Parameters:
    ///   - coordinate: The geographic position of the pin.
    ///   - type: The semantic pin type (start, end, or via-point).
    init(coordinate: CLLocationCoordinate2D, type: PinType) {
        self.pinType = type
        super.init()
        self.coordinate = coordinate
        switch type {
        case .start: self.title = "Start"
        case .end: self.title = "End"
        case .via(let i): self.title = "Via \(i + 1)"
        }
    }
}

// MARK: - Route Planning Map (NSViewRepresentable)

/// An `NSViewRepresentable` wrapping `MKMapView` for offline route planning.
///
/// Displays tiles from a local MBTiles database, pin annotations for start/end/via-points,
/// and a route polyline. Reports tap coordinates back to the parent view via a callback.
private struct RoutePlanningMapView: NSViewRepresentable {
    /// Diameter of pin annotation views in points.
    static let pinSize: CGFloat = 28

    /// Stroke width for the route polyline.
    static let routeLineWidth: CGFloat = 4

    /// The region providing bounding box and MBTiles path.
    let region: Region

    /// Start coordinate (green pin), if placed.
    let startCoordinate: CLLocationCoordinate2D?

    /// End coordinate (red pin), if placed.
    let endCoordinate: CLLocationCoordinate2D?

    /// Ordered via-point coordinates (blue pins).
    let viaPoints: [CLLocationCoordinate2D]

    /// Coordinates of the computed route polyline, or empty.
    let routeCoordinates: [CLLocationCoordinate2D]

    /// Called when the user clicks the map at a geographic coordinate.
    var onMapClick: ((CLLocationCoordinate2D) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator

        // Add offline tile overlay from the region's MBTiles database
        let mbtilesPath = RegionStorage.shared.mbtilesURL(for: region).path
        do {
            let overlay = try MBTilesTileOverlay(
                mbtilesPath: mbtilesPath,
                minZoom: region.zoomLevels.lowerBound,
                maxZoom: region.zoomLevels.upperBound
            )
            mapView.addOverlay(overlay, level: .aboveLabels)
            context.coordinator.tileOverlay = overlay
        } catch {
            print("Failed to open MBTiles overlay: \(error.localizedDescription)")
        }

        // Set initial region from bounding box
        let bb = region.boundingBox
        let center = CLLocationCoordinate2D(latitude: bb.center.latitude, longitude: bb.center.longitude)
        let span = MKCoordinateSpan(
            latitudeDelta: bb.north - bb.south,
            longitudeDelta: bb.east - bb.west
        )
        mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)

        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsZoomControls = true

        // Add click gesture recognizer for pin placement
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        mapView.addGestureRecognizer(click)

        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator

        // Update annotations
        let existingPins = mapView.annotations.compactMap { $0 as? RoutePinAnnotation }
        mapView.removeAnnotations(existingPins)

        if let start = startCoordinate {
            mapView.addAnnotation(RoutePinAnnotation(coordinate: start, type: .start))
        }
        if let end = endCoordinate {
            mapView.addAnnotation(RoutePinAnnotation(coordinate: end, type: .end))
        }
        for (i, point) in viaPoints.enumerated() {
            mapView.addAnnotation(RoutePinAnnotation(coordinate: point, type: .via(i)))
        }

        // Update route polyline
        if let oldPolyline = coordinator.routePolyline {
            mapView.removeOverlay(oldPolyline)
            coordinator.routePolyline = nil
        }
        if routeCoordinates.count >= 2 {
            var coords = routeCoordinates
            let polyline = MKPolyline(coordinates: &coords, count: coords.count)
            mapView.addOverlay(polyline, level: .aboveLabels)
            coordinator.routePolyline = polyline
        }
    }

    // MARK: - Coordinator

    /// Coordinator managing `MKMapViewDelegate` callbacks and gesture handling.
    final class Coordinator: NSObject, MKMapViewDelegate {
        let parent: RoutePlanningMapView

        /// Reference to the offline tile overlay.
        var tileOverlay: MBTilesTileOverlay?

        /// Reference to the current route polyline overlay.
        var routePolyline: MKPolyline?

        init(parent: RoutePlanningMapView) {
            self.parent = parent
        }

        /// Handles a click on the map view and converts to geographic coordinates.
        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onMapClick?(coordinate)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(overlay: tileOverlay)
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .purple
                renderer.lineWidth = RoutePlanningMapView.routeLineWidth
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? RoutePinAnnotation else { return nil }

            let identifier = "RoutePinView"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.canShowCallout = false

            let color: NSColor
            let iconName: String
            switch pin.pinType {
            case .start:
                color = .systemGreen
                iconName = "flag.fill"
            case .end:
                color = .systemRed
                iconName = "mappin"
            case .via:
                color = .systemBlue
                iconName = "circle.fill"
            }

            let size = RoutePlanningMapView.pinSize
            let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                // Draw circle background
                color.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()

                // Draw white border
                NSColor.white.setStroke()
                let borderPath = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
                borderPath.lineWidth = 2
                borderPath.stroke()

                // Draw SF Symbol icon
                if let symbolImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                    let config = NSImage.SymbolConfiguration(pointSize: size / 2.5, weight: .bold)
                    let configured = symbolImage.withSymbolConfiguration(config) ?? symbolImage
                    let symbolSize = configured.size
                    let symbolRect = NSRect(
                        x: (rect.width - symbolSize.width) / 2,
                        y: (rect.height - symbolSize.height) / 2,
                        width: symbolSize.width,
                        height: symbolSize.height
                    )
                    configured.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                }
                return true
            }
            view.image = image
            view.centerOffset = .zero

            return view
        }
    }
}

// MARK: - Route Planning View

/// macOS interactive route planning view.
///
/// Users click on the map to place start (green), end (red), and via-points (blue).
/// The ``RoutingEngine`` computes the optimal hiking or cycling path and displays
/// it as a polyline with distance, elevation, and turn-by-turn instructions.
///
/// The map displays downloaded OpenTopoMap tiles offline from the region's MBTiles
/// database using a custom ``MBTilesTileOverlay``.
///
/// ## Interaction Model
/// 1. First click → place start pin (green)
/// 2. Second click → place end pin (red), auto-compute route
/// 3. Subsequent clicks → add via-points (blue), re-compute
/// 4. Click existing pin → remove it
/// 5. Save → store to ``PlannedRouteStore``, sync to iPhone via iCloud
struct MacRoutePlanningView: View {
    @Environment(\.dismiss) private var dismiss

    /// The region whose routing database and tiles to use.
    let region: Region

    /// Callback to dismiss this view and return to the route list.
    var onDismiss: (() -> Void)? = nil

    // MARK: - Layout Constants

    /// Minimum width of the map panel.
    private static let mapMinWidth: CGFloat = 400

    /// Width of the side panel with stats and directions.
    private static let sidePanelWidth: CGFloat = 320

    /// Width of the routing mode picker in the toolbar.
    private static let modePickerWidth: CGFloat = 180

    /// Width of direction instruction icons.
    private static let directionIconWidth: CGFloat = 20

    /// Corner radius for card-style panels.
    private static let cardCornerRadius: CGFloat = 8

    // MARK: - Route State

    /// Hiking or cycling mode.
    @State private var routingMode: RoutingMode = .hiking

    /// Start coordinate set by the user's first click.
    @State private var startCoordinate: CLLocationCoordinate2D?

    /// End coordinate set by the user's second click.
    @State private var endCoordinate: CLLocationCoordinate2D?

    /// Ordered via-points added after start and end.
    @State private var viaPoints: [CLLocationCoordinate2D] = []

    /// The computed route result from the routing engine.
    @State private var computedRoute: ComputedRoute?

    /// Turn-by-turn instructions for the computed route.
    @State private var turnInstructions: [TurnInstruction] = []

    /// Whether the routing engine is computing.
    @State private var isComputing = false

    /// Error message for the alert.
    @State private var errorMessage: String?

    /// Whether the error alert is shown.
    @State private var showError = false

    /// User-provided name for the route.
    @State private var routeName = ""

    /// Whether the save success alert is shown.
    @State private var showSaveSuccess = false

    /// Whether directions are expanded.
    @State private var showDirections = false

    // MARK: - Body

    var body: some View {
        HSplitView {
            RoutePlanningMapView(
                region: region,
                startCoordinate: startCoordinate,
                endCoordinate: endCoordinate,
                viaPoints: viaPoints,
                routeCoordinates: computedRoute?.coordinates ?? [],
                onMapClick: handleMapClick
            )
            .frame(minWidth: Self.mapMinWidth)

            sidePanel
                .frame(width: Self.sidePanelWidth)
        }
        .navigationTitle("Plan Route — \(region.name)")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    onDismiss?()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .help("Return to route list")

                Picker("Mode", selection: $routingMode) {
                    Label("Hiking", systemImage: "figure.hiking").tag(RoutingMode.hiking)
                    Label("Cycling", systemImage: "bicycle").tag(RoutingMode.cycling)
                }
                .pickerStyle(.segmented)
                .frame(width: Self.modePickerWidth)

                if computedRoute != nil {
                    Button("Save Route") {
                        saveRoute()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Clear All") {
                    clearAll()
                }
                .disabled(startCoordinate == nil)
            }
        }
        .onChange(of: routingMode) { _, _ in
            computeRoute()
        }
        .alert("Route Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .alert("Route Saved", isPresented: $showSaveSuccess) {
            Button("OK", role: .cancel) {}
            Button("Sync to iPhone") {
                Task {
                    await CloudSyncManager.shared.performSync()
                }
            }
        } message: {
            Text("Your route has been saved. Sync to iPhone to transfer it to your Apple Watch.")
        }
    }

    // MARK: - Side Panel

    /// The side panel with instructions, stats, and directions.
    private var sidePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                instructionSection

                if let route = computedRoute {
                    statsSection(route)
                }

                if isComputing {
                    HStack {
                        ProgressView()
                        Text("Computing route...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }

                if !turnInstructions.isEmpty {
                    directionsSection
                }

                if computedRoute != nil {
                    saveSection
                }
            }
            .padding()
        }
    }

    /// Current instruction text based on pin placement state.
    private var instructionSection: some View {
        HStack(spacing: 12) {
            Image(systemName: instructionIcon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(instructionTitle)
                    .font(.headline)
                Text(instructionSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: Self.cardCornerRadius))
    }

    /// Route statistics display.
    private func statsSection(_ route: ComputedRoute) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Route Statistics")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                statItem(icon: "ruler", label: "Distance",
                         value: HikeStatsFormatter.formatDistance(route.totalDistance, useMetric: true))
                Spacer()
                statItem(icon: "clock", label: "Duration",
                         value: formatDuration(route.estimatedDuration))
            }

            HStack {
                statItem(icon: "arrow.up.right", label: "Gain",
                         value: "+\(HikeStatsFormatter.formatElevation(route.elevationGain, useMetric: true))")
                Spacer()
                statItem(icon: "arrow.down.right", label: "Loss",
                         value: "-\(HikeStatsFormatter.formatElevation(route.elevationLoss, useMetric: true))")
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: Self.cardCornerRadius))
    }

    /// A single stat item.
    private func statItem(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
    }

    /// Turn-by-turn directions section.
    private var directionsSection: some View {
        DisclosureGroup("Directions (\(turnInstructions.count) steps)", isExpanded: $showDirections) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(turnInstructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: instruction.direction.sfSymbolName)
                            .frame(width: Self.directionIconWidth)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(instruction.description)
                                .font(.caption)
                            if instruction.distanceFromPrevious > 0 {
                                Text(HikeStatsFormatter.formatDistance(instruction.distanceFromPrevious, useMetric: true))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    /// Route save section with name field.
    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save Route")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Route name", text: $routeName)
                .textFieldStyle(.roundedBorder)

            Button {
                saveRoute()
            } label: {
                HStack {
                    Spacer()
                    Label("Save & Sync", systemImage: "square.and.arrow.down")
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Instruction State

    private var instructionIcon: String {
        if startCoordinate == nil { return "1.circle" }
        if endCoordinate == nil { return "2.circle" }
        return "checkmark.circle"
    }

    private var instructionTitle: String {
        if startCoordinate == nil { return "Set Start Point" }
        if endCoordinate == nil { return "Set Destination" }
        return "Route Ready"
    }

    private var instructionSubtitle: String {
        if startCoordinate == nil { return "Click the map to place the start pin" }
        if endCoordinate == nil { return "Click to set your destination" }
        return "Click to add via-points, or save your route"
    }

    // MARK: - Actions

    /// Handles a click on the map to place pins.
    private func handleMapClick(_ coordinate: CLLocationCoordinate2D) {
        if startCoordinate == nil {
            startCoordinate = coordinate
        } else if endCoordinate == nil {
            endCoordinate = coordinate
            computeRoute()
        } else {
            viaPoints.append(coordinate)
            computeRoute()
        }
    }

    /// Removes the start pin and clears the route.
    private func removeStart() {
        startCoordinate = nil
        computedRoute = nil
        turnInstructions = []
    }

    /// Removes the end pin and clears the route.
    private func removeEnd() {
        endCoordinate = nil
        computedRoute = nil
        turnInstructions = []
    }

    /// Removes a via-point and recomputes the route.
    private func removeViaPoint(at index: Int) {
        viaPoints.remove(at: index)
        computeRoute()
    }

    /// Clears all pins and the computed route.
    private func clearAll() {
        startCoordinate = nil
        endCoordinate = nil
        viaPoints.removeAll()
        computedRoute = nil
        turnInstructions = []
        routeName = ""
    }

    /// Computes the route using the routing engine.
    ///
    /// Opens a ``RoutingStore`` for the region's routing database, creates a
    /// ``RoutingEngine``, and runs A* pathfinding between the placed pins.
    /// Results (route polyline + turn instructions) are dispatched to the main actor.
    private func computeRoute() {
        guard let start = startCoordinate, let end = endCoordinate else { return }

        isComputing = true
        computedRoute = nil
        turnInstructions = []

        Task {
            do {
                let routingDbPath = RegionStorage.shared.routingDbURL(for: region).path

                let store = RoutingStore(path: routingDbPath)
                try store.open()
                let engine = RoutingEngine(store: store)

                let route = try engine.findRoute(
                    from: start,
                    to: end,
                    via: viaPoints,
                    mode: routingMode
                )

                let instructions = TurnInstructionGenerator.generate(from: route)

                await MainActor.run {
                    self.computedRoute = route
                    self.turnInstructions = instructions
                    self.isComputing = false
                }
            } catch {
                await MainActor.run {
                    self.isComputing = false
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }

    /// Saves the planned route and triggers iCloud sync.
    private func saveRoute() {
        guard let route = computedRoute else { return }

        let name = routeName.isEmpty ? "Route \(Date().formatted(date: .abbreviated, time: .omitted))" : routeName
        let planned = PlannedRoute.from(
            computedRoute: route,
            name: name,
            mode: routingMode,
            regionId: region.id
        )

        do {
            try PlannedRouteStore.shared.save(planned)
            showSaveSuccess = true
        } catch {
            errorMessage = "Failed to save route: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Formats a duration in seconds to a human-readable string.
    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
