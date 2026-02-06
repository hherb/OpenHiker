import Foundation
import SpriteKit
import CoreLocation

/// SpriteKit-based map renderer for watchOS
/// Displays pre-rendered raster tiles from an MBTiles database
final class MapRenderer: ObservableObject {
    // MARK: - Published Properties

    @Published var isLoading = false
    @Published var loadError: Error?
    @Published var currentZoom: Int = 14
    @Published var centerCoordinate: CLLocationCoordinate2D?

    // MARK: - Properties

    private var tileStore: TileStore?
    private var mapScene: MapScene?
    private var regionMetadata: RegionMetadata?

    /// Zoom level bounds
    let minZoom: Int
    let maxZoom: Int

    /// Tile size in points (for rendering)
    static let tileSize: CGFloat = 256

    // MARK: - Initialization

    init(minZoom: Int = 12, maxZoom: Int = 16) {
        self.minZoom = minZoom
        self.maxZoom = maxZoom
    }

    // MARK: - Public Methods

    /// Load a region's MBTiles database
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

    /// Unload current region
    func unloadRegion() {
        tileStore?.close()
        tileStore = nil
        regionMetadata = nil
        centerCoordinate = nil
    }

    /// Create a SpriteKit scene for the map
    func createScene(size: CGSize) -> MapScene {
        let mapScene = MapScene(size: size, renderer: self)
        self.mapScene = mapScene
        return mapScene
    }

    /// Get tile image data for a coordinate
    func getTileData(for coordinate: TileCoordinate) -> Data? {
        guard let store = tileStore else { return nil }
        return try? store.getTile(coordinate)
    }

    /// Update the map center
    func setCenter(_ coordinate: CLLocationCoordinate2D) {
        centerCoordinate = coordinate
        mapScene?.updateVisibleTiles()
    }

    /// Zoom in
    func zoomIn() {
        guard currentZoom < maxZoom else { return }
        currentZoom += 1
        mapScene?.updateVisibleTiles()
    }

    /// Zoom out
    func zoomOut() {
        guard currentZoom > minZoom else { return }
        currentZoom -= 1
        mapScene?.updateVisibleTiles()
    }

    /// Set zoom level
    func setZoom(_ zoom: Int) {
        let clampedZoom = max(minZoom, min(maxZoom, zoom))
        guard clampedZoom != currentZoom else { return }
        currentZoom = clampedZoom
        mapScene?.updateVisibleTiles()
    }

    /// Check if a coordinate is within the loaded region
    func isCoordinateInRegion(_ coordinate: CLLocationCoordinate2D) -> Bool {
        regionMetadata?.contains(coordinate: coordinate) ?? false
    }
}

// MARK: - SpriteKit Map Scene

/// SpriteKit scene that displays map tiles
final class MapScene: SKScene {
    private weak var renderer: MapRenderer?

    /// Node containing all tile sprites
    private let tilesNode = SKNode()

    /// Node for overlays (current position, route, etc.)
    private let overlaysNode = SKNode()

    /// Current user position marker
    private var positionMarker: SKShapeNode?

    /// Cache of loaded tile textures
    private var textureCache: [TileCoordinate: SKTexture] = [:]

    /// Maximum cache size
    private let maxCacheSize = 100

    // MARK: - Initialization

    init(size: CGSize, renderer: MapRenderer) {
        self.renderer = renderer
        super.init(size: size)

        backgroundColor = .darkGray
        scaleMode = .resizeFill

        addChild(tilesNode)
        addChild(overlaysNode)

        setupPositionMarker()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupPositionMarker() {
        let marker = SKShapeNode(circleOfRadius: 8)
        marker.fillColor = .blue
        marker.strokeColor = .white
        marker.lineWidth = 2
        marker.zPosition = 100
        marker.isHidden = true

        // Pulsing animation
        let scaleUp = SKAction.scale(to: 1.2, duration: 0.5)
        let scaleDown = SKAction.scale(to: 1.0, duration: 0.5)
        let pulse = SKAction.sequence([scaleUp, scaleDown])
        marker.run(SKAction.repeatForever(pulse))

        self.positionMarker = marker
        overlaysNode.addChild(marker)
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

    /// Update the visible tiles based on current center and zoom
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

    /// Update the current position marker
    func updatePositionMarker(coordinate: CLLocationCoordinate2D) {
        guard let renderer = renderer,
              let center = renderer.centerCoordinate else {
            positionMarker?.isHidden = true
            return
        }

        let zoom = renderer.currentZoom
        let tileSize = MapRenderer.tileSize

        // Convert coordinate to screen position
        let centerTile = TileCoordinate(
            latitude: center.latitude,
            longitude: center.longitude,
            zoom: zoom
        )
        let positionTile = TileCoordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            zoom: zoom
        )

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

    /// Hide the position marker
    func hidePositionMarker() {
        positionMarker?.isHidden = true
    }

    // MARK: - Helpers

    private func makeTileName(_ tile: TileCoordinate) -> String {
        "tile_\(tile.z)_\(tile.x)_\(tile.y)"
    }

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
