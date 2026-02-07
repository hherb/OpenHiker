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
import SQLite3
#if canImport(UIKit)
import UIKit
#elseif canImport(WatchKit)
import WatchKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Errors that can occur when working with the tile store.
///
/// Each case provides a human-readable `errorDescription` via `LocalizedError`
/// so that error messages can be displayed directly to the user.
enum TileStoreError: Error, LocalizedError {
    /// The SQLite database connection has not been opened yet
    case databaseNotOpen
    /// A SQLite operation failed with the given error message
    case databaseError(String)
    /// The requested tile was not found in the database
    case tileNotFound
    /// The tile data in the database is corrupted or unreadable
    case invalidTileData
    /// The MBTiles file does not exist at the given path
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotOpen:
            return "Database is not open"
        case .databaseError(let message):
            return "Database error: \(message)"
        case .tileNotFound:
            return "Tile not found"
        case .invalidTileData:
            return "Invalid tile data"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}

/// Read-only MBTiles-compatible tile storage using SQLite.
///
/// Opens an MBTiles file (a SQLite database following the MBTiles specification) and provides
/// tile lookup by `TileCoordinate`. The MBTiles format stores tiles with TMS y-coordinates
/// (inverted compared to the standard "slippy map" XYZ convention), so this class handles
/// the y-coordinate flipping internally.
///
/// All database operations are dispatched on a serial queue for thread safety.
/// The class is marked `@unchecked Sendable` because it manages its own synchronization.
///
/// Used by the watch app's `MapRenderer` to read pre-downloaded tiles for offline display.
final class TileStore: @unchecked Sendable {
    /// The underlying SQLite database connection (nil when closed)
    private var db: OpaquePointer?
    /// File path to the MBTiles database
    private let path: String
    /// Serial dispatch queue ensuring thread-safe database access
    private let queue = DispatchQueue(label: "com.openhiker.tilestore", qos: .userInitiated)

    /// Metadata about the tileset as read from the MBTiles `metadata` table.
    struct Metadata: Sendable {
        /// Name of the tileset (from the `name` metadata key)
        let name: String?
        /// Tile image format: "png", "jpg", or "pbf"
        let format: String
        /// Minimum zoom level available
        let minZoom: Int
        /// Maximum zoom level available
        let maxZoom: Int
        /// Geographic bounds of the tileset, if specified
        let bounds: BoundingBox?
        /// Default center view (latitude, longitude, zoom), if specified
        let center: (lat: Double, lon: Double, zoom: Int)?
    }

    /// Cached metadata loaded when the database is opened
    private(set) var metadata: Metadata?

    /// Create a tile store for the MBTiles file at the given path.
    ///
    /// The database is not opened until `open()` is called.
    ///
    /// - Parameter path: File system path to the MBTiles SQLite database.
    init(path: String) {
        self.path = path
    }

    deinit {
        close()
    }

    /// Open the MBTiles database for reading.
    ///
    /// Verifies the file exists, opens it in read-only mode with full-mutex threading,
    /// and loads the tileset metadata from the `metadata` table.
    ///
    /// - Throws: `TileStoreError.fileNotFound` if the file doesn't exist,
    ///   or `TileStoreError.databaseError` if SQLite fails to open the file.
    func open() throws {
        try queue.sync {
            guard FileManager.default.fileExists(atPath: path) else {
                throw TileStoreError.fileNotFound(path)
            }

            var dbPointer: OpaquePointer?
            let result = sqlite3_open_v2(
                path,
                &dbPointer,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
                nil
            )

            guard result == SQLITE_OK, let db = dbPointer else {
                let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
                sqlite3_close(dbPointer)
                throw TileStoreError.databaseError(errorMessage)
            }

            self.db = db

            // Load metadata
            self.metadata = try loadMetadata()
        }
    }

    /// Close the database connection and release resources.
    ///
    /// Safe to call multiple times; subsequent calls are no-ops.
    func close() {
        queue.sync {
            if let db = db {
                sqlite3_close(db)
                self.db = nil
            }
        }
    }

