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
import AppKit
import CoreLocation
import UniformTypeIdentifiers

/// Handles GPX file import on macOS via ``NSOpenPanel`` and drag-and-drop.
///
/// GPX files are parsed into ``PlannedRoute`` objects and saved to the
/// ``PlannedRouteStore``. Supports both single and batch GPX import.
enum GPXImportHandler {

    /// The UTType for GPX files.
    static let gpxType = UTType(filenameExtension: "gpx") ?? UTType.xml

    /// Presents an ``NSOpenPanel`` for the user to choose GPX files.
    ///
    /// Allows multiple selection. Each GPX file is parsed and imported
    /// as a ``PlannedRoute``.
    ///
    /// - Returns: The number of routes successfully imported.
    @MainActor
    static func presentImportPanel() async -> Int {
        let panel = NSOpenPanel()
        panel.title = "Import GPX Route"
        panel.message = "Select one or more GPX files to import as planned routes."
        panel.allowedContentTypes = [gpxType, .xml]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        let response = panel.runModal()
        guard response == .OK else { return 0 }

        var importCount = 0
        for url in panel.urls {
            do {
                let route = try parseGPXFile(at: url)
                try PlannedRouteStore.shared.save(route)
                importCount += 1
            } catch {
                print("Failed to import GPX \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return importCount
    }

    /// Imports a GPX file from a URL (used by drag-and-drop handlers).
    ///
    /// - Parameter url: The file URL of the GPX file.
    /// - Returns: The imported ``PlannedRoute``.
    /// - Throws: Parsing errors if the GPX is invalid.
    static func importFile(at url: URL) throws -> PlannedRoute {
        let route = try parseGPXFile(at: url)
        try PlannedRouteStore.shared.save(route)
        return route
    }

    /// Parses a GPX file into a ``PlannedRoute``.
    ///
    /// Extracts the route name from the GPX `<name>` element (or filename),
    /// and track points from `<trkpt>` elements. Computes distance and
    /// elevation stats from the track points.
    ///
    /// - Parameter url: The file URL of the GPX file.
    /// - Returns: A ``PlannedRoute`` with coordinates, distance, and elevation data.
    /// - Throws: File read or XML parsing errors.
    static func parseGPXFile(at url: URL) throws -> PlannedRoute {
        let data = try Data(contentsOf: url)
        let parser = GPXParser(data: data)
        let result = try parser.parse()

        let coordinates = result.trackPoints.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }

        guard coordinates.count >= 2 else {
            throw GPXError.insufficientPoints
        }

        // Calculate total distance
        var totalDistance: Double = 0
        for i in 1..<coordinates.count {
            let prev = CLLocation(latitude: coordinates[i-1].latitude, longitude: coordinates[i-1].longitude)
            let curr = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            totalDistance += prev.distance(from: curr)
        }

        // Calculate elevation gain/loss
        var elevationGain: Double = 0
        var elevationLoss: Double = 0
        let elevations = result.trackPoints.compactMap { $0.elevation }
        for i in 1..<elevations.count {
            let diff = elevations[i] - elevations[i-1]
            if diff > 0 { elevationGain += diff }
            else { elevationLoss += abs(diff) }
        }

        // Build elevation profile
        var elevationProfile: [ElevationPoint] = []
        var cumulativeDistance: Double = 0
        for i in 0..<result.trackPoints.count {
            if i > 0 {
                let prev = CLLocation(latitude: coordinates[i-1].latitude, longitude: coordinates[i-1].longitude)
                let curr = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
                cumulativeDistance += prev.distance(from: curr)
            }
            if let ele = result.trackPoints[i].elevation {
                elevationProfile.append(ElevationPoint(distance: cumulativeDistance, elevation: ele))
            }
        }

        let name = result.name ?? url.deletingPathExtension().lastPathComponent

        // Estimate duration using Naismith's rule: 5 km/h + 1h per 600m ascent
        let baseDuration = totalDistance / 5000 * 3600
        let climbDuration = elevationGain / 600 * 3600
        let estimatedDuration = baseDuration + climbDuration

        return PlannedRoute(
            id: UUID(),
            name: name,
            coordinates: coordinates,
            totalDistance: totalDistance,
            estimatedDuration: estimatedDuration,
            elevationGain: elevationGain,
            elevationLoss: elevationLoss,
            elevationProfile: elevationProfile,
            turnInstructions: [],
            mode: .hiking,
            regionId: nil,
            createdAt: Date()
        )
    }
}

// MARK: - GPX Parsing

/// Errors that can occur during GPX import.
enum GPXError: Error, LocalizedError {
    /// The GPX file contains fewer than 2 track points.
    case insufficientPoints
    /// The GPX file could not be parsed as valid XML.
    case invalidXML(String)

    var errorDescription: String? {
        switch self {
        case .insufficientPoints:
            return "GPX file must contain at least 2 track points"
        case .invalidXML(let msg):
            return "Invalid GPX file: \(msg)"
        }
    }
}

/// A point parsed from a GPX track.
struct GPXTrackPoint {
    /// Latitude in degrees.
    let latitude: Double
    /// Longitude in degrees.
    let longitude: Double
    /// Elevation in metres (optional).
    let elevation: Double?
}

/// The result of parsing a GPX file.
struct GPXParseResult {
    /// The route name from the GPX `<name>` element.
    let name: String?
    /// All track points from `<trkpt>` elements.
    let trackPoints: [GPXTrackPoint]
}

/// A simple GPX XML parser using Foundation's ``XMLParser``.
///
/// Extracts `<name>` and `<trkpt>` elements from GPX 1.1 files.
/// Supports tracks (`<trk>/<trkseg>/<trkpt>`) and routes (`<rte>/<rtept>`).
class GPXParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var name: String?
    private var trackPoints: [GPXTrackPoint] = []

    private var currentElement = ""
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: String = ""
    private var currentName: String = ""
    private var inTrackPoint = false
    private var inName = false
    private var parsingError: Error?

    /// Creates a GPX parser for the given data.
    init(data: Data) {
        self.data = data
    }

    /// Parses the GPX data and returns the result.
    ///
    /// - Returns: A ``GPXParseResult`` with the name and track points.
    /// - Throws: ``GPXError/invalidXML(_:)`` if parsing fails.
    func parse() throws -> GPXParseResult {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        if let error = parsingError {
            throw error
        }

        return GPXParseResult(name: name, trackPoints: trackPoints)
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        if elementName == "trkpt" || elementName == "rtept" {
            inTrackPoint = true
            currentLat = Double(attributeDict["lat"] ?? "")
            currentLon = Double(attributeDict["lon"] ?? "")
            currentEle = ""
        } else if elementName == "name" && !inTrackPoint {
            inName = true
            currentName = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTrackPoint && currentElement == "ele" {
            currentEle += string
        } else if inName {
            currentName += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if (elementName == "trkpt" || elementName == "rtept"), inTrackPoint {
            if let lat = currentLat, let lon = currentLon {
                let ele = Double(currentEle.trimmingCharacters(in: .whitespacesAndNewlines))
                trackPoints.append(GPXTrackPoint(latitude: lat, longitude: lon, elevation: ele))
            }
            inTrackPoint = false
        } else if elementName == "name" && inName {
            if name == nil {
                name = currentName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            inName = false
        }
        currentElement = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        parsingError = GPXError.invalidXML(parseError.localizedDescription)
    }
}
