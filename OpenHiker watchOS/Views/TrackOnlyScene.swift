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

import SpriteKit
import CoreLocation
import WatchKit
import os

/// A lightweight SpriteKit scene that displays a recorded GPS trail on a pure black background.
///
/// Used as a fallback when no map region is loaded, so the user can see their recorded trail
/// in real time during hike recording. The trail is drawn as a purple polyline with a cyan
/// position marker on a black OLED-optimized background.
///
/// The scene uses a simple geographic projection (meters → screen points) rather than
/// Web Mercator tile math, since there are no tiles to align with. The Digital Crown
/// controls the visible radius from 100m to 3km.
///
/// ## Node hierarchy
/// ```
/// Scene (black background)
///   ├── mapContentNode         ← Rotates for heading-up display
///   │     └── trackNode (z=50)  ← Purple trail polyline
///   ├── positionMarker (z=100)  ← Cyan GPS dot (screen-fixed)
///   │     └── headingCone (z=99)
///   ├── compassNode (z=200)     ← Red/white compass (screen-fixed)
///   └── radiusLabel (z=200)     ← "500m" radius indicator
/// ```
final class TrackOnlyScene: SKScene {

    // MARK: - Configuration

    /// Available zoom radius values in meters, controlled by Digital Crown.
    static let viewRadii: [Double] = [100, 250, 500, 1000, 2000, 3000]

    /// Meters per degree of latitude (approximately constant).
    private static let metersPerDegreeLat: Double = 111_320.0

    /// Logger for track-only scene events.
    private static let logger = Logger(
        subsystem: "com.openhiker.watchos",
        category: "TrackOnlyScene"
    )

    // MARK: - State

    /// The geographic center of the display (always the user's current GPS position).
    private var centerCoordinate: CLLocationCoordinate2D?

    /// The visible radius in meters (controlled by Digital Crown).
    private var viewRadiusMeters: Double = 500.0

    /// Whether heading-up mode is active (map rotates so heading points up).
    var isHeadingUpMode: Bool = true

    /// The current compass heading in degrees (0 = north, 90 = east).
    private var currentHeadingDegrees: Double = 0

    // MARK: - Scene Nodes

    /// Container node for overlays that rotate with heading.
    private let mapContentNode = SKNode()

    /// The purple polyline showing the recorded hike track.
    private var trackNode: SKShapeNode?

    /// The cyan circle marking the user's current GPS position (screen-fixed).
    private var positionMarker: SKShapeNode?

    /// A triangular cone on the position marker indicating compass heading.
    private var headingCone: SKShapeNode?

    /// A compass indicator showing north direction, positioned in the top-right corner.
    private var compassNode: SKNode?

    /// A label showing the current view radius (e.g., "500m").
    private var radiusLabel: SKLabelNode?

    /// The screen-space Y position of the user's position marker.
    /// Placed in the lower third of the display so more trail is visible ahead.
    private var userScreenY: CGFloat {
        size.height * 0.25
    }

    // MARK: - Initialization

    /// Creates a new track-only scene with the given size.
    ///
    /// Sets up the node hierarchy, position marker, compass, and radius label
    /// on a pure black background optimized for OLED displays.
    ///
    /// - Parameter size: The scene size in points (typically the watch screen size).
    override init(size: CGSize) {
        super.init(size: size)

        backgroundColor = .black
        scaleMode = .resizeFill

        addChild(mapContentNode)

        setupPositionMarker()
        setupCompass()
        setupRadiusLabel()

        Self.logger.info("TrackOnlyScene initialized at \(size.width)x\(size.height)")
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    /// Creates the cyan GPS position marker with a heading cone and pulsing animation.
    ///
    /// The marker is an 8pt radius circle in cyan with a white border. A triangular
    /// heading cone is added as a child node. The marker pulses between 1.0x and 1.15x
    /// scale to draw attention.
    private func setupPositionMarker() {
        let marker = SKShapeNode(circleOfRadius: 8)
        marker.fillColor = .cyan
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
        cone.fillColor = UIColor.cyan.withAlphaComponent(0.6)
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
        addChild(compass)
    }

    /// Creates the radius indicator label in the bottom-left corner.
    ///
    /// Shows the current view radius (e.g., "500m" or "2.0 km") so the user
    /// knows how much area is visible on screen.
    private func setupRadiusLabel() {
        let label = SKLabelNode(text: formatRadius(viewRadiusMeters))
        label.fontSize = 11
        label.fontName = "Helvetica"
        label.fontColor = UIColor(white: 0.7, alpha: 1.0)
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .bottom
        label.position = CGPoint(x: 8, y: 8)
        label.zPosition = 200
        self.radiusLabel = label
        addChild(label)
    }

    // MARK: - Public API

    /// Updates the geographic center of the display.
    ///
    /// The center is always the user's current GPS position. All trail points
    /// are projected relative to this center.
    ///
    /// - Parameter coordinate: The user's current GPS coordinate.
    func updateCenter(_ coordinate: CLLocationCoordinate2D) {
        centerCoordinate = coordinate
    }

    /// Sets the visible radius and updates the radius label.
    ///
    /// - Parameter meters: The new visible radius in meters.
    func setViewRadius(_ meters: Double) {
        viewRadiusMeters = meters
        radiusLabel?.text = formatRadius(meters)
    }

    /// Renders a polyline trail showing the recorded hike track.
    ///
    /// Removes any existing trail and creates a new one from the given track points.
    /// Each point is projected from geographic coordinates to screen position using
    /// simple geographic distance math. The trail is drawn as a purple 3pt line with
    /// rounded caps and joins.
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
            guard let screenPos = projectToLocal(point.coordinate) else { continue }

            if !started {
                path.move(to: screenPos)
                started = true
            } else {
                path.addLine(to: screenPos)
            }
        }

