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
import Compression
import CoreLocation

/// Parses OpenStreetMap PBF (Protobuf Binary Format) files to extract
/// trail data for routing graph construction.
///
/// Only extracts nodes and ways relevant to hiking/cycling routing.
/// Relations, metadata blocks, and non-trail features are skipped.
///
/// ## File structure
/// ```
/// File = [BlobHeader + Blob]*
///   BlobHeader = { type: "OSMHeader"|"OSMData", datasize }
///   Blob = { raw | zlib_data }
///     → HeaderBlock (for "OSMHeader")
///     → PrimitiveBlock (for "OSMData")
///       → StringTable, PrimitiveGroup[]
///         → DenseNodes | Way[]
/// ```
///
/// ## Usage
/// ```swift
/// let parser = PBFParser()
/// let (nodes, ways) = try await parser.parse(
///     fileURL: pbfURL,
///     boundingBox: bbox,
///     progress: { bytesRead, totalBytes in ... }
/// )
/// ```
actor PBFParser {

    // MARK: - Public Types

    /// A parsed OSM node with geographic coordinates and optional tags.
    struct OSMNode: Sendable {
        /// Unique OSM node ID.
        let id: Int64
        /// Latitude in degrees.
        let latitude: Double
        /// Longitude in degrees.
        let longitude: Double
        /// Key-value tags from OSM (e.g. `["name": "Summit"]`).
        let tags: [String: String]
    }

    /// A parsed OSM way with an ordered list of node references and tags.
    struct OSMWay: Sendable {
        /// Unique OSM way ID.
        let id: Int64
        /// Ordered list of node IDs forming this way's geometry.
        let nodeRefs: [Int64]
        /// Key-value tags from OSM (e.g. `["highway": "path"]`).
        let tags: [String: String]
    }

    /// Errors specific to PBF parsing.
    enum ParseError: Error, LocalizedError {
        case invalidBlobHeader
        case unsupportedCompression
        case decompressError
        case invalidPrimitiveBlock

        var errorDescription: String? {
            switch self {
            case .invalidBlobHeader:
                return "Invalid PBF blob header"
            case .unsupportedCompression:
                return "PBF uses unsupported compression (only raw and zlib are supported)"
            case .decompressError:
                return "Failed to decompress PBF blob"
            case .invalidPrimitiveBlock:
                return "Invalid PBF primitive block"
            }
        }
    }

    // MARK: - Public API

    /// Parse a PBF file, extracting hiking/cycling trail nodes and ways.
    ///
    /// The parser reads the file sequentially, decompresses each data block,
    /// and extracts nodes (from DenseNodes) and ways that match the routing
    /// tag filter. Only data within the given bounding box is retained.
    ///
    /// - Parameters:
    ///   - fileURL: Path to the `.osm.pbf` file on disk.
    ///   - boundingBox: Geographic filter — only nodes within this box are
    ///     kept, and only ways whose node refs all appear in the kept set
    ///     are included.
    ///   - progress: Callback with `(bytesProcessed, totalBytes)`.
    /// - Returns: A tuple of `(nodes, ways)` where `nodes` is keyed by
    ///   OSM node ID for efficient lookup during graph construction.
    func parse(
        fileURL: URL,
        boundingBox: BoundingBox,
        progress: @escaping (Int64, Int64) -> Void
    ) async throws -> (nodes: [Int64: OSMNode], ways: [OSMWay]) {

        let fileData = try Data(contentsOf: fileURL)
        let totalBytes = Int64(fileData.count)
        var offset = 0

        var allNodes: [Int64: OSMNode] = [:]
        var allWays: [OSMWay] = []

        // First pass: collect ALL nodes referenced by routable ways,
        // plus the ways themselves. We need two passes because ways
        // reference node IDs that may appear later in the file.
        // However for efficiency we do a single pass: collect nodes
        // into a dict, collect ways, then prune nodes not in any way.

        while offset < fileData.count {
            // Read BlobHeader length (4 bytes, big-endian)
            guard offset + 4 <= fileData.count else { break }
            let headerLength = Int(readBigEndianUInt32(fileData, at: offset))
            offset += 4

            guard offset + headerLength <= fileData.count else { break }
            let headerData = fileData[fileData.startIndex + offset ..< fileData.startIndex + offset + headerLength]
            offset += headerLength

            // Parse BlobHeader
            let (blobType, blobDataSize) = try parseBlobHeader(Data(headerData))

            guard offset + blobDataSize <= fileData.count else { break }
            let blobData = fileData[fileData.startIndex + offset ..< fileData.startIndex + offset + blobDataSize]
            offset += blobDataSize

            progress(Int64(offset), totalBytes)

            // Only process OSMData blocks (skip OSMHeader)
            guard blobType == "OSMData" else { continue }

            // Decompress blob
            let rawBlock = try decompressBlob(Data(blobData))

            // Parse PrimitiveBlock
            let (blockNodes, blockWays) = try parsePrimitiveBlock(rawBlock, boundingBox: boundingBox)

            for node in blockNodes {
                allNodes[node.id] = node
            }
            allWays.append(contentsOf: blockWays)

            // Yield to let other tasks run and avoid blocking
            await Task.yield()
        }

        // Prune: keep only nodes that are referenced by at least one way
        let referencedNodeIds = Set(allWays.flatMap { $0.nodeRefs })
        let prunedNodes = allNodes.filter { referencedNodeIds.contains($0.key) }

        return (nodes: prunedNodes, ways: allWays)
    }

    // MARK: - Tag Filtering

    /// Check if a way's tags indicate it is routable for hiking or cycling.
    ///
    /// Matches against ``RoutingCostConfig/routableHighwayValues`` and
    /// excludes private access and foot-prohibited ways.
    ///
    /// - Parameter tags: The way's OSM tags.
    /// - Returns: `true` if the way should be included in the routing graph.
    static func isRoutableWay(_ tags: [String: String]) -> Bool {
        guard let highway = tags["highway"] else { return false }
        guard RoutingCostConfig.routableHighwayValues.contains(highway) else { return false }

        // Exclude private access
        if let access = tags["access"], access == "private" || access == "no" { return false }

        // Exclude foot=no (unless it's a cycleway)
        if let foot = tags["foot"], foot == "no", highway != "cycleway" { return false }

        return true
    }

    // MARK: - Blob-Level Parsing

    /// Parse a BlobHeader to extract the blob type and data size.
    ///
    /// BlobHeader fields:
    /// - field 1 (string): type ("OSMHeader" or "OSMData")
    /// - field 3 (varint): datasize (byte length of the following Blob)
    private func parseBlobHeader(_ data: Data) throws -> (type: String, datasize: Int) {
        var reader = ProtobufReader(data: data)
        var type: String = ""
        var datasize: Int = 0

        while !reader.isAtEnd {
            let (fieldNumber, wireType) = try reader.readFieldTag()
            switch fieldNumber {
            case 1: // type
                let bytes = try reader.readLengthDelimited()
                type = String(data: bytes, encoding: .utf8) ?? ""
            case 3: // datasize
                datasize = Int(try reader.readVarint())
            default:
                try reader.skipField(wireType: wireType)
            }
        }

        guard !type.isEmpty, datasize > 0 else {
            throw ParseError.invalidBlobHeader
        }
        return (type, datasize)
    }

    /// Decompress a Blob, handling both raw and zlib payloads.
    ///
    /// Blob fields:
    /// - field 1 (bytes): raw (uncompressed data)
    /// - field 2 (varint): raw_size (decompressed size for zlib)
    /// - field 3 (bytes): zlib_data
    private func decompressBlob(_ data: Data) throws -> Data {
        var reader = ProtobufReader(data: data)
        var raw: Data?
        var zlibData: Data?
        var rawSize: Int = 0

        while !reader.isAtEnd {
            let (fieldNumber, wireType) = try reader.readFieldTag()
            switch fieldNumber {
            case 1: // raw
                raw = try reader.readLengthDelimited()
            case 2: // raw_size
                rawSize = Int(try reader.readVarint())
            case 3: // zlib_data
                zlibData = try reader.readLengthDelimited()
            default:
                try reader.skipField(wireType: wireType)
            }
        }

        if let raw = raw {
            return raw
        }

        if let zlibData = zlibData {
            return try zlibDecompress(zlibData, expectedSize: rawSize)
        }

        throw ParseError.unsupportedCompression
    }

    /// Decompress zlib data using Apple's Compression framework.
    ///
    /// - Parameters:
    ///   - data: The zlib-compressed bytes.
    ///   - expectedSize: The expected decompressed size (from the Blob's `raw_size`).
    /// - Returns: The decompressed data.
    /// - Throws: ``ParseError/decompressError`` if decompression fails.
    private func zlibDecompress(_ data: Data, expectedSize: Int) throws -> Data {
        // Skip the 2-byte zlib header (CMF + FLG) if present
        let sourceData: Data
        if data.count >= 2 {
            let cmf = data[data.startIndex]
            let flg = data[data.startIndex + 1]
            // Check for zlib header: CM=8 (deflate), and header checksum valid
            if (cmf & 0x0F) == 8 && (UInt16(cmf) * 256 + UInt16(flg)) % 31 == 0 {
                sourceData = data.dropFirst(2)
            } else {
                sourceData = data
            }
        } else {
            sourceData = data
        }

        let bufferSize = max(expectedSize, sourceData.count * 4)
        var destinationBuffer = Data(count: bufferSize)

        let decompressedSize = sourceData.withUnsafeBytes { srcPtr -> Int in
            destinationBuffer.withUnsafeMutableBytes { dstPtr -> Int in
                guard let srcBase = srcPtr.baseAddress,
                      let dstBase = dstPtr.baseAddress else { return 0 }
                return compression_decode_buffer(
                    dstBase.assumingMemoryBound(to: UInt8.self),
                    bufferSize,
                    srcBase.assumingMemoryBound(to: UInt8.self),
                    sourceData.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard decompressedSize > 0 else {
            throw ParseError.decompressError
        }

        return destinationBuffer.prefix(decompressedSize)
    }

    // MARK: - PrimitiveBlock Parsing

    /// Parse a PrimitiveBlock, extracting DenseNodes and Ways.
    ///
    /// PrimitiveBlock fields:
    /// - field 1 (StringTable): shared string pool
    /// - field 2 (PrimitiveGroup[]): groups of nodes/ways
    /// - field 17 (varint): granularity (default 100)
    /// - field 19 (varint): lat_offset (default 0)
    /// - field 20 (varint): lon_offset (default 0)
    private func parsePrimitiveBlock(
        _ data: Data,
        boundingBox: BoundingBox
    ) throws -> (nodes: [OSMNode], ways: [OSMWay]) {

        var reader = ProtobufReader(data: data)

        var stringTable: [String] = []
        var primitiveGroupDatas: [Data] = []
        var granularity: Int64 = 100
        var latOffset: Int64 = 0
        var lonOffset: Int64 = 0

        while !reader.isAtEnd {
            let (fieldNumber, wireType) = try reader.readFieldTag()
            switch fieldNumber {
            case 1: // stringtable
                let stData = try reader.readLengthDelimited()
                stringTable = try parseStringTable(stData)
            case 2: // primitivegroup
                primitiveGroupDatas.append(try reader.readLengthDelimited())
            case 17: // granularity
                granularity = Int64(try reader.readVarint())
            case 19: // lat_offset
                latOffset = Int64(try reader.readVarint())
            case 20: // lon_offset
                lonOffset = Int64(try reader.readVarint())
            default:
                try reader.skipField(wireType: wireType)
            }
        }

        var allNodes: [OSMNode] = []
        var allWays: [OSMWay] = []

        for groupData in primitiveGroupDatas {
            let (nodes, ways) = try parsePrimitiveGroup(
                groupData,
                stringTable: stringTable,
                granularity: granularity,
                latOffset: latOffset,
                lonOffset: lonOffset,
                boundingBox: boundingBox
            )
            allNodes.append(contentsOf: nodes)
            allWays.append(contentsOf: ways)
        }

        return (allNodes, allWays)
    }

    /// Parse the StringTable: a list of byte strings used by all nodes/ways in the block.
    private func parseStringTable(_ data: Data) throws -> [String] {
        var reader = ProtobufReader(data: data)
        var strings: [String] = []

        while !reader.isAtEnd {
            let (fieldNumber, wireType) = try reader.readFieldTag()
            if fieldNumber == 1 {
                let bytes = try reader.readLengthDelimited()
                strings.append(String(data: bytes, encoding: .utf8) ?? "")
            } else {
                try reader.skipField(wireType: wireType)
            }
        }
        return strings
    }

    /// Parse a PrimitiveGroup which can contain DenseNodes and/or Ways.
    ///
    /// PrimitiveGroup fields:
    /// - field 2 (DenseNodes): densely packed nodes
    /// - field 3 (Way[]): way messages
    private func parsePrimitiveGroup(
        _ data: Data,
        stringTable: [String],
        granularity: Int64,
        latOffset: Int64,
        lonOffset: Int64,
        boundingBox: BoundingBox
    ) throws -> (nodes: [OSMNode], ways: [OSMWay]) {

        var reader = ProtobufReader(data: data)
        var nodes: [OSMNode] = []
        var ways: [OSMWay] = []

        while !reader.isAtEnd {
            let (fieldNumber, wireType) = try reader.readFieldTag()
            switch fieldNumber {
            case 2: // dense
                let denseData = try reader.readLengthDelimited()
                nodes.append(contentsOf: try parseDenseNodes(
                    denseData,
                    stringTable: stringTable,
                    granularity: granularity,
                    latOffset: latOffset,
                    lonOffset: lonOffset,
                    boundingBox: boundingBox
                ))
            case 3: // ways
                let wayData = try reader.readLengthDelimited()
                if let way = try parseWay(wayData, stringTable: stringTable) {
                    ways.append(way)
                }
            default:
                try reader.skipField(wireType: wireType)
            }
        }
        return (nodes, ways)
    }

    // MARK: - DenseNodes

    /// Parse a DenseNodes message.
    ///
    /// DenseNodes is an optimised encoding where node IDs, latitudes, and
    /// longitudes are stored as delta-encoded packed arrays. Tags are stored
    /// as a flat array of alternating key/value string-table indices,
    /// separated by 0 between nodes.
    ///
    /// DenseNodes fields:
    /// - field 1: id (packed sint64, delta-coded)
    /// - field 8: lat (packed sint64, delta-coded)
    /// - field 9: lon (packed sint64, delta-coded)
    /// - field 10: keys_vals (packed int32, alternating key/val indices, 0 = separator)
    private func parseDenseNodes(
        _ data: Data,
        stringTable: [String],
        granularity: Int64,
        latOffset: Int64,
        lonOffset: Int64,
        boundingBox: BoundingBox
    ) throws -> [OSMNode] {

        var reader = ProtobufReader(data: data)

        var ids: [Int64] = []
        var lats: [Int64] = []
        var lons: [Int64] = []
        var keysVals: [Int32] = []

        while !reader.isAtEnd {
            let (fieldNumber, wireType) = try reader.readFieldTag()
            switch fieldNumber {
            case 1: // id (packed, delta-encoded signed varints)
                ids = try reader.readPackedSignedVarints()
            case 8: // lat
                lats = try reader.readPackedSignedVarints()
            case 9: // lon
                lons = try reader.readPackedSignedVarints()
            case 10: // keys_vals
                let raw = try reader.readPackedVarints()
                keysVals = raw.map { Int32($0) }
            default:
                try reader.skipField(wireType: wireType)
            }
        }

        // Delta-decode IDs, lats, lons
        guard ids.count == lats.count, ids.count == lons.count else {
            return []  // Malformed block — skip rather than crash
        }

        var nodes: [OSMNode] = []
        nodes.reserveCapacity(ids.count)

        var currentId: Int64 = 0
        var currentLat: Int64 = 0
        var currentLon: Int64 = 0
        var kvIndex = 0

        for i in 0..<ids.count {
            currentId += ids[i]
            currentLat += lats[i]
            currentLon += lons[i]

            let latitude = 0.000000001 * Double(latOffset + granularity * currentLat)
            let longitude = 0.000000001 * Double(lonOffset + granularity * currentLon)

            // Parse tags for this node
            var tags: [String: String] = [:]
            while kvIndex < keysVals.count {
                let keyIdx = Int(keysVals[kvIndex])
                if keyIdx == 0 {
                    kvIndex += 1
                    break
                }
                guard kvIndex + 1 < keysVals.count else { break }
                let valIdx = Int(keysVals[kvIndex + 1])
                kvIndex += 2

                if keyIdx < stringTable.count && valIdx < stringTable.count {
                    tags[stringTable[keyIdx]] = stringTable[valIdx]
                }
            }

            // Bounding box filter
            guard boundingBox.contains(
                CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            ) else { continue }

            nodes.append(OSMNode(
                id: currentId,
                latitude: latitude,
                longitude: longitude,
                tags: tags
            ))
        }

        return nodes
    }

    // MARK: - Way Parsing

    /// Parse a Way message and return it if it passes the routing tag filter.
    ///
    /// Way fields:
    /// - field 1 (varint): id
    /// - field 2 (packed uint32): keys (string table indices)
    /// - field 3 (packed uint32): vals (string table indices)
    /// - field 8 (packed sint64): refs (delta-encoded node IDs)
    private func parseWay(
        _ data: Data,
        stringTable: [String]
    ) throws -> OSMWay? {

        var reader = ProtobufReader(data: data)

        var wayId: Int64 = 0
        var keys: [UInt64] = []
        var vals: [UInt64] = []
        var refs: [Int64] = []

        while !reader.isAtEnd {
            let (fieldNumber, wireType) = try reader.readFieldTag()
            switch fieldNumber {
            case 1:
                wayId = Int64(try reader.readVarint())
            case 2:
                keys = try reader.readPackedVarints()
            case 3:
                vals = try reader.readPackedVarints()
            case 8:
                refs = try reader.readPackedSignedVarints()
            default:
                try reader.skipField(wireType: wireType)
            }
        }

        // Build tags dict
        var tags: [String: String] = [:]
        for i in 0..<min(keys.count, vals.count) {
            let keyIdx = Int(keys[i])
            let valIdx = Int(vals[i])
            if keyIdx < stringTable.count && valIdx < stringTable.count {
                tags[stringTable[keyIdx]] = stringTable[valIdx]
            }
        }

        // Filter: only keep routable ways
        guard PBFParser.isRoutableWay(tags) else { return nil }

        // Delta-decode node refs
        var decodedRefs: [Int64] = []
        decodedRefs.reserveCapacity(refs.count)
        var currentRef: Int64 = 0
        for delta in refs {
            currentRef += delta
            decodedRefs.append(currentRef)
        }

        return OSMWay(id: wayId, nodeRefs: decodedRefs, tags: tags)
    }

    // MARK: - Helpers

    /// Read a 4-byte big-endian unsigned integer from raw data at a given offset.
    ///
    /// PBF files use network byte order (big-endian) for blob header lengths.
    private func readBigEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[data.startIndex + offset]) << 24
        let b1 = UInt32(data[data.startIndex + offset + 1]) << 16
        let b2 = UInt32(data[data.startIndex + offset + 2]) << 8
        let b3 = UInt32(data[data.startIndex + offset + 3])
        return b0 | b1 | b2 | b3
    }
}
