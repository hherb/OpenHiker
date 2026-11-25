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

// MARK: - Elevation Point

/// A single point in an elevation profile, pairing cumulative distance with elevation.
///
/// Used by ``PlannedRoute`` to store a pre-computed elevation profile that can be
/// rendered by ``ElevationProfileView`` without needing the original routing database.
struct ElevationPoint: Codable, Sendable, Equatable {
    /// Cumulative horizontal distance from the route start in metres.
    let distance: Double
    /// Elevation above sea level in metres (from SRTM/Copernicus data).
    let elevation: Double
}

/// Notification posted when a planned route is received via WatchConnectivity sync.
///
/// Views observing this notification should reload their planned routes from the store.
extension Notification.Name {
    static let plannedRouteSyncReceived = Notification.Name("plannedRouteSyncReceived")
}

// MARK: - Planned Route

/// A route computed by the routing engine, ready for navigation on the watch.
///
/// Created on iPhone via ``RoutePlanningView`` after the user sets start, end,
/// and optional via-points. Contains the full polyline coordinates, aggregated
/// statistics, and turn-by-turn instructions.
///
/// ## Persistence
/// Stored as JSON files in `Documents/planned_routes/` via ``PlannedRouteStore``.
///
/// ## Transfer
/// Sent from iPhone to Apple Watch via `WCSession.transferFile()` with
/// `type: "plannedRoute"` metadata. The watch's ``WatchConnectivityReceiver``
/// decodes the JSON and saves it locally.
///
/// ## Usage
/// ```swift
/// let planned = PlannedRoute(
///     name: "Morning Ridge Hike",
///     mode: .hiking,
///     startCoordinate: start,
///     endCoordinate: end,
///     viaPoints: [via1],
///     coordinates: computedRoute.coordinates,
///     turnInstructions: TurnInstructionGenerator.generate(from: computedRoute),
///     totalDistance: computedRoute.totalDistance,
///     estimatedDuration: computedRoute.estimatedDuration,
///     elevationGain: computedRoute.elevationGain,
///     elevationLoss: computedRoute.elevationLoss
/// )
/// ```
struct PlannedRoute: Identifiable, Codable, Sendable, Equatable {
    /// Unique identifier for this planned route.
    let id: UUID

    /// User-editable name for the route (e.g., "Morning Ridge Hike").
    var name: String

    /// The routing mode used to compute this route.
    let mode: RoutingMode

    /// Geographic coordinate of the route start point.
    let startCoordinate: CLLocationCoordinate2D

    /// Geographic coordinate of the route end point.
    let endCoordinate: CLLocationCoordinate2D

    /// Ordered intermediate waypoints the route passes through.
    let viaPoints: [CLLocationCoordinate2D]

    /// Full ordered coordinate sequence for rendering a polyline on the map.
    ///
    /// Includes start, intermediate geometry, and end points.
    let coordinates: [CLLocationCoordinate2D]

    /// Turn-by-turn navigation instructions generated at route junctions.
    let turnInstructions: [TurnInstruction]

    /// Total route distance in metres (horizontal).
    let totalDistance: Double

    /// Estimated travel time in seconds based on the routing cost function.
    let estimatedDuration: TimeInterval

    /// Cumulative elevation gain along the route in metres.
    let elevationGain: Double

    /// Cumulative elevation loss along the route in metres.
    let elevationLoss: Double

    /// Timestamp when this route was created.
    let createdAt: Date

    /// UUID of the map region used for routing, or `nil` if not associated.
    let regionId: UUID?

    /// Pre-computed elevation profile for rendering a chart.
    ///
    /// Each point pairs cumulative distance (metres) with elevation (metres above sea level).
    /// Generated from routing node elevations at route creation time.
    /// `nil` for routes created before this feature was added.
    let elevationProfile: [ElevationPoint]?

    /// Timestamp of the most recent modification (name edit).
    ///
    /// Used by ``CloudSyncManager`` to detect local changes that need to be
    /// pushed to iCloud. `nil` for routes created before iCloud sync was added.
    var modifiedAt: Date?

