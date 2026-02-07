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
/// - A planned route polyline for turn-by-turn navigation
/// - Heading-up map rotation with user position in lower third
///
/// Tiles are organized in a 3x3 grid around the center tile, repositioned
/// using Web Mercator math to achieve sub-tile-precision scrolling.
///
/// ## Node hierarchy
/// ```
/// Scene
///   ├── mapContentNode   ← Rotates for heading-up display
///   │     ├── tilesNode        ← Contains tile sprites (z=0)
///   │     └── rotatingOverlaysNode ← Overlays that rotate with map
///   │           ├── routeNode (z=40) ← Planned route polyline (purple)
///   │           ├── trackNode (z=50) ← Recorded track trail (orange)
///   │           └── waypointMarkers (z=75)
///   ├── positionMarker (z=100) ← Stays screen-fixed in lower third
///   │     └── headingCone (z=99)
///   └── compassNode (z=200)    ← Stays screen-fixed, rotates to show north
/// ```
final class MapScene: SKScene {
    /// Weak reference to the renderer that provides tile data and coordinate state.
    private weak var renderer: MapRenderer?

    /// Container node for tiles and map overlays. Rotated for heading-up display.
    private let mapContentNode = SKNode()

    /// Parent node containing all tile sprites.
    private let tilesNode = SKNode()

    /// Parent node for overlay elements that rotate with the map (route, track, waypoints).
    private let rotatingOverlaysNode = SKNode()

    /// The blue circle marking the user's current GPS position (screen-fixed).
    private var positionMarker: SKShapeNode?

    /// A triangular cone on the position marker indicating compass heading.
    private var headingCone: SKShapeNode?

    /// A compass indicator showing north direction, positioned in the top-right corner.
    private var compassNode: SKNode?

    /// A polyline shape node showing the recorded hike track.
    private var trackNode: SKShapeNode?

    /// A polyline shape node showing the planned route for active navigation.
    private var routeNode: SKShapeNode?

    /// In-memory cache of tile textures to avoid re-creating them from PNG data.
    private var textureCache: [TileCoordinate: SKTexture] = [:]

    /// Maximum number of textures to keep in the cache before evicting old entries.
    private let maxCacheSize = 100

    /// Whether heading-up mode is active (map rotates so heading points up).
    var isHeadingUpMode: Bool = true

    /// The current heading in degrees (0 = north, 90 = east). Updated externally.
    private var currentHeadingDegrees: Double = 0

    /// The screen-space Y position of the user's position marker.
    /// Placed in the lower third of the display so more map is visible ahead.
    private var userScreenY: CGFloat {
        size.height * 0.25
    }

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

        // Map content node holds tiles and rotating overlays, and is rotated for heading-up
        mapContentNode.addChild(tilesNode)
        mapContentNode.addChild(rotatingOverlaysNode)
        addChild(mapContentNode)

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
    ///
    /// In heading-up mode, the marker stays at a fixed screen position in the lower third.
    /// The heading cone always points up (direction of travel) when heading-up is active.
    private func setupPositionMarker() {
        let marker = SKShapeNode(circleOfRadius: 8)
        marker.fillColor = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        marker.strokeColor = .white
        marker.lineWidth = 2
        marker.zPosition = 100
        marker.isHidden = true

        // Heading direction cone (triangle pointing up = direction of travel)
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
        // Added directly to scene (not mapContentNode) so it stays screen-fixed
        addChild(marker)
    }

    /// Creates the compass indicator in the top-right corner of the scene.
    ///
    /// The compass consists of a semi-transparent background circle, a red north
    /// arrow, a white south arrow, and an "N" label. In heading-up mode, the
    /// compass rotates to indicate where north is relative to the current heading.
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
        // Added directly to scene (not mapContentNode) so it stays screen-fixed
        addChild(compass)
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

        // In heading-up mode, the map is rotated, so we need a larger grid to cover
        // screen corners. A 5x5 grid ensures full coverage at any rotation angle.
        let tileRadius = isHeadingUpMode ? 2 : 1
        let visibleTiles = getVisibleTiles(around: centerTile, radius: tileRadius)

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

