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

import UIKit
import MapKit
import SwiftUI
import Charts
import CoreLocation

/// Generates multi-page PDF hike reports on iOS.
///
/// Uses `UIGraphicsPDFRenderer` to compose a professional-quality report with:
/// - **Page 1**: Cover with map snapshot, title, date, and statistics table
/// - **Page 2**: Full-width elevation profile chart with annotations
/// - **Page 3+**: Photo gallery (2-up grid) with captions -- skipped if no photos
/// - **Final page**: Waypoint table and user comments
///
/// ## Dependencies
/// - `MKMapSnapshotter` for static map images with route polyline overlay
/// - `ImageRenderer` (iOS 16+) for rendering SwiftUI Charts to a bitmap
/// - `UIGraphicsPDFRenderer` for PDF composition
///
/// ## Thread Safety
/// Export must be called from an async context. Map snapshot and chart rendering
/// are performed asynchronously.
///
/// ## Usage
/// ```swift
/// let pdfData = try await PDFExporter.exportAsPDF(
///     route: savedRoute,
///     waypoints: linkedWaypoints,
///     useMetric: true
/// )
/// ```
enum PDFExporter {

    // MARK: - Constants

    /// Standard US Letter page size in points (612 x 792).
    private static let pageSize = CGSize(width: 612, height: 792)

    /// Page margins in points.
    private static let margin: CGFloat = 50

    /// Usable content width after subtracting left and right margins.
    private static let contentWidth: CGFloat = 512

    /// Height allocated for the map snapshot on the cover page.
    private static let mapSnapshotHeight: CGFloat = 280

    /// Height allocated for the elevation chart on page 2.
    private static let elevationChartHeight: CGFloat = 300

    /// Grid cell size for photo thumbnails (2-up layout).
    private static let photoGridCellSize = CGSize(width: 240, height: 180)

    /// Spacing between photo grid cells.
    private static let photoGridSpacing: CGFloat = 32

    /// Maximum photos per page in the gallery.
    private static let photosPerPage = 4

    /// Font size for the title heading.
    private static let titleFontSize: CGFloat = 24

    /// Font size for section headings.
    private static let sectionFontSize: CGFloat = 16

    /// Font size for body text and table content.
    private static let bodyFontSize: CGFloat = 11

    /// Font size for small annotations and captions.
    private static let captionFontSize: CGFloat = 9

    /// Row height in the statistics and waypoint tables.
    private static let tableRowHeight: CGFloat = 22

    /// Number of coordinate decimal places for display.
    private static let coordinateDecimalPlaces = 4

    /// Padding factor applied to map bounds for visual breathing room.
    private static let mapBoundsPaddingFactor = 1.3

    /// Minimum coordinate span in degrees for the map region.
    private static let mapMinSpanDegrees = 0.005

    /// Line width for the route polyline on the map snapshot.
    private static let routeLineWidth: CGFloat = 3.0

    /// Diameter of the start/end marker circles on the map snapshot.
    private static let startEndMarkerSize: CGFloat = 12

    /// Diameter of waypoint marker circles on the map snapshot.
    private static let waypointMarkerSize: CGFloat = 8

    /// Height reserved below each photo for caption text.
    private static let photoCaptionHeight: CGFloat = 40

    /// Maximum characters shown for a waypoint note in the table.
    private static let noteMaxDisplayLength = 30

    /// Column widths for the waypoint table: #, Name, Category, Coordinate, Note.
    private static let waypointTableColumnWidths: [CGFloat] = [30, 120, 80, 150, 132]

    // MARK: - Error Types

    /// Errors that can occur during PDF export.
    enum ExportError: Error, LocalizedError {
        /// The map snapshot generation failed.
        case mapSnapshotFailed(String)
        /// The elevation chart rendering failed.
        case chartRenderFailed
        /// The PDF rendering context could not be created.
        case pdfRenderFailed

        var errorDescription: String? {
            switch self {
            case .mapSnapshotFailed(let message):
                return "Map snapshot failed: \(message)"
            case .chartRenderFailed:
                return "Failed to render elevation chart"
            case .pdfRenderFailed:
                return "Failed to create PDF"
            }
        }
    }

    // MARK: - Public API

