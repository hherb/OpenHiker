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

/// Low-level CloudKit CRUD operations for OpenHiker data types.
///
/// Wraps `CKDatabase` and `CKContainer` to provide typed save/fetch/delete
/// operations for ``SavedRoute``, ``Waypoint``, and ``PlannedRoute`` records.
///
/// ## Record Types
/// - `SavedRoute` — maps to CKRecord type "SavedRoute"
/// - `Waypoint` — maps to CKRecord type "Waypoint"
/// - `PlannedRoute` — maps to CKRecord type "PlannedRoute"
///
/// ## Container
/// Uses the default iCloud container: `iCloud.com.openhiker.ios`.
///
/// ## Thread Safety
/// This is a Swift Actor, so all methods are automatically serialized.
///
/// ## Error Handling
/// Network errors are wrapped in ``CloudKitStoreError`` with descriptive messages.
/// Callers (typically ``CloudSyncManager``) handle retry logic with exponential backoff.
actor CloudKitStore {

    // MARK: - Constants

    /// The CloudKit container identifier.
    static let containerIdentifier = "iCloud.com.openhiker.ios"

    /// CKRecord type name for saved routes.
    static let savedRouteRecordType = "SavedRoute"

    /// CKRecord type name for waypoints.
    static let waypointRecordType = "Waypoint"

    /// CKRecord type name for planned routes.
    static let plannedRouteRecordType = "PlannedRoute"

    /// Maximum number of records per batch operation.
    static let batchSize = 50

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
            }
        }
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
    /// - Returns: An array of tuples containing the record ID and decoded route.
    /// - Throws: ``CloudKitStoreError`` if the query fails.
    func fetchAllRoutes() async throws -> [(recordID: String, route: SavedRoute)] {
        let query = CKQuery(
            recordType: Self.savedRouteRecordType,
            predicate: NSPredicate(value: true)
        )
        // Note: No sortDescriptors — CloudKit auto-created schemas don't mark
        // fields as queryable/sortable. Sort locally after fetching instead.

        var results: [(String, SavedRoute)] = []

        do {
            let (matchResults, _) = try await database.records(matching: query)
            for (_, result) in matchResults {
                guard let record = try? result.get() else { continue }
                if let route = decodeRoute(from: record) {
                    results.append((record.recordID.recordName, route))
                }
            }
        } catch where Self.isSchemaNotReadyError(error) {
            print("CloudKitStore: Record type \(Self.savedRouteRecordType) not found in schema, returning empty")
            return []
        } catch {
            throw CloudKitStoreError.operationFailed(error.localizedDescription)
        }

        return results
    }

    /// Deletes a ``SavedRoute`` record from CloudKit.
    ///
    /// - Parameter recordID: The CloudKit record ID string.
    /// - Throws: ``CloudKitStoreError`` if the deletion fails.
    func deleteRoute(recordID: String) async throws {
        let ckRecordID = CKRecord.ID(recordName: recordID)
        do {
            try await database.deleteRecord(withID: ckRecordID)
        } catch {
            throw CloudKitStoreError.operationFailed(error.localizedDescription)
        }
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
    /// - Returns: An array of tuples containing the record ID and decoded waypoint.
    /// - Throws: ``CloudKitStoreError`` if the query fails.
    func fetchAllWaypoints() async throws -> [(recordID: String, waypoint: Waypoint)] {
        let query = CKQuery(
            recordType: Self.waypointRecordType,
            predicate: NSPredicate(value: true)
        )
        // Note: No sortDescriptors — CloudKit auto-created schemas don't mark
        // fields as queryable/sortable. Sort locally after fetching instead.

        var results: [(String, Waypoint)] = []

        do {
            let (matchResults, _) = try await database.records(matching: query)
            for (_, result) in matchResults {
                guard let record = try? result.get() else { continue }
                if let waypoint = decodeWaypoint(from: record) {
                    results.append((record.recordID.recordName, waypoint))
                }
            }
        } catch where Self.isSchemaNotReadyError(error) {
            print("CloudKitStore: Record type \(Self.waypointRecordType) not found in schema, returning empty")
            return []
        } catch {
            throw CloudKitStoreError.operationFailed(error.localizedDescription)
        }

        return results
    }

    /// Deletes a ``Waypoint`` record from CloudKit.
    ///
    /// - Parameter recordID: The CloudKit record ID string.
    /// - Throws: ``CloudKitStoreError`` if the deletion fails.
    func deleteWaypoint(recordID: String) async throws {
        let ckRecordID = CKRecord.ID(recordName: recordID)
        do {
            try await database.deleteRecord(withID: ckRecordID)
        } catch {
            throw CloudKitStoreError.operationFailed(error.localizedDescription)
        }
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
    /// - Returns: An array of tuples containing the record ID and decoded route.
    /// - Throws: ``CloudKitStoreError`` if the query fails.
    func fetchAllPlannedRoutes() async throws -> [(recordID: String, route: PlannedRoute)] {
        let query = CKQuery(
            recordType: Self.plannedRouteRecordType,
            predicate: NSPredicate(value: true)
        )
        // Note: No sortDescriptors — CloudKit auto-created schemas don't mark
        // fields as queryable/sortable. Sort locally after fetching instead.

        var results: [(String, PlannedRoute)] = []

        do {
            let (matchResults, _) = try await database.records(matching: query)
            for (_, result) in matchResults {
                guard let record = try? result.get() else { continue }
                if let route = decodePlannedRoute(from: record) {
                    results.append((record.recordID.recordName, route))
                }
            }
        } catch where Self.isSchemaNotReadyError(error) {
            print("CloudKitStore: Record type \(Self.plannedRouteRecordType) not found in schema, returning empty")
            return []
        } catch {
            throw CloudKitStoreError.operationFailed(error.localizedDescription)
        }

        return results
    }

    /// Deletes a ``PlannedRoute`` record from CloudKit.
    ///
    /// - Parameter recordID: The CloudKit record ID string.
    /// - Throws: ``CloudKitStoreError`` if the deletion fails.
    func deletePlannedRoute(recordID: String) async throws {
        let ckRecordID = CKRecord.ID(recordName: recordID)
        do {
            try await database.deleteRecord(withID: ckRecordID)
        } catch {
            throw CloudKitStoreError.operationFailed(error.localizedDescription)
        }
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
                print("CloudKitStore: Skipping subscription for \(recordType) " +
                      "(will retry after first sync): \(error.localizedDescription)")
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

    /// Checks if a CloudKit error indicates the schema isn't ready for queries.
    ///
    /// This covers two cases on a fresh or newly-created CloudKit schema:
    /// - Record type doesn't exist yet (no records have been saved)
    /// - Fields aren't marked queryable (auto-created schema lacks indexes)
    ///
    /// Both are transient: CloudKit auto-creates record types on first save,
    /// and these errors resolve once the schema is properly initialized.
    private static func isSchemaNotReadyError(_ error: Error) -> Bool {
        let description = error.localizedDescription
        return description.contains("Did not find record type")
            || description.contains("is not marked queryable")
    }

    // MARK: - Private Decoders

    /// Decodes a ``SavedRoute`` from a CloudKit record.
    ///
    /// - Parameter record: The CKRecord to decode.
    /// - Returns: A ``SavedRoute`` if all required fields are present, or `nil`.
    private func decodeRoute(from record: CKRecord) -> SavedRoute? {
        guard let localIDString = record["localID"] as? String,
              let id = UUID(uuidString: localIDString),
              let name = record["name"] as? String,
              let startTime = record["startTime"] as? Date,
              let endTime = record["endTime"] as? Date,
              let trackData = record["trackData"] as? Data else {
            return nil
        }

        let regionId: UUID?
        if let regionIdString = record["regionId"] as? String {
            regionId = UUID(uuidString: regionIdString)
        } else {
            regionId = nil
        }

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
    /// - Returns: A ``PlannedRoute`` if the data can be decoded, or `nil`.
    private func decodePlannedRoute(from record: CKRecord) -> PlannedRoute? {
        guard let routeData = record["routeData"] as? Data else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            var route = try decoder.decode(PlannedRoute.self, from: routeData)
            route.cloudKitRecordID = record.recordID.recordName
            route.modifiedAt = record.modificationDate
            return route
        } catch {
            print("CloudKitStore: Failed to decode PlannedRoute: \(error.localizedDescription)")
            return nil
        }
    }

    /// Decodes a ``Waypoint`` from a CloudKit record.
    ///
    /// - Parameter record: The CKRecord to decode.
    /// - Returns: A ``Waypoint`` if all required fields are present, or `nil`.
    private func decodeWaypoint(from record: CKRecord) -> Waypoint? {
        guard let localIDString = record["localID"] as? String,
              let id = UUID(uuidString: localIDString),
              let timestamp = record["timestamp"] as? Date else {
            return nil
        }

        let categoryString = record["category"] as? String ?? "custom"
        let category = WaypointCategory(rawValue: categoryString) ?? .custom

        let hikeId: UUID?
        if let hikeIdString = record["hikeId"] as? String {
            hikeId = UUID(uuidString: hikeIdString)
        } else {
            hikeId = nil
        }

        return Waypoint(
            id: id,
            latitude: record["latitude"] as? Double ?? 0,
            longitude: record["longitude"] as? Double ?? 0,
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
