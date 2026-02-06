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

// MARK: - Protobuf Wire Format Reader

/// Minimal protobuf wire-format reader for decoding OSM PBF files.
///
/// The PBF file format uses a fixed, small set of protobuf messages
/// (BlobHeader, Blob, HeaderBlock, PrimitiveBlock, etc.) so we do NOT
/// need a full protobuf library. This reader decodes just the wire
/// primitives: varints, length-delimited fields, and fixed-width values.
///
/// ## Wire types
/// | Wire type | Meaning              | Encoding                      |
/// |-----------|----------------------|-------------------------------|
/// | 0         | Varint               | Variable-length integer        |
/// | 1         | 64-bit               | Fixed 8 bytes (little-endian) |
/// | 2         | Length-delimited     | Varint length + raw bytes     |
/// | 5         | 32-bit               | Fixed 4 bytes (little-endian) |
///
/// Wire types 3 and 4 (start/end group) are deprecated and not supported.
struct ProtobufReader {

    /// Errors that can occur while reading protobuf data.
    enum Error: Swift.Error, LocalizedError {
        /// The data buffer ran out before a complete value could be read.
        case unexpectedEndOfData
        /// A varint exceeded 10 bytes (the maximum for 64-bit values).
        case varintTooLong
        /// An unsupported wire type was encountered.
        case unsupportedWireType(Int)
        /// A ZigZag-decoded value would overflow Int64.
        case signedOverflow

        var errorDescription: String? {
            switch self {
            case .unexpectedEndOfData:
                return "Unexpected end of protobuf data"
            case .varintTooLong:
                return "Varint exceeds maximum length"
            case .unsupportedWireType(let wt):
                return "Unsupported protobuf wire type: \(wt)"
            case .signedOverflow:
                return "Signed varint overflow"
            }
        }
    }

    /// The raw protobuf data being read.
    private let data: Data

    /// Current byte offset within `data`.
    private(set) var offset: Int

    /// Create a reader over the given data, starting at byte 0.
    ///
    /// - Parameter data: The raw protobuf-encoded bytes.
    init(data: Data) {
        self.data = data
        self.offset = 0
    }

    /// Whether the reader has consumed all available bytes.
    var isAtEnd: Bool { offset >= data.count }

    /// Number of bytes remaining from the current offset.
    var bytesRemaining: Int { data.count - offset }

    // MARK: - Primitive Reads

    /// Read a single raw byte and advance the offset.
    ///
    /// - Returns: The byte value.
    /// - Throws: ``Error/unexpectedEndOfData`` if no bytes remain.
    mutating func readByte() throws -> UInt8 {
        guard offset < data.count else { throw Error.unexpectedEndOfData }
        let byte = data[data.startIndex + offset]
        offset += 1
        return byte
    }