    /// Generates a multi-page PDF report for a completed hike.
    ///
    /// - Parameters:
    ///   - route: The completed hike to export.
    ///   - waypoints: Waypoints linked to this hike (may be empty).
    ///   - useMetric: If `true`, uses km/m; if `false`, uses mi/ft.
    /// - Returns: The PDF document as `Data`.
    /// - Throws: ``ExportError`` if map snapshot or chart rendering fails.
    static func exportAsPDF(
        route: SavedRoute,
        waypoints: [Waypoint],
        useMetric: Bool
    ) async throws -> Data {
        // Decode track data
        let locations = TrackCompression.decode(route.trackData)
        let coordinates = locations.map { $0.coordinate }
        let elevationProfile = TrackCompression.extractElevationProfile(route.trackData)

        // Generate map snapshot
        let mapImage = try await generateMapSnapshot(
            coordinates: coordinates,
            waypoints: waypoints,
            size: CGSize(width: contentWidth * 2, height: mapSnapshotHeight * 2)
        )

        // Generate elevation chart image
        let chartImage = renderElevationChart(
            elevationData: elevationProfile,
            useMetric: useMetric
        )

        // Fetch photo data for waypoints that have photos
        let photoEntries = loadWaypointPhotos(waypoints: waypoints)

        // Compose PDF
        let pdfData = renderPDF(
            route: route,
            waypoints: waypoints,
            mapImage: mapImage,
            chartImage: chartImage,
            photoEntries: photoEntries,
            useMetric: useMetric
        )

        return pdfData
    }

    // MARK: - Map Snapshot

