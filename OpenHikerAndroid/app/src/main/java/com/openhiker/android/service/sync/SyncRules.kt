/*
 * OpenHiker - Offline Hiking Navigation
 * Copyright (C) 2024 - 2026 Dr Horst Herb
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package com.openhiker.android.service.sync

import com.openhiker.core.formats.Tombstone
import java.io.IOException
import java.time.Instant
import java.time.format.DateTimeParseException

/**
 * Decides whether a local entity with no cloud copy must be uploaded.
 *
 * An entity that has a cloud copy is decided by [reconcile] instead.
 *
 * @param modifiedAt ISO-8601 time of the entity's last change, or null if never recorded.
 * @param lastSyncTimestamp This device's last error-free sync in epoch milliseconds, or 0.
 * @return True on the first sync, when the entity changed after the last sync, or when its
 *   time is missing or unparseable (uploading too much is safer than losing an edit).
 */
internal fun shouldUpload(modifiedAt: String?, lastSyncTimestamp: Long): Boolean {
    if (lastSyncTimestamp == 0L || modifiedAt == null) return true
    val modified = parseInstant(modifiedAt) ?: return true
    return modified.toEpochMilli() > lastSyncTimestamp
}

/** What a sync does with an entity that has both a local and a cloud copy. */
internal enum class SyncAction {
    /** The local copy is newer: write it over the cloud copy. */
    UPLOAD,

    /** The cloud copy is newer: store it locally. */
    DOWNLOAD,

    /** Both copies are equally new: do nothing. */
    NONE
}

/**
 * Decides which copy of an entity wins when it exists both locally and in the cloud folder.
 *
 * The newer copy always wins, so a device whose last-sync time is old (after an error, or on
 * its first sync) never writes an older copy over another device's newer edit.
 *
 * @param localModifiedAt ISO-8601 change time of the local copy, or null.
 * @param cloudModifiedAt ISO-8601 change time of the cloud copy, or null.
 * @return [SyncAction.UPLOAD] or [SyncAction.DOWNLOAD] for the strictly newer copy, where a
 *   copy with a time is newer than one without; otherwise [SyncAction.NONE]. Times are compared
 *   as instants, so `…00Z` and `…00.000Z` are equal; an unparseable time falls back to text
 *   comparison.
 */
internal fun reconcile(localModifiedAt: String?, cloudModifiedAt: String?): SyncAction {
    if (localModifiedAt == null) {
        return if (cloudModifiedAt == null) SyncAction.NONE else SyncAction.DOWNLOAD
    }
    if (cloudModifiedAt == null) return SyncAction.UPLOAD
    val local = parseInstant(localModifiedAt)
    val cloud = parseInstant(cloudModifiedAt)
    val order = if (local != null && cloud != null) {
        local.compareTo(cloud)
    } else {
        localModifiedAt.compareTo(cloudModifiedAt)
    }
    return when {
        order > 0 -> SyncAction.UPLOAD
        order < 0 -> SyncAction.DOWNLOAD
        else -> SyncAction.NONE
    }
}

/**
 * Decides what a sync does with one readable cloud entity that has no tombstone.
 *
 * A local file that exists but cannot be read is never overwritten: it may hold an edit the
 * cloud copy lacks, and its read failure may be temporary. The user deletes it from the sync
 * banner; the next sync then downloads the cloud copy (#77, Apple #80).
 *
 * @param localModifiedAt Change time of the readable local copy, or null.
 * @param hasLocal True if a readable local copy exists.
 * @param localUnreadable True if the local file for this id exists but cannot be read.
 * @param cloudModifiedAt Change time of the cloud copy, or null.
 * @return [reconcile]'s answer for an entity in both places, [SyncAction.NONE] for an
 *   unreadable local file, otherwise [SyncAction.DOWNLOAD].
 */
internal fun cloudEntityAction(
    localModifiedAt: String?,
    hasLocal: Boolean,
    localUnreadable: Boolean,
    cloudModifiedAt: String?
): SyncAction = when {
    localUnreadable -> SyncAction.NONE
    hasLocal -> reconcile(localModifiedAt, cloudModifiedAt)
    else -> SyncAction.DOWNLOAD
}

/**
 * Merges the cloud manifest's tombstones with this device's unpublished ones.
 *
 * @param manifest Tombstones already in the cloud manifest.
 * @param pending Deletions recorded on this device that are not yet in the manifest.
 * @return One tombstone per UUID, keeping the earliest deletion time; any fixed choice keeps
 *   the merge the same on every device, and the earliest also expires soonest.
 */
internal fun mergeTombstones(manifest: List<Tombstone>, pending: List<Tombstone>): List<Tombstone> =
    (manifest + pending).groupBy { it.uuid }.map { (_, group) -> group.minBy { it.deletedAt } }

/**
 * Decides whether a sync error may clear by itself, so the worker retries it with backoff.
 *
 * @param error The exception a sync step caught.
 * @return True for an I/O failure (a provider offline or slow), unless content that does not
 *   parse caused it: a broken file stays broken until a device rewrites it. False for any
 *   other exception, such as a database error, which the next period retries anyway.
 */
internal fun isTransient(error: Throwable): Boolean =
    error is IOException &&
        // kotlinx.serialization's SerializationException is an IllegalArgumentException.
        generateSequence<Throwable>(error) { it.cause }.none { it is IllegalArgumentException }

/**
 * The result of a sync that stopped because the cloud folder cannot be used.
 *
 * Neither case is retried with backoff. A revoked permission needs the user. A folder that
 * cannot be found was removed or its provider is offline; the next period tries again.
 *
 * @param hasPermission True if the app still holds the folder's read and write permission.
 * @return [CloudDriveSyncEngine.FOLDER_UNAVAILABLE] without the permission, otherwise
 *   [CloudDriveSyncEngine.FOLDER_UNREACHABLE].
 */
internal fun folderErrorResult(hasPermission: Boolean): SyncResult = SyncResult(
    errors = listOf(
        if (hasPermission) {
            CloudDriveSyncEngine.FOLDER_UNREACHABLE
        } else {
            CloudDriveSyncEngine.FOLDER_UNAVAILABLE
        }
    ),
    retryable = false
)

/** Parses an ISO-8601 instant, or returns null if [text] is not one. */
private fun parseInstant(text: String): Instant? = try {
    Instant.parse(text)
} catch (e: DateTimeParseException) {
    null
}
