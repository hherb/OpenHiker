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
import Compression

/// Compresses and decompresses GPS track data using a compact binary format with zlib compression.
///
/// ## Binary Format
/// Each track point is stored as a sequential record of:
/// - `Float32` latitude  (4 bytes)
/// - `Float32` longitude (4 bytes)
/// - `Float32` altitude  (4 bytes)
/// - `Float64` timestamp (8 bytes, seconds since reference date)
///
/// **Total: 20 bytes per point** vs ~150 bytes per GPX text point.
///
/// The raw binary data is then compressed using Apple's `Compression` framework
/// with the `COMPRESSION_ZLIB` algorithm, typically achieving 50-60% further reduction.
///
/// ## Example
/// A 1000-point hike:
/// - Raw binary: 20,000 bytes (20 KB)
/// - After zlib: ~8,000–10,000 bytes (8-10 KB)
/// - GPX text equivalent: ~150,000 bytes (150 KB)
///
/// ## Thread Safety
/// All methods are pure static functions with no shared state, making them safe
/// to call from any thread.
enum TrackCompression {

    /// Size in bytes of a single uncompressed track point record.
    ///
    /// Layout: Float32 (lat) + Float32 (lon) + Float32 (alt) + Float64 (timestamp)
    /// = 4 + 4 + 4 + 8 = 20 bytes.
    static let bytesPerPoint = 20

    /// Extra bytes added to the compression output buffer beyond the source size.
    ///
    /// Zlib output is typically smaller than input, but for very small inputs
    /// the overhead of zlib framing can make the output slightly larger. This
    /// safety margin prevents buffer overruns.
    private static let compressionBufferMargin = 64

    /// Multiplier applied to compressed data size to estimate the decompression
    /// buffer size.
    ///
    /// For our binary track records, the typical compression ratio is ~2:1.
    /// Using 10x provides a safe upper bound while keeping allocation reasonable.
    private static let decompressionBufferMultiplier = 10

    // MARK: - Encode

    /// Encodes an array of CLLocation objects into compressed binary data.
    ///
    /// The encoding process:
    /// 1. Packs each location into 20-byte records (Float32 lat/lon/alt + Float64 timestamp)
    /// 2. Compresses the packed data using zlib
    ///
    /// - Parameter locations: The GPS track points to encode.
    /// - Returns: Zlib-compressed binary data, or empty `Data` if the input is empty.
    static func encode(_ locations: [CLLocation]) -> Data {
        guard !locations.isEmpty else { return Data() }

        // Pack into raw binary: 20 bytes per point
        var rawData = Data(capacity: locations.count * bytesPerPoint)

        for location in locations {
            var lat = Float32(location.coordinate.latitude)
            var lon = Float32(location.coordinate.longitude)
            var alt = Float32(location.altitude)
            var timestamp = Float64(location.timestamp.timeIntervalSinceReferenceDate)

            rawData.append(Data(bytes: &lat, count: MemoryLayout<Float32>.size))
            rawData.append(Data(bytes: &lon, count: MemoryLayout<Float32>.size))
            rawData.append(Data(bytes: &alt, count: MemoryLayout<Float32>.size))
            rawData.append(Data(bytes: &timestamp, count: MemoryLayout<Float64>.size))
        }

        // Compress with zlib
        return compress(rawData) ?? rawData
    }

    // MARK: - Decode

    /// Decodes compressed binary data back into an array of CLLocation objects.
    ///
    /// The decoding process:
    /// 1. Decompresses the zlib data
    /// 2. Unpacks each 20-byte record into Float32 lat/lon/alt + Float64 timestamp
    /// 3. Creates CLLocation objects with the extracted values
    ///
    /// - Parameter data: Zlib-compressed binary track data from ``encode(_:)``.
    /// - Returns: An array of CLLocation objects, or an empty array if decompression fails
    ///   or the data is empty.
    static func decode(_ data: Data) -> [CLLocation] {
        guard !data.isEmpty else { return [] }

        // Decompress
        guard let rawData = decompress(data) else {
            // If decompression fails, try reading as uncompressed data
            // (backwards compatibility if data was stored without compression)
            return decodeRaw(data)
        }

        return decodeRaw(rawData)
    }

    // MARK: - Elevation Data Extraction