    /// Generates a static map image with the route polyline and waypoint markers.
    ///
    /// Uses `MKMapSnapshotter` with standard Apple Maps (OpenTopoMap tiles cannot
    /// be used in MKMapSnapshotter). The route polyline is drawn in orange, with
    /// green start and red end markers.
    ///
    /// - Parameters:
    ///   - coordinates: The route polyline coordinates.
    ///   - waypoints: Waypoints to render as markers.
    ///   - size: The desired image size in pixels.
    /// - Returns: A `UIImage` of the map with overlays.
    /// - Throws: ``ExportError/mapSnapshotFailed(_:)`` if the snapshotter fails.
    private static func generateMapSnapshot(
        coordinates: [CLLocationCoordinate2D],
        waypoints: [Waypoint],
        size: CGSize
    ) async throws -> UIImage {
        guard !coordinates.isEmpty else {
            // Return a blank placeholder if no track data
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                UIColor.systemGray5.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
        }

        // Compute region from coordinates
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * mapBoundsPaddingFactor, mapMinSpanDegrees),
            longitudeDelta: max((maxLon - minLon) * mapBoundsPaddingFactor, mapMinSpanDegrees)
        )
        let region = MKCoordinateRegion(center: center, span: span)

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.mapType = .standard

        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot: MKMapSnapshotter.Snapshot
        do {
            snapshot = try await snapshotter.start()
        } catch {
            throw ExportError.mapSnapshotFailed(error.localizedDescription)
        }

        // Draw overlays on the snapshot
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            snapshot.image.draw(at: .zero)
            let cgContext = context.cgContext

            // Draw route polyline
            if coordinates.count >= 2 {
                cgContext.setStrokeColor(UIColor.orange.cgColor)
                cgContext.setLineWidth(routeLineWidth)
                cgContext.setLineCap(.round)
                cgContext.setLineJoin(.round)

                let firstPoint = snapshot.point(for: coordinates[0])
                cgContext.move(to: firstPoint)

                for coord in coordinates.dropFirst() {
                    let point = snapshot.point(for: coord)
                    cgContext.addLine(to: point)
                }
                cgContext.strokePath()
            }

            // Draw start marker (green circle)
            if let startCoord = coordinates.first {
                let point = snapshot.point(for: startCoord)
                cgContext.setFillColor(UIColor.systemGreen.cgColor)
                cgContext.fillEllipse(in: CGRect(
                    x: point.x - startEndMarkerSize / 2,
                    y: point.y - startEndMarkerSize / 2,
                    width: startEndMarkerSize,
                    height: startEndMarkerSize
                ))
            }

            // Draw end marker (red circle)
            if let endCoord = coordinates.last, coordinates.count > 1 {
                let point = snapshot.point(for: endCoord)
                cgContext.setFillColor(UIColor.systemRed.cgColor)
                cgContext.fillEllipse(in: CGRect(
                    x: point.x - startEndMarkerSize / 2,
                    y: point.y - startEndMarkerSize / 2,
                    width: startEndMarkerSize,
                    height: startEndMarkerSize
                ))
            }

            // Draw waypoint markers
            for waypoint in waypoints {
                let point = snapshot.point(for: waypoint.coordinate)
                cgContext.setFillColor(UIColor.systemBlue.cgColor)
                cgContext.fillEllipse(in: CGRect(
                    x: point.x - waypointMarkerSize / 2,
                    y: point.y - waypointMarkerSize / 2,
                    width: waypointMarkerSize,
                    height: waypointMarkerSize
                ))
            }
        }
    }

    // MARK: - Elevation Chart

    /// Renders the elevation profile chart as a UIImage using ImageRenderer.
    ///
    /// Falls back to a simple Core Graphics chart if ImageRenderer is unavailable.
    ///
    /// - Parameters:
    ///   - elevationData: The elevation profile data points.
    ///   - useMetric: Whether to use metric units.
    /// - Returns: A rendered chart image, or `nil` if the data is empty.
    private static func renderElevationChart(
        elevationData: [(distance: Double, elevation: Double)],
        useMetric: Bool
    ) -> UIImage? {
        guard elevationData.count >= 2 else { return nil }

        let chartView = ElevationProfileView(
            elevationData: elevationData,
            useMetric: useMetric
        )
        .frame(width: contentWidth * 2, height: elevationChartHeight * 2)
        .padding()
        .background(Color.white)

        let renderer = ImageRenderer(content: chartView)
        renderer.scale = 2.0
        return renderer.uiImage
    }

    // MARK: - Photo Loading

    /// A photo entry with image data and metadata for the PDF gallery.
    private struct PhotoEntry {
        /// The photo image.
        let image: UIImage
        /// The waypoint label or category name.
        let caption: String
        /// The formatted coordinate string.
        let coordinate: String
        /// The waypoint note text.
        let note: String
    }

    /// Loads photo data for waypoints that have attached photos.
    ///
    /// Reads photo BLOBs from the ``WaypointStore`` and converts them to `UIImage`.
    ///
    /// - Parameter waypoints: The waypoints to check for photos.
    /// - Returns: An array of ``PhotoEntry`` for waypoints with valid photos.
    private static func loadWaypointPhotos(waypoints: [Waypoint]) -> [PhotoEntry] {
        var entries: [PhotoEntry] = []

        for waypoint in waypoints where waypoint.hasPhoto {
            guard let photoData = try? WaypointStore.shared.fetchPhoto(id: waypoint.id),
                  let image = UIImage(data: photoData) else {
                continue
            }

            let caption = waypoint.label.isEmpty ? waypoint.category.displayName : waypoint.label
            let coordinate = String(
                format: "%.\(coordinateDecimalPlaces)f, %.\(coordinateDecimalPlaces)f",
                waypoint.latitude, waypoint.longitude
            )

            entries.append(PhotoEntry(
                image: image,
                caption: caption,
                coordinate: coordinate,
                note: waypoint.note
            ))
        }

        return entries
    }

    // MARK: - PDF Composition

    /// Renders the complete multi-page PDF document.
    ///
    /// - Parameters:
    ///   - route: The hike data.
    ///   - waypoints: Linked waypoints.
    ///   - mapImage: Pre-rendered map snapshot.
    ///   - chartImage: Pre-rendered elevation chart (may be nil).
    ///   - photoEntries: Photo gallery entries.
    ///   - useMetric: Unit preference.
    /// - Returns: The complete PDF as `Data`.
    private static func renderPDF(
        route: SavedRoute,
        waypoints: [Waypoint],
        mapImage: UIImage,
        chartImage: UIImage?,
        photoEntries: [PhotoEntry],
        useMetric: Bool
    ) -> Data {
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        return pdfRenderer.pdfData { context in
            // Page 1: Cover & Summary
            renderCoverPage(
                context: context,
                route: route,
                mapImage: mapImage,
                useMetric: useMetric
            )

            // Page 2: Elevation Profile (if data exists)
            if let chartImage = chartImage {
                renderElevationPage(
                    context: context,
                    route: route,
                    chartImage: chartImage,
                    useMetric: useMetric
                )
            }

            // Page 3+: Photo Gallery (if photos exist)
            if !photoEntries.isEmpty {
                renderPhotoPages(
                    context: context,
                    photoEntries: photoEntries
                )
            }

            // Final Page: Waypoint Table & Comments
            if !waypoints.isEmpty || !route.comment.isEmpty {
                renderWaypointPage(
                    context: context,
                    route: route,
                    waypoints: waypoints,
                    useMetric: useMetric
                )
            }
        }
    }

    // MARK: - Page Renderers

    /// Renders the cover page with map, title, date, and statistics.
    private static func renderCoverPage(
        context: UIGraphicsPDFRendererContext,
        route: SavedRoute,
        mapImage: UIImage,
        useMetric: Bool
    ) {
        context.beginPage()
        var y = margin

        // Title
        let titleFont = UIFont.boldSystemFont(ofSize: titleFontSize)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ]
        let title = route.name as NSString
        title.draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttributes)
        y += titleFont.lineHeight + 8

        // Date
        let dateFont = UIFont.systemFont(ofSize: bodyFontSize)
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: dateFont,
            .foregroundColor: UIColor.darkGray
        ]
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        let dateString = "\(dateFormatter.string(from: route.startTime)) \u{2013} \(dateFormatter.string(from: route.endTime))"
        (dateString as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: dateAttributes)
        y += dateFont.lineHeight + 16

        // Map snapshot
        let mapRect = CGRect(x: margin, y: y, width: contentWidth, height: mapSnapshotHeight)
        mapImage.draw(in: mapRect)
        y += mapSnapshotHeight + 20

        // Statistics table
        let sectionFont = UIFont.boldSystemFont(ofSize: sectionFontSize)
        let sectionAttributes: [NSAttributedString.Key: Any] = [
            .font: sectionFont,
            .foregroundColor: UIColor.black
        ]
        ("Statistics" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttributes)
        y += sectionFont.lineHeight + 8

        let statsRows = buildStatsRows(route: route, useMetric: useMetric)
        y = drawTable(rows: statsRows, x: margin, y: y, width: contentWidth)

        // Footer
        drawFooter(y: pageSize.height - margin + 10)
    }

    /// Renders the elevation profile page.
    private static func renderElevationPage(
        context: UIGraphicsPDFRendererContext,
        route: SavedRoute,
        chartImage: UIImage,
        useMetric: Bool
    ) {
        context.beginPage()
        var y = margin

        let sectionFont = UIFont.boldSystemFont(ofSize: sectionFontSize)
        let sectionAttributes: [NSAttributedString.Key: Any] = [
            .font: sectionFont,
            .foregroundColor: UIColor.black
        ]
        ("Elevation Profile" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttributes)
        y += sectionFont.lineHeight + 12

        let chartRect = CGRect(x: margin, y: y, width: contentWidth, height: elevationChartHeight)
        chartImage.draw(in: chartRect)
        y += elevationChartHeight + 20

        // Elevation annotations
        let captionFont = UIFont.systemFont(ofSize: captionFontSize)
        let captionAttributes: [NSAttributedString.Key: Any] = [
            .font: captionFont,
            .foregroundColor: UIColor.darkGray
        ]

        let elevationData = TrackCompression.extractElevationProfile(route.trackData)
        if !elevationData.isEmpty {
            let minEle = elevationData.map { $0.elevation }.min() ?? 0
            let maxEle = elevationData.map { $0.elevation }.max() ?? 0
            let avgEle = elevationData.map { $0.elevation }.reduce(0, +) / Double(elevationData.count)

            let annotationText = "Min: \(HikeStatsFormatter.formatElevation(minEle, useMetric: useMetric)) | " +
                "Max: \(HikeStatsFormatter.formatElevation(maxEle, useMetric: useMetric)) | " +
                "Avg: \(HikeStatsFormatter.formatElevation(avgEle, useMetric: useMetric))"
            (annotationText as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: captionAttributes)
        }

        drawFooter(y: pageSize.height - margin + 10)
    }

    /// Renders photo gallery pages (2-up grid layout).
    private static func renderPhotoPages(
        context: UIGraphicsPDFRendererContext,
        photoEntries: [PhotoEntry]
    ) {
        let captionFont = UIFont.systemFont(ofSize: captionFontSize)
        let captionAttributes: [NSAttributedString.Key: Any] = [
            .font: captionFont,
            .foregroundColor: UIColor.darkGray
        ]
        let boldCaptionAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: captionFontSize),
            .foregroundColor: UIColor.black
        ]

        var photoIndex = 0

        while photoIndex < photoEntries.count {
            context.beginPage()
            var y = margin

            let sectionFont = UIFont.boldSystemFont(ofSize: sectionFontSize)
            let sectionAttributes: [NSAttributedString.Key: Any] = [
                .font: sectionFont,
                .foregroundColor: UIColor.black
            ]
            ("Photos" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttributes)
            y += sectionFont.lineHeight + 12

            // 2-up grid: 2 columns, 2 rows per page = 4 photos
            for row in 0..<2 {
                for col in 0..<2 {
                    guard photoIndex < photoEntries.count else { break }
                    let entry = photoEntries[photoIndex]
                    photoIndex += 1

                    let x = margin + CGFloat(col) * (photoGridCellSize.width + photoGridSpacing)
                    let cellY = y + CGFloat(row) * (photoGridCellSize.height + photoCaptionHeight + photoGridSpacing)

                    // Draw photo
                    let photoRect = CGRect(x: x, y: cellY, width: photoGridCellSize.width, height: photoGridCellSize.height)
                    entry.image.draw(in: photoRect)

                    // Draw caption below photo
                    let captionY = cellY + photoGridCellSize.height + 4
                    (entry.caption as NSString).draw(
                        at: CGPoint(x: x, y: captionY),
                        withAttributes: boldCaptionAttributes
                    )
                    if !entry.note.isEmpty {
                        (entry.note as NSString).draw(
                            at: CGPoint(x: x, y: captionY + captionFont.lineHeight + 2),
                            withAttributes: captionAttributes
                        )
                    }
                }
            }

            drawFooter(y: pageSize.height - margin + 10)
        }
    }

    /// Renders the waypoint table and comments page.
    private static func renderWaypointPage(
        context: UIGraphicsPDFRendererContext,
        route: SavedRoute,
        waypoints: [Waypoint],
        useMetric: Bool
    ) {
        context.beginPage()
        var y = margin

        // Waypoint table
        if !waypoints.isEmpty {
            let sectionFont = UIFont.boldSystemFont(ofSize: sectionFontSize)
            let sectionAttributes: [NSAttributedString.Key: Any] = [
                .font: sectionFont,
                .foregroundColor: UIColor.black
            ]
            ("Waypoints" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttributes)
            y += sectionFont.lineHeight + 8

            // Table header
            let headerRow = ["#", "Name", "Category", "Coordinate", "Note"]
            y = drawTableHeader(columns: headerRow, x: margin, y: y, width: contentWidth)

            // Table rows
            for (index, wp) in waypoints.enumerated() {
                let label = wp.label.isEmpty ? "-" : wp.label
                let coord = String(
                    format: "%.\(coordinateDecimalPlaces)f, %.\(coordinateDecimalPlaces)f",
                    wp.latitude, wp.longitude
                )
                let noteTruncated = wp.note.count > noteMaxDisplayLength
                    ? String(wp.note.prefix(noteMaxDisplayLength)) + "..."
                    : wp.note

                let row = ["\(index + 1)", label, wp.category.displayName, coord, noteTruncated]
                y = drawTableRow(columns: row, x: margin, y: y, width: contentWidth)

                // Start a new page if we're running out of space
                if y > pageSize.height - margin - 100 && index < waypoints.count - 1 {
                    drawFooter(y: pageSize.height - margin + 10)
                    context.beginPage()
                    y = margin
                }
            }

            y += 20
        }

        // Comments
        if !route.comment.isEmpty {
            let sectionFont = UIFont.boldSystemFont(ofSize: sectionFontSize)
            let sectionAttributes: [NSAttributedString.Key: Any] = [
                .font: sectionFont,
                .foregroundColor: UIColor.black
            ]
            ("Comments" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttributes)
            y += sectionFont.lineHeight + 8

            let bodyFont = UIFont.systemFont(ofSize: bodyFontSize)
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: UIColor.black
            ]
            let commentRect = CGRect(x: margin, y: y, width: contentWidth, height: 200)
            (route.comment as NSString).draw(in: commentRect, withAttributes: bodyAttributes)
        }

        drawFooter(y: pageSize.height - margin + 10)
    }

    // MARK: - Drawing Helpers

    /// Builds the statistics rows for the cover page table.
    private static func buildStatsRows(route: SavedRoute, useMetric: Bool) -> [[String]] {
        var rows: [[String]] = []

        rows.append(["Distance", HikeStatsFormatter.formatDistance(route.totalDistance, useMetric: useMetric)])
        rows.append(["Elevation Gain", "+\(HikeStatsFormatter.formatElevation(route.elevationGain, useMetric: useMetric))"])
        rows.append(["Elevation Loss", "-\(HikeStatsFormatter.formatElevation(route.elevationLoss, useMetric: useMetric))"])
        rows.append(["Duration", HikeStatsFormatter.formatDuration(route.duration)])
        rows.append(["Walking Time", HikeStatsFormatter.formatDuration(route.walkingTime)])
        rows.append(["Resting Time", HikeStatsFormatter.formatDuration(route.restingTime)])

        if let avgHR = route.averageHeartRate {
            rows.append(["Avg Heart Rate", HikeStatsFormatter.formatHeartRate(avgHR)])
        }
        if let maxHR = route.maxHeartRate {
            rows.append(["Max Heart Rate", HikeStatsFormatter.formatHeartRate(maxHR)])
        }
        if let calories = route.estimatedCalories {
            rows.append(["Calories", "~\(HikeStatsFormatter.formatCalories(calories))"])
        }
        if route.walkingTime > 0 {
            let avgSpeed = route.totalDistance / route.walkingTime
            rows.append(["Avg Speed", HikeStatsFormatter.formatSpeed(avgSpeed, useMetric: useMetric)])
        }

        return rows
    }

    /// Draws a two-column table and returns the Y position after the last row.
    private static func drawTable(rows: [[String]], x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        var currentY = y
        let font = UIFont.systemFont(ofSize: bodyFontSize)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: bodyFontSize),
            .foregroundColor: UIColor.darkGray
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]

        for (index, row) in rows.enumerated() {
            guard row.count >= 2 else { continue }

            // Alternating row background
            if index % 2 == 0 {
                UIColor.systemGray6.setFill()
                UIBezierPath(rect: CGRect(x: x, y: currentY, width: width, height: tableRowHeight)).fill()
            }

            (row[0] as NSString).draw(
                at: CGPoint(x: x + 8, y: currentY + 4),
                withAttributes: labelAttributes
            )
            (row[1] as NSString).draw(
                at: CGPoint(x: x + width / 2, y: currentY + 4),
                withAttributes: valueAttributes
            )

            currentY += tableRowHeight
        }

        return currentY
    }

    /// Draws a multi-column table header row.
    private static func drawTableHeader(columns: [String], x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        let font = UIFont.boldSystemFont(ofSize: captionFontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]

        // Header background
        UIColor.darkGray.setFill()
        UIBezierPath(rect: CGRect(x: x, y: y, width: width, height: tableRowHeight)).fill()

        var colX = x + 4

        for (index, col) in columns.enumerated() {
            let colWidth = index < waypointTableColumnWidths.count ? waypointTableColumnWidths[index] : 80
            (col as NSString).draw(at: CGPoint(x: colX, y: y + 4), withAttributes: attributes)
            colX += colWidth
        }

        return y + tableRowHeight
    }

    /// Draws a multi-column table data row.
    private static func drawTableRow(columns: [String], x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: captionFontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]

        var colX = x + 4

        // Row separator line
        UIColor.systemGray4.setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x, y: y + tableRowHeight))
        path.addLine(to: CGPoint(x: x + width, y: y + tableRowHeight))
        path.lineWidth = 0.5
        path.stroke()

        for (index, col) in columns.enumerated() {
            let colWidth = index < waypointTableColumnWidths.count ? waypointTableColumnWidths[index] : 80
            (col as NSString).draw(at: CGPoint(x: colX, y: y + 4), withAttributes: attributes)
            colX += colWidth
        }

        return y + tableRowHeight
    }

    /// Draws the page footer with the OpenHiker attribution.
    private static func drawFooter(y: CGFloat) {
        let font = UIFont.systemFont(ofSize: captionFontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.lightGray
        ]
        let footer = "Generated by OpenHiker — https://github.com/hherb/OpenHiker"
        (footer as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: attributes)
    }
}