    /// The screen-space anchor point where the map center coordinate is rendered.
    ///
    /// In heading-up mode this is the user's position in the lower third.
    /// In north-up mode this is the screen center.
    private var mapAnchorPoint: CGPoint {
        if isHeadingUpMode {
            return CGPoint(x: size.width / 2, y: userScreenY)
        } else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
    }

    /// Repositions all tile sprites based on the current center coordinate.
    ///
    /// Uses Web Mercator math to calculate the fractional pixel offset within the
    /// center tile, providing smooth sub-tile scrolling. Each tile is positioned
    /// relative to the map anchor point (lower third in heading-up mode, or screen
    /// center in north-up mode).
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

        // When mapContentNode is positioned at the anchor and rotated, tile positions
        // must be relative to (0,0) in mapContentNode's local coordinate space.
        // If mapContentNode.position == anchor, then a child at (0,0) appears at anchor on screen.
        // If mapContentNode.position == .zero (north-up), children are in absolute screen coords.
        let offsetX: CGFloat
        let offsetY: CGFloat
        if isHeadingUpMode {
            // mapContentNode is positioned at anchor, so (0,0) = anchor on screen
            offsetX = 0
            offsetY = 0
        } else {
            // mapContentNode at (0,0), so use anchor directly
            offsetX = mapAnchorPoint.x
            offsetY = mapAnchorPoint.y
        }

