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
import os

/// iCloud records deleted on this device that are not yet deleted in iCloud (#89).
///
/// When a local store deletes an item, it adds the item's record here (its
/// `cloudKitRecordID`, or its UUID if it has none yet). The next sync deletes each queued record from iCloud and
/// then removes it from the queue. Until then, pulls skip queued records, so the
/// deleted item does not come back. The queue lives in `UserDefaults`, so a deletion
/// made offline survives an app restart.
///
/// Records are grouped by CloudKit record type (for example
/// ``CloudKitStore/waypointRecordType``). Safe to use from any thread.
final class CloudDeletionQueue: @unchecked Sendable {

    /// Shared instance used by the local stores and ``CloudSyncManager``.
    static let shared = CloudDeletionQueue()

    /// `UserDefaults` key of the queue: a dictionary from record type to record names.
    static let defaultsKey = "cloudPendingDeletions"

    /// Where the queue is stored.
    private let defaults: UserDefaults

    /// Serialises the read-modify-write of the stored dictionary.
    private let lock = NSLock()

    /// Logs a stored queue that cannot be read.
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openhiker",
        category: "CloudDeletionQueue"
    )

    /// Creates a queue stored in the given defaults.
    ///
    /// - Parameter defaults: The app uses `.standard`; tests pass their own suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Queues a record for deletion from iCloud.
    ///
    /// Does nothing on watchOS: the watch does not sync with iCloud, and deleting a
    /// route copy on the watch must not delete the user's route everywhere.
    ///
    /// - Parameters:
    ///   - recordID: The item's `cloudKitRecordID` (the CloudKit record name).
    ///   - recordType: The CloudKit record type of the item.
    func add(recordID: String, recordType: String) {
        #if !os(watchOS)
        modify { queue in
            if !queue[recordType, default: []].contains(recordID) {
                queue[recordType, default: []].append(recordID)
            }
        }
        #endif
    }

    /// The queued record names of one record type, oldest first.
    ///
    /// - Parameter recordType: The CloudKit record type.
    /// - Returns: The record names still to delete from iCloud.
    func pending(recordType: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return stored()[recordType] ?? []
    }

    /// Removes a record from the queue once iCloud has deleted it.
    ///
    /// - Parameters:
    ///   - recordID: The CloudKit record name.
    ///   - recordType: The CloudKit record type.
    func remove(recordID: String, recordType: String) {
        modify { queue in
            queue[recordType]?.removeAll { $0 == recordID }
            if queue[recordType]?.isEmpty == true { queue[recordType] = nil }
        }
    }

    /// Moves a record to the back of its queue after its deletion failed, so it does not
    /// block the records behind it on the next sync. Does nothing if it is not queued.
    ///
    /// - Parameters:
    ///   - recordID: The CloudKit record name.
    ///   - recordType: The CloudKit record type.
    func moveToBack(recordID: String, recordType: String) {
        modify { queue in
            guard queue[recordType]?.contains(recordID) == true else { return }
            queue[recordType]?.removeAll { $0 == recordID }
            queue[recordType]?.append(recordID)
        }
    }

    /// Reads the stored dictionary. Call with ``lock`` held.
    ///
    /// A stored value of the wrong shape reads as empty and is logged; the next change
    /// overwrites it.
    private func stored() -> [String: [String]] {
        guard let raw = defaults.object(forKey: Self.defaultsKey) else { return [:] }
        guard let queue = raw as? [String: [String]] else {
            Self.logger.error("Unreadable iCloud deletion queue, discarding it: \(String(describing: raw))")
            return [:]
        }
        return queue
    }

    /// Applies a change to the stored dictionary under the lock.
    private func modify(_ change: (inout [String: [String]]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var queue = stored()
        change(&queue)
        defaults.set(queue, forKey: Self.defaultsKey)
    }
}
