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

import AppKit
import SwiftUI
import CoreLocation
import UniformTypeIdentifiers

/// The available export formats for the macOS NSSavePanel-based export.
///
/// Maps to file extensions and UTTypes for the macOS file exporter.
enum MacExportFormat: String, CaseIterable, Identifiable {
    /// Personal hike summary as Markdown text.
    case markdown = "Quick Summary (Markdown)"
    /// GPS track as GPX 1.1 XML.
    case gpx = "GPS Track (GPX)"
    /// Multi-page PDF report (uses AppKit PDF rendering).
    case pdf = "Detailed Report (PDF)"

    var id: String { rawValue }

    /// SF Symbol icon name for this format.
    var iconName: String {
        switch self {
        case .markdown: return "doc.text"
        case .gpx: return "point.topleft.down.to.point.bottomright.curvepath"
        case .pdf: return "doc.richtext"
        }
    }

    /// File extension for the exported file.
    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .gpx: return "gpx"
        case .pdf: return "pdf"
        }
    }

    /// UTType for the macOS file exporter.
    var contentType: UTType {
        switch self {
        case .markdown: return .plainText
        case .gpx: return .xml
        case .pdf: return .pdf
        }
    }
}

/// A `FileDocument` wrapper that generates export data on demand.
///
/// Used with SwiftUI's `.fileExporter()` modifier to present the macOS
/// NSSavePanel. Generates the export content lazily when the system requests
/// the file data.
struct ExportDocument: FileDocument {
    /// The supported content types for this document.
    static var readableContentTypes: [UTType] { [.plainText, .xml, .pdf] }

    /// The route to export.
    let route: SavedRoute

    /// Waypoints linked to the route.
    let waypoints: [Waypoint]

    /// The export format.
    let format: MacExportFormat

    /// Whether to use metric units.
    let useMetric: Bool

    /// Creates an ExportDocument for the given route and format.
    init(route: SavedRoute, waypoints: [Waypoint], format: MacExportFormat, useMetric: Bool) {
        self.route = route
        self.waypoints = waypoints
        self.format = format
        self.useMetric = useMetric
    }

    /// Required init for reading (not used -- export only).
    init(configuration: ReadConfiguration) throws {
        fatalError("ExportDocument is write-only")
    }

    /// Generates the export content and writes it to a file wrapper.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data: Data

        switch format {
        case .markdown:
            let markdown = HikeSummaryExporter.toMarkdown(
                route: route,
                waypoints: waypoints,
                useMetric: useMetric
            )
            data = Data(markdown.utf8)

        case .gpx:
            data = HikeSummaryExporter.toGPX(route: route, waypoints: waypoints)

        case .pdf:
            data = MacPDFExporter.exportAsPDF(
                route: route,
                waypoints: waypoints,
                useMetric: useMetric
            )
        }

        return FileWrapper(regularFileWithContents: data)
    }
}

/// Generates multi-page PDF hike reports on macOS using AppKit.
///
/// The macOS equivalent of ``PDFExporter`` (iOS). Uses Core Graphics PDF context
/// directly instead of `UIGraphicsPDFRenderer`, producing the same page layout:
/// - **Page 1**: Title, date, statistics table
/// - **Page 2**: Waypoint table and comments
///
/// Map snapshots and elevation charts are omitted on macOS because
/// `MKMapSnapshotter` and `ImageRenderer` have limited reliability in
/// non-interactive (headless) contexts on macOS. A future version could
/// add these using NSBitmapImageRep-based rendering.
enum MacPDFExporter {

    // MARK: - Constants

    /// Standard US Letter page size in points.
    private static let pageSize = CGSize(width: 612, height: 792)

    /// Page margins in points.
    private static let margin: CGFloat = 50

    /// Usable content width after subtracting margins.
    private static let contentWidth: CGFloat = 512

    /// Font size for the title heading.
    private static let titleFontSize: CGFloat = 24

    /// Font size for section headings.
    private static let sectionFontSize: CGFloat = 16

    /// Font size for body text and table content.
    private static let bodyFontSize: CGFloat = 11

    /// Font size for small annotations and captions.
    private static let captionFontSize: CGFloat = 9

    /// Row height in the statistics table.
    private static let tableRowHeight: CGFloat = 22

    // MARK: - Public API