    /// Read a base-128 varint (unsigned).
    ///
    /// Varints are the fundamental integer encoding in protobuf.
    /// Each byte contributes 7 bits; the MSB indicates continuation.
    ///
    /// - Returns: The decoded 64-bit unsigned value.
    /// - Throws: ``Error/varintTooLong`` if more than 10 bytes are used.
    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        for _ in 0..<10 {
            let byte = try readByte()
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }
        throw Error.varintTooLong
    }

    /// Read a ZigZag-encoded signed varint.
    ///
    /// Protobuf encodes signed integers using ZigZag encoding so that
    /// small absolute values (both positive and negative) use few bytes.
    /// Mapping: 0→0, -1→1, 1→2, -2→3, 2→4, …
    ///
    /// - Returns: The decoded signed 64-bit value.
    mutating func readSignedVarint() throws -> Int64 {
        let raw = try readVarint()
        // ZigZag decode: (raw >>> 1) ^ -(raw & 1)
        let decoded = Int64(bitPattern: (raw >> 1) ^ (0 &- (raw & 1)))
        return decoded
    }

    /// Read a 32-bit little-endian unsigned integer (wire type 5).
    ///
    /// - Returns: The 32-bit value.
    /// - Throws: ``Error/unexpectedEndOfData`` if fewer than 4 bytes remain.
    mutating func readFixed32() throws -> UInt32 {
        guard offset + 4 <= data.count else { throw Error.unexpectedEndOfData }
        let value = data.withUnsafeBytes { ptr -> UInt32 in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        offset += 4
        return UInt32(littleEndian: value)
    }

    /// Read a 64-bit little-endian unsigned integer (wire type 1).
    ///
    /// - Returns: The 64-bit value.
    /// - Throws: ``Error/unexpectedEndOfData`` if fewer than 8 bytes remain.
    mutating func readFixed64() throws -> UInt64 {
        guard offset + 8 <= data.count else { throw Error.unexpectedEndOfData }
        let value = data.withUnsafeBytes { ptr -> UInt64 in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
        }
        offset += 8
        return UInt64(littleEndian: value)
    }

    /// Read a length-delimited field (wire type 2).
    ///
    /// First reads a varint giving the byte length, then reads that many bytes.
    ///
    /// - Returns: A `Data` slice containing the field's raw bytes.
    /// - Throws: ``Error/unexpectedEndOfData`` if the data is too short.
    mutating func readLengthDelimited() throws -> Data {
        let length = Int(try readVarint())
        guard offset + length <= data.count else { throw Error.unexpectedEndOfData }
        let result = data[data.startIndex + offset ..< data.startIndex + offset + length]
        offset += length
        return Data(result)
    }

    /// Skip `count` bytes without reading them.
    ///
    /// - Parameter count: Number of bytes to skip.
    /// - Throws: ``Error/unexpectedEndOfData`` if not enough bytes remain.
    mutating func skip(_ count: Int) throws {
        guard offset + count <= data.count else { throw Error.unexpectedEndOfData }
        offset += count
    }

    // MARK: - Field-Level Reads

    /// Read a protobuf field tag: the field number and wire type.
    ///
    /// In the protobuf wire format every field is preceded by a varint
    /// whose lower 3 bits encode the wire type and upper bits encode
    /// the field number.
    ///
    /// - Returns: A tuple of `(fieldNumber, wireType)`.
    mutating func readFieldTag() throws -> (fieldNumber: Int, wireType: Int) {
        let tag = try readVarint()
        let wireType = Int(tag & 0x07)
        let fieldNumber = Int(tag >> 3)
        return (fieldNumber, wireType)
    }

    /// Skip a field value based on its wire type.
    ///
    /// Used to skip over fields we don't care about when parsing a message.
    ///
    /// - Parameter wireType: The wire type of the field to skip.
    /// - Throws: ``Error/unsupportedWireType(_:)`` for wire types 3 and 4.
    mutating func skipField(wireType: Int) throws {
        switch wireType {
        case 0:
            _ = try readVarint()
        case 1:
            try skip(8)
        case 2:
            let length = Int(try readVarint())
            try skip(length)
        case 5:
            try skip(4)
        default:
            throw Error.unsupportedWireType(wireType)
        }
    }

    // MARK: - Packed Repeated Fields

    /// Read a packed repeated field of varints.
    ///
    /// Packed repeated fields store all values back-to-back in a single
    /// length-delimited field, which is more compact than one tag per value.
    ///
    /// - Returns: An array of decoded unsigned 64-bit varints.
    mutating func readPackedVarints() throws -> [UInt64] {
        let fieldData = try readLengthDelimited()
        var sub = ProtobufReader(data: fieldData)
        var values: [UInt64] = []
        while !sub.isAtEnd {
            values.append(try sub.readVarint())
        }
        return values
    }

    /// Read a packed repeated field of ZigZag-encoded signed varints.
    ///
    /// - Returns: An array of decoded signed 64-bit values.
    mutating func readPackedSignedVarints() throws -> [Int64] {
        let fieldData = try readLengthDelimited()
        var sub = ProtobufReader(data: fieldData)
        var values: [Int64] = []
        while !sub.isAtEnd {
            values.append(try sub.readSignedVarint())
        }
        return values
    }
}
