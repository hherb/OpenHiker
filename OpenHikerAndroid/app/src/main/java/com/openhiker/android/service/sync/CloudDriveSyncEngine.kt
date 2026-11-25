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

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import com.openhiker.android.data.db.SyncStamp
import com.openhiker.android.data.repository.PlannedRouteRepository
import com.openhiker.android.data.repository.RouteRepository
import com.openhiker.android.data.repository.WaypointRepository
import com.openhiker.android.data.sync.SyncStateStore
import com.openhiker.core.formats.SyncManifest
import com.openhiker.core.model.PlannedRoute
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Result of a sync operation.
 *
 * @property uploaded Number of entities uploaded to the cloud drive.
 * @property downloaded Number of entities downloaded from the cloud drive.
 * @property deleted Number of local entities deleted because another device deleted them.
 * @property errors List of error descriptions from the sync cycle.
 * @property retryable True when every error may clear by itself soon (an I/O failure, a
 *   provider offline), so the worker retries with backoff. False when at least one error
 *   needs the user or another device to act (a revoked or missing folder, a file that does not
 *   parse), so the worker waits for the next period instead of re-uploading everything.
 */
data class SyncResult(
    val uploaded: Int = 0,
    val downloaded: Int = 0,
    val deleted: Int = 0,
    val errors: List<String> = emptyList(),
    val retryable: Boolean = true
) {
    /** True if the sync completed without errors. */
    val isSuccess: Boolean get() = errors.isEmpty()
}

/**
 * Engine for bidirectional synchronisation with a cloud drive folder.
 *
 * Syncs planned routes, saved routes (hikes), and waypoints between the
 * local device and a user-selected cloud drive directory (Google Drive,
 * Dropbox, etc.) via Android's Storage Access Framework (SAF).
 *
 * The cloud folder's `manifest.json` ([SyncManifest]) holds the tombstones (deletion records)
 * of all devices. Each device keeps its own last-sync time and unpublished deletions in
 * [SyncStateStore]. When an entity exists both locally and in the cloud, the newer copy wins
 * ([reconcile]). An entity with no cloud copy is uploaded if it changed since this device's
 * last error-free sync or has no recorded change time ([shouldUpload]).
 *
 * File layout in cloud folder:
 * ```
 * OpenHiker/
 *   manifest.json
 *   planned_routes/
 *     {uuid}.json      PlannedRoute
 *   saved_routes/
 *     {uuid}.json      SavedRouteRecord (track Base64-encoded)
 *   waypoints/
 *     {uuid}.json      WaypointRecord (photo and thumbnail Base64-encoded)
 * ```
 *
 * @param context Application context for SAF file operations.
 * @param plannedRouteRepository Local planned route storage.
 * @param routeRepository Local saved route (hike) storage.
 * @param waypointRepository Local waypoint storage.
 * @param syncStateStore This device's last-sync time and pending deletions.
 */