        let trail = SKShapeNode(path: path)
        trail.strokeColor = UIColor(red: 0.6, green: 0.2, blue: 0.9, alpha: 0.9)
        trail.lineWidth = 3
        trail.lineCap = .round
        trail.lineJoin = .round
        trail.zPosition = 50
        trail.isAntialiased = true

        self.trackNode = trail
        mapContentNode.addChild(trail)
    }

    /// Updates the position marker to show the user's current GPS location.
    ///
    /// In heading-up mode, the marker stays at a fixed screen position in the
    /// lower third of the display. In north-up mode, the marker is always
    /// at screen center (since the view is always centered on the user).
    ///
    /// - Parameter coordinate: The user's current GPS coordinate.
    func updatePositionMarker(coordinate: CLLocationCoordinate2D) {
        if isHeadingUpMode {
            positionMarker?.position = CGPoint(x: size.width / 2, y: userScreenY)
        } else {
            positionMarker?.position = CGPoint(x: size.width / 2, y: size.height / 2)
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

        let anchor: CGPoint
        if isHeadingUpMode {
            anchor = CGPoint(x: size.width / 2, y: userScreenY)
        } else {
            anchor = CGPoint(x: size.width / 2, y: size.height / 2)
        }

        if isHeadingUpMode {
            let headingRadians = CGFloat(-trueHeading * .pi / 180.0)
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

    // MARK: - Coordinate Projection

    /// Projects a geographic coordinate to a position in the `mapContentNode`'s local coordinate space.
    ///
    /// Uses simple geographic distance (meters per degree) rather than Web Mercator,
    /// since there are no tiles to align with. The projection maps the distance from the
    /// center coordinate to screen points based on the current view radius.
    ///
    /// - Parameter coordinate: The geographic coordinate to project.
    /// - Returns: The screen position in `mapContentNode` local space, or `nil` if the center is not set.
    private func projectToLocal(_ coordinate: CLLocationCoordinate2D) -> CGPoint? {
        guard let center = centerCoordinate else { return nil }

        let metersPerDegreeLon = Self.metersPerDegreeLat * cos(center.latitude * .pi / 180.0)

        let dx = (coordinate.longitude - center.longitude) * metersPerDegreeLon
        let dy = (coordinate.latitude - center.latitude) * Self.metersPerDegreeLat

        // Map meters to screen points: half the smaller screen dimension = viewRadiusMeters
        let screenRadius = min(size.width, size.height) / 2.0
        let pointsPerMeter = screenRadius / CGFloat(viewRadiusMeters)

        // Offset for non-heading-up mode (heading-up uses mapContentNode position instead)
        let offsetX: CGFloat
        let offsetY: CGFloat
        if isHeadingUpMode {
            offsetX = 0
            offsetY = 0
        } else {
            offsetX = size.width / 2
            offsetY = size.height / 2
        }

        return CGPoint(
            x: offsetX + CGFloat(dx) * pointsPerMeter,
            y: offsetY + CGFloat(dy) * pointsPerMeter
        )
    }

    // MARK: - Formatting

    /// Formats a radius value for display (e.g., "500m" or "2.0 km").
    ///
    /// - Parameter meters: The radius in meters.
    /// - Returns: A human-readable string.
    private func formatRadius(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000.0)
        } else {
            return "\(Int(meters))m"
        }
    }
}