    /// Retrieve tile image data for the given coordinates.
    ///
    /// Looks up the tile in the MBTiles `tiles` table, converting from XYZ to TMS
    /// y-coordinates internally (TMS flips the y-axis: `tmsY = 2^z - 1 - y`).
    ///
    /// - Parameter coordinate: The tile coordinate (in standard XYZ / slippy map convention).
    /// - Returns: The raw tile image data (typically PNG).
    /// - Throws: `TileStoreError.databaseNotOpen` if the database hasn't been opened,
    ///   `TileStoreError.tileNotFound` if no tile exists at these coordinates,
    ///   or `TileStoreError.invalidTileData` if the stored blob is null.
    func getTile(_ coordinate: TileCoordinate) throws -> Data {
        try queue.sync {
            guard let db = db else {
                throw TileStoreError.databaseNotOpen
            }

            // MBTiles uses TMS y-coordinate (inverted from standard XYZ)
            let tmsY = (1 << coordinate.z) - 1 - coordinate.y

            let query = "SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?"
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                throw TileStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int(statement, 1, Int32(coordinate.z))
            sqlite3_bind_int(statement, 2, Int32(coordinate.x))
            sqlite3_bind_int(statement, 3, Int32(tmsY))

            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw TileStoreError.tileNotFound
            }

            guard let blob = sqlite3_column_blob(statement, 0) else {
                throw TileStoreError.invalidTileData
            }

            let size = sqlite3_column_bytes(statement, 0)
            return Data(bytes: blob, count: Int(size))
        }
    }

    /// Check if a tile exists in the database.
    ///
    /// Attempts to retrieve the tile and returns `true` if it exists, `false` otherwise.
    ///
    /// - Parameter coordinate: The tile coordinate to check.
    /// - Returns: `true` if the tile exists in the store.
    func hasTile(_ coordinate: TileCoordinate) -> Bool {
        do {
            _ = try getTile(coordinate)
            return true
        } catch {
            return false
        }
    }

    /// Retrieve all tiles within a tile range.
    ///
    /// Iterates over every tile in the range and returns those that exist in the database.
    /// Tiles that are missing are silently skipped.
    ///
    /// - Parameter range: The tile range to query.
    /// - Returns: An array of (coordinate, data) tuples for each found tile.
    /// - Throws: Rethrows any unexpected database errors.
    func getTiles(in range: TileRange) throws -> [(TileCoordinate, Data)] {
        var results: [(TileCoordinate, Data)] = []

        for tile in range.allTiles() {
            if let data = try? getTile(tile) {
                results.append((tile, data))
            }
        }

        return results
    }

    // MARK: - Private Methods

    /// Load and parse metadata from the MBTiles `metadata` table.
    ///
    /// Reads all key-value pairs from the `metadata` table and extracts known fields
    /// (name, format, minzoom, maxzoom, bounds, center). Returns sensible defaults
    /// if the metadata table doesn't exist.
    ///
    /// - Returns: A `Metadata` struct with the parsed values.
    /// - Throws: `TileStoreError.databaseNotOpen` if the database isn't open.
    private func loadMetadata() throws -> Metadata {
        guard let db = db else {
            throw TileStoreError.databaseNotOpen
        }

        var metadataDict: [String: String] = [:]

        let query = "SELECT name, value FROM metadata"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            // Metadata table might not exist - return defaults
            return Metadata(
                name: nil,
                format: "png",
                minZoom: 0,
                maxZoom: 22,
                bounds: nil,
                center: nil
            )
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(statement, 0),
               let valuePtr = sqlite3_column_text(statement, 1) {
                let name = String(cString: namePtr)
                let value = String(cString: valuePtr)
                metadataDict[name] = value
            }
        }

        // Parse bounds: "west,south,east,north"
        var bounds: BoundingBox?
        if let boundsStr = metadataDict["bounds"] {
            let parts = boundsStr.split(separator: ",").compactMap { Double($0) }
            if parts.count == 4 {
                bounds = BoundingBox(north: parts[3], south: parts[1], east: parts[2], west: parts[0])
            }
        }

        // Parse center: "lon,lat,zoom"
        var center: (lat: Double, lon: Double, zoom: Int)?
        if let centerStr = metadataDict["center"] {
            let parts = centerStr.split(separator: ",")
            if parts.count >= 3,
               let lon = Double(parts[0]),
               let lat = Double(parts[1]),
               let zoom = Int(parts[2]) {
                center = (lat: lat, lon: lon, zoom: zoom)
            }
        }

        return Metadata(
            name: metadataDict["name"],
            format: metadataDict["format"] ?? "png",
            minZoom: Int(metadataDict["minzoom"] ?? "0") ?? 0,
            maxZoom: Int(metadataDict["maxzoom"] ?? "22") ?? 22,
            bounds: bounds,
            center: center
        )
    }
}

