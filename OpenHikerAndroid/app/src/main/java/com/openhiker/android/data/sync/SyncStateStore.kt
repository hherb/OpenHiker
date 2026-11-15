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

package com.openhiker.android.data.sync

import android.content.Context
import android.util.Log
import com.openhiker.core.formats.SyncManifest
import com.openhiker.core.formats.Tombstone
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Sync state that belongs to this device only, never to the shared cloud folder.
 *
 * @property lastSyncTimestamp Epoch milliseconds of this device's last error-free sync, or 0.
 * @property pendingTombstones Local deletions not yet published to the cloud manifest.
 */
@Serializable
data class SyncState(
    val lastSyncTimestamp: Long = 0L,
    val pendingTombstones: List<Tombstone> = emptyList()
)

/**
 * Stores this device's [SyncState] as a JSON file in app-private storage.
 *
 * The last-sync time must be per device: the manifest's timestamp is rewritten by every device,
 * so comparing local edits against it would skip edits made before another device's sync.
 * Repositories call [recordDeletion] when they delete an entity, so the next sync can publish
 * the deletion instead of downloading the entity again.
 *
 * @param file The JSON file holding the state.
 * @param clock Returns the current epoch milliseconds; replaceable in tests.
 */
@Singleton
class SyncStateStore internal constructor(
    private val file: File,
    private val clock: () -> Long
) {
    /**
     * Creates the store in the app's files directory.
     *
     * @param context Application context.
     */
    @Inject
    constructor(@ApplicationContext context: Context) :
        this(File(context.filesDir, FILE_NAME), System::currentTimeMillis)

    private val mutex = Mutex()
    private val json = Json { ignoreUnknownKeys = true }

    /**
     * Reads the current state.
     *
     * @return The stored state, or a fresh [SyncState] if none is stored or the file is corrupt.
     */
    suspend fun load(): SyncState = mutex.withLock { read() }

    /**
     * Records that the entity [uuid] was deleted on this device.
     *
     * Pending tombstones older than [SyncManifest.TOMBSTONE_EXPIRY_MILLIS] are dropped, so the
     * list stays bounded when sync is never set up.
     *
     * @param uuid The UUID of the deleted entity.
     */
    suspend fun recordDeletion(uuid: String) = mutex.withLock {
        val now = clock()
        val state = read()
        val kept = state.pendingTombstones.filter {
            it.uuid != uuid && it.deletedAt > now - SyncManifest.TOMBSTONE_EXPIRY_MILLIS
        }
        write(state.copy(pendingTombstones = kept + Tombstone(uuid, now)))
    }

    /**
     * Updates the state after a sync wrote the manifest.
     *
     * @param publishedUuids UUIDs whose tombstones are now in the cloud manifest; they stop
     *   being pending.
     * @param lastSyncTimestamp The new last-sync time, or null to keep the old one (when the
     *   sync had errors, so the next sync retries everything since the old time).
     */
    suspend fun completeSync(publishedUuids: Set<String>, lastSyncTimestamp: Long?) =
        mutex.withLock {
            val state = read()
            write(
                SyncState(
                    lastSyncTimestamp = lastSyncTimestamp ?: state.lastSyncTimestamp,
                    pendingTombstones = state.pendingTombstones.filterNot {
                        it.uuid in publishedUuids
                    }
                )
            )
        }

    /** Reads the state file; the caller holds [mutex]. */
    private suspend fun read(): SyncState = withContext(Dispatchers.IO) {
        if (!file.exists()) return@withContext SyncState()
        try {
            json.decodeFromString<SyncState>(file.readText())
        } catch (e: Exception) {
            // Losing the state only costs a full re-upload and may let deleted items return.
            Log.w(TAG, "Corrupt sync state, starting fresh", e)
            SyncState()
        }
    }

    /** Writes the state file atomically; the caller holds [mutex]. */
    private suspend fun write(state: SyncState) = withContext(Dispatchers.IO) {
        val tmp = File(file.parentFile, "${file.name}.tmp")
        tmp.writeText(json.encodeToString(state))
        if (!tmp.renameTo(file)) {
            throw java.io.IOException("Cannot replace sync state file ${file.path}")
        }
    }

    private companion object {
        const val TAG = "SyncStateStore"
        const val FILE_NAME = "sync_state.json"
    }
}
