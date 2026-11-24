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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
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
 * @property lastErrors One "part: reason" entry per failure of the most recent sync, "Sync now"
 *   or background; empty after a clean sync or when the user dismissed them.
 * @property stateWasReset True after a corrupt state file was replaced by a fresh one, which may
 *   have lost pending deletions; stays set until the user dismisses the notice.
 */
@Serializable
data class SyncState(
    val lastSyncTimestamp: Long = 0L,
    val pendingTombstones: List<Tombstone> = emptyList(),
    val lastErrors: List<String> = emptyList(),
    val stateWasReset: Boolean = false
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
 * @param logError Logs an error with its cause; replaceable in tests, where `android.util.Log`
 *   is not available.
 */
@Singleton
class SyncStateStore internal constructor(
    private val file: File,
    private val clock: () -> Long,
    private val logError: (String, Throwable) -> Unit = { msg, e -> Log.e(TAG, msg, e) }
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
    private val _state = MutableStateFlow<SyncState?>(null)

    /**
     * The state as last read or written, for the UI to observe; null until the first [load]
     * or update. The background worker shares this singleton when it runs in the app process.
     */
    val state: StateFlow<SyncState?> = _state.asStateFlow()

    /**
     * Reads the current state.
     *
     * @return The stored state, or a fresh [SyncState] if none is stored or the file is corrupt.
     * @throws java.io.IOException if the file exists but cannot be read.
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
                state.copy(
                    lastSyncTimestamp = lastSyncTimestamp ?: state.lastSyncTimestamp,
                    pendingTombstones = state.pendingTombstones.filterNot {
                        it.uuid in publishedUuids
                    }
                )
            )
        }

    /**
     * Records the errors of a sync that just finished, so the UI can show them even when the
     * sync ran in the background.
     *
     * @param errors The sync's errors; empty for a clean sync.
     */
    suspend fun recordOutcome(errors: List<String>) = mutex.withLock {
        write(read().copy(lastErrors = errors))
    }

    /** Hides the last sync's errors and the reset notice until a later sync fails again. */
    suspend fun dismissErrors() = mutex.withLock {
        write(read().copy(lastErrors = emptyList(), stateWasReset = false))
    }

    /**
     * Reads the state file; the caller holds [mutex].
     *
     * A corrupt file is moved aside to `sync_state.json.corrupt` and replaced by a fresh state
     * with [SyncState.stateWasReset] set, so the user learns of it: that costs a full sync and
     * may let deleted items return, but never blocks deleting.
     * A read error is thrown instead, so a passing I/O fault cannot wipe pending deletions.
     */
    private suspend fun read(): SyncState = withContext(Dispatchers.IO) {
        if (!file.exists()) return@withContext SyncState().also { _state.value = it }
        val text = file.readText()
        try {
            json.decodeFromString<SyncState>(text).also { _state.value = it }
        } catch (e: SerializationException) {
            logError("Corrupt sync state, moved aside; starting fresh", e)
            file.renameTo(File(file.parentFile, "${file.name}$CORRUPT_SUFFIX"))
            SyncState(stateWasReset = true).also { write(it) }
        }
    }

    /** Writes the state file atomically; the caller holds [mutex]. */
    private suspend fun write(state: SyncState) = withContext(Dispatchers.IO) {
        val tmp = File(file.parentFile, "${file.name}.tmp")
        tmp.writeText(json.encodeToString(state))
        if (!tmp.renameTo(file)) {
            throw java.io.IOException("Cannot replace sync state file ${file.path}")
        }
        _state.value = state
    }

    private companion object {
        const val TAG = "SyncStateStore"
        const val FILE_NAME = "sync_state.json"
        const val CORRUPT_SUFFIX = ".corrupt"
    }
}