        tilesNode.children.forEach { node in
            guard let tileName = node.name,
                  let tile = parseTileName(tileName) else { return }

            let dx = tile.x - centerTile.x
            let dy = tile.y - centerTile.y

            node.position = CGPoint(
                x: offsetX + CGFloat(dx) * tileSize + centerOffset.x,
                y: offsetY - CGFloat(dy) * tileSize + centerOffset.y
            )
        }
    }

    // MARK: - Position Marker

    /// Updates the position marker to show the user's current GPS location.
    ///
    /// In heading-up mode, the marker stays at a fixed screen position in the
    /// lower third of the display — the map moves and rotates underneath it.
    /// In north-up mode, the marker moves on screen relative to the map center.
    ///
    /// - Parameter coordinate: The user's current GPS coordinate.
    func updatePositionMarker(coordinate: CLLocationCoordinate2D) {
        guard let renderer = renderer,
              let center = renderer.centerCoordinate else {
            positionMarker?.isHidden = true
            return
        }

        if isHeadingUpMode {
            // Fixed position in lower third of screen
            positionMarker?.position = CGPoint(x: size.width / 2, y: userScreenY)
        } else {
            // Calculate pixel offset from map center
            let zoom = renderer.currentZoom
            let tileSize = MapRenderer.tileSize
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
        }
        positionMarker?.isHidden = false
    }

    /// Updates the map rotation and heading indicators based on compass heading.
    ///
    /// In heading-up mode:
    /// - Rotates the entire `mapContentNode` so the heading direction points up
    /// - The heading cone always points straight up (direction of travel)
    /// - The compass rotates to show where north is
    ///
    /// In north-up mode:
    /// - The map stays fixed (north up)
    /// - The heading cone rotates to show direction of travel
    ///
    /// - Parameter trueHeading: The compass heading in degrees (0 = north, 90 = east).
    func updateHeading(trueHeading: Double) {
        currentHeadingDegrees = trueHeading

        if isHeadingUpMode {
            // Rotate map so heading points up. The rotation pivot is at the
            // mapContentNode's position, so we set its position to the user's
            // screen location and rotate around that point.
            let headingRadians = CGFloat(-trueHeading * .pi / 180.0)
            let anchor = mapAnchorPoint
            mapContentNode.position = anchor
            mapContentNode.zRotation = headingRadians

            // Heading cone always points up in heading-up mode (direction of travel)
            headingCone?.zRotation = 0
            headingCone?.isHidden = false

            // Compass rotates to show north direction relative to heading
            compassNode?.zRotation = headingRadians
        } else {
            // North-up mode: map doesn't rotate
            mapContentNode.position = .zero
            mapContentNode.zRotation = 0

            // Rotate heading cone to show direction of travel
            let rotation = -trueHeading * .pi / 180.0
            headingCone?.zRotation = CGFloat(rotation)
            headingCone?.isHidden = false

            // Compass stays fixed (north is up)
            compassNode?.zRotation = 0
        }
    }

    /// Hides both the position marker and heading cone.
    func hidePositionMarker() {
        positionMarker?.isHidden = true
        headingCone?.isHidden = true
    }

    // MARK: - Coordinate Projection

    /// Projects a geographic coordinate to a position in the `mapContentNode`'s local coordinate space.
    ///
    /// This accounts for the heading-up offset so that overlays (track trail, route, waypoints)
    /// positioned in `rotatingOverlaysNode` align correctly with the tiles.
    ///
    /// - Parameter coordinate: The geographic coordinate to project.
    /// - Returns: The position in `mapContentNode` local space, or `nil` if no renderer/center is available.
    private func projectToMapLocal(_ coordinate: CLLocationCoordinate2D) -> CGPoint? {
        guard let renderer = renderer,
              let center = renderer.centerCoordinate else { return nil }

        let zoom = renderer.currentZoom
        let tileSize = MapRenderer.tileSize
        let n = Double(1 << zoom)

        let centerX = (center.longitude + 180.0) / 360.0 * n
        let centerLatRad = center.latitude * .pi / 180.0
        let centerY = (1.0 - asinh(tan(centerLatRad)) / .pi) / 2.0 * n

        let posX = (coordinate.longitude + 180.0) / 360.0 * n
        let posLatRad = coordinate.latitude * .pi / 180.0
        let posY = (1.0 - asinh(tan(posLatRad)) / .pi) / 2.0 * n

        // Same offset logic as updateTilePositions
        let offsetX: CGFloat
        let offsetY: CGFloat
        if isHeadingUpMode {
            offsetX = 0
            offsetY = 0
        } else {
            offsetX = mapAnchorPoint.x
            offsetY = mapAnchorPoint.y
        }

        return CGPoint(
            x: offsetX + CGFloat(posX - centerX) * tileSize,
            y: offsetY - CGFloat(posY - centerY) * tileSize
        )
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

        guard trackPoints.count >= 2 else { return }

        let path = CGMutablePath()
        var started = false

        for point in trackPoints {
            guard let screenPos = projectToMapLocal(point.coordinate) else { continue }

            if !started {
                path.move(to: screenPos)
                started = true
            } else {
                path.addLine(to: screenPos)
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
        rotatingOverlaysNode.addChild(trail)
    }

    // MARK: - Route Polyline

    /// Renders a planned route polyline on the map for active navigation.
    ///
    /// Removes any existing route polyline and creates a new purple line from the
    /// given coordinates. Each coordinate is projected from geographic to screen
    /// position using Web Mercator math. The route line sits below the track trail
    /// (z=40 vs z=50) so recorded tracks overlay the planned route.
    ///
    /// - Parameter coordinates: The ordered polyline coordinates of the planned route,
    ///   or an empty array to clear the route display.
    func updateRouteLine(coordinates: [CLLocationCoordinate2D]) {
        // Remove old route node
        routeNode?.removeFromParent()
        routeNode = nil

        guard coordinates.count >= 2 else { return }

        let path = CGMutablePath()
        var started = false

        for coord in coordinates {
            guard let screenPos = projectToMapLocal(coord) else { continue }

            if !started {
                path.move(to: screenPos)
                started = true
            } else {
                path.addLine(to: screenPos)
            }
        }

        let routeLine = SKShapeNode(path: path)
        routeLine.strokeColor = UIColor(red: 0.58, green: 0.29, blue: 0.85, alpha: 0.9)
        routeLine.lineWidth = 4
        routeLine.lineCap = .round
        routeLine.lineJoin = .round
        routeLine.zPosition = 40
        routeLine.isAntialiased = true

        self.routeNode = routeLine
        rotatingOverlaysNode.addChild(routeLine)
    }

    /// Removes the planned route polyline from the map.
    func clearRouteLine() {
        routeNode?.removeFromParent()
        routeNode = nil
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
        guard renderer != nil else { return }

        // Build set of current waypoint IDs
        let currentIds = Set(waypoints.map { "waypoint-\($0.id.uuidString)" })

        // Remove markers that no longer exist
        rotatingOverlaysNode.children
            .filter { ($0.name ?? "").hasPrefix("waypoint-") && !currentIds.contains($0.name ?? "") }
            .forEach { $0.removeFromParent() }

        // Add or update markers
        for waypoint in waypoints {
            let nodeName = "waypoint-\(waypoint.id.uuidString)"
            let coord = CLLocationCoordinate2D(latitude: waypoint.latitude, longitude: waypoint.longitude)

            guard let screenPos = projectToMapLocal(coord) else { continue }

            if let existingNode = rotatingOverlaysNode.childNode(withName: nodeName) {
                // Reposition existing marker
                existingNode.position = screenPos
            } else {
                // Create new marker
                let marker = createWaypointMarkerNode(for: waypoint)
                marker.name = nodeName
                marker.position = screenPos
                rotatingOverlaysNode.addChild(marker)
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
    // MARK: - Waypoint Marker Layout Constants

    /// Radius of the circular pin head (10pt: large enough to tap on watch, small enough to not obscure map).
    private let pinCircleRadius: CGFloat = 10
    /// Height of the triangular pin stem below the circle.
    private let pinStemHeight: CGFloat = 6
    /// Half-width of the pin stem base.
    private let pinStemHalfWidth: CGFloat = 4
    /// Stroke width for the pin circle border.
    private let pinCircleStrokeWidth: CGFloat = 1.5
    /// Stroke width for the pin stem border.
    private let pinStemStrokeWidth: CGFloat = 1.0
    /// SF Symbol rendering point size for the category icon.
    private let pinIconPointSize: CGFloat = 11
    /// Display size of the icon sprite (2pt larger than pointSize to avoid clipping rounded symbols).
    private let pinIconSpriteSize: CGFloat = 13
    /// Vertical offset to visually center the icon within the circle.
    private let pinIconVerticalOffset: CGFloat = 1
    /// Z-position for waypoint markers (between track trail at 50 and position marker at 100).
    private let waypointZPosition: CGFloat = 75

    private func createWaypointMarkerNode(for waypoint: Waypoint) -> SKNode {
        let container = SKNode()
        container.zPosition = waypointZPosition

        let pinColor = colorFromHex(waypoint.category.colorHex)

        // Pin circle
        let circle = SKShapeNode(circleOfRadius: pinCircleRadius)
        circle.fillColor = pinColor
        circle.strokeColor = .white
        circle.lineWidth = pinCircleStrokeWidth

        // Pin stem (triangle pointing down)
        let stemPath = CGMutablePath()
        stemPath.move(to: CGPoint(x: -pinStemHalfWidth, y: -pinCircleRadius))
        stemPath.addLine(to: CGPoint(x: 0, y: -pinCircleRadius - pinStemHeight))
        stemPath.addLine(to: CGPoint(x: pinStemHalfWidth, y: -pinCircleRadius))
        stemPath.closeSubpath()

        let stem = SKShapeNode(path: stemPath)
        stem.fillColor = pinColor
        stem.strokeColor = .white
        stem.lineWidth = pinStemStrokeWidth

        container.addChild(stem)
        container.addChild(circle)

        // Category icon rendered as SF Symbol texture
        let iconConfig = UIImage.SymbolConfiguration(pointSize: pinIconPointSize, weight: .bold)
        if let iconImage = UIImage(systemName: waypoint.category.iconName, withConfiguration: iconConfig)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) {
            let iconTexture = SKTexture(image: iconImage)
            let iconSprite = SKSpriteNode(texture: iconTexture)
            iconSprite.size = CGSize(width: pinIconSpriteSize, height: pinIconSpriteSize)
            iconSprite.position = CGPoint(x: 0, y: pinIconVerticalOffset)
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
