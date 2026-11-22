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
import CloudKit
import os

/// Low-level CloudKit CRUD operations for OpenHiker data types.
///
/// Wraps `CKDatabase` and `CKContainer` to provide typed save/fetch/delete
/// operations for ``SavedRoute``, ``Waypoint``, and ``PlannedRoute`` records.
///
/// ## Record Types
/// - `SavedRoute` — maps to CKRecord type "SavedRoute"
/// - `Waypoint` — maps to CKRecord type "Waypoint"
/// - `PlannedRoute` — maps to CKRecord type "PlannedRoute"
/// - `DeletedRecord` — a tombstone for a record deleted on any device (see ``Tombstone``)
///
/// ## Container
/// Uses the default iCloud container: `iCloud.com.openhiker.ios`.
///
/// ## Thread Safety
/// This is a Swift Actor, so all methods are automatically serialized.
///
/// ## Error Handling
/// Network errors are wrapped in ``CloudKitStoreError`` with descriptive messages, except
/// that ``delete(recordID:)`` throws the `CKError` itself so callers can read its code.
/// Callers (typically ``CloudSyncManager``) handle retry logic with exponential backoff.
actor CloudKitStore {

    // MARK: - Constants

    /// Logger for CloudKit operations (debug-level for expected conditions).
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openhiker",
        category: "CloudKitStore"
    )

    /// The CloudKit container identifier.
    static let containerIdentifier = "iCloud.com.openhiker.ios"

    /// CKRecord type name for saved routes.
    static let savedRouteRecordType = "SavedRoute"

    /// CKRecord type name for waypoints.
    static let waypointRecordType = "Waypoint"

    /// CKRecord type name for planned routes.
    static let plannedRouteRecordType = "PlannedRoute"

    /// CKRecord type name for tombstones: one per record deleted on any device (#91).
    static let deletedRecordType = "DeletedRecord"

    /// Maximum number of records per batch operation.
    static let batchSize = 50

    /// How many unreadable records the error text names; the rest are counted (all are logged).
    static let maxListedUnreadableRecords = 3

    // MARK: - Error Types

    /// Errors that can occur during CloudKit operations.
    enum CloudKitStoreError: Error, LocalizedError {
        /// The iCloud account is not available (user not signed in).
        case accountUnavailable
        /// A CloudKit operation failed with the given underlying error.
        case operationFailed(String)
        /// The record could not be found in CloudKit.
        case recordNotFound
        /// The record data could not be serialized or deserialized.
        case serializationError(String)
        /// A fetch skipped records it could not load or decode; one "record: reason" each.
        case unreadableRecords([String])

        var errorDescription: String? {
            switch self {
            case .accountUnavailable:
                return "iCloud account is not available. Please sign in to iCloud in Settings."
            case .operationFailed(let message):
                return "CloudKit operation failed: \(message)"
            case .recordNotFound:
                return "CloudKit record not found"
            case .serializationError(let message):
                return "CloudKit serialization error: \(message)"
            case .unreadableRecords(let entries):
                let noun = entries.count == 1 ? "record" : "records"
                var listed = entries.prefix(CloudKitStore.maxListedUnreadableRecords).joined(separator: "; ")
                let unlisted = entries.count - CloudKitStore.maxListedUnreadableRecords
                if unlisted > 0 {
                    listed += "; and \(unlisted) more"
                }
                return "\(entries.count) \(noun) could not be read: \(listed)"
            }
        }
    }

    /// One page of query results, as `CKDatabase.records(matching:)` returns them.
    typealias MatchResults = [(CKRecord.ID, Result<CKRecord, any Error>)]

    /// The records a fetch could read, and the ones it had to skip.
    ///
    /// A pull merges ``items`` and then calls ``throwIfSkipped()``, so the readable
    /// records still sync while the user learns that some could not be read (#85).
    struct FetchResult<Item> {
        /// Each readable record's CloudKit record name and decoded item.
        var items: [(recordID: String, item: Item)] = []
        /// One "record name: reason" entry per record that could not be loaded or decoded.
        var skipped: [String] = []

        /// Throws ``CloudKitStoreError/unreadableRecords(_:)`` if any record was skipped.
        func throwIfSkipped() throws {
            if !skipped.isEmpty { throw CloudKitStoreError.unreadableRecords(skipped) }
        }
    }

    /// A record deleted on some device, kept in iCloud so other devices delete it too (#91).
    ///
    /// The deleting device saves the tombstone before it deletes the record. Other devices
    /// delete their synced copy and skip the record in uploads and pulls. A device that
    /// uploads a never-synced item under a tombstoned name (the user added it again, e.g.
    /// by re-downloading a community route) deletes the tombstone first. Tombstones live
    /// in the user's own account, so signing in to another account deletes nothing.
    struct Tombstone: Hashable {
        /// The CloudKit record type of the deleted record, e.g. ``CloudKitStore/waypointRecordType``.
        let recordType: String
        /// The deleted record's name: the item's `cloudKitRecordID`, or its UUID.
        let recordName: String
    }

    // MARK: - Properties

    /// The CloudKit container for this app.
    private let container: CKContainer

    /// The private database (user's own data).
    private let database: CKDatabase

    // MARK: - Initialization

    /// Creates a CloudKitStore connected to the OpenHiker iCloud container.
    init() {
        self.container = CKContainer(identifier: Self.containerIdentifier)
        self.database = container.privateCloudDatabase
    }

    // MARK: - Account Status

    /// Checks whether the user's iCloud account is available for CloudKit operations.
    ///
    /// - Returns: `true` if the account status is `.available`.
    /// - Throws: ``CloudKitStoreError`` if the account check fails.
    func isAccountAvailable() async throws -> Bool {
        let status = try await container.accountStatus()
        return status == .available
    }

    // MARK: - SavedRoute Operations

    /// Saves or updates a ``SavedRoute`` record in CloudKit.
    ///
    /// If `cloudKitRecordID` is set, updates the existing record. Otherwise, creates
    /// a new record and returns its record ID for the caller to persist locally.
    ///
    /// - Parameter route: The route to save.
    /// - Returns: The CloudKit record ID string for storage in the local database.
    /// - Throws: ``CloudKitStoreError`` if the operation fails.
    func save(route: SavedRoute) async throws -> String {
        let recordID: CKRecord.ID
        if let existingID = route.cloudKitRecordID {
            recordID = CKRecord.ID(recordName: existingID)
        } else {
            recordID = CKRecord.ID(recordName: route.id.uuidString)
        }

        let record = CKRecord(recordType: Self.savedRouteRecordType, recordID: recordID)
        record["localID"] = route.id.uuidString
        record["name"] = route.name
        record["startLatitude"] = route.startLatitude
        record["startLongitude"] = route.startLongitude
        record["endLatitude"] = route.endLatitude
        record["endLongitude"] = route.endLongitude
        record["startTime"] = route.startTime
        record["endTime"] = route.endTime
        record["totalDistance"] = route.totalDistance
        record["elevationGain"] = route.elevationGain
        record["elevationLoss"] = route.elevationLoss
        record["walkingTime"] = route.walkingTime
        record["restingTime"] = route.restingTime
        record["averageHeartRate"] = route.averageHeartRate
        record["maxHeartRate"] = route.maxHeartRate
        record["estimatedCalories"] = route.estimatedCalories
        record["comment"] = route.comment
        record["regionId"] = route.regionId?.uuidString
        record["trackData"] = route.trackData

        return try await saveWithOverwrite(record)
    }

    /// Fetches all ``SavedRoute`` records from CloudKit.
    ///
    /// Returns lightweight metadata for conflict resolution — the full track data
    /// is included because it's needed for local storage.
    ///
    /// - Returns: Each readable record's ID and decoded route, and the records that could
    ///   not be read (see ``FetchResult``).
    /// - Throws: ``CloudKitStoreError`` if the query fails.
    func fetchAllRoutes() async throws -> FetchResult<SavedRoute> {
        try await fetchAll(recordType: Self.savedRouteRecordType, decode: Self.decodeRoute)
    }

    /// Deletes one record of any type from CloudKit.
    ///
    /// A record that is already gone (for example deleted from another device) counts
    /// as deleted, so a queued deletion does not fail forever. So does a record that never
    /// reached iCloud: stores queue an unsynced item under its UUID (#89).
    ///
    /// - Parameter recordID: The CloudKit record name (the item's `cloudKitRecordID`).
    /// - Throws: The `CKError` itself if the deletion fails, so its code is kept (#93).
    func delete(recordID: String) async throws {
        do {
            try await database.deleteRecord(withID: CKRecord.ID(recordName: recordID))
        } catch where Self.isAlreadyDeleted(error) {
            Self.logger.debug("Record \(recordID) already deleted from iCloud")
        }
    }

    // MARK: - Tombstone Operations

    /// Saves a tombstone for a record that this device is about to delete (#91).
    ///
    /// Saving it again overwrites the same tombstone, so a retried deletion adds nothing.
    ///
    /// - Parameter tombstone: The record being deleted.
    /// - Throws: ``CloudKitStoreError/operationFailed(_:)`` if the save fails.
    func save(tombstone: Tombstone) async throws {
        _ = try await saveWithOverwrite(Self.makeTombstoneRecord(tombstone))
    }

    /// Deletes a tombstone, because the user added its record again on some device.
    ///
    /// - Parameter tombstone: The record that is no longer deleted.
    /// - Throws: The `CKError` if the deletion fails; a missing tombstone is not an error.
    func delete(tombstone: Tombstone) async throws {
        try await delete(recordID: Self.tombstoneRecordName(tombstone))
    }

    /// The record name of a tombstone: "type.name", so each deleted record has one.
    ///
    /// - Parameter tombstone: The deleted record.
    /// - Returns: The `DeletedRecord` record's name.
    static func tombstoneRecordName(_ tombstone: Tombstone) -> String {
        "\(tombstone.recordType).\(tombstone.recordName)"
    }

    /// Fetches every tombstone, of all record types.
    ///
    /// - Returns: The readable tombstones, and the ones that could not be read.
    /// - Throws: ``CloudKitStoreError/operationFailed(_:)`` if the query fails.
    func fetchAllTombstones() async throws -> FetchResult<Tombstone> {
        try await fetchAll(recordType: Self.deletedRecordType, decode: Self.decodeTombstone)
    }

    /// Builds the CloudKit record of a tombstone.
    ///
    /// Its record name is ``tombstoneRecordName(_:)``, so each deleted record has exactly
    /// one tombstone.
    ///
    /// - Parameter tombstone: The deleted record.
    /// - Returns: A `DeletedRecord` record holding the deleted record's type and name.
    static func makeTombstoneRecord(_ tombstone: Tombstone) -> CKRecord {
        let record = CKRecord(
            recordType: deletedRecordType,
            recordID: CKRecord.ID(recordName: tombstoneRecordName(tombstone))
        )
        record["itemType"] = tombstone.recordType
        record["itemName"] = tombstone.recordName
        return record
    }

    /// Decodes a tombstone from a CloudKit record.
    ///
    /// - Parameter record: A `DeletedRecord` record.
    /// - Returns: The deleted record's type and name.
    /// - Throws: ``CloudKitStoreError/serializationError(_:)`` if either field is missing.
    static func decodeTombstone(from record: CKRecord) throws -> Tombstone {
        guard let recordType = record["itemType"] as? String,
              let recordName = record["itemName"] as? String else {
            throw missingFieldsError
        }
        return Tombstone(recordType: recordType, recordName: recordName)
    }

    /// Whether a delete failed only because the record does not exist in iCloud.
    ///
    /// - Parameter error: The error `deleteRecord(withID:)` threw.
    /// - Returns: `true` for `CKError.unknownItem`; the deletion then counts as done.
    static func isAlreadyDeleted(_ error: Error) -> Bool {
        (error as? CKError)?.code == .unknownItem
    }

    // MARK: - Waypoint Operations

    /// Saves or updates a ``Waypoint`` record in CloudKit.
    ///
    /// - Parameter waypoint: The waypoint to save.
    /// - Returns: The CloudKit record ID string.
    /// - Throws: ``CloudKitStoreError`` if the operation fails.
    func save(waypoint: Waypoint) async throws -> String {
        let recordID: CKRecord.ID
        if let existingID = waypoint.cloudKitRecordID {
            recordID = CKRecord.ID(recordName: existingID)
        } else {
            recordID = CKRecord.ID(recordName: waypoint.id.uuidString)
        }

        let record = CKRecord(recordType: Self.waypointRecordType, recordID: recordID)
        record["localID"] = waypoint.id.uuidString
        record["latitude"] = waypoint.latitude
        record["longitude"] = waypoint.longitude
        record["altitude"] = waypoint.altitude
        record["timestamp"] = waypoint.timestamp
        record["label"] = waypoint.label
        record["category"] = waypoint.category.rawValue
        record["note"] = waypoint.note
        record["hasPhoto"] = waypoint.hasPhoto ? 1 : 0
        record["hikeId"] = waypoint.hikeId?.uuidString

        return try await saveWithOverwrite(record)
    }

    /// Fetches all ``Waypoint`` records from CloudKit.
    ///
    /// - Returns: Each readable record's ID and decoded waypoint, and the records that could
    ///   not be read (see ``FetchResult``).
    /// - Throws: ``CloudKitStoreError`` if the query fails.
    func fetchAllWaypoints() async throws -> FetchResult<Waypoint> {
        try await fetchAll(recordType: Self.waypointRecordType, decode: Self.decodeWaypoint)
    }

    // MARK: - PlannedRoute Operations

    /// Saves or updates a ``PlannedRoute`` record in CloudKit.
    ///
    /// Encodes the entire route as a JSON blob in a `routeData` field, with
    /// `localID`, `name`, and `createdAt` stored as individual fields for
    /// queryability and conflict resolution.
    ///
    /// - Parameter route: The planned route to save.
    /// - Returns: The CloudKit record ID string for storage in the local store.
    /// - Throws: ``CloudKitStoreError`` if the operation fails.
    func save(plannedRoute route: PlannedRoute) async throws -> String {
        let recordID: CKRecord.ID
        if let existingID = route.cloudKitRecordID {
            recordID = CKRecord.ID(recordName: existingID)
        } else {
            recordID = CKRecord.ID(recordName: route.id.uuidString)
        }

        let record = CKRecord(recordType: Self.plannedRouteRecordType, recordID: recordID)
        record["localID"] = route.id.uuidString
        record["name"] = route.name
        record["createdAt"] = route.createdAt

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let routeData = try encoder.encode(route)
            record["routeData"] = routeData
        } catch {
            throw CloudKitStoreError.serializationError("Failed to encode PlannedRoute: \(error.localizedDescription)")
        }

        return try await saveWithOverwrite(record)
    }

    /// Fetches all ``PlannedRoute`` records from CloudKit.
    ///
    /// - Returns: Each readable record's ID and decoded route, and the records that could
    ///   not be read (see ``FetchResult``).
    /// - Throws: ``CloudKitStoreError`` if the query fails.
    func fetchAllPlannedRoutes() async throws -> FetchResult<PlannedRoute> {
        try await fetchAll(recordType: Self.plannedRouteRecordType, decode: Self.decodePlannedRoute)
    }

    // MARK: - Subscription

    /// Whether subscriptions have been successfully created for all record types.
    /// When `false`, ``setupSubscriptions()`` will retry on the next sync cycle.
    private(set) var subscriptionsReady = false

    /// Creates CloudKit subscriptions for change notifications.
    ///
    /// Subscribes to changes in all three record types so the app can be notified
    /// of remote changes via push notifications. Tolerates failures for individual
    /// record types (e.g., when the schema hasn't been initialized yet) — the record
    /// types are auto-created on first push, and subscriptions succeed on retry.
    func setupSubscriptions() async throws {
        let recordTypes = [
            Self.savedRouteRecordType,
            Self.waypointRecordType,
            Self.plannedRouteRecordType
        ]

        var allSucceeded = true

        for recordType in recordTypes {
            let subscriptionID = "subscription-\(recordType)"
            let subscription = CKQuerySubscription(
                recordType: recordType,
                predicate: NSPredicate(value: true),
                subscriptionID: subscriptionID,
                options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
            )

            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            subscription.notificationInfo = notificationInfo

            do {
                _ = try await database.save(subscription)
            } catch let error as CKError where error.code == .serverRejectedRequest {
                // Subscription already exists — this is fine
            } catch {
                // Record type may not exist yet (schema not initialized). This is
                // expected on first launch before any records have been pushed.
                // The types are auto-created on first save, and subscriptions will
                // succeed on the next sync cycle.
                Self.logger.debug("Skipping subscription for \(recordType) (will retry after first sync): \(error.localizedDescription)")
                allSucceeded = false
            }
        }

        subscriptionsReady = allSucceeded
    }

    // MARK: - Save Helper

    /// Saves a record to CloudKit, overwriting any existing server version.
    ///
    /// Uses `CKModifyRecordsOperation` with `savePolicy = .allKeys` so that
    /// a locally-constructed `CKRecord` can update a server record without
    /// first fetching it. This avoids "record to insert already exists"
    /// errors when re-syncing records after a schema reset.
    ///
    /// - Parameter record: The record to save (may be new or existing).
    /// - Returns: The saved record's `recordName`.
    /// - Throws: ``CloudKitStoreError`` if the operation fails.
    private func saveWithOverwrite(_ record: CKRecord) async throws -> String {
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.savePolicy = .allKeys
        operation.qualityOfService = .userInitiated

        return try await withCheckedThrowingContinuation { continuation in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: record.recordID.recordName)
                case .failure(let error):
                    continuation.resume(throwing: CloudKitStoreError.operationFailed(error.localizedDescription))
                }
            }
            database.add(operation)
        }
    }

    // MARK: - Error Helpers

    /// Checks if a CloudKit error says the record type does not exist yet.
    ///
    /// That is expected before any record of the type was saved: CloudKit creates
    /// the type on first save, so the query has nothing to return.
    ///
    /// "is not marked queryable" is not matched: it means the schema lacks the
    /// `recordName` query index, which never fixes itself, so every pull would
    /// silently return nothing. It is reported as a failed fetch instead.
    private static func isRecordTypeMissingError(_ error: Error) -> Bool {
        error.localizedDescription.contains("Did not find record type")
    }

    // MARK: - Paged Fetch

    /// Fetches every record of one type, following the query cursor to the last page.
    ///
    /// - Parameters:
    ///   - recordType: The CKRecord type to query.
    ///   - decode: Turns one record into an item; throws if the record is incomplete.
    /// - Returns: The decoded items and the records that were skipped (also logged).
    /// - Throws: ``CloudKitStoreError/operationFailed(_:)`` if any page fails to load.
    private func fetchAll<Item>(
        recordType: CKRecord.RecordType,
        decode: (CKRecord) throws -> Item
    ) async throws -> FetchResult<Item> {
        let database = self.database
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        // No sortDescriptors: CloudKit auto-created schemas don't mark fields
        // sortable. Callers don't need an order.
        do {
            let matches = try await Self.collectPages(
                first: { try await database.records(matching: query) },
                next: { try await database.records(continuingMatchFrom: $0) }
            )
            let result = Self.decodeAll(matches, decode: decode)
            for entry in result.skipped {
                Self.logger.error("Skipped unreadable \(recordType) record \(entry)")
            }
            return result
        } catch where Self.isRecordTypeMissingError(error) {
            Self.logger.debug("Record type \(recordType) not in schema yet (expected on first launch)")
            return FetchResult()
        } catch {
            throw CloudKitStoreError.operationFailed(error.localizedDescription)
        }
    }

    /// Loads the first page of a query and every page after it.
    ///
    /// `records(matching:)` returns at most one batch plus a cursor for the rest;
    /// dropping the cursor would leave the later records unsynced (#85).
    ///
    /// - Parameters:
    ///   - first: Loads the first page and the cursor to the next one, if any.
    ///   - next: Loads the page a cursor points to.
    /// - Returns: The results of all pages, in order.
    /// - Throws: The first error from `first` or `next`.
    static func collectPages<Cursor>(
        first: () async throws -> (matchResults: MatchResults, queryCursor: Cursor?),
        next: (Cursor) async throws -> (matchResults: MatchResults, queryCursor: Cursor?)
    ) async throws -> MatchResults {
        var (matches, cursor) = try await first()
        while let current = cursor {
            let page = try await next(current)
            matches += page.matchResults
            cursor = page.queryCursor
        }
        return matches
    }

    /// Decodes query results, keeping a "record name: reason" entry for each one that fails.
    ///
    /// - Parameters:
    ///   - matches: Query results; a record can fail to load on its own.
    ///   - decode: Turns one record into an item; throws if the record is incomplete.
    /// - Returns: The decoded items and the skipped records.
    static func decodeAll<Item>(
        _ matches: MatchResults,
        decode: (CKRecord) throws -> Item
    ) -> FetchResult<Item> {
        var result = FetchResult<Item>()
        for (recordID, match) in matches {
            do {
                let record = try match.get()
                result.items.append((record.recordID.recordName, try decode(record)))
            } catch {
                result.skipped.append("\(recordID.recordName): \(error.localizedDescription)")
            }
        }
        return result
    }

    /// The error a decoder throws when a record lacks a field it needs.
    private static let missingFieldsError = CloudKitStoreError.serializationError("missing required fields")

    /// Reads an optional UUID field.
    ///
    /// A record that has the field but not a valid UUID in it is broken, not unlinked:
    /// accepting it as `nil` would overwrite the local link on merge.
    ///
    /// - Parameters:
    ///   - key: The field name.
    ///   - record: The record to read.
    /// - Returns: The UUID, or `nil` if the field is absent.
    /// - Throws: ``CloudKitStoreError/serializationError(_:)`` if the field holds no valid UUID.
    static func optionalUUID(_ key: String, in record: CKRecord) throws -> UUID? {
        guard let string = record[key] as? String else { return nil }
        guard let uuid = UUID(uuidString: string) else {
            throw CloudKitStoreError.serializationError("invalid \(key)")
        }
        return uuid
    }

    // MARK: - Decoders

    /// Decodes a ``SavedRoute`` from a CloudKit record.
    ///
    /// - Parameter record: The CKRecord to decode.
    /// - Returns: The decoded ``SavedRoute``.
    /// - Throws: ``CloudKitStoreError/serializationError(_:)`` if a required field is missing
    ///   or a UUID field is invalid.
    static func decodeRoute(from record: CKRecord) throws -> SavedRoute {
        guard let localIDString = record["localID"] as? String,
              let id = UUID(uuidString: localIDString),
              let name = record["name"] as? String,
              let startTime = record["startTime"] as? Date,
              let endTime = record["endTime"] as? Date,
              let trackData = record["trackData"] as? Data else {
            throw missingFieldsError
        }

        let regionId = try optionalUUID("regionId", in: record)

        return SavedRoute(
            id: id,
            name: name,
            startLatitude: record["startLatitude"] as? Double ?? 0,
            startLongitude: record["startLongitude"] as? Double ?? 0,
            endLatitude: record["endLatitude"] as? Double ?? 0,
            endLongitude: record["endLongitude"] as? Double ?? 0,
            startTime: startTime,
            endTime: endTime,
            totalDistance: record["totalDistance"] as? Double ?? 0,
            elevationGain: record["elevationGain"] as? Double ?? 0,
            elevationLoss: record["elevationLoss"] as? Double ?? 0,
            walkingTime: record["walkingTime"] as? Double ?? 0,
            restingTime: record["restingTime"] as? Double ?? 0,
            averageHeartRate: record["averageHeartRate"] as? Double,
            maxHeartRate: record["maxHeartRate"] as? Double,
            estimatedCalories: record["estimatedCalories"] as? Double,
            comment: record["comment"] as? String ?? "",
            regionId: regionId,
            trackData: trackData,
            modifiedAt: record.modificationDate,
            cloudKitRecordID: record.recordID.recordName
        )
    }

    /// Decodes a ``PlannedRoute`` from a CloudKit record.
    ///
    /// The route is stored as a JSON blob in the `routeData` field. After
    /// decoding, the `cloudKitRecordID` is set from the record's ID and
    /// `modifiedAt` from the record's server modification date.
    ///
    /// - Parameter record: The CKRecord to decode.
    /// - Returns: The decoded ``PlannedRoute``.
    /// - Throws: ``CloudKitStoreError/serializationError(_:)`` if `routeData` is missing or
    ///   is not a valid route.
    static func decodePlannedRoute(from record: CKRecord) throws -> PlannedRoute {
        guard let routeData = record["routeData"] as? Data else {
            throw missingFieldsError
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var route: PlannedRoute
        do {
            route = try decoder.decode(PlannedRoute.self, from: routeData)
        } catch {
            throw CloudKitStoreError.serializationError("invalid routeData: \(error.localizedDescription)")
        }
        route.cloudKitRecordID = record.recordID.recordName
        route.modifiedAt = record.modificationDate
        return route
    }

    /// Decodes a ``Waypoint`` from a CloudKit record.
    ///
    /// - Parameter record: The CKRecord to decode.
    /// - Returns: The decoded ``Waypoint``.
    /// - Throws: ``CloudKitStoreError/serializationError(_:)`` if a required field is missing
    ///   or a UUID field is invalid.
    static func decodeWaypoint(from record: CKRecord) throws -> Waypoint {
        guard let localIDString = record["localID"] as? String,
              let id = UUID(uuidString: localIDString),
              let timestamp = record["timestamp"] as? Date,
              let latitude = record["latitude"] as? Double,
              let longitude = record["longitude"] as? Double else {
            throw missingFieldsError
        }

        let categoryString = record["category"] as? String ?? "custom"
        let category = WaypointCategory(rawValue: categoryString) ?? .custom

        let hikeId = try optionalUUID("hikeId", in: record)

        return Waypoint(
            id: id,
            latitude: latitude,
            longitude: longitude,
            altitude: record["altitude"] as? Double,
            timestamp: timestamp,
            label: record["label"] as? String ?? "",
            category: category,
            note: record["note"] as? String ?? "",
            hasPhoto: (record["hasPhoto"] as? Int ?? 0) != 0,
            hikeId: hikeId,
            modifiedAt: record.modificationDate,
            cloudKitRecordID: record.recordID.recordName
        )
    }
}
