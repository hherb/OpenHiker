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
import SpriteKit
import CoreLocation

/// SpriteKit-based map renderer for watchOS.
///
/// Manages loading MBTiles databases and providing tile data to the ``MapScene``.
/// Acts as the bridge between the SwiftUI view layer (``MapView``) and the SpriteKit
/// scene that renders tiles.
///
/// ## Responsibilities
/// - Opening/closing ``TileStore`` connections to MBTiles SQLite databases
/// - Tracking the current zoom level and map center coordinate
/// - Creating and managing the ``MapScene`` instance
/// - Providing tile image data to the scene for rendering
///
/// The ``currentZoom`` property is bound to the Digital Crown via SwiftUI's
/// `digitalCrownRotation` modifier, allowing smooth zoom control.
final class MapRenderer: ObservableObject {
    // MARK: - Published Properties

    /// Whether a region is currently being loaded.
    @Published var isLoading = false

    /// Any error that occurred during the last load attempt.
    @Published var loadError: Error?

    /// The current zoom level, bound to the Digital Crown. Defaults to 14.
    @Published var currentZoom: Int = 14

    /// The current map center coordinate in WGS84, or `nil` if no region is loaded.
    @Published var centerCoordinate: CLLocationCoordinate2D?

    // MARK: - Properties

    /// The currently open tile store for reading tile data.
    private var tileStore: TileStore?

    /// The active SpriteKit scene, held weakly to avoid retain cycles.
    private var mapScene: MapScene?

    /// Metadata for the currently loaded region.
    private var regionMetadata: RegionMetadata?

    /// The minimum allowed zoom level.
    let minZoom: Int

    /// The maximum allowed zoom level.
    let maxZoom: Int

    /// The size of each tile in points (standard web mercator tile size).
    static let tileSize: CGFloat = 256

    // MARK: - Initialization

    /// Creates a new map renderer with the specified zoom bounds.
    ///
    /// - Parameters:
    ///   - minZoom: The minimum zoom level (default: 12).
    ///   - maxZoom: The maximum zoom level (default: 16).
    init(minZoom: Int = 12, maxZoom: Int = 16) {
        self.minZoom = minZoom
        self.maxZoom = maxZoom
    }

    // MARK: - Public Methods

    /// Loads a region's MBTiles database for tile rendering.
    ///
    /// Opens the SQLite database at the expected path in Documents/regions/,
    /// sets the initial zoom to the region's midpoint zoom (clamped to available range),
    /// and centers on the region's bounding box center.
    ///
    /// - Parameter metadata: The ``RegionMetadata`` describing the region to load.
    /// - Throws: ``TileStoreError`` if the database cannot be opened.
    func loadRegion(_ metadata: RegionMetadata) throws {
        isLoading = true
        loadError = nil

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let mbtilesPath = documentsDir
            .appendingPathComponent("regions")
            .appendingPathComponent("\(metadata.id.uuidString).mbtiles")
            .path

        let store = TileStore(path: mbtilesPath)
        try store.open()

        self.tileStore = store
        self.regionMetadata = metadata
        self.currentZoom = max(metadata.minZoom, min(metadata.maxZoom, 14))

        // Set initial center to region center
        self.centerCoordinate = metadata.boundingBox.center

        isLoading = false
    }

    /// Unloads the current region and releases the tile store connection.
    func unloadRegion() {
        tileStore?.close()
        tileStore = nil
        regionMetadata = nil
        centerCoordinate = nil
    }

    /// Creates a new SpriteKit scene for displaying map tiles.
    ///
    /// The scene is sized to the provided dimensions (typically the watch screen size)
    /// and configured with a reference to this renderer for tile data access.
    ///
    /// - Parameter size: The size of the scene in points.
    /// - Returns: A configured ``MapScene`` ready for display in a `SpriteView`.
    func createScene(size: CGSize) -> MapScene {
        let mapScene = MapScene(size: size, renderer: self)
        self.mapScene = mapScene
        return mapScene
    }

    /// Retrieves tile image data (PNG) for the given tile coordinate.
    ///
    /// Reads from the currently open ``TileStore``. Returns `nil` if no region
    /// is loaded or the tile doesn't exist in the database.
    ///
    /// - Parameter coordinate: The ``TileCoordinate`` specifying zoom, x, and y.
    /// - Returns: The tile's PNG image data, or `nil`.
    func getTileData(for coordinate: TileCoordinate) -> Data? {
        guard let store = tileStore else { return nil }
        return try? store.getTile(coordinate)
    }