// MARK: - TileStore Creation (iOS and macOS)

#if os(iOS) || os(macOS)
extension TileStore {
    /// Create a new MBTiles database for writing tiles.
    ///
    /// This is a convenience factory method that creates a `WritableTileStore` at the
    /// given path with the specified metadata entries.
    ///
    /// - Parameters:
    ///   - path: File system path for the new MBTiles file.
    ///   - metadata: Key-value pairs to write into the MBTiles `metadata` table.
    /// - Returns: A `WritableTileStore` ready for inserting tiles.
    /// - Throws: `TileStoreError.databaseError` if the database cannot be created.
    static func create(at path: String, metadata: [String: String]) throws -> WritableTileStore {
        try WritableTileStore(path: path, metadata: metadata)
    }
}

/// A writable tile store for creating MBTiles files on iOS.
///
/// Used by `TileDownloader` to build an MBTiles database as tiles are downloaded from
/// OpenTopoMap. Supports transactional bulk inserts for efficient writing.
///
/// The database is opened in read-write mode with full-mutex threading. All operations
/// are dispatched on a serial queue for thread safety.
final class WritableTileStore: @unchecked Sendable {
    /// The underlying SQLite database connection (nil when closed)
    private var db: OpaquePointer?
    /// File path to the MBTiles database
    private let path: String
    /// Serial dispatch queue ensuring thread-safe database access
    private let queue = DispatchQueue(label: "com.openhiker.writabletilestore", qos: .userInitiated)

    /// Create a new MBTiles database at the given path.
    ///
    /// Creates the parent directory if needed, removes any existing file at the path,
    /// opens a new SQLite database, creates the MBTiles schema, and inserts the metadata.
    ///
    /// - Parameters:
    ///   - path: File system path for the new database.
    ///   - metadata: Key-value pairs to write into the `metadata` table.
    /// - Throws: `TileStoreError.databaseError` if the database cannot be created.
    init(path: String, metadata: [String: String]) throws {
        self.path = path

        // Create directory if needed
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        // Remove existing file
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }

        var dbPointer: OpaquePointer?
        let result = sqlite3_open_v2(
            path,
            &dbPointer,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard result == SQLITE_OK, let db = dbPointer else {
            let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
            sqlite3_close(dbPointer)
            throw TileStoreError.databaseError(errorMessage)
        }

        self.db = db

        try createSchema()
        try insertMetadata(metadata)
    }

    deinit {
        close()
    }

    /// Close the database connection and release resources.
    ///
    /// Safe to call multiple times; subsequent calls are no-ops.
    func close() {
        queue.sync {
            if let db = db {
                sqlite3_close(db)
                self.db = nil
            }
        }
    }