    /// Generates a PDF report for the given hike.
    ///
    /// - Parameters:
    ///   - route: The completed hike to export.
    ///   - waypoints: Waypoints linked to this hike.
    ///   - useMetric: Whether to use metric units.
    /// - Returns: The PDF document as `Data`.
    static func exportAsPDF(
        route: SavedRoute,
        waypoints: [Waypoint],
        useMetric: Bool
    ) -> Data {
        let pdfData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        // Page 1: Cover & Statistics
        context.beginPDFPage(nil)
        var y = margin

        // Title
        y = drawText(
            route.name,
            in: context,
            x: margin, y: y,
            fontSize: titleFontSize,
            bold: true
        )
        y += 8

        // Date range
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        let dateString = "\(dateFormatter.string(from: route.startTime)) \u{2013} \(dateFormatter.string(from: route.endTime))"
        y = drawText(dateString, in: context, x: margin, y: y, fontSize: bodyFontSize)
        y += 16

        // Statistics section
        y = drawText("Statistics", in: context, x: margin, y: y, fontSize: sectionFontSize, bold: true)
        y += 8

        let statsRows = buildStatsRows(route: route, useMetric: useMetric)
        for row in statsRows {
            y = drawTableRow(label: row.0, value: row.1, in: context, x: margin, y: y)
        }
        y += 16

        drawFooter(in: context)
        context.endPDFPage()

        // Page 2: Waypoints & Comments (if applicable)
        if !waypoints.isEmpty || !route.comment.isEmpty {
            context.beginPDFPage(nil)
            y = margin

            if !waypoints.isEmpty {
                y = drawText(
                    "Waypoints (\(waypoints.count))",
                    in: context, x: margin, y: y,
                    fontSize: sectionFontSize, bold: true
                )
                y += 8

                for (index, wp) in waypoints.enumerated() {
                    let label = wp.label.isEmpty ? wp.category.displayName : wp.label
                    let line = "\(index + 1). \(label) (\(wp.formattedCoordinate))"
                    y = drawText(line, in: context, x: margin, y: y, fontSize: bodyFontSize)

                    if !wp.note.isEmpty {
                        y = drawText("   \(wp.note)", in: context, x: margin, y: y, fontSize: captionFontSize)
                    }

                    // Start a new page if running out of space
                    if y > pageSize.height - margin - 60 && index < waypoints.count - 1 {
                        drawFooter(in: context)
                        context.endPDFPage()
                        context.beginPDFPage(nil)
                        y = margin
                    }
                }
                y += 16
            }

            if !route.comment.isEmpty {
                y = drawText("Comments", in: context, x: margin, y: y, fontSize: sectionFontSize, bold: true)
                y += 8
                _ = drawText(route.comment, in: context, x: margin, y: y, fontSize: bodyFontSize)
            }

            drawFooter(in: context)
            context.endPDFPage()
        }

        context.closePDF()
        return pdfData as Data
    }

    // MARK: - Drawing Helpers

    /// Draws text at the given position and returns the Y position after the text.
    @discardableResult
    private static func drawText(
        _ text: String,
        in context: CGContext,
        x: CGFloat, y: CGFloat,
        fontSize: CGFloat,
        bold: Bool = false
    ) -> CGFloat {
        let font = bold
            ? NSFont.boldSystemFont(ofSize: fontSize)
            : NSFont.systemFont(ofSize: fontSize)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]

        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let bounds = CTLineGetBoundsWithOptions(line, [])

        // PDF coordinate system is bottom-up; we work top-down
        let pdfY = pageSize.height - y - bounds.height

        context.saveGState()
        context.textPosition = CGPoint(x: x, y: pdfY)
        CTLineDraw(line, context)
        context.restoreGState()

        return y + bounds.height + 2
    }

    /// Draws a statistics table row (label: value) and returns the Y after the row.
    private static func drawTableRow(
        label: String,
        value: String,
        in context: CGContext,
        x: CGFloat,
        y: CGFloat
    ) -> CGFloat {
        let font = NSFont.systemFont(ofSize: bodyFontSize)
        let boldFont = NSFont.boldSystemFont(ofSize: bodyFontSize)

        let labelAttrs: [NSAttributedString.Key: Any] = [.font: boldFont, .foregroundColor: NSColor.darkGray]
        let valueAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]

        let pdfY = pageSize.height - y - tableRowHeight + 4

        let labelStr = NSAttributedString(string: label, attributes: labelAttrs)
        let labelLine = CTLineCreateWithAttributedString(labelStr)
        context.saveGState()
        context.textPosition = CGPoint(x: x + 8, y: pdfY)
        CTLineDraw(labelLine, context)
        context.restoreGState()

        let valueStr = NSAttributedString(string: value, attributes: valueAttrs)
        let valueLine = CTLineCreateWithAttributedString(valueStr)
        context.saveGState()
        context.textPosition = CGPoint(x: x + contentWidth / 2, y: pdfY)
        CTLineDraw(valueLine, context)
        context.restoreGState()

        return y + tableRowHeight
    }

    /// Builds the statistics table rows.
    private static func buildStatsRows(route: SavedRoute, useMetric: Bool) -> [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("Distance", HikeStatsFormatter.formatDistance(route.totalDistance, useMetric: useMetric)))
        rows.append(("Elevation Gain", "+\(HikeStatsFormatter.formatElevation(route.elevationGain, useMetric: useMetric))"))
        rows.append(("Elevation Loss", "-\(HikeStatsFormatter.formatElevation(route.elevationLoss, useMetric: useMetric))"))
        rows.append(("Duration", HikeStatsFormatter.formatDuration(route.duration)))
        rows.append(("Walking Time", HikeStatsFormatter.formatDuration(route.walkingTime)))
        rows.append(("Resting Time", HikeStatsFormatter.formatDuration(route.restingTime)))

        if let avgHR = route.averageHeartRate {
            rows.append(("Avg Heart Rate", HikeStatsFormatter.formatHeartRate(avgHR)))
        }
        if let maxHR = route.maxHeartRate {
            rows.append(("Max Heart Rate", HikeStatsFormatter.formatHeartRate(maxHR)))
        }
        if let calories = route.estimatedCalories {
            rows.append(("Calories", "~\(HikeStatsFormatter.formatCalories(calories))"))
        }
        return rows
    }

    /// Draws the page footer.
    private static func drawFooter(in context: CGContext) {
        let font = NSFont.systemFont(ofSize: captionFontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.lightGray]
        let footer = NSAttributedString(
            string: "Generated by OpenHiker \u{2014} https://github.com/hherb/OpenHiker",
            attributes: attrs
        )
        let line = CTLineCreateWithAttributedString(footer)
        context.saveGState()
        context.textPosition = CGPoint(x: margin, y: 30)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