    /// Updates the map center coordinate and refreshes visible tiles.
    ///
    /// - Parameter coordinate: The new center coordinate in WGS84.
    func setCenter(_ coordinate: CLLocationCoordinate2D) {
        centerCoordinate = coordinate
        mapScene?.updateVisibleTiles()
    }

    /// Increases the zoom level by one step (if not at maximum).
    func zoomIn() {
        guard currentZoom < maxZoom else { return }
        currentZoom += 1
        mapScene?.updateVisibleTiles()
    }

    /// Decreases the zoom level by one step (if not at minimum).
    func zoomOut() {
        guard currentZoom > minZoom else { return }
        currentZoom -= 1
        mapScene?.updateVisibleTiles()
    }

    /// Sets the zoom level to the specified value, clamped to the valid range.
    ///
    /// - Parameter zoom: The desired zoom level.
    func setZoom(_ zoom: Int) {
        let clampedZoom = max(minZoom, min(maxZoom, zoom))
        guard clampedZoom != currentZoom else { return }
        currentZoom = clampedZoom
        mapScene?.updateVisibleTiles()
    }

    /// Checks whether a coordinate falls within the currently loaded region's bounds.
    ///
    /// - Parameter coordinate: The coordinate to check.
    /// - Returns: `true` if the coordinate is within the region, `false` otherwise.
    func isCoordinateInRegion(_ coordinate: CLLocationCoordinate2D) -> Bool {
        regionMetadata?.contains(coordinate: coordinate) ?? false
    }
}

// MARK: - SpriteKit Map Scene

/// A SpriteKit scene that renders offline map tiles with GPS overlays.
///
/// This scene manages:
/// - A grid of tile sprites loaded from the ``MapRenderer``'s tile store
/// - A blue pulsing position marker showing the user's GPS location
/// - A directional cone showing the compass heading
/// - A compass indicator in the top-right corner
/// - A track trail polyline showing recorded hike points
///
/// Tiles are organized in a 3x3 grid around the center tile, repositioned
/// using Web Mercator math to achieve sub-tile-precision scrolling.
///
/// ## Node hierarchy
/// ```
/// Scene
///   ├── tilesNode        ← Contains tile sprites (z=0)
///   └── overlaysNode     ← Contains markers and compass (z>0)
///         ├── positionMarker (z=100)
///         │     └── headingCone (z=99)
///         ├── compassNode (z=200)
///         └── trackNode (z=50)
/// ```
final class MapScene: SKScene {
    /// Weak reference to the renderer that provides tile data and coordinate state.
    private weak var renderer: MapRenderer?

    /// Parent node containing all tile sprites.
    private let tilesNode = SKNode()

    /// Parent node for overlay elements (position marker, compass, track trail).
    private let overlaysNode = SKNode()

    /// The blue circle marking the user's current GPS position.
    private var positionMarker: SKShapeNode?

    /// A triangular cone on the position marker indicating compass heading.
    private var headingCone: SKShapeNode?

    /// A compass indicator showing north direction, positioned in the top-right corner.
    private var compassNode: SKNode?

    /// A polyline shape node showing the recorded hike track.
    private var trackNode: SKShapeNode?

    /// In-memory cache of tile textures to avoid re-creating them from PNG data.
    private var textureCache: [TileCoordinate: SKTexture] = [:]

    /// Maximum number of textures to keep in the cache before evicting old entries.
    private let maxCacheSize = 100

    // MARK: - Initialization

