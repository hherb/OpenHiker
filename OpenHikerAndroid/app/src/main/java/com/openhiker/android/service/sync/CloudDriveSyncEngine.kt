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
import kotlinx.coroutines.Dispatchers
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
 */
data class SyncResult(
    val uploaded: Int = 0,
    val downloaded: Int = 0,
    val deleted: Int = 0,
    val errors: List<String> = emptyList()
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
 * [SyncStateStore]: only entities changed since this device's last error-free sync are
 * uploaded.
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

    /**
     * How the engine lists, reads, stores and deletes one entity type.
     *
     * @param T The type written to the cloud folder.
     * @property label Name used in error messages.
     * @property dirName Cloud subdirectory for this type.
     * @property serializer JSON serializer for [T].
     * @property idOf Returns the entity UUID.
     * @property modifiedAtOf Returns the entity's ISO-8601 change time, or null.
     * @property localStamps Lists the id and change time of every local entity.
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
        val localStamps: suspend () -> List<SyncStamp>,
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
            localStamps = {
                // The repository's list is empty until loaded, as in a fresh worker process.
                plannedRouteRepository.loadAll()
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
     * 2. For each entity type: delete local entities that have a tombstone, upload local
     *    entities changed since this device's last sync, delete tombstoned cloud files, and
     *    download cloud entities that are new or newer than the local copy.
     * 3. Write the manifest with the merged, pruned tombstones.
     * 4. Mark the published deletions as done; advance the last-sync time only if there
     *    were no errors, so a failed upload is retried next time.
     *
     * @param cloudFolderUri The SAF URI of the cloud sync directory.
     * @return A [SyncResult] describing the outcome.
     */
    suspend fun sync(cloudFolderUri: Uri): SyncResult = withContext(Dispatchers.IO) {
        val errors = mutableListOf<String>()
        var total = SyncResult()

        try {
            val cloudFolder = DocumentFile.fromTreeUri(context, cloudFolderUri)
                ?: return@withContext SyncResult(errors = listOf("Cannot access cloud folder"))

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
                    continue
                }
                val result = syncChannel(channel, dir, state.lastSyncTimestamp, deletedIds)
                total = SyncResult(
                    uploaded = total.uploaded + result.uploaded,
                    downloaded = total.downloaded + result.downloaded,
                    deleted = total.deleted + result.deleted
                )
                errors.addAll(result.errors)
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
        } catch (e: Exception) {
            Log.e(TAG, "Sync failed", e)
            errors.add("Sync failed: ${e.message}")
        }

        total.copy(errors = errors)
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

        val local: Map<String, String?>
        val cloudFiles: Map<String, DocumentFile>
        try {
            local = channel.localStamps().associate { it.id to it.modifiedAt }
            cloudFiles = dir.listFiles()
                .filter { it.name?.endsWith(JSON_SUFFIX) == true }
                .associateBy { it.name!!.removeSuffix(JSON_SUFFIX) }
        } catch (e: Exception) {
            Log.e(TAG, "${channel.label}: cannot list entities", e)
            return SyncResult(errors = listOf("${channel.label}: ${e.message}"))
        }

        for (id in local.keys intersect deletedIds) {
            try {
                channel.deleteLocal(id)
                deleted++
            } catch (e: Exception) {
                Log.e(TAG, "${channel.label}: cannot apply deletion of $id", e)
                errors.add("${channel.label} delete $id: ${e.message}")
            }
        }

        val uploadedIds = mutableSetOf<String>()
        for ((id, modifiedAt) in local) {
            if (id in deletedIds || !shouldUpload(modifiedAt, lastSync)) continue
            try {
                val item = channel.loadLocal(id) ?: continue
                writeJsonToCloud(
                    dir, cloudFiles[id], "$id$JSON_SUFFIX",
                    json.encodeToString(channel.serializer, item)
                )
                uploadedIds.add(id)
                uploaded++
            } catch (e: Exception) {
                Log.e(TAG, "${channel.label}: cannot upload $id", e)
                errors.add("${channel.label} upload $id: ${e.message}")
            }
        }

        // shortcut: reads every cloud file on each sync; skip unchanged files by
        // DocumentFile.lastModified() if large photo-heavy folders make sync slow.
        for ((id, file) in cloudFiles) {
            if (id in deletedIds) {
                if (!file.delete()) {
                    Log.w(TAG, "${channel.label}: cannot delete cloud file ${file.name}")
                }
                continue
            }
            if (id in uploadedIds) continue
            val text = readFileFromCloud(file) ?: continue
            try {
                val item = json.decodeFromString(channel.serializer, text)
                val itemId = channel.idOf(item)
                if (shouldDownload(channel.modifiedAtOf(item), local[itemId], itemId in local)) {
                    channel.saveLocal(item)
                    downloaded++
                }
            } catch (e: Exception) {
                Log.w(TAG, "${channel.label}: skipping corrupted cloud file ${file.name}", e)
            }
        }

        return SyncResult(uploaded, downloaded, deleted, errors)
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
     * @return The deserialized manifest, or null if not found or corrupted.
     */
    private fun readManifest(cloudFolder: DocumentFile): SyncManifest? {
        val manifestFile = cloudFolder.findFile(MANIFEST_FILENAME) ?: return null
        val content = readFileFromCloud(manifestFile) ?: return null
        return try {
            json.decodeFromString<SyncManifest>(content)
        } catch (e: Exception) {
            Log.w(TAG, "Corrupted manifest, starting fresh", e)
            null
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
     * @return The file content as a string, or null on failure.
     */
    private fun readFileFromCloud(file: DocumentFile): String? {
        return try {
            context.contentResolver.openInputStream(file.uri)?.use { stream ->
                stream.bufferedReader().readText()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read cloud file: ${file.name}", e)
            null
        }
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
    }
}
