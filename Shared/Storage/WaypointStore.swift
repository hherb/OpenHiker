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
import CoreLocation

/// Errors that can occur when working with the waypoint store.
///
/// Each case provides a human-readable `errorDescription` via `LocalizedError`
/// so that error messages can be displayed directly to the user.
enum WaypointStoreError: Error, LocalizedError {
    /// The SQLite database connection has not been opened yet.
    case databaseNotOpen
    /// A SQLite operation failed with the given error message.
    case databaseError(String)
    /// The requested waypoint was not found in the database.
    case waypointNotFound
    /// The waypoint data in the database is corrupted or unreadable.
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotOpen:
            return "Waypoint database is not open"
        case .databaseError(let message):
            return "Waypoint database error: \(message)"
        case .waypointNotFound:
            return "Waypoint not found"
        case .invalidData(let message):
            return "Invalid waypoint data: \(message)"
        }
    }
}

/// SQLite-backed storage for waypoints, following the ``TileStore`` pattern.
///
/// Provides CRUD operations for ``Waypoint`` objects plus spatial and hike-based
/// queries. Photo data (full-res JPEG and 100x100 thumbnail) is stored as BLOBs
/// in separate columns to keep the ``Waypoint`` struct lightweight.
///
/// All database operations are dispatched on a serial queue for thread safety.
/// The class is marked `@unchecked Sendable` because it manages its own
/// synchronization via `DispatchQueue`.
///
/// ## Database location
/// The database file is stored at `Documents/waypoints.db` on both platforms.
///
/// ## Usage
/// ```swift
/// let store = WaypointStore.shared
/// try store.open()
/// try store.insert(waypoint)
/// let all = try store.fetchAll()
/// store.close()
/// ```
final class WaypointStore: @unchecked Sendable, ObservableObject {
    // MARK: - Singleton

    /// Shared singleton instance used across the app.
    ///
    /// The database path defaults to `Documents/waypoints.db`.
    static let shared: WaypointStore = {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        let dbPath = documentsDir.appendingPathComponent("waypoints.db").path
        return WaypointStore(path: dbPath)
    }()

    // MARK: - Published Properties

    /// In-memory cache of all waypoints, kept in sync with the database.
    ///
    /// Views can observe this via `@ObservedObject` to automatically refresh
    /// when waypoints are inserted, updated, or deleted.
    @Published var waypoints: [Waypoint] = []

    // MARK: - Properties

    /// The underlying SQLite database connection (nil when closed).
    private var db: OpaquePointer?

    /// File path to the waypoints SQLite database.
    private let path: String

    /// Serial dispatch queue ensuring thread-safe database access.
    private let queue = DispatchQueue(label: "com.openhiker.waypointstore", qos: .userInitiated)

    /// ISO 8601 date formatter used for persisting timestamps.
    ///
    /// Using a shared formatter avoids creating a new one per operation.
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // MARK: - Initialization

    /// Creates a waypoint store for the database at the given path.
    ///
    /// The database is not opened until ``open()`` is called.
    ///
    /// - Parameter path: File system path to the SQLite database.
    init(path: String) {
        self.path = path
    }

    deinit {
        close()
    }

    // MARK: - Lifecycle

    /// Opens (or creates) the waypoint database.
    ///
    /// Creates the parent directory if it doesn't exist, opens the SQLite
    /// database in read-write mode with full-mutex threading, and creates
    /// the schema (tables and indexes) if they don't already exist.
    ///
    /// - Throws: ``WaypointStoreError/databaseError(_:)`` if SQLite fails to open.
    func open() throws {
        try queue.sync {
            // Create directory if needed
            let directory = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )

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
                throw WaypointStoreError.databaseError(errorMessage)
            }