    /// Creates a new map scene with the given size and renderer.
    ///
    /// Sets up the node hierarchy, position marker with pulsing animation,
    /// and compass indicator.
    ///
    /// - Parameters:
    ///   - size: The scene size in points (typically the watch screen size).
    ///   - renderer: The ``MapRenderer`` providing tile data and map state.
    init(size: CGSize, renderer: MapRenderer) {
        self.renderer = renderer
        super.init(size: size)

        backgroundColor = .darkGray
        scaleMode = .resizeFill

        addChild(tilesNode)
        addChild(overlaysNode)

        setupPositionMarker()
        setupCompass()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    /// Creates the blue GPS position marker with a heading cone and pulsing animation.
    ///
    /// The marker is an 8pt radius circle in iOS-blue with a white border. A triangular
    /// heading cone is added as a child node. The marker pulses between 1.0x and 1.15x
    /// scale to draw attention.
    private func setupPositionMarker() {
        let marker = SKShapeNode(circleOfRadius: 8)
        marker.fillColor = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        marker.strokeColor = .white
        marker.lineWidth = 2
        marker.zPosition = 100
        marker.isHidden = true

        // Heading direction cone (triangle pointing in travel direction)
        let conePath = CGMutablePath()
        conePath.move(to: CGPoint(x: 0, y: 18))     // tip
        conePath.addLine(to: CGPoint(x: -7, y: 4))   // bottom-left
        conePath.addLine(to: CGPoint(x: 7, y: 4))    // bottom-right
        conePath.closeSubpath()

        let cone = SKShapeNode(path: conePath)
        cone.fillColor = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 0.6)
        cone.strokeColor = .white
        cone.lineWidth = 1
        cone.zPosition = 99
        cone.isHidden = true
        self.headingCone = cone
        marker.addChild(cone)

        // Pulsing animation
        let scaleUp = SKAction.scale(to: 1.15, duration: 0.8)
        let scaleDown = SKAction.scale(to: 1.0, duration: 0.8)
        let pulse = SKAction.sequence([scaleUp, scaleDown])
        marker.run(SKAction.repeatForever(pulse))

        self.positionMarker = marker
        overlaysNode.addChild(marker)
    }

    /// Creates the compass indicator in the top-right corner of the scene.
    ///
    /// The compass consists of a semi-transparent background circle, a red north
    /// arrow, a white south arrow, and an "N" label.
    private func setupCompass() {
        let compass = SKNode()
        compass.zPosition = 200

        // Background circle
        let bg = SKShapeNode(circleOfRadius: 14)
        bg.fillColor = UIColor(white: 0.15, alpha: 0.8)
        bg.strokeColor = UIColor(white: 0.4, alpha: 0.8)
        bg.lineWidth = 1
        compass.addChild(bg)

        // North arrow (red triangle pointing up)
        let northPath = CGMutablePath()
        northPath.move(to: CGPoint(x: 0, y: 11))
        northPath.addLine(to: CGPoint(x: -4, y: -2))
        northPath.addLine(to: CGPoint(x: 4, y: -2))
        northPath.closeSubpath()

        let northArrow = SKShapeNode(path: northPath)
        northArrow.fillColor = UIColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 1.0)
        northArrow.strokeColor = .white
        northArrow.lineWidth = 0.5
        compass.addChild(northArrow)

        // South half (white triangle pointing down)
        let southPath = CGMutablePath()
        southPath.move(to: CGPoint(x: 0, y: -11))
        southPath.addLine(to: CGPoint(x: -4, y: 2))
        southPath.addLine(to: CGPoint(x: 4, y: 2))
        southPath.closeSubpath()

        let southArrow = SKShapeNode(path: southPath)
        southArrow.fillColor = UIColor(white: 0.85, alpha: 1.0)
        southArrow.strokeColor = UIColor(white: 0.5, alpha: 0.5)
        southArrow.lineWidth = 0.5
        compass.addChild(southArrow)

        // "N" label
        let nLabel = SKLabelNode(text: "N")
        nLabel.fontSize = 7
        nLabel.fontName = "Helvetica-Bold"
        nLabel.fontColor = .white
        nLabel.verticalAlignmentMode = .center
        nLabel.position = CGPoint(x: 0, y: -8)
        compass.addChild(nLabel)

        // Position in top-right corner
        compass.position = CGPoint(x: size.width - 22, y: size.height - 22)