    /// Extracts elevation profile data points from compressed track data.
    ///
    /// Each returned point contains the cumulative distance from the start
    /// and the elevation at that point. Used by ``ElevationProfileView`` on iOS
    /// for rendering Swift Charts.
    ///
    /// - Parameter data: Zlib-compressed binary track data.
    /// - Returns: An array of `(distance, elevation)` tuples where distance is in
    ///   meters from the track start and elevation is in meters above sea level.
    static func extractElevationProfile(_ data: Data) -> [(distance: Double, elevation: Double)] {
        let locations = decode(data)
        guard !locations.isEmpty else { return [] }

        var profile: [(distance: Double, elevation: Double)] = []
        var cumulativeDistance: Double = 0

        profile.append((distance: 0, elevation: locations[0].altitude))

        for i in 1..<locations.count {
            cumulativeDistance += locations[i].distance(from: locations[i - 1])
            profile.append((distance: cumulativeDistance, elevation: locations[i].altitude))
        }

        return profile
    }

    // MARK: - Private Helpers

    /// Decodes raw (uncompressed) binary track data into CLLocation objects.
    ///
    /// - Parameter rawData: Uncompressed binary data with 20-byte point records.
    /// - Returns: An array of CLLocation objects.
    private static func decodeRaw(_ rawData: Data) -> [CLLocation] {
        let pointCount = rawData.count / bytesPerPoint
        guard pointCount > 0 else { return [] }

        var locations: [CLLocation] = []
        locations.reserveCapacity(pointCount)

        rawData.withUnsafeBytes { buffer in
            let base = buffer.baseAddress!
            for i in 0..<pointCount {
                let offset = i * bytesPerPoint

                // Use loadUnaligned because the Float64 timestamp sits at byte
                // offset 12 within each 20-byte record, which is not 8-byte aligned.
                let lat = base.loadUnaligned(fromByteOffset: offset, as: Float32.self)
                let lon = base.loadUnaligned(fromByteOffset: offset + 4, as: Float32.self)
                let alt = base.loadUnaligned(fromByteOffset: offset + 8, as: Float32.self)
                let timestamp = base.loadUnaligned(fromByteOffset: offset + 12, as: Float64.self)

                let coordinate = CLLocationCoordinate2D(
                    latitude: Double(lat),
                    longitude: Double(lon)
                )
                let date = Date(timeIntervalSinceReferenceDate: timestamp)

                let location = CLLocation(
                    coordinate: coordinate,
                    altitude: Double(alt),
                    horizontalAccuracy: 0,
                    verticalAccuracy: 0,
                    timestamp: date
                )
                locations.append(location)
            }
        }

        return locations
    }

    /// Compresses data using the zlib algorithm via Apple's Compression framework.
    ///
    /// Allocates a destination buffer sized to the source data length (zlib output
    /// is typically smaller, but in worst case can be slightly larger for tiny inputs).
    /// Returns `nil` if compression fails.
    ///
    /// - Parameter sourceData: The raw data to compress.
    /// - Returns: Zlib-compressed data, or `nil` if compression fails.
    private static func compress(_ sourceData: Data) -> Data? {
        // Destination buffer — same size as source is usually enough for zlib
        // (compressed output is smaller). Add a small margin for safety.
        let destinationBufferSize = sourceData.count + compressionBufferMargin
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
        defer { destinationBuffer.deallocate() }

        let compressedSize = sourceData.withUnsafeBytes { sourceBuffer -> Int in
            guard let sourcePtr = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }
            return compression_encode_buffer(
                destinationBuffer,
                destinationBufferSize,
                sourcePtr,
                sourceData.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard compressedSize > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: compressedSize)
    }

    /// Decompresses zlib-compressed data via Apple's Compression framework.
    ///
    /// Allocates a destination buffer at 10x the compressed size to accommodate
    /// the expected expansion ratio. Returns `nil` if decompression fails.
    ///
    /// - Parameter compressedData: Zlib-compressed data.
    /// - Returns: The decompressed raw data, or `nil` if decompression fails.
    private static func decompress(_ compressedData: Data) -> Data? {
        // Estimate decompressed size: for our binary track data, typical ratio is ~2:1
        // Use 10x as upper bound to be safe.
        let destinationBufferSize = compressedData.count * decompressionBufferMultiplier
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = compressedData.withUnsafeBytes { sourceBuffer -> Int in
            guard let sourcePtr = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }
            return compression_decode_buffer(
                destinationBuffer,
                destinationBufferSize,
                sourcePtr,
                compressedData.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: decompressedSize)
    }
}