            self.db = db
            try createSchema()
        }
        reloadWaypoints()
    }

    /// Closes the database connection and releases resources.
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

    /// Reloads the in-memory ``waypoints`` cache from the database.
    ///
    /// Called internally after any mutation (insert, update, delete) to keep
    /// the `@Published` array in sync. Dispatches to the main queue so
    /// SwiftUI views update correctly.
    func reloadWaypoints() {
        guard db != nil else { return }
        do {
            let loaded = try fetchWaypoints(sql: "SELECT * FROM waypoints ORDER BY timestamp DESC")
            DispatchQueue.main.async {
                self.waypoints = loaded
            }
        } catch {
            print("Error reloading waypoints cache: \(error.localizedDescription)")
        }
    }

    // MARK: - Insert

    /// Inserts a waypoint into the database without photo data.
    ///
    /// - Parameter waypoint: The ``Waypoint`` to insert.
    /// - Throws: ``WaypointStoreError`` if the insert fails.
    func insert(_ waypoint: Waypoint) throws {
        try insert(waypoint, photo: nil, thumbnail: nil)
    }

    /// Inserts a waypoint into the database with optional photo and thumbnail data.
    ///
    /// If a waypoint with the same ID already exists, it is replaced (INSERT OR REPLACE).
    ///
    /// - Parameters:
    ///   - waypoint: The ``Waypoint`` to insert.
    ///   - photo: Optional full-resolution JPEG data (iOS only, typically).
    ///   - thumbnail: Optional 100x100 JPEG thumbnail data (synced to both platforms).
    /// - Throws: ``WaypointStoreError`` if the insert fails.
    func insert(_ waypoint: Waypoint, photo: Data?, thumbnail: Data?) throws {
        try queue.sync {
            guard let db = db else {
                throw WaypointStoreError.databaseNotOpen
            }

            let sql = """
                INSERT OR REPLACE INTO waypoints
                (id, latitude, longitude, altitude, timestamp, label, category, note,
                 has_photo, hike_id, photo_data, photo_thumbnail)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw WaypointStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            let idString = waypoint.id.uuidString
            let timestampString = dateFormatter.string(from: waypoint.timestamp)
            let hikeIdString = waypoint.hikeId?.uuidString

            sqlite3_bind_text(statement, 1, idString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_double(statement, 2, waypoint.latitude)
            sqlite3_bind_double(statement, 3, waypoint.longitude)

            if let altitude = waypoint.altitude {
                sqlite3_bind_double(statement, 4, altitude)
            } else {
                sqlite3_bind_null(statement, 4)
            }

            sqlite3_bind_text(statement, 5, timestampString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(statement, 6, waypoint.label, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(statement, 7, waypoint.category.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(statement, 8, waypoint.note, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int(statement, 9, waypoint.hasPhoto ? 1 : 0)

            if let hikeIdString = hikeIdString {
                sqlite3_bind_text(statement, 10, hikeIdString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            } else {
                sqlite3_bind_null(statement, 10)
            }

            if let photo = photo {
                _ = photo.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(statement, 11, ptr.baseAddress, Int32(photo.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            } else {
                sqlite3_bind_null(statement, 11)
            }

            if let thumbnail = thumbnail {
                _ = thumbnail.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(statement, 12, ptr.baseAddress, Int32(thumbnail.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            } else {
                sqlite3_bind_null(statement, 12)
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw WaypointStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
        }
        reloadWaypoints()
    }

    // MARK: - Update

    /// Updates an existing waypoint's mutable fields (label, category, note, hasPhoto).
    ///
    /// Does not modify photo BLOB data. Use ``insert(_:photo:thumbnail:)`` with
    /// the same ID to replace photo data.
    ///
    /// - Parameter waypoint: The ``Waypoint`` with updated fields.
    /// - Throws: ``WaypointStoreError`` if the update fails or the waypoint doesn't exist.
    func update(_ waypoint: Waypoint) throws {
        try queue.sync {
            guard let db = db else {
                throw WaypointStoreError.databaseNotOpen
            }

            let sql = """
                UPDATE waypoints SET
                    label = ?, category = ?, note = ?, has_photo = ?, hike_id = ?
                WHERE id = ?
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw WaypointStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            let idString = waypoint.id.uuidString
            let hikeIdString = waypoint.hikeId?.uuidString

            sqlite3_bind_text(statement, 1, waypoint.label, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(statement, 2, waypoint.category.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(statement, 3, waypoint.note, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int(statement, 4, waypoint.hasPhoto ? 1 : 0)

            if let hikeIdString = hikeIdString {
                sqlite3_bind_text(statement, 5, hikeIdString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            } else {
                sqlite3_bind_null(statement, 5)
            }

            sqlite3_bind_text(statement, 6, idString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw WaypointStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }

            if sqlite3_changes(db) == 0 {
                throw WaypointStoreError.waypointNotFound
            }
        }
        reloadWaypoints()
    }

    // MARK: - Delete

    /// Deletes a waypoint by its UUID.
    ///
    /// Also removes any associated photo data from the database.
    ///
    /// - Parameter id: The UUID of the waypoint to delete.
    /// - Throws: ``WaypointStoreError`` if the delete fails or the waypoint doesn't exist.
    func delete(id: UUID) throws {
        try queue.sync {
            guard let db = db else {
                throw WaypointStoreError.databaseNotOpen
            }

            let sql = "DELETE FROM waypoints WHERE id = ?"
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw WaypointStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            let idString = id.uuidString
            sqlite3_bind_text(statement, 1, idString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw WaypointStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }

            if sqlite3_changes(db) == 0 {
                throw WaypointStoreError.waypointNotFound
            }
        }
        reloadWaypoints()
    }

    // MARK: - Fetch

    /// Fetches all waypoints from the database, ordered by timestamp descending (newest first).
    ///
    /// - Returns: An array of all ``Waypoint`` objects in the database.
    /// - Throws: ``WaypointStoreError`` if the query fails.
    func fetchAll() throws -> [Waypoint] {
        try fetchWaypoints(sql: "SELECT * FROM waypoints ORDER BY timestamp DESC")
    }

    /// Fetches all waypoints associated with a specific hike/route.
    ///
    /// - Parameter hikeId: The UUID of the hike to filter by.
    /// - Returns: An array of ``Waypoint`` objects linked to the given hike.
    /// - Throws: ``WaypointStoreError`` if the query fails.
    func fetchForHike(_ hikeId: UUID) throws -> [Waypoint] {
        try queue.sync {
            guard let db = db else {
                throw WaypointStoreError.databaseNotOpen
            }

            let sql = "SELECT * FROM waypoints WHERE hike_id = ? ORDER BY timestamp ASC"
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw WaypointStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            let hikeIdString = hikeId.uuidString
            sqlite3_bind_text(statement, 1, hikeIdString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            var waypoints: [Waypoint] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let waypoint = parseWaypointRow(statement) {
                    waypoints.append(waypoint)
                }
            }
            return waypoints
        }
    }

    /// Fetches waypoints within a radius of a geographic point.
    ///
    /// Uses a bounding-box pre-filter for efficiency, then applies the Haversine
    /// formula to compute exact great-circle distance for final filtering.
    ///
    /// - Parameters:
    ///   - latitude: Center latitude in degrees.
    ///   - longitude: Center longitude in degrees.
    ///   - radiusMeters: Search radius in meters.
    /// - Returns: Waypoints within the specified radius, ordered by distance ascending.
    /// - Throws: ``WaypointStoreError`` if the query fails.
    func fetchNearby(latitude: Double, longitude: Double, radiusMeters: Double) throws -> [Waypoint] {
        try queue.sync {
            guard let db = db else {
                throw WaypointStoreError.databaseNotOpen
            }

            // Pre-filter with a bounding box for efficiency.
            // 111,320 m/degree = Earth circumference (40,075 km) / 360 degrees at equator.
            // Longitude spacing shrinks by cos(latitude) toward the poles.
            let metersPerDegreeLat = 111320.0
            let metersPerDegreeLon = 111320.0 * cos(latitude * .pi / 180.0)
            let latDelta = radiusMeters / metersPerDegreeLat
            let lonDelta = radiusMeters / max(metersPerDegreeLon, 1.0)

            let sql = """
                SELECT * FROM waypoints
                WHERE latitude BETWEEN ? AND ?
                AND longitude BETWEEN ? AND ?
                ORDER BY timestamp DESC
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw WaypointStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_double(statement, 1, latitude - latDelta)
            sqlite3_bind_double(statement, 2, latitude + latDelta)
            sqlite3_bind_double(statement, 3, longitude - lonDelta)
            sqlite3_bind_double(statement, 4, longitude + lonDelta)

            let centerLocation = CLLocation(latitude: latitude, longitude: longitude)
            var waypoints: [Waypoint] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                if let waypoint = parseWaypointRow(statement) {
                    // Exact distance check using Haversine (via CLLocation)
                    let waypointLocation = CLLocation(
                        latitude: waypoint.latitude,
                        longitude: waypoint.longitude
                    )
                    if centerLocation.distance(from: waypointLocation) <= radiusMeters {
                        waypoints.append(waypoint)
                    }
                }
            }

            // Sort by distance ascending
            waypoints.sort { wp1, wp2 in
                let loc1 = CLLocation(latitude: wp1.latitude, longitude: wp1.longitude)
                let loc2 = CLLocation(latitude: wp2.latitude, longitude: wp2.longitude)
                return centerLocation.distance(from: loc1) < centerLocation.distance(from: loc2)
            }

            return waypoints
        }
    }

    // MARK: - Photo Access

    /// Fetches the thumbnail JPEG data for a waypoint.
    ///
    /// Thumbnails are 100x100 pixel JPEG images, small enough to sync
    /// to Apple Watch via WatchConnectivity.
    ///
    /// - Parameter id: The UUID of the waypoint.
    /// - Returns: The thumbnail JPEG data, or `nil` if none exists.
    /// - Throws: ``WaypointStoreError`` if the query fails.
    func fetchThumbnail(id: UUID) throws -> Data? {
        try fetchBlob(column: "photo_thumbnail", id: id)
    }

    /// Fetches the full-resolution photo JPEG data for a waypoint.
    ///
    /// Full photos are only stored on iOS (too large for watch storage).
    ///
    /// - Parameter id: The UUID of the waypoint.
    /// - Returns: The full-resolution JPEG data, or `nil` if none exists.
    /// - Throws: ``WaypointStoreError`` if the query fails.
    func fetchPhoto(id: UUID) throws -> Data? {
        try fetchBlob(column: "photo_data", id: id)
    }

    // MARK: - Private Helpers

    /// Creates the waypoints table and indexes if they don't already exist.
    ///
    /// - Throws: ``WaypointStoreError`` if schema creation fails.
    private func createSchema() throws {
        guard let db = db else {
            throw WaypointStoreError.databaseNotOpen
        }

        let createTableSQL = """
            CREATE TABLE IF NOT EXISTS waypoints (
                id TEXT PRIMARY KEY,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                altitude REAL,
                timestamp TEXT NOT NULL,
                label TEXT NOT NULL DEFAULT '',
                category TEXT NOT NULL DEFAULT 'custom',
                note TEXT NOT NULL DEFAULT '',
                has_photo INTEGER NOT NULL DEFAULT 0,
                hike_id TEXT,
                photo_data BLOB,
                photo_thumbnail BLOB
            )
        """

        let createHikeIndexSQL = """
            CREATE INDEX IF NOT EXISTS idx_waypoints_hike ON waypoints(hike_id)
        """

        let createLocationIndexSQL = """
            CREATE INDEX IF NOT EXISTS idx_waypoints_location ON waypoints(latitude, longitude)
        """

        try executeSQL(createTableSQL, on: db)
        try executeSQL(createHikeIndexSQL, on: db)
        try executeSQL(createLocationIndexSQL, on: db)
        migrateSchema(db: db)
    }

    /// Adds columns introduced in Phase 6 (iCloud sync) if they don't already exist.
    ///
    /// Uses `ALTER TABLE ... ADD COLUMN` which silently fails if the column
    /// already exists (caught and ignored). This avoids needing a version table
    /// or user_version pragma for this simple migration.
    private func migrateSchema(db: OpaquePointer) {
        let migrations = [
            "ALTER TABLE waypoints ADD COLUMN modified_at TEXT",
            "ALTER TABLE waypoints ADD COLUMN cloudkit_record_id TEXT"
        ]

        for sql in migrations {
            var errorMessage: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
            if result != SQLITE_OK {
                // "duplicate column name" is expected when migration already applied
                sqlite3_free(errorMessage)
            }
        }
    }

    /// Executes a raw SQL statement (DDL or DML without result set).
    ///
    /// - Parameters:
    ///   - sql: The SQL statement to execute.
    ///   - db: The open database connection.
    /// - Throws: ``WaypointStoreError/databaseError(_:)`` on failure.
    private func executeSQL(_ sql: String, on db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)

        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw WaypointStoreError.databaseError(message)
        }
    }

    /// Fetches waypoints using a SQL query that returns all columns.
    ///
    /// - Parameter sql: A `SELECT *` SQL query.
    /// - Returns: An array of parsed ``Waypoint`` objects.
    /// - Throws: ``WaypointStoreError`` if the query fails.
    private func fetchWaypoints(sql: String) throws -> [Waypoint] {
        try queue.sync {
            guard let db = db else {
                throw WaypointStoreError.databaseNotOpen
            }

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw WaypointStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            var waypoints: [Waypoint] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let waypoint = parseWaypointRow(statement) {
                    waypoints.append(waypoint)
                }
            }
            return waypoints
        }
    }

    /// Parses a single waypoint row from a prepared SQLite statement.
    ///
    /// Expects the statement to have all columns from the `waypoints` table in
    /// the order defined by the schema. Returns `nil` if required fields are
    /// missing or malformed.
    ///
    /// - Parameter statement: A stepped SQLite statement positioned on a row.
    /// - Returns: A parsed ``Waypoint``, or `nil` if parsing fails.
    private func parseWaypointRow(_ statement: OpaquePointer?) -> Waypoint? {
        guard let idText = sqlite3_column_text(statement, 0),
              let timestampText = sqlite3_column_text(statement, 4),
              let categoryText = sqlite3_column_text(statement, 6) else {
            return nil
        }

        let idString = String(cString: idText)
        guard let id = UUID(uuidString: idString) else { return nil }

        let latitude = sqlite3_column_double(statement, 1)
        let longitude = sqlite3_column_double(statement, 2)

        let altitude: Double?
        if sqlite3_column_type(statement, 3) != SQLITE_NULL {
            altitude = sqlite3_column_double(statement, 3)
        } else {
            altitude = nil
        }

        let timestampString = String(cString: timestampText)
        guard let timestamp = dateFormatter.date(from: timestampString) else { return nil }

        let label: String
        if let labelText = sqlite3_column_text(statement, 5) {
            label = String(cString: labelText)
        } else {
            label = ""
        }

        let categoryString = String(cString: categoryText)
        let category = WaypointCategory(rawValue: categoryString) ?? .custom

        let note: String
        if let noteText = sqlite3_column_text(statement, 7) {
            note = String(cString: noteText)
        } else {
            note = ""
        }

        let hasPhoto = sqlite3_column_int(statement, 8) != 0

        let hikeId: UUID?
        if sqlite3_column_type(statement, 9) != SQLITE_NULL,
           let hikeIdText = sqlite3_column_text(statement, 9) {
            hikeId = UUID(uuidString: String(cString: hikeIdText))
        } else {
            hikeId = nil
        }

        return Waypoint(
            id: id,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            timestamp: timestamp,
            label: label,
            category: category,
            note: note,
            hasPhoto: hasPhoto,
            hikeId: hikeId
        )
    }

    /// Fetches a BLOB column value for a waypoint by ID.
    ///
    /// Used internally by ``fetchPhoto(id:)`` and ``fetchThumbnail(id:)``.
    ///
    /// - Parameters:
    ///   - column: The column name to read (`photo_data` or `photo_thumbnail`).
    ///   - id: The UUID of the waypoint.
    /// - Returns: The BLOB data, or `nil` if the column is NULL.
    /// - Throws: ``WaypointStoreError`` if the query fails.
    private func fetchBlob(column: String, id: UUID) throws -> Data? {
        try queue.sync {
            guard let db = db else {
                throw WaypointStoreError.databaseNotOpen
            }

            let sql = "SELECT \(column) FROM waypoints WHERE id = ?"
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw WaypointStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            let idString = id.uuidString
            sqlite3_bind_text(statement, 1, idString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }

            guard sqlite3_column_type(statement, 0) != SQLITE_NULL,
                  let blob = sqlite3_column_blob(statement, 0) else {
                return nil
            }

            let size = sqlite3_column_bytes(statement, 0)
            return Data(bytes: blob, count: Int(size))
        }
    }
}