    /// The CloudKit record ID for this planned route, populated after the first successful sync.
    ///
    /// `nil` for routes that have not yet been synced to iCloud.
    var cloudKitRecordID: String?

    /// Creates a new planned route with the given properties.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to a new UUID).
    ///   - name: Human-readable name for the route.
    ///   - mode: Routing mode (hiking or cycling).
    ///   - startCoordinate: Start point coordinate.
    ///   - endCoordinate: End point coordinate.
    ///   - viaPoints: Ordered intermediate waypoints.
    ///   - coordinates: Full polyline coordinate sequence.
    ///   - turnInstructions: Turn-by-turn instructions.
    ///   - totalDistance: Total distance in metres.
    ///   - estimatedDuration: Estimated travel time in seconds.
    ///   - elevationGain: Total elevation gain in metres.
    ///   - elevationLoss: Total elevation loss in metres.
    ///   - createdAt: Creation timestamp (defaults to now).
    ///   - regionId: Associated map region UUID.
    ///   - elevationProfile: Pre-computed elevation profile data.
    ///   - modifiedAt: Last modification timestamp for iCloud sync (defaults to `nil`).
    ///   - cloudKitRecordID: CloudKit record ID (defaults to `nil`).
    init(
        id: UUID = UUID(),
        name: String,
        mode: RoutingMode,
        startCoordinate: CLLocationCoordinate2D,
        endCoordinate: CLLocationCoordinate2D,
        viaPoints: [CLLocationCoordinate2D] = [],
        coordinates: [CLLocationCoordinate2D],
        turnInstructions: [TurnInstruction],
        totalDistance: Double,
        estimatedDuration: TimeInterval,
        elevationGain: Double,
        elevationLoss: Double,
        createdAt: Date = Date(),
        regionId: UUID? = nil,
        elevationProfile: [ElevationPoint]? = nil,
        modifiedAt: Date? = nil,
        cloudKitRecordID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.startCoordinate = startCoordinate
        self.endCoordinate = endCoordinate
        self.viaPoints = viaPoints
        self.coordinates = coordinates
        self.turnInstructions = turnInstructions
        self.totalDistance = totalDistance
        self.estimatedDuration = estimatedDuration
        self.elevationGain = elevationGain
        self.elevationLoss = elevationLoss
        self.createdAt = createdAt
        self.regionId = regionId
        self.elevationProfile = elevationProfile
        self.modifiedAt = modifiedAt
        self.cloudKitRecordID = cloudKitRecordID
    }

    /// Creates a ``PlannedRoute`` from a ``ComputedRoute`` and auto-generated turn instructions.
    ///
    /// Convenience factory that handles extracting coordinates, generating turn instructions,
    /// and assembling all the statistics.
    ///
    /// - Parameters:
    ///   - computedRoute: The route computed by ``RoutingEngine``.
    ///   - name: Human-readable name.
    ///   - mode: The routing mode used.
    ///   - regionId: Associated map region UUID.
    /// - Returns: A fully populated ``PlannedRoute``.
    static func from(
        computedRoute: ComputedRoute,
        name: String,
        mode: RoutingMode,
        regionId: UUID? = nil
    ) -> PlannedRoute {
        let instructions = TurnInstructionGenerator.generate(from: computedRoute)

        let startCoord = computedRoute.coordinates.first
            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let endCoord = computedRoute.coordinates.last
            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)

        let profile = Self.buildElevationProfile(from: computedRoute)

