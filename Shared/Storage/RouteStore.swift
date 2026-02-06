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

/// Errors that can occur when working with the route store.
///
/// Each case provides a human-readable `errorDescription` via `LocalizedError`
/// so that error messages can be displayed directly to the user.
enum RouteStoreError: Error, LocalizedError {
    /// The SQLite database connection has not been opened yet.
    case databaseNotOpen
    /// A SQLite operation failed with the given error message.
    case databaseError(String)
    /// The requested route was not found in the database.
    case routeNotFound
    /// The route data in the database is corrupted or unreadable.
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotOpen:
            return "Route database is not open"
        case .databaseError(let message):
            return "Route database error: \(message)"
        case .routeNotFound:
            return "Route not found"
        case .invalidData(let message):
            return "Invalid route data: \(message)"
        }
    }
}

/// SQLite-backed storage for saved hiking routes, following the ``WaypointStore`` pattern.
///
/// Provides CRUD operations for ``SavedRoute`` objects. The compressed binary
/// track data (see ``TrackCompression``) is stored as a BLOB in the `track_data`
/// column.
///
/// All database operations are dispatched on a serial queue for thread safety.
/// The class is marked `@unchecked Sendable` because it manages its own
/// synchronization via `DispatchQueue`.
///
/// ## Database location
/// The database file is stored at `Documents/routes.db` on both platforms.
///
/// ## Usage
/// ```swift
/// let store = RouteStore.shared
/// try store.open()
/// try store.insert(route)
/// let all = try store.fetchAll()
/// store.close()
/// ```
final class RouteStore: @unchecked Sendable, ObservableObject {
    // MARK: - Singleton

    /// Shared singleton instance used across the app.
    ///
    /// The database path defaults to `Documents/routes.db`.
    static let shared: RouteStore = {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        let dbPath = documentsDir.appendingPathComponent("routes.db").path
        return RouteStore(path: dbPath)
    }()

    // MARK: - Properties

    /// The underlying SQLite database connection (nil when closed).
    private var db: OpaquePointer?

    /// File path to the routes SQLite database.
    private let path: String

    /// Serial dispatch queue ensuring thread-safe database access.
    private let queue = DispatchQueue(label: "com.openhiker.routestore", qos: .userInitiated)

    /// ISO 8601 date formatter used for persisting timestamps.
    ///
    /// Using a shared formatter avoids creating a new one per operation.
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // MARK: - Initialization

    /// Creates a route store for the database at the given path.
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

