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

package com.openhiker.core.formats

import kotlinx.serialization.Serializable

/**
 * Manifest file for cloud drive sync.
 *
 * Stored as `manifest.json` in the sync directory root. Tracks the
 * last sync timestamp and tombstones (deletion records) to enable
 * delta-based synchronisation across devices.
 *
 * The format is platform-agnostic: both iOS and Android can read/write
 * the same manifest to share data via a common cloud drive folder.
 *
 * @property version Schema version for forward compatibility (currently 1).
 * @property lastSyncTimestamp Epoch milliseconds of the last successful sync.
 * @property tombstones List of deletion records for entities removed since last sync.
 */
@Serializable
data class SyncManifest(
    val version: Int = CURRENT_VERSION,
    val lastSyncTimestamp: Long = 0L,
    val tombstones: List<Tombstone> = emptyList()
) {
    companion object {
        /** Current schema version. */
        const val CURRENT_VERSION = 1

        /** Tombstones older than this are pruned to prevent unbounded growth. */
        const val TOMBSTONE_EXPIRY_MILLIS = 30L * 24 * 60 * 60 * 1000 // 30 days
    }

    /**
     * Returns a new manifest with expired tombstones removed.
     *
     * Tombstones older than [TOMBSTONE_EXPIRY_MILLIS] from the current time
     * are pruned. This prevents the tombstone list from growing indefinitely.
     *
     * @param currentTimeMillis The current time in epoch milliseconds.
     * @return A new manifest with only non-expired tombstones.
     */
    fun pruneExpiredTombstones(currentTimeMillis: Long): SyncManifest {
        val cutoff = currentTimeMillis - TOMBSTONE_EXPIRY_MILLIS
        return copy(
            tombstones = tombstones.filter { it.deletedAt > cutoff }
        )
    }
}

/**
 * A deletion record (tombstone) for a synced entity.
 *
 * When an entity is deleted locally, a tombstone is added to the manifest
 * so that other devices can replicate the deletion. Tombstones expire
 * after 30 days to prevent unbounded growth.
 *
 * @property uuid The UUID of the deleted entity.
 * @property deletedAt Epoch milliseconds when the deletion occurred.
 */
@Serializable
data class Tombstone(
    val uuid: String,
    val deletedAt: Long
)