        return PlannedRoute(
            name: name,
            mode: mode,
            startCoordinate: startCoord,
            endCoordinate: endCoord,
            viaPoints: computedRoute.viaPoints,
            coordinates: computedRoute.coordinates,
            turnInstructions: instructions,
            totalDistance: computedRoute.totalDistance,
            estimatedDuration: computedRoute.estimatedDuration,
            elevationGain: computedRoute.elevationGain,
            elevationLoss: computedRoute.elevationLoss,
            regionId: regionId,
            elevationProfile: profile
        )
    }

    /// Builds an elevation profile from the routing nodes of a computed route.
    ///
    /// Iterates through each junction node on the route, pairing its SRTM elevation
    /// (if available) with the cumulative horizontal distance from the start.
    /// Nodes without elevation data are skipped.
    ///
    /// - Parameter computedRoute: The route with ordered nodes and edges.
    /// - Returns: An array of ``ElevationPoint``s, or `nil` if no elevation data exists.
    private static func buildElevationProfile(from computedRoute: ComputedRoute) -> [ElevationPoint]? {
        var profile: [ElevationPoint] = []
        var cumulativeDistance: Double = 0

        for (index, node) in computedRoute.nodes.enumerated() {
            if let elevation = node.elevation {
                profile.append(ElevationPoint(
                    distance: cumulativeDistance,
                    elevation: elevation
                ))
            }

            if index < computedRoute.edges.count {
                cumulativeDistance += computedRoute.edges[index].distance
            }
        }

        return profile.count >= 2 ? profile : nil
    }

    /// Formatted estimated duration for display (e.g., "4h 23m").
    var formattedDuration: String {
        let totalMinutes = Int(estimatedDuration / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Formatted total distance for display (e.g., "12.4 km").
    var formattedDistance: String {
        HikeStatsFormatter.formatDistance(totalDistance, useMetric: true)
    }

    /// Formatted creation date for display.
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    static func == (lhs: PlannedRoute, rhs: PlannedRoute) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Planned Route Store

/// JSON-based storage for planned routes.
///
/// Persists ``PlannedRoute`` objects as individual JSON files in
/// `Documents/planned_routes/`. Uses the file system rather than SQLite
/// because planned routes are relatively few and small compared to saved hikes.
///
/// Thread-safe via a serial dispatch queue. Both iOS and watchOS use this
/// store: iOS creates routes, watchOS receives them via WatchConnectivity.
///
/// ## File layout
/// ```
/// Documents/
///   planned_routes/
///     <uuid>.json    ← One file per planned route
/// ```
final class PlannedRouteStore: @unchecked Sendable, ObservableObject {

    /// Shared singleton instance used across the app.
    static let shared = PlannedRouteStore()

    /// In-memory cache of all planned routes, sorted by creation date descending.
    @Published var routes: [PlannedRoute] = []

    /// Problems found by the last ``loadAll()``: one "file name: reason" entry per route file
    /// that could not be read, or a single entry if the folder itself could not be read.
    /// Empty when everything loaded. Route list views show these to the user.
    @Published var loadErrors: [String] = []

    /// Route files the last ``loadAll()`` could not read. Route lists offer to delete them
    /// with ``deleteUnreadableFiles()``. Left unchanged if the folder could not be read.
    @Published var unreadableFiles: [URL] = []

    /// A route file that could not be read or decoded.
    struct SkippedFile: Equatable {
        /// The file in the routes folder.
        let url: URL
        /// Why it could not be read.
        let reason: String

        /// "file name: reason", for logs and the route lists.
        var message: String { "\(url.lastPathComponent): \(reason)" }

        /// The route UUID the file is named after (`<uuid>.json`), or `nil` for another name.
        var routeID: UUID? { UUID(uuidString: url.deletingPathExtension().lastPathComponent) }
    }

    /// What ``loadAllFromDisk()`` read from disk.
    struct LoadResult {
        /// Every route that loaded, sorted by creation date, newest first.
        let routes: [PlannedRoute]
        /// Every route file that could not be read or decoded.
        let skippedFiles: [SkippedFile]
    }

    /// Serial queue for thread-safe file I/O.
    private let queue = DispatchQueue(label: "com.openhiker.plannedroutestore", qos: .userInitiated)

    /// JSON encoder configured for readable output and ISO 8601 dates.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    /// JSON decoder configured for ISO 8601 dates.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// The directory where planned route JSON files are stored.
    private let storageDirectory: URL

    /// Where ``delete(id:)`` queues the iCloud records of deleted routes.
    private let deletionQueue: CloudDeletionQueue

    /// Creates a store that keeps its route files in `storageDirectory`.
    ///
    /// - Parameters:
    ///   - storageDirectory: Folder for the `<uuid>.json` files. The app uses the
    ///     default, `Documents/planned_routes/`; tests pass a temporary folder.
    ///   - deletionQueue: Where deletions of synced routes are queued for iCloud.
    ///     The app uses the shared queue; tests pass their own.
    init(
        storageDirectory: URL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("planned_routes", isDirectory: true),
        deletionQueue: CloudDeletionQueue = .shared
    ) {
        self.storageDirectory = storageDirectory
        self.deletionQueue = deletionQueue
    }

    // MARK: - Lifecycle

    /// Reads all planned routes from disk and returns them directly.
    ///
    /// Unlike ``loadAll()`` this does not update the in-memory `routes` cache
    /// via the main queue, so it's safe to call from any thread or actor
    /// without worrying about async dispatch timing.
    ///
    /// A route file that cannot be read or decoded is skipped and listed in the
    /// result, so the caller can log it and tell the user.
    ///
    /// - Returns: The routes that loaded (newest first) and the files that were skipped.
    ///   Both are empty if the folder does not exist yet.
    /// - Throws: A file system error if the folder exists but cannot be listed. Returning
    ///   an empty list instead would make iCloud sync treat every route as missing locally
    ///   and overwrite newer local edits with the cloud copies.
    func loadAllFromDisk() throws -> LoadResult {
        try queue.sync {
            let directory = storageDirectory
            guard FileManager.default.fileExists(atPath: directory.path) else {
                return LoadResult(routes: [], skippedFiles: [])
            }

            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" }

            var loaded: [PlannedRoute] = []
            var skipped: [SkippedFile] = []
            for file in files {
                do {
                    let data = try Data(contentsOf: file)
                    loaded.append(try decoder.decode(PlannedRoute.self, from: data))
                } catch {
                    skipped.append(SkippedFile(url: file, reason: error.localizedDescription))
                }
            }

            loaded.sort { $0.createdAt > $1.createdAt }
            return LoadResult(routes: loaded, skippedFiles: skipped)
        }
    }

    /// Loads all planned routes from disk into the in-memory cache.
    ///
    /// Call this on app launch and whenever a route list appears. Routes are sorted
    /// by creation date, newest first. Problems are logged and published in
    /// ``loadErrors``. If the folder cannot be read, `routes` is left unchanged.
    func loadAll() {
        do {
            let result = try loadAllFromDisk()
            for entry in result.skippedFiles {
                print("Error loading planned route \(entry.message)")
            }
            DispatchQueue.main.async {
                self.routes = result.routes
                self.loadErrors = result.skippedFiles.map(\.message)
                self.unreadableFiles = result.skippedFiles.map(\.url)
            }
        } catch {
            print("Error reading planned routes directory: \(error.localizedDescription)")
            let message = "Cannot read the planned routes folder: \(error.localizedDescription)"
            DispatchQueue.main.async {
                self.loadErrors = [message]
            }
        }
    }

    /// Errors of ``deleteUnreadableFiles()``.
    enum DeleteUnreadableError: Error, LocalizedError, Equatable {
        /// These files could not be deleted; one "file name: reason" entry each.
        case notDeleted([String])

        var errorDescription: String? {
            switch self {
            case .notDeleted(let entries):
                return "Could not delete: \(entries.joined(separator: "; "))"
            }
        }
    }

    /// Deletes every route file that cannot be read, after the user confirmed it (#80).
    ///
    /// The files are read again first, so one that became readable meanwhile is kept. No
    /// iCloud deletion is queued: the user discards a broken local copy, not the route, so
    /// the next sync downloads the iCloud copy of the route if there is one. Calls
    /// ``loadAll()`` afterwards to refresh the route lists.
    ///
    /// - Throws: A file system error if the folder cannot be listed, or
    ///   ``DeleteUnreadableError/notDeleted(_:)`` naming the files that could not be deleted
    ///   (the others are deleted).
    func deleteUnreadableFiles() throws {
        defer { loadAll() }
        let skipped = try loadAllFromDisk().skippedFiles
        let failures: [String] = queue.sync {
            skipped.compactMap { file in
                do {
                    try FileManager.default.removeItem(at: file.url)
                    return nil
                } catch {
                    return "\(file.url.lastPathComponent): \(error.localizedDescription)"
                }
            }
        }
        if !failures.isEmpty { throw DeleteUnreadableError.notDeleted(failures) }
    }

    // MARK: - CRUD

    /// Saves a planned route to disk and updates the in-memory cache.
    ///
    /// If a route with the same ID already exists, it is replaced.
    ///
    /// - Parameter route: The ``PlannedRoute`` to save.
    /// - Throws: File system or encoding errors.
    func save(_ route: PlannedRoute) throws {
        try queue.sync {
            let directory = storageDirectory
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let fileURL = directory.appendingPathComponent("\(route.id.uuidString).json")
            let data = try encoder.encode(route)
            try data.write(to: fileURL, options: .atomic)

            DispatchQueue.main.async {
                self.routes.removeAll { $0.id == route.id }
                self.routes.insert(route, at: 0)
            }
        }
    }

    /// Deletes a planned route from disk and the in-memory cache.
    ///
    /// Its iCloud record is queued in the deletion queue so the next sync deletes it
    /// there too (#89). The record name is the file's `cloudKitRecordID`, or the route's
    /// UUID when it has none or the file cannot be read: an upload still in flight names
    /// the new record after the UUID. A record that never reached iCloud costs one
    /// harmless delete call.
    ///
    /// - Parameter id: The UUID of the route to delete.
    /// - Throws: File system errors.
    func delete(id: UUID) throws {
        try queue.sync {
            let fileURL = storageDirectory.appendingPathComponent("\(id.uuidString).json")

            if FileManager.default.fileExists(atPath: fileURL.path) {
                var recordName = id.uuidString
                do {
                    let data = try Data(contentsOf: fileURL)
                    if let cloudKitRecordID = try decoder.decode(PlannedRoute.self, from: data).cloudKitRecordID {
                        recordName = cloudKitRecordID
                    }
                } catch {
                    print("Planned route \(id.uuidString): cannot read iCloud record ID before delete, using the UUID: \(error.localizedDescription)")
                }
                try FileManager.default.removeItem(at: fileURL)
                deletionQueue.add(recordID: recordName, recordType: CloudKitStore.plannedRouteRecordType)
            }

            DispatchQueue.main.async {
                self.routes.removeAll { $0.id == id }
            }
        }
    }

    /// Fetches all planned routes associated with a given region.
    ///
    /// Reads from disk directly to ensure all routes are included regardless
    /// of whether the in-memory cache is up to date. Unreadable route files are
    /// logged and left out. If any were skipped, this calls ``loadAll()``, which
    /// publishes them in ``loadErrors`` for the route lists to show.
    ///
    /// - Parameter regionId: The UUID of the region to match.
    /// - Returns: An array of ``PlannedRoute`` objects with matching `regionId`.
    /// - Throws: A file system error if the routes folder exists but cannot be listed.
    func fetchForRegion(_ regionId: UUID) throws -> [PlannedRoute] {
        let result = try loadAllFromDisk()
        if !result.skippedFiles.isEmpty {
            loadAll()
        }
        return result.routes.filter { $0.regionId == regionId }
    }

    /// Returns the file URL for a planned route's JSON file.
    ///
    /// Used when preparing the file for WatchConnectivity transfer.
    ///
    /// - Parameter id: The UUID of the route.
    /// - Returns: The file URL, or `nil` if the file doesn't exist.
    func fileURL(for id: UUID) -> URL? {
        let url = storageDirectory.appendingPathComponent("\(id.uuidString).json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