    /// Insert a tile into the database, replacing any existing tile at the same coordinates.
    ///
    /// Converts from standard XYZ coordinates to the TMS y-coordinate convention used
    /// by MBTiles (`tmsY = 2^z - 1 - y`).
    ///
    /// - Parameters:
    ///   - coordinate: The tile coordinate (in standard XYZ convention).
    ///   - data: The raw tile image data (typically PNG).
    /// - Throws: `TileStoreError.databaseNotOpen` or `TileStoreError.databaseError`.
    func insertTile(_ coordinate: TileCoordinate, data: Data) throws {
        try queue.sync {
            guard let db = db else {
                throw TileStoreError.databaseNotOpen
            }

            // MBTiles uses TMS y-coordinate
            let tmsY = (1 << coordinate.z) - 1 - coordinate.y

            let query = "INSERT OR REPLACE INTO tiles (zoom_level, tile_column, tile_row, tile_data) VALUES (?, ?, ?, ?)"
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                throw TileStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int(statement, 1, Int32(coordinate.z))
            sqlite3_bind_int(statement, 2, Int32(coordinate.x))
            sqlite3_bind_int(statement, 3, Int32(tmsY))

            _ = data.withUnsafeBytes { ptr in
                sqlite3_bind_blob(statement, 4, ptr.baseAddress, Int32(data.count), nil)
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TileStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    /// Begin a SQLite transaction for efficient bulk inserts.
    ///
    /// Call this before inserting a batch of tiles, then call `commitTransaction()` when done.
    /// Wrapping bulk inserts in a transaction dramatically improves write performance.
    ///
    /// - Throws: `TileStoreError.databaseError` if the transaction cannot be started.
    func beginTransaction() throws {
        try execute("BEGIN TRANSACTION")
    }

    /// Commit the current SQLite transaction, persisting all changes since `beginTransaction()`.
    ///
    /// - Throws: `TileStoreError.databaseError` if the commit fails.
    func commitTransaction() throws {
        try execute("COMMIT")
    }

    /// Rollback the current SQLite transaction, discarding all changes since `beginTransaction()`.
    ///
    /// - Throws: `TileStoreError.databaseError` if the rollback fails.
    func rollbackTransaction() throws {
        try execute("ROLLBACK")
    }

    /// Create the MBTiles database schema (metadata and tiles tables plus index).
    ///
    /// - Throws: `TileStoreError.databaseError` if schema creation fails.
    private func createSchema() throws {
        // MBTiles schema
        try execute("""
            CREATE TABLE IF NOT EXISTS metadata (
                name TEXT PRIMARY KEY,
                value TEXT
            )
        """)

        try execute("""
            CREATE TABLE IF NOT EXISTS tiles (
                zoom_level INTEGER,
                tile_column INTEGER,
                tile_row INTEGER,
                tile_data BLOB,
                PRIMARY KEY (zoom_level, tile_column, tile_row)
            )
        """)

        // Index for faster lookups
        try execute("""
            CREATE INDEX IF NOT EXISTS tiles_idx ON tiles (zoom_level, tile_column, tile_row)
        """)
    }

    /// Insert metadata key-value pairs into the `metadata` table.
    ///
    /// - Parameter metadata: Dictionary of metadata entries to insert.
    /// - Throws: `TileStoreError.databaseNotOpen` or `TileStoreError.databaseError`.
    private func insertMetadata(_ metadata: [String: String]) throws {
        guard let db = db else {
            throw TileStoreError.databaseNotOpen
        }

        let query = "INSERT OR REPLACE INTO metadata (name, value) VALUES (?, ?)"

        for (name, value) in metadata {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                throw TileStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, name, -1, nil)
            sqlite3_bind_text(statement, 2, value, -1, nil)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TileStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    /// Execute a raw SQL statement.
    ///
    /// Used for DDL statements (CREATE TABLE) and transaction control (BEGIN, COMMIT, ROLLBACK).
    ///
    /// - Parameter sql: The SQL statement to execute.
    /// - Throws: `TileStoreError.databaseNotOpen` or `TileStoreError.databaseError`.
    private func execute(_ sql: String) throws {
        try queue.sync {
            guard let db = db else {
                throw TileStoreError.databaseNotOpen
            }

            var errorMessage: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)

            if result != SQLITE_OK {
                let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
                sqlite3_free(errorMessage)
                throw TileStoreError.databaseError(message)
            }
        }
    }
}
#endif
