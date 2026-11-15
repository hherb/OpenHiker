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
import java.time.Instant
import java.time.format.DateTimeParseException

/**
 * Decides whether a local entity must be uploaded.
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

/**
 * Decides whether a cloud entity must replace or add to local data.
 *
 * @param cloudModifiedAt ISO-8601 change time of the cloud copy, or null.
 * @param localModifiedAt ISO-8601 change time of the local copy, or null.
 * @param existsLocally Whether a local copy exists at all.
 * @return True if there is no local copy, the local copy has no time, or the cloud copy is
 *   strictly newer. Times are compared as instants, so `…00Z` and `…00.000Z` are equal; an
 *   unparseable time falls back to text comparison.
 */
internal fun shouldDownload(
    cloudModifiedAt: String?,
    localModifiedAt: String?,
    existsLocally: Boolean
): Boolean {
    if (!existsLocally || localModifiedAt == null) return true
    if (cloudModifiedAt == null) return false
    val cloud = parseInstant(cloudModifiedAt)
    val local = parseInstant(localModifiedAt)
    return if (cloud != null && local != null) cloud > local else cloudModifiedAt > localModifiedAt
}

/**
 * Merges the cloud manifest's tombstones with this device's unpublished ones.
 *
 * @param manifest Tombstones already in the cloud manifest.
 * @param pending Deletions recorded on this device since its last sync.
 * @return One tombstone per UUID, keeping the earliest deletion time.
 */
internal fun mergeTombstones(manifest: List<Tombstone>, pending: List<Tombstone>): List<Tombstone> =
    (manifest + pending).groupBy { it.uuid }.map { (_, group) -> group.minBy { it.deletedAt } }

/** Parses an ISO-8601 instant, or returns null if [text] is not one. */
private fun parseInstant(text: String): Instant? = try {
    Instant.parse(text)
} catch (e: DateTimeParseException) {
    null
}