        self.compassNode = compass
        overlaysNode.addChild(compass)
    }

    // MARK: - Scene Lifecycle

    #if os(iOS) || os(macOS) || os(tvOS)
    override func didMove(to view: SKView) {
        super.didMove(to: view)
        updateVisibleTiles()
    }
    #else
    override func sceneDidLoad() {
        super.sceneDidLoad()
        updateVisibleTiles()
    }
    #endif

    // MARK: - Tile Management

    /// Recalculates which tiles should be visible and updates the scene.
    ///
    /// This is called whenever the map center or zoom level changes. It:
    /// 1. Determines the center tile from the current coordinate and zoom
    /// 2. Calculates a 3x3 grid of tiles around the center
    /// 3. Removes tiles that are no longer visible
    /// 4. Adds sprites for newly visible tiles
    /// 5. Repositions all tiles with sub-tile precision
    func updateVisibleTiles() {
        guard let renderer = renderer,
              let center = renderer.centerCoordinate else {
            return
        }

        let zoom = renderer.currentZoom

        // Calculate which tiles are visible
        let centerTile = TileCoordinate(
            latitude: center.latitude,
            longitude: center.longitude,
            zoom: zoom
        )

        // For a watch screen, we typically need a 3x3 grid of tiles
        let visibleTiles = getVisibleTiles(around: centerTile, radius: 1)

        // Remove tiles that are no longer visible
        let visibleSet = Set(visibleTiles)
        tilesNode.children.forEach { node in
            if let tileName = node.name,
               let tile = parseTileName(tileName),
               !visibleSet.contains(tile) {
                node.removeFromParent()
            }
        }

        // Add new visible tiles
        for tile in visibleTiles {
            let tileName = makeTileName(tile)
            if tilesNode.childNode(withName: tileName) == nil {
                addTileSprite(for: tile)
            }
        }

        // Update tile positions
        updateTilePositions(centerTile: centerTile)
    }

    /// Returns all valid tiles within a radius of the center tile.
    ///
    /// - Parameters:
    ///   - center: The center tile coordinate.
    ///   - radius: The number of tiles to include in each direction (1 = 3x3 grid).
    /// - Returns: An array of valid ``TileCoordinate`` values.
    private func getVisibleTiles(around center: TileCoordinate, radius: Int) -> [TileCoordinate] {
        var tiles: [TileCoordinate] = []

        for dx in -radius...radius {
            for dy in -radius...radius {
                let tile = TileCoordinate(
                    x: center.x + dx,
                    y: center.y + dy,
                    z: center.z
                )
                if tile.isValid {
                    tiles.append(tile)
                }
            }
        }

        return tiles
    }

    /// Creates a SpriteKit sprite node for a tile and adds it to the scene.
    ///
    /// Attempts to load tile data from the renderer's tile store. If the tile
    /// exists, creates a textured sprite and caches the texture. If not,
    /// creates a placeholder tile with coordinate labels.
    ///
    /// - Parameter tile: The ``TileCoordinate`` to create a sprite for.
    private func addTileSprite(for tile: TileCoordinate) {
        guard let renderer = renderer,
              let tileData = renderer.getTileData(for: tile) else {
            // No tile data - show placeholder
            addPlaceholderTile(for: tile)
            return
        }

        // Create texture from tile data
        #if os(watchOS)
        guard let uiImage = UIImage(data: tileData) else {
            addPlaceholderTile(for: tile)
            return
        }
        #else
        guard let uiImage = UIImage(data: tileData) else {
            addPlaceholderTile(for: tile)
            return
        }
        #endif

        let texture = SKTexture(image: uiImage)
        textureCache[tile] = texture

        // Manage cache size
        if textureCache.count > maxCacheSize {
            // Remove oldest entries (simple FIFO for now)
            let keysToRemove = Array(textureCache.keys.prefix(textureCache.count - maxCacheSize))
            keysToRemove.forEach { textureCache.removeValue(forKey: $0) }
        }

        let sprite = SKSpriteNode(texture: texture)
        sprite.name = makeTileName(tile)
        sprite.size = CGSize(width: MapRenderer.tileSize, height: MapRenderer.tileSize)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        tilesNode.addChild(sprite)
    }

    /// Creates a gray placeholder tile with coordinate labels for debugging.
    ///
    /// - Parameter tile: The ``TileCoordinate`` to create a placeholder for.
    private func addPlaceholderTile(for tile: TileCoordinate) {
        let placeholder = SKShapeNode(rectOf: CGSize(
            width: MapRenderer.tileSize,
            height: MapRenderer.tileSize
        ))
        placeholder.name = makeTileName(tile)
        placeholder.fillColor = .darkGray
        placeholder.strokeColor = .gray
        placeholder.lineWidth = 1

        // Add tile coordinates as label (for debugging)
        let label = SKLabelNode(text: "\(tile.z)/\(tile.x)/\(tile.y)")
        label.fontSize = 10
        label.fontColor = .lightGray
        label.verticalAlignmentMode = .center
        placeholder.addChild(label)

        tilesNode.addChild(placeholder)
    }

    /// Repositions all tile sprites based on the current center coordinate.
    ///
    /// Uses Web Mercator math to calculate the fractional pixel offset within the
    /// center tile, providing smooth sub-tile scrolling. Each tile is positioned
    /// relative to the screen center based on its offset from the center tile.
    ///
    /// - Parameter centerTile: The tile coordinate at the map center.
    private func updateTilePositions(centerTile: TileCoordinate) {
        guard let renderer = renderer,
              let center = renderer.centerCoordinate else { return }

        let zoom = renderer.currentZoom
        let tileSize = MapRenderer.tileSize

        // Calculate the fractional position within the center tile
        let n = Double(1 << zoom)
        let xFraction = ((center.longitude + 180.0) / 360.0 * n).truncatingRemainder(dividingBy: 1.0)
        let latRad = center.latitude * .pi / 180.0
        let yFraction = ((1.0 - asinh(tan(latRad)) / .pi) / 2.0 * n).truncatingRemainder(dividingBy: 1.0)

        let centerOffset = CGPoint(
            x: CGFloat(0.5 - xFraction) * tileSize,
            y: CGFloat(yFraction - 0.5) * tileSize
        )

        tilesNode.children.forEach { node in
            guard let tileName = node.name,
                  let tile = parseTileName(tileName) else { return }

            let dx = tile.x - centerTile.x
            let dy = tile.y - centerTile.y

            node.position = CGPoint(
                x: size.width / 2 + CGFloat(dx) * tileSize + centerOffset.x,
                y: size.height / 2 - CGFloat(dy) * tileSize + centerOffset.y
            )
        }
    }

    // MARK: - Position Marker

    /// Updates the position marker to show the user's current GPS location.
    ///
    /// Converts the geographic coordinate to screen position using Web Mercator
    /// projection math, relative to the current map center.
    ///
    /// - Parameter coordinate: The user's current GPS coordinate.
    func updatePositionMarker(coordinate: CLLocationCoordinate2D) {
        guard let renderer = renderer,
              let center = renderer.centerCoordinate else {
            positionMarker?.isHidden = true
            return
        }

        let zoom = renderer.currentZoom
        let tileSize = MapRenderer.tileSize

        // Calculate pixel offset
        let n = Double(1 << zoom)

        let centerX = (center.longitude + 180.0) / 360.0 * n
        let centerLatRad = center.latitude * .pi / 180.0
        let centerY = (1.0 - asinh(tan(centerLatRad)) / .pi) / 2.0 * n

        let posX = (coordinate.longitude + 180.0) / 360.0 * n
        let posLatRad = coordinate.latitude * .pi / 180.0
        let posY = (1.0 - asinh(tan(posLatRad)) / .pi) / 2.0 * n

        let screenX = size.width / 2 + CGFloat(posX - centerX) * tileSize
        let screenY = size.height / 2 - CGFloat(posY - centerY) * tileSize

        positionMarker?.position = CGPoint(x: screenX, y: screenY)
        positionMarker?.isHidden = false
    }

    /// Rotates the heading cone to point in the compass direction.
    ///
    /// Converts the true heading (clockwise degrees from north) to SpriteKit's
    /// rotation system (counter-clockwise radians).
    ///
    /// - Parameter trueHeading: The compass heading in degrees (0 = north, 90 = east).
    func updateHeading(trueHeading: Double) {
        guard let cone = headingCone else { return }
        // SpriteKit rotation is counter-clockwise in radians; heading is clockwise degrees from north
        // In SpriteKit, 0 radians = pointing right, positive = counter-clockwise
        // Our cone points up (north) by default. To rotate it to the heading:
        // Convert heading (clockwise from north) to SpriteKit rotation (counter-clockwise from up)
        let rotation = -trueHeading * .pi / 180.0
        cone.zRotation = CGFloat(rotation)
        cone.isHidden = false
    }

    /// Hides both the position marker and heading cone.
    func hidePositionMarker() {
        positionMarker?.isHidden = true
        headingCone?.isHidden = true
    }

    // MARK: - Track Trail

    /// Renders a polyline trail showing the recorded hike track.
    ///
    /// Removes any existing trail and creates a new one from the given track points.
    /// Each point is projected from geographic coordinates to screen position using
    /// Web Mercator math. The trail is drawn as an orange 3pt line with rounded
    /// caps and joins.
    ///
    /// - Parameter trackPoints: The array of ``CLLocation`` points to render.
    func updateTrackTrail(trackPoints: [CLLocation]) {
        // Remove old track node
        trackNode?.removeFromParent()
        trackNode = nil

        guard let renderer = renderer,
              let center = renderer.centerCoordinate,
              trackPoints.count >= 2 else { return }

        let zoom = renderer.currentZoom
        let tileSize = MapRenderer.tileSize
        let n = Double(1 << zoom)

        let centerX = (center.longitude + 180.0) / 360.0 * n
        let centerLatRad = center.latitude * .pi / 180.0
        let centerY = (1.0 - asinh(tan(centerLatRad)) / .pi) / 2.0 * n

        let path = CGMutablePath()
        var started = false

        for point in trackPoints {
            let posX = (point.coordinate.longitude + 180.0) / 360.0 * n
            let posLatRad = point.coordinate.latitude * .pi / 180.0
            let posY = (1.0 - asinh(tan(posLatRad)) / .pi) / 2.0 * n

            let screenX = size.width / 2 + CGFloat(posX - centerX) * tileSize
            let screenY = size.height / 2 - CGFloat(posY - centerY) * tileSize

            if !started {
                path.move(to: CGPoint(x: screenX, y: screenY))
                started = true
            } else {
                path.addLine(to: CGPoint(x: screenX, y: screenY))
            }
        }

        let trail = SKShapeNode(path: path)
        trail.strokeColor = UIColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 0.9)
        trail.lineWidth = 3
        trail.lineCap = .round
        trail.lineJoin = .round
        trail.zPosition = 50
        trail.isAntialiased = true

        self.trackNode = trail
        overlaysNode.addChild(trail)
    }

    // MARK: - Waypoint Markers

    /// Updates the waypoint markers displayed on the map.
    ///
    /// Removes markers for waypoints that no longer exist, adds markers for
    /// new waypoints, and repositions all markers based on the current map
    /// center and zoom level. Each marker is an `SKNode` rendering the
    /// category's SF Symbol inside a colored pin shape.
    ///
    /// Markers use the naming convention `"waypoint-<uuid>"` for identification.
    ///
    /// - Parameter waypoints: The full list of waypoints to display on the map.
    func updateWaypointMarkers(waypoints: [Waypoint]) {
        guard let renderer = renderer,
              let center = renderer.centerCoordinate else { return }

        let zoom = renderer.currentZoom
        let tileSize = MapRenderer.tileSize

        let n = Double(1 << zoom)
        let centerX = (center.longitude + 180.0) / 360.0 * n
        let centerLatRad = center.latitude * .pi / 180.0
        let centerY = (1.0 - asinh(tan(centerLatRad)) / .pi) / 2.0 * n

        // Build set of current waypoint IDs
        let currentIds = Set(waypoints.map { "waypoint-\($0.id.uuidString)" })

        // Remove markers that no longer exist
        overlaysNode.children
            .filter { ($0.name ?? "").hasPrefix("waypoint-") && !currentIds.contains($0.name ?? "") }
            .forEach { $0.removeFromParent() }

        // Add or update markers
        for waypoint in waypoints {
            let nodeName = "waypoint-\(waypoint.id.uuidString)"

            // Calculate screen position from lat/lon
            let posX = (waypoint.longitude + 180.0) / 360.0 * n
            let posLatRad = waypoint.latitude * .pi / 180.0
            let posY = (1.0 - asinh(tan(posLatRad)) / .pi) / 2.0 * n

            let screenX = size.width / 2 + CGFloat(posX - centerX) * tileSize
            let screenY = size.height / 2 - CGFloat(posY - centerY) * tileSize

            if let existingNode = overlaysNode.childNode(withName: nodeName) {
                // Reposition existing marker
                existingNode.position = CGPoint(x: screenX, y: screenY)
            } else {
                // Create new marker
                let marker = createWaypointMarkerNode(for: waypoint)
                marker.name = nodeName
                marker.position = CGPoint(x: screenX, y: screenY)
                overlaysNode.addChild(marker)
            }
        }
    }

    /// Creates a SpriteKit node for a waypoint marker.
    ///
    /// Renders a colored circle with the category's SF Symbol icon inside, plus
    /// a small triangular pin stem pointing downward. The circle has a white
    /// border for visibility against any map background.
    ///
    /// - Parameter waypoint: The waypoint to create a marker for.
    /// - Returns: A configured `SKNode` representing the waypoint on the map.
    private func createWaypointMarkerNode(for waypoint: Waypoint) -> SKNode {
        let container = SKNode()
        // Between track trail (z=50) and position marker (z=100)
        container.zPosition = 75

        // Pin circle: 10pt radius chosen to be large enough to tap on the
        // watch's small screen but small enough not to obscure nearby tiles
        let circleRadius: CGFloat = 10
        let circle = SKShapeNode(circleOfRadius: circleRadius)
        circle.fillColor = colorFromHex(waypoint.category.colorHex)
        circle.strokeColor = .white
        circle.lineWidth = 1.5

        // Pin stem (triangle pointing down) — 6pt tall, 8pt wide at base
        let stemPath = CGMutablePath()
        stemPath.move(to: CGPoint(x: -4, y: -circleRadius))
        stemPath.addLine(to: CGPoint(x: 0, y: -circleRadius - 6))
        stemPath.addLine(to: CGPoint(x: 4, y: -circleRadius))
        stemPath.closeSubpath()

        let stem = SKShapeNode(path: stemPath)
        stem.fillColor = colorFromHex(waypoint.category.colorHex)
        stem.strokeColor = .white
        stem.lineWidth = 1

        container.addChild(stem)
        container.addChild(circle)

        // Category icon: rendered at 11pt and displayed at 13x13pt for crisp
        // rendering — the 2pt padding avoids clipping on rounded SF Symbols
        let iconPointSize: CGFloat = 11
        let iconSpriteSize: CGFloat = 13
        let iconConfig = UIImage.SymbolConfiguration(pointSize: iconPointSize, weight: .bold)
        if let iconImage = UIImage(systemName: waypoint.category.iconName, withConfiguration: iconConfig)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) {
            let iconTexture = SKTexture(image: iconImage)
            let iconSprite = SKSpriteNode(texture: iconTexture)
            iconSprite.size = CGSize(width: iconSpriteSize, height: iconSpriteSize)
            // Offset 1pt up to visually center within the circle
            iconSprite.position = CGPoint(x: 0, y: 1)
            container.addChild(iconSprite)
        }

        return container
    }

    /// Converts a 6-character hex color string to a `UIColor`.
    ///
    /// - Parameter hex: A hex string (e.g., "4A90D9") without the `#` prefix.
    /// - Returns: The corresponding `UIColor`, or `.orange` if parsing fails.
    private func colorFromHex(_ hex: String) -> UIColor {
        var hexValue: UInt64 = 0
        guard hex.count == 6, Scanner(string: hex).scanHexInt64(&hexValue) else {
            return .orange
        }
        return UIColor(
            red: CGFloat((hexValue >> 16) & 0xFF) / 255.0,
            green: CGFloat((hexValue >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hexValue & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    // MARK: - Helpers

    /// Creates a unique node name for a tile coordinate (e.g., "tile_14_8192_5461").
    ///
    /// - Parameter tile: The tile coordinate.
    /// - Returns: A string name for the SpriteKit node.
    private func makeTileName(_ tile: TileCoordinate) -> String {
        "tile_\(tile.z)_\(tile.x)_\(tile.y)"
    }

    /// Parses a tile node name back into a ``TileCoordinate``.
    ///
    /// - Parameter name: The node name string (e.g., "tile_14_8192_5461").
    /// - Returns: The parsed ``TileCoordinate``, or `nil` if the format is invalid.
    private func parseTileName(_ name: String) -> TileCoordinate? {
        let parts = name.split(separator: "_")
        guard parts.count == 4,
              parts[0] == "tile",
              let z = Int(parts[1]),
              let x = Int(parts[2]),
              let y = Int(parts[3]) else {
            return nil
        }
        return TileCoordinate(x: x, y: y, z: z)
    }
}

// MARK: - UIImage Extension for watchOS

#if os(watchOS)
import UIKit
#endif
