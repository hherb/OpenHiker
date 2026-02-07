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
import CoreLocation

/// Downloads OSM trail data for a geographic region using the Overpass API.
///
/// For regions ≤ 100×100 km the Overpass API is used because it returns only
/// the data we need (filtered by highway tags). For very large regions,
/// downloading a full Geofabrik PBF extract and filtering locally would be
/// more appropriate — but for typical hiking regions the Overpass approach
/// is lighter and faster.
///
/// This actor mirrors the ``TileDownloader`` pattern: it owns its own
/// `URLSession`, uses exponential-backoff retries, and reports progress
/// to a callback.
actor OSMDataDownloader {

    // MARK: - Configuration

    /// Primary Overpass API endpoint.
    private static let overpassEndpoint = "https://overpass-api.de/api/interpreter"

    /// Fallback Overpass API endpoint (Kumi Systems mirror).
    private static let overpassFallbackEndpoint = "https://overpass.kumi.systems/api/interpreter"

    /// Maximum area in square kilometres for an Overpass query.
    /// Beyond this the query may time out; fall back to Geofabrik.
    static let maxOverpassAreaKm2: Double = 10_000  // 100×100 km

    /// Maximum number of download retries before giving up.
    private static let maxRetries: Int = 4

    /// Overpass API timeout in seconds (sent as `[timeout:…]`).
    private static let overpassTimeoutSeconds: Int = 300

    /// Nanoseconds per second, used in retry delay calculations.
    private static let nanosecondsPerSecond: UInt64 = 1_000_000_000

    // MARK: - Properties

    /// URL session for API requests.
    private let session: URLSession

    /// Local cache directory for downloaded PBF/XML files.
    private let cacheDirectory: URL

    // MARK: - Init

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [
            "User-Agent": "OpenHiker/1.0 (iOS; hiking navigation app)"
        ]
        self.session = URLSession(configuration: config)

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = caches.appendingPathComponent("OSMDataCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Download OSM trail data for a bounding box and save it as a local PBF file.
    ///
    /// Uses the Overpass API to query specifically for hiking/cycling-relevant
    /// ways and their referenced nodes within the bounding box.
    ///
    /// - Parameters:
    ///   - boundingBox: The geographic area to download.
    ///   - progress: Callback with `(stepDescription, fractionComplete)`.
    /// - Returns: The file URL of the downloaded PBF (actually XML from Overpass).
    /// - Throws: ``OSMDownloadError`` on failure.
    func downloadTrailData(
        boundingBox: BoundingBox,
        progress: @escaping (String, Double) -> Void
    ) async throws -> URL {

        // Check area isn't too large for Overpass
        let areaKm2 = boundingBox.areaKm2
        if areaKm2 > Self.maxOverpassAreaKm2 {
            throw OSMDownloadError.areaTooLarge(areaKm2)
        }

        progress("Querying trail data from OpenStreetMap...", 0.1)

        let query = buildOverpassQuery(boundingBox: boundingBox)
        let data = try await executeOverpassQuery(query: query)

        // Save to cache
        let filename = "trails_\(Int(boundingBox.south))_\(Int(boundingBox.west))_\(Int(boundingBox.north))_\(Int(boundingBox.east)).osm"
        let outputURL = cacheDirectory.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try data.write(to: outputURL)

        progress("Trail data downloaded (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))", 1.0)

        return outputURL
    }

    /// Download trail data and parse it into nodes and ways.
    ///
    /// This is a convenience method that downloads the Overpass XML response
    /// and parses it into the same format as ``PBFParser`` output, so the
    /// ``RoutingGraphBuilder`` can use either source transparently.
    ///
    /// - Parameters:
    ///   - boundingBox: The geographic area to download.
    ///   - progress: Callback with `(stepDescription, fractionComplete)`.
    /// - Returns: Tuple of (nodes, ways) ready for ``RoutingGraphBuilder``.
    func downloadAndParseTrailData(
        boundingBox: BoundingBox,
        progress: @escaping (String, Double) -> Void
    ) async throws -> (nodes: [Int64: PBFParser.OSMNode], ways: [PBFParser.OSMWay]) {

        // Same area check as downloadTrailData
        let areaKm2 = boundingBox.areaKm2
        if areaKm2 > Self.maxOverpassAreaKm2 {
            throw OSMDownloadError.areaTooLarge(areaKm2)
        }

        progress("Downloading trail data...", 0.1)

        let query = buildOverpassQuery(boundingBox: boundingBox)
        let data = try await executeOverpassQuery(query: query)

        // Write to a temp file so we can release the raw Data from memory
        // before parsing.  The Overpass XML response can be 50–200 MB for
        // large regions; holding both the raw bytes and the parsed structures
        // in memory simultaneously doubles the peak footprint.
        let tempURL = cacheDirectory.appendingPathComponent("overpass_temp_\(UUID().uuidString).osm")
        try data.write(to: tempURL)
        // data goes out of scope here — memory is now reclaimable

        defer { try? FileManager.default.removeItem(at: tempURL) }

        progress("Parsing trail data...", 0.6)

        let (nodes, ways) = try parseOverpassXML(url: tempURL, boundingBox: boundingBox)

        progress("Parsed \(nodes.count) nodes and \(ways.count) trails", 1.0)
        return (nodes, ways)
    }

    // MARK: - Overpass Query

    /// Build an Overpass QL query for hiking/cycling trails in a bounding box.
    ///
    /// The query requests:
    /// - All ways with `highway` tags matching our routable set
    /// - All nodes referenced by those ways (via `(._;>;)` recurse-down)
    /// - Output in XML format for reliable parsing
    ///
    /// - Parameter boundingBox: The geographic area.
    /// - Returns: The Overpass QL query string.
    private func buildOverpassQuery(boundingBox: BoundingBox) -> String {
        let bbox = "\(boundingBox.south),\(boundingBox.west),\(boundingBox.north),\(boundingBox.east)"

        let highwayValues = RoutingCostConfig.routableHighwayValues.sorted().joined(separator: "|")

        // Apply bbox only to the way query (not globally) so that
        // recurse-down (._;>;) can fetch nodes outside the bbox that
        // are referenced by ways crossing the boundary.
        return """
        [out:xml][timeout:\(Self.overpassTimeoutSeconds)];
        way["highway"~"^(\(highwayValues))$"](\(bbox));
        (._;>;);
        out body;
        """
    }

    /// Execute an Overpass API query with retry and exponential backoff.
    ///
    /// Tries the primary endpoint first, then the fallback. Retries up to
    /// ``maxRetries`` times total with 2/4/8/16-second delays.
    ///
    /// - Parameter query: The Overpass QL query string.
    /// - Returns: The raw response data (XML).
    /// - Throws: ``OSMDownloadError`` on all retries failing.
    private func executeOverpassQuery(query: String) async throws -> Data {
        let endpoints = [Self.overpassEndpoint, Self.overpassFallbackEndpoint]
        var lastError: Error = OSMDownloadError.allRetriesFailed

        for endpoint in endpoints {
            for attempt in 0..<Self.maxRetries {
                do {
                    guard let url = URL(string: endpoint) else { continue }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                    // Use a restricted character set for form encoding — .urlQueryAllowed
                    // leaves &, =, + unescaped which are special in form bodies.
                    var formAllowed = CharacterSet.alphanumerics
                    formAllowed.insert(charactersIn: "-._~")
                    let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? query
                    request.httpBody = "data=\(encodedQuery)".data(using: .utf8)

                    let (data, response) = try await session.data(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OSMDownloadError.invalidResponse
                    }

                    switch httpResponse.statusCode {
                    case 200:
                        return data
                    case 429:
                        // Rate limited — wait longer
                        lastError = OSMDownloadError.httpError(429)
                        let delay = UInt64(pow(2.0, Double(attempt + 2))) * Self.nanosecondsPerSecond
                        try await Task.sleep(nanoseconds: delay)
                        continue
                    case 504:
                        // Gateway timeout — query too complex or server busy
                        throw OSMDownloadError.queryTimeout
                    default:
                        throw OSMDownloadError.httpError(httpResponse.statusCode)
                    }
                } catch let error as OSMDownloadError {
                    lastError = error
                    if case .queryTimeout = error { break }  // Don't retry timeouts on same endpoint
                } catch {
                    lastError = error
                    if attempt < Self.maxRetries - 1 {
                        let delay = UInt64(pow(2.0, Double(attempt + 1))) * Self.nanosecondsPerSecond
                        try await Task.sleep(nanoseconds: delay)
                    }
                }
            }
        }

        throw lastError
    }

    // MARK: - Overpass XML Parsing

    /// Parse Overpass API XML from an in-memory Data buffer.
    ///
    /// Prefer ``parseOverpassXML(url:boundingBox:)`` for large responses to
    /// avoid keeping both the raw bytes and parsed structures in memory.
    private func parseOverpassXML(
        data: Data,
        boundingBox: BoundingBox
    ) throws -> (nodes: [Int64: PBFParser.OSMNode], ways: [PBFParser.OSMWay]) {

        let parser = OverpassXMLParser(boundingBox: boundingBox)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser

        guard xmlParser.parse() else {
            throw OSMDownloadError.xmlParseError(xmlParser.parserError?.localizedDescription ?? "Unknown XML error")
        }

        return (parser.nodes, parser.ways)
    }

    /// Parse Overpass API XML from a file on disk.
    ///
    /// Uses `XMLParser(contentsOf:)` which streams the file, keeping only a
    /// small read buffer in memory instead of the entire XML document.
    private func parseOverpassXML(
        url: URL,
        boundingBox: BoundingBox
    ) throws -> (nodes: [Int64: PBFParser.OSMNode], ways: [PBFParser.OSMWay]) {

        let parser = OverpassXMLParser(boundingBox: boundingBox)
        guard let xmlParser = XMLParser(contentsOf: url) else {
            throw OSMDownloadError.xmlParseError("Could not open XML file at \(url.path)")
        }
        xmlParser.delegate = parser

        guard xmlParser.parse() else {
            throw OSMDownloadError.xmlParseError(xmlParser.parserError?.localizedDescription ?? "Unknown XML error")
        }

        return (parser.nodes, parser.ways)
    }
}

// MARK: - Overpass XML Parser Delegate

/// NSXMLParser delegate that extracts nodes and ways from Overpass API XML responses.
///
/// This is used internally by ``OSMDataDownloader`` to convert the XML into
/// the same `PBFParser.OSMNode` and `PBFParser.OSMWay` types, so the
/// ``RoutingGraphBuilder`` can consume data from either source.
private class OverpassXMLParser: NSObject, XMLParserDelegate {
    /// Parsed nodes keyed by OSM node ID.
    var nodes: [Int64: PBFParser.OSMNode] = [:]
    /// Parsed routable ways.
    var ways: [PBFParser.OSMWay] = []

    private let boundingBox: BoundingBox

    // Parsing state
    private var currentNodeId: Int64 = 0
    private var currentNodeLat: Double = 0
    private var currentNodeLon: Double = 0
    private var currentNodeTags: [String: String] = [:]
    private var inNode = false

    private var currentWayId: Int64 = 0
    private var currentWayRefs: [Int64] = []
    private var currentWayTags: [String: String] = [:]
    private var inWay = false

    init(boundingBox: BoundingBox) {
        self.boundingBox = boundingBox
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "node":
            inNode = true
            currentNodeId = Int64(attributeDict["id"] ?? "0") ?? 0
            currentNodeLat = Double(attributeDict["lat"] ?? "0") ?? 0
            currentNodeLon = Double(attributeDict["lon"] ?? "0") ?? 0
            currentNodeTags = [:]

        case "way":
            inWay = true
            currentWayId = Int64(attributeDict["id"] ?? "0") ?? 0
            currentWayRefs = []
            currentWayTags = [:]

        case "nd":
            if inWay, let refStr = attributeDict["ref"], let ref = Int64(refStr) {
                currentWayRefs.append(ref)
            }

        case "tag":
            let key = attributeDict["k"] ?? ""
            let value = attributeDict["v"] ?? ""
            if inNode {
                currentNodeTags[key] = value
            } else if inWay {
                currentWayTags[key] = value
            }

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "node":
            // Keep all nodes — ways may reference nodes outside the bbox,
            // and the Overpass query already filters ways by area.
            nodes[currentNodeId] = PBFParser.OSMNode(
                id: currentNodeId,
                latitude: currentNodeLat,
                longitude: currentNodeLon,
                tags: currentNodeTags
            )
            inNode = false

        case "way":
            if PBFParser.isRoutableWay(currentWayTags) && currentWayRefs.count >= 2 {
                ways.append(PBFParser.OSMWay(
                    id: currentWayId,
                    nodeRefs: currentWayRefs,
                    tags: currentWayTags
                ))
            }
            inWay = false

        default:
            break
        }
    }
}

// MARK: - OSM Download Errors

/// Errors that can occur during OSM data download.
enum OSMDownloadError: Error, LocalizedError {
    /// The requested area exceeds the Overpass API size limit.
    case areaTooLarge(Double)
    /// The Overpass API query timed out (region may be too large or server busy).
    case queryTimeout
    /// HTTP error from the Overpass API.
    case httpError(Int)
    /// The server response was not a valid HTTP response.
    case invalidResponse
    /// All retry attempts failed.
    case allRetriesFailed
    /// The XML response could not be parsed.
    case xmlParseError(String)

    var errorDescription: String? {
        switch self {
        case .areaTooLarge(let area):
            return String(format: "Region too large for Overpass API (%.0f km²). Maximum is %.0f km².",
                          area, OSMDataDownloader.maxOverpassAreaKm2)
        case .queryTimeout:
            return "The trail data query timed out. Try a smaller region."
        case .httpError(let code):
            return "Overpass API returned HTTP \(code)"
        case .invalidResponse:
            return "Invalid response from Overpass API"
        case .allRetriesFailed:
            return "Failed to download trail data after multiple attempts"
        case .xmlParseError(let detail):
            return "Failed to parse trail data: \(detail)"
        }
    }
}