    /// Opens (or creates) the route database.
    ///
    /// Creates the parent directory if it doesn't exist, opens the SQLite
    /// database in read-write mode with full-mutex threading, and creates
    /// the schema (tables and indexes) if they don't already exist.
    ///
    /// - Throws: ``RouteStoreError/databaseError(_:)`` if SQLite fails to open.
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
                throw RouteStoreError.databaseError(errorMessage)
            }

            self.db = db
            try createSchema()
        }
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

    // MARK: - Insert

    /// Inserts a saved route into the database.
    ///
    /// If a route with the same ID already exists, it is replaced (INSERT OR REPLACE).
    ///
    /// - Parameter route: The ``SavedRoute`` to insert.
    /// - Throws: ``RouteStoreError`` if the insert fails.
    func insert(_ route: SavedRoute) throws {
        try queue.sync {
            guard let db = db else {
                throw RouteStoreError.databaseNotOpen
            }

            let sql = """
                INSERT OR REPLACE INTO saved_routes
                (id, name, start_latitude, start_longitude, end_latitude, end_longitude,
                 start_time, end_time, total_distance, elevation_gain, elevation_loss,
                 walking_time, resting_time, avg_heart_rate, max_heart_rate,
                 estimated_calories, comment, region_id, track_data)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw RouteStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            let idString = route.id.uuidString
            let startTimeString = dateFormatter.string(from: route.startTime)
            let endTimeString = dateFormatter.string(from: route.endTime)
            let regionIdString = route.regionId?.uuidString

            sqlite3_bind_text(statement, 1, idString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(statement, 2, route.name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_double(statement, 3, route.startLatitude)
            sqlite3_bind_double(statement, 4, route.startLongitude)
            sqlite3_bind_double(statement, 5, route.endLatitude)
            sqlite3_bind_double(statement, 6, route.endLongitude)
            sqlite3_bind_text(statement, 7, startTimeString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(statement, 8, endTimeString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_double(statement, 9, route.totalDistance)
            sqlite3_bind_double(statement, 10, route.elevationGain)
            sqlite3_bind_double(statement, 11, route.elevationLoss)
            sqlite3_bind_double(statement, 12, route.walkingTime)
            sqlite3_bind_double(statement, 13, route.restingTime)

            if let avgHR = route.averageHeartRate {
                sqlite3_bind_double(statement, 14, avgHR)
            } else {
                sqlite3_bind_null(statement, 14)
            }

            if let maxHR = route.maxHeartRate {
                sqlite3_bind_double(statement, 15, maxHR)
            } else {
                sqlite3_bind_null(statement, 15)
            }

            if let calories = route.estimatedCalories {
                sqlite3_bind_double(statement, 16, calories)
            } else {
                sqlite3_bind_null(statement, 16)
            }

            sqlite3_bind_text(statement, 17, route.comment, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            if let regionIdString = regionIdString {
                sqlite3_bind_text(statement, 18, regionIdString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            } else {
                sqlite3_bind_null(statement, 18)
            }

            route.trackData.withUnsafeBytes { ptr in
                sqlite3_bind_blob(statement, 19, ptr.baseAddress, Int32(route.trackData.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw RouteStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    // MARK: - Update

    /// Updates a saved route's mutable fields (name, comment).
    ///
    /// Only the `name` and `comment` fields are updated. All other fields are
    /// immutable once the hike is saved.
    ///
    /// - Parameter route: The ``SavedRoute`` with updated `name` and/or `comment`.
    /// - Throws: ``RouteStoreError`` if the update fails or the route doesn't exist.
    func update(_ route: SavedRoute) throws {
        try queue.sync {
            guard let db = db else {
                throw RouteStoreError.databaseNotOpen
            }

            let sql = "UPDATE saved_routes SET name = ?, comment = ? WHERE id = ?"

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw RouteStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            let idString = route.id.uuidString

            sqlite3_bind_text(statement, 1, route.name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(statement, 2, route.comment, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(statement, 3, idString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw RouteStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }

            if sqlite3_changes(db) == 0 {
                throw RouteStoreError.routeNotFound
            }
        }
    }

    // MARK: - Delete

    /// Deletes a saved route by its UUID.
    ///
    /// - Parameter id: The UUID of the route to delete.
    /// - Throws: ``RouteStoreError`` if the delete fails or the route doesn't exist.
    func delete(id: UUID) throws {
        try queue.sync {
            guard let db = db else {
                throw RouteStoreError.databaseNotOpen
            }

            let sql = "DELETE FROM saved_routes WHERE id = ?"
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw RouteStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            let idString = id.uuidString
            sqlite3_bind_text(statement, 1, idString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw RouteStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }

            if sqlite3_changes(db) == 0 {
                throw RouteStoreError.routeNotFound
            }
        }
    }

    // MARK: - Fetch

    /// Fetches all saved routes from the database, ordered by start time descending (newest first).
    ///
    /// - Returns: An array of all ``SavedRoute`` objects in the database.
    /// - Throws: ``RouteStoreError`` if the query fails.
    func fetchAll() throws -> [SavedRoute] {
        try queue.sync {
            guard let db = db else {
                throw RouteStoreError.databaseNotOpen
            }

            let sql = "SELECT * FROM saved_routes ORDER BY start_time DESC"
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw RouteStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            var routes: [SavedRoute] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let route = parseRouteRow(statement) {
                    routes.append(route)
                }
            }
            return routes
        }
    }

    /// Fetches a single saved route by its UUID.
    ///
    /// - Parameter id: The UUID of the route to fetch.
    /// - Returns: The ``SavedRoute`` if found, or `nil`.
    /// - Throws: ``RouteStoreError`` if the query fails.
    func fetch(id: UUID) throws -> SavedRoute? {
        try queue.sync {
            guard let db = db else {
                throw RouteStoreError.databaseNotOpen
            }

            let sql = "SELECT * FROM saved_routes WHERE id = ?"
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw RouteStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            let idString = id.uuidString
            sqlite3_bind_text(statement, 1, idString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }

            return parseRouteRow(statement)
        }
    }

    /// Returns the total number of saved routes in the database.
    ///
    /// - Returns: The count of saved routes.
    /// - Throws: ``RouteStoreError`` if the query fails.
    func count() throws -> Int {
        try queue.sync {
            guard let db = db else {
                throw RouteStoreError.databaseNotOpen
            }

            let sql = "SELECT COUNT(*) FROM saved_routes"
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw RouteStoreError.databaseError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return 0
            }

            return Int(sqlite3_column_int(statement, 0))
        }
    }

    // MARK: - Private Helpers

    /// Creates the saved_routes table and indexes if they don't already exist.
    ///
    /// - Throws: ``RouteStoreError`` if schema creation fails.
    private func createSchema() throws {
        guard let db = db else {
            throw RouteStoreError.databaseNotOpen
        }

        let createTableSQL = """
            CREATE TABLE IF NOT EXISTS saved_routes (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                start_latitude REAL NOT NULL,
                start_longitude REAL NOT NULL,
                end_latitude REAL NOT NULL,
                end_longitude REAL NOT NULL,
                start_time TEXT NOT NULL,
                end_time TEXT NOT NULL,
                total_distance REAL NOT NULL,
                elevation_gain REAL NOT NULL,
                elevation_loss REAL NOT NULL,
                walking_time REAL NOT NULL,
                resting_time REAL NOT NULL,
                avg_heart_rate REAL,
                max_heart_rate REAL,
                estimated_calories REAL,
                comment TEXT NOT NULL DEFAULT '',
                region_id TEXT,
                track_data BLOB NOT NULL
            )
        """

        let createTimeIndexSQL = """
            CREATE INDEX IF NOT EXISTS idx_routes_time ON saved_routes(start_time)
        """

        try executeSQL(createTableSQL, on: db)
        try executeSQL(createTimeIndexSQL, on: db)
    }

    /// Executes a raw SQL statement (DDL or DML without result set).
    ///
    /// - Parameters:
    ///   - sql: The SQL statement to execute.
    ///   - db: The open database connection.
    /// - Throws: ``RouteStoreError/databaseError(_:)`` on failure.
    private func executeSQL(_ sql: String, on db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)

        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw RouteStoreError.databaseError(message)
        }
    }

    /// Parses a single route row from a prepared SQLite statement.
    ///
    /// Expects the statement to have all columns from the `saved_routes` table
    /// in schema order. Returns `nil` if required fields are missing or malformed.
    ///
    /// Column order (0-indexed):
    /// 0: id, 1: name, 2: start_latitude, 3: start_longitude, 4: end_latitude,
    /// 5: end_longitude, 6: start_time, 7: end_time, 8: total_distance,
    /// 9: elevation_gain, 10: elevation_loss, 11: walking_time, 12: resting_time,
    /// 13: avg_heart_rate, 14: max_heart_rate, 15: estimated_calories,
    /// 16: comment, 17: region_id, 18: track_data
    ///
    /// - Parameter statement: A stepped SQLite statement positioned on a row.
    /// - Returns: A parsed ``SavedRoute``, or `nil` if parsing fails.
    private func parseRouteRow(_ statement: OpaquePointer?) -> SavedRoute? {
        guard let idText = sqlite3_column_text(statement, 0),
              let nameText = sqlite3_column_text(statement, 1),
              let startTimeText = sqlite3_column_text(statement, 6),
              let endTimeText = sqlite3_column_text(statement, 7) else {
            return nil
        }

        let idString = String(cString: idText)
        guard let id = UUID(uuidString: idString) else { return nil }

        let name = String(cString: nameText)

        let startTimeString = String(cString: startTimeText)
        let endTimeString = String(cString: endTimeText)
        guard let startTime = dateFormatter.date(from: startTimeString),
              let endTime = dateFormatter.date(from: endTimeString) else {
            return nil
        }

        let startLatitude = sqlite3_column_double(statement, 2)
        let startLongitude = sqlite3_column_double(statement, 3)
        let endLatitude = sqlite3_column_double(statement, 4)
        let endLongitude = sqlite3_column_double(statement, 5)
        let totalDistance = sqlite3_column_double(statement, 8)
        let elevationGain = sqlite3_column_double(statement, 9)
        let elevationLoss = sqlite3_column_double(statement, 10)
        let walkingTime = sqlite3_column_double(statement, 11)
        let restingTime = sqlite3_column_double(statement, 12)

        let averageHeartRate: Double?
        if sqlite3_column_type(statement, 13) != SQLITE_NULL {
            averageHeartRate = sqlite3_column_double(statement, 13)
        } else {
            averageHeartRate = nil
        }

        let maxHeartRate: Double?
        if sqlite3_column_type(statement, 14) != SQLITE_NULL {
            maxHeartRate = sqlite3_column_double(statement, 14)
        } else {
            maxHeartRate = nil
        }

        let estimatedCalories: Double?
        if sqlite3_column_type(statement, 15) != SQLITE_NULL {
            estimatedCalories = sqlite3_column_double(statement, 15)
        } else {
            estimatedCalories = nil
        }

        let comment: String
        if let commentText = sqlite3_column_text(statement, 16) {
            comment = String(cString: commentText)
        } else {
            comment = ""
        }

        let regionId: UUID?
        if sqlite3_column_type(statement, 17) != SQLITE_NULL,
           let regionIdText = sqlite3_column_text(statement, 17) {
            regionId = UUID(uuidString: String(cString: regionIdText))
        } else {
            regionId = nil
        }

        // Read track_data BLOB
        let trackData: Data
        if sqlite3_column_type(statement, 18) != SQLITE_NULL,
           let blob = sqlite3_column_blob(statement, 18) {
            let size = sqlite3_column_bytes(statement, 18)
            trackData = Data(bytes: blob, count: Int(size))
        } else {
            trackData = Data()
        }

        return SavedRoute(
            id: id,
            name: name,
            startLatitude: startLatitude,
            startLongitude: startLongitude,
            endLatitude: endLatitude,
            endLongitude: endLongitude,
            startTime: startTime,
            endTime: endTime,
            totalDistance: totalDistance,
            elevationGain: elevationGain,
            elevationLoss: elevationLoss,
            walkingTime: walkingTime,
            restingTime: restingTime,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            estimatedCalories: estimatedCalories,
            comment: comment,
            regionId: regionId,
            trackData: trackData
        )
    }
}
