import Foundation
import SQLite3
#if canImport(UIKit)
import UIKit
#elseif canImport(WatchKit)
import WatchKit
#endif

/// Errors that can occur when working with the tile store
enum TileStoreError: Error, LocalizedError {
    case databaseNotOpen
    case databaseError(String)
    case tileNotFound
    case invalidTileData
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

/// MBTiles-compatible tile storage using SQLite
/// Supports reading pre-rendered raster tiles from an MBTiles file
final class TileStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let path: String
    private let queue = DispatchQueue(label: "com.openhiker.tilestore", qos: .userInitiated)

    /// Metadata about the tileset
    struct Metadata: Sendable {
        let name: String?
        let format: String  // "png", "jpg", "pbf"
        let minZoom: Int
        let maxZoom: Int
        let bounds: BoundingBox?
        let center: (lat: Double, lon: Double, zoom: Int)?
    }

    private(set) var metadata: Metadata?

    init(path: String) {
        self.path = path
    }

    deinit {
        close()
    }

    /// Open the MBTiles database
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

    /// Close the database connection
    func close() {
        queue.sync {
            if let db = db {
                sqlite3_close(db)
                self.db = nil
            }
        }
    }

    /// Get a tile image for the given coordinates
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

    /// Check if a tile exists
    func hasTile(_ coordinate: TileCoordinate) -> Bool {
        do {
            _ = try getTile(coordinate)
            return true
        } catch {
            return false
        }
    }

    /// Get all tiles in a range
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

// MARK: - TileStore Creation (iOS only)

#if os(iOS)
extension TileStore {
    /// Create a new MBTiles database for writing tiles
    static func create(at path: String, metadata: [String: String]) throws -> WritableTileStore {
        try WritableTileStore(path: path, metadata: metadata)
    }
}

/// A writable tile store for creating MBTiles files on iOS
final class WritableTileStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let path: String
    private let queue = DispatchQueue(label: "com.openhiker.writabletilestore", qos: .userInitiated)

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

    func close() {
        queue.sync {
            if let db = db {
                sqlite3_close(db)
                self.db = nil
            }
        }
    }

    /// Insert a tile into the database
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

            data.withUnsafeBytes { ptr in
                sqlite3_bind_blob(statement, 4, ptr.baseAddress, Int32(data.count), nil)
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TileStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    /// Begin a transaction for bulk inserts
    func beginTransaction() throws {
        try execute("BEGIN TRANSACTION")
    }

    /// Commit the current transaction
    func commitTransaction() throws {
        try execute("COMMIT")
    }

    /// Rollback the current transaction
    func rollbackTransaction() throws {
        try execute("ROLLBACK")
    }

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