@Singleton
class CloudDriveSyncEngine @Inject constructor(
    @ApplicationContext private val context: Context,
    private val plannedRouteRepository: PlannedRouteRepository,
    private val routeRepository: RouteRepository,
    private val waypointRepository: WaypointRepository,
    private val syncStateStore: SyncStateStore
) {
    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
    }

    /** Serialises "Sync now" and the background worker, which share this singleton. */
    private val syncMutex = Mutex()

    private val _isSyncing = MutableStateFlow(false)

    /** True while a sync runs, from "Sync now", the banner's Retry or the background worker. */
    val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

    /**
     * How the engine lists, reads, stores and deletes one entity type.
     *
     * @param T The type written to the cloud folder.
     * @property label Name used in error messages.
     * @property dirName Cloud subdirectory for this type.
     * @property serializer JSON serializer for [T].
     * @property idOf Returns the entity UUID.
     * @property modifiedAtOf Returns the entity's ISO-8601 change time, or null.
     * @property localStamps Lists the id and change time of every local entity. Puts each local
     *   entity it had to skip because it could not be read into the given map, as id to
     *   "file: reason".
     * @property loadLocal Loads one local entity as [T], or null if it is gone.
     * @property saveLocal Stores [T] locally, replacing any entity with the same id.
     * @property deleteLocal Deletes the local entity with the given id.
     */
    private class SyncChannel<T>(
        val label: String,
        val dirName: String,
        val serializer: KSerializer<T>,
        val idOf: (T) -> String,
        val modifiedAtOf: (T) -> String?,
        val localStamps: suspend (MutableMap<String, String>) -> List<SyncStamp>,
        val loadLocal: suspend (String) -> T?,
        val saveLocal: suspend (T) -> Unit,
        val deleteLocal: suspend (String) -> Unit
    )

    private val channels: List<SyncChannel<*>> = listOf(
        SyncChannel(
            label = "Planned routes",
            dirName = PLANNED_ROUTES_DIR,
            serializer = PlannedRoute.serializer(),
            idOf = { it.id },
            modifiedAtOf = { it.modifiedAt },
            localStamps = { unreadable ->
                // The repository's list is empty until loaded, as in a fresh worker process.
                plannedRouteRepository.loadAll().forEach { unreadable[it.id] = it.message }
                plannedRouteRepository.routes.value.map { SyncStamp(it.id, it.modifiedAt) }
            },
            loadLocal = { plannedRouteRepository.getById(it) },
            saveLocal = { plannedRouteRepository.save(it) },
            deleteLocal = { plannedRouteRepository.delete(it) }
        ),
        SyncChannel(
            label = "Saved routes",
            dirName = SAVED_ROUTES_DIR,
            serializer = SavedRouteRecord.serializer(),
            idOf = { it.route.id },
            modifiedAtOf = { it.route.modifiedAt },
            localStamps = { routeRepository.getSyncStamps() },
            loadLocal = { routeRepository.getById(it)?.toSyncRecord() },
            saveLocal = { routeRepository.save(it.toEntity()) },
            deleteLocal = { routeRepository.delete(it) }
        ),
        SyncChannel(
            label = "Waypoints",
            dirName = WAYPOINTS_DIR,
            serializer = WaypointRecord.serializer(),
            idOf = { it.waypoint.id },
            modifiedAtOf = { it.waypoint.modifiedAt },
            localStamps = { waypointRepository.getSyncStamps() },
            loadLocal = { waypointRepository.getById(it)?.toSyncRecord() },
            saveLocal = { waypointRepository.save(it.toEntity()) },
            deleteLocal = { waypointRepository.delete(it) }
        )
    )

    /**
     * Runs a full bidirectional sync cycle with the cloud drive folder.
     *
     * Steps:
     * 1. Read the cloud manifest and merge this device's pending deletions into its tombstones.
     * 2. For each entity type: delete local entities and cloud files that have a tombstone, keep
     *    the newer copy of entities found in both places, download cloud-only entities, and
     *    upload local-only entities changed since this device's last sync.
     * 3. Write the manifest with the merged, pruned tombstones.
     * 4. Mark the published deletions as done; advance the last-sync time only if there
     *    were no errors, so a failed upload is retried next time.
     *
     * A manifest that exists but cannot be read stops the sync before anything is written, so
     * other devices' tombstones are never lost.
     *
     * The errors are recorded in [SyncStateStore] (the UI's banner reads them there), and
     * [isSyncing] is true while the sync runs.
     *
     * @param cloudFolderUri The SAF URI of the cloud sync directory.
     * @return A [SyncResult] describing the outcome.
     */
    suspend fun sync(cloudFolderUri: Uri): SyncResult = syncMutex.withLock {
        _isSyncing.value = true
        try {
            val result = withContext(Dispatchers.IO) { syncLocked(cloudFolderUri) }
            try {
                syncStateStore.recordOutcome(result.errors)
                result
            } catch (e: IOException) {
                Log.e(TAG, "Cannot record the sync outcome", e)
                result.copy(
                    errors = result.errors + "${SyncStateStore.SAVE_FAILED_MESSAGE}: ${e.message}"
                )
            }
        } finally {
            _isSyncing.value = false
        }
    }

    /**
     * True if the app still holds read and write permission for [uri], which it took when the
     * user picked the folder. Revoked permission, or a cleared app, makes every access fail.
     */
    private fun hasFolderPermission(uri: Uri): Boolean =
        context.contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission && it.isWritePermission
        }

    /** Body of [sync]; the caller holds [syncMutex] and runs on [Dispatchers.IO]. */
    private suspend fun syncLocked(cloudFolderUri: Uri): SyncResult {
        val errors = mutableListOf<String>()
        var total = SyncResult()
        var retryable = true

        try {
            val hasPermission = hasFolderPermission(cloudFolderUri)
            // isDirectory is only asked with the permission held; without it the provider throws.
            val cloudFolder = DocumentFile.fromTreeUri(context, cloudFolderUri)
                ?.takeIf { hasPermission && it.isDirectory }
                ?: return folderErrorResult(hasPermission)

            val currentTime = System.currentTimeMillis()
            val manifest = readManifest(cloudFolder) ?: SyncManifest()
            val state = syncStateStore.load()
            val tombstones = SyncManifest(
                tombstones = mergeTombstones(manifest.tombstones, state.pendingTombstones)
            ).pruneExpiredTombstones(currentTime).tombstones
            val deletedIds = tombstones.map { it.uuid }.toSet()

            for (channel in channels) {
                val dir = ensureSubDir(cloudFolder, channel.dirName)
                if (dir == null) {
                    errors.add("${channel.label}: cannot create folder ${channel.dirName}")
                    continue // a provider failure, so retryable stays as it is
                }
                val result = syncChannel(channel, dir, state.lastSyncTimestamp, deletedIds)
                total = SyncResult(
                    uploaded = total.uploaded + result.uploaded,
                    downloaded = total.downloaded + result.downloaded,
                    deleted = total.deleted + result.deleted
                )
                errors.addAll(result.errors)
                retryable = retryable && result.retryable
            }

            writeManifest(
                cloudFolder,
                SyncManifest(
                    version = SyncManifest.CURRENT_VERSION,
                    lastSyncTimestamp = currentTime,
                    tombstones = tombstones
                )
            )
            // deletedIds also covers deletions this sync applied, which the repositories
            // recorded as pending.
            syncStateStore.completeSync(
                publishedUuids = deletedIds,
                lastSyncTimestamp = if (errors.isEmpty()) currentTime else null
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "Sync failed", e)
            errors.add("Sync failed: ${e.message}")
            retryable = retryable && isTransient(e)
        }

        return total.copy(errors = errors, retryable = retryable)
    }

    /**
     * Syncs one entity type with its cloud subdirectory.
     *
     * Each step catches its own errors, so one bad entity does not stop the others.
     *
     * @param channel The entity type.
     * @param dir The type's cloud subdirectory.
     * @param lastSync This device's last error-free sync in epoch milliseconds, or 0.
     * @param deletedIds UUIDs with a tombstone; they are deleted, never uploaded or downloaded.
     * @return Counts and errors for this type.
     */
    private suspend fun <T> syncChannel(
        channel: SyncChannel<T>,
        dir: DocumentFile,
        lastSync: Long,
        deletedIds: Set<String>
    ): SyncResult {
        val errors = mutableListOf<String>()
        var uploaded = 0
        var downloaded = 0
        var deleted = 0
        var retryable = true

        val local: Map<String, String?>
        // Local files that exist but cannot be read: never overwritten or uploaded (#77).
        val unreadable = mutableMapOf<String, String>()
        val cloudFiles: List<DocumentFile>
        try {
            local = channel.localStamps(unreadable).associate { it.id to it.modifiedAt }
            cloudFiles = dir.listFiles().filter { it.name?.endsWith(JSON_SUFFIX) == true }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "${channel.label}: cannot list entities", e)
            return channelResult(
                channel.label,
                unreadable = unreadable,
                errors = listOf("${channel.label}: ${e.message}"),
                retryable = isTransient(e)
            )
        }

        for (id in localIdsToDelete(local.keys, unreadable.keys, deletedIds)) {
            try {
                channel.deleteLocal(id)
                unreadable.remove(id)
                deleted++
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "${channel.label}: cannot apply deletion of $id", e)
                errors.add("${channel.label} delete $id: ${e.message}")
                retryable = retryable && isTransient(e)
            }
        }

        /** Writes the local entity [id] into [existing], or into a new file if null. */
        suspend fun upload(id: String, existing: DocumentFile?) {
            try {
                val item = channel.loadLocal(id) ?: return
                writeJsonToCloud(
                    dir, existing, "$id$JSON_SUFFIX",
                    json.encodeToString(channel.serializer, item)
                )
                uploaded++
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "${channel.label}: cannot upload $id", e)
                errors.add("${channel.label} upload $id: ${e.message}")
                retryable = retryable && isTransient(e)
            }
        }

        /** Deletes a cloud file whose entity has a tombstone. */
        fun deleteCloudFile(file: DocumentFile) {
            if (!file.delete()) {
                Log.e(TAG, "${channel.label}: cannot delete cloud file ${file.name}")
                errors.add("${channel.label}: cannot delete cloud file ${file.name}")
            }
        }

        // Ids with a cloud file, readable or not: never create a second file for them, and
        // never overwrite a file that could not be read.
        val inCloud = mutableSetOf<String>()
        // shortcut: reads every cloud file on each sync; skip unchanged files by
        // DocumentFile.lastModified() if large photo-heavy folders make sync slow.
        for (file in cloudFiles) {
            val fileId = file.name!!.removeSuffix(JSON_SUFFIX)
            inCloud.add(fileId)
            if (fileId in deletedIds) {
                deleteCloudFile(file)
                continue
            }
            val item = try {
                json.decodeFromString(channel.serializer, readFileFromCloud(file))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "${channel.label}: cannot read cloud file ${file.name}", e)
                errors.add("${channel.label}: cannot read cloud file ${file.name}: ${e.message}")
                retryable = retryable && isTransient(e)
                continue
            }
            // A provider may name a duplicate "<uuid> (1).json"; the record's own id decides.
            val itemId = channel.idOf(item)
            inCloud.add(itemId)
            if (itemId in deletedIds) {
                deleteCloudFile(file)
                continue
            }
            val action = cloudEntityAction(
                localModifiedAt = local[itemId],
                hasLocal = itemId in local,
                localUnreadable = itemId in unreadable,
                cloudModifiedAt = channel.modifiedAtOf(item)
            )
            when (action) {
                SyncAction.UPLOAD -> upload(itemId, file)
                SyncAction.NONE -> Unit
                SyncAction.DOWNLOAD -> try {
                    channel.saveLocal(item)
                    downloaded++
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Log.e(TAG, "${channel.label}: cannot store $itemId", e)
                    errors.add("${channel.label} download $itemId: ${e.message}")
                    retryable = retryable && isTransient(e)
                }
            }
        }

        for ((id, modifiedAt) in local) {
            if (id in deletedIds || id in inCloud || !shouldUpload(modifiedAt, lastSync)) continue
            upload(id, null)
        }

        return channelResult(channel.label, uploaded, downloaded, deleted, unreadable, errors, retryable)
    }

    // ── SAF file helpers ────────────────────────────────────────

    /**
     * Ensures a subdirectory exists in the cloud folder, creating it if needed.
     *
     * @param parent The parent DocumentFile.
     * @param name The subdirectory name.
     * @return The subdirectory DocumentFile, or null on failure.
     */
    private fun ensureSubDir(parent: DocumentFile, name: String): DocumentFile? {
        return parent.findFile(name) ?: parent.createDirectory(name)
    }

    /**
     * Reads the sync manifest from the cloud folder.
     *
     * @param cloudFolder The root cloud sync directory.
     * @return The deserialized manifest, or null if there is none yet.
     * @throws IOException if the manifest exists but cannot be read or parsed; writing a fresh
     *   one would drop every other device's tombstones.
     */
    private fun readManifest(cloudFolder: DocumentFile): SyncManifest? {
        val manifestFile = cloudFolder.findFile(MANIFEST_FILENAME) ?: return null
        return try {
            json.decodeFromString<SyncManifest>(readFileFromCloud(manifestFile))
        } catch (e: Exception) {
            throw IOException(
                "Cannot read $MANIFEST_FILENAME, sync stopped so no deletions are lost: " +
                    e.message,
                e
            )
        }
    }

    /**
     * Writes the sync manifest to the cloud folder.
     *
     * @param cloudFolder The root cloud sync directory.
     * @param manifest The manifest to write.
     */
    private fun writeManifest(cloudFolder: DocumentFile, manifest: SyncManifest) {
        writeJsonToCloud(
            cloudFolder,
            cloudFolder.findFile(MANIFEST_FILENAME),
            MANIFEST_FILENAME,
            json.encodeToString(manifest)
        )
    }

    /**
     * Reads the text content of a DocumentFile.
     *
     * @param file The DocumentFile to read.
     * @return The file content as a string.
     * @throws IOException if the provider cannot open or read the file.
     */
    private fun readFileFromCloud(file: DocumentFile): String {
        val stream = context.contentResolver.openInputStream(file.uri)
            ?: throw IOException("Cannot open ${file.name}")
        return stream.use { it.bufferedReader().readText() }
    }

    /**
     * Writes a JSON string to a file in the cloud directory.
     *
     * Overwrites [existing] if given, otherwise creates the file.
     *
     * @param dir The directory to write in.
     * @param existing The file if it already exists in [dir], or null.
     * @param filename The file name.
     * @param content The JSON content to write.
     * @throws IOException if the provider cannot create or open the file.
     */
    private fun writeJsonToCloud(
        dir: DocumentFile,
        existing: DocumentFile?,
        filename: String,
        content: String
    ) {
        val file = existing ?: dir.createFile("application/json", filename)
            ?: throw IOException("Cannot create $filename in ${dir.name}")
        val stream = context.contentResolver.openOutputStream(file.uri, "wt")
            ?: throw IOException("Cannot open $filename for writing")
        stream.use { it.write(content.toByteArray(Charsets.UTF_8)) }
    }

    companion object {
        private const val TAG = "CloudDriveSync"
        private const val MANIFEST_FILENAME = "manifest.json"
        private const val PLANNED_ROUTES_DIR = "planned_routes"
        private const val SAVED_ROUTES_DIR = "saved_routes"
        private const val WAYPOINTS_DIR = "waypoints"
        private const val JSON_SUFFIX = ".json"

        /** Error shown when the app no longer holds the folder's permission. */
        const val FOLDER_UNAVAILABLE =
            "Sync folder unavailable: access to it was revoked. " +
                "Choose the folder again in Settings."

        /** Error shown when the folder cannot be found, though the permission is held. */
        const val FOLDER_UNREACHABLE =
            "Cannot reach the sync folder: it was removed, or its storage provider is offline. " +
                "If it was removed, choose a folder again in Settings."
    }
}
