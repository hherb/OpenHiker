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
import com.openhiker.android.data.repository.PlannedRouteRepository
import com.openhiker.android.data.repository.RouteRepository
import com.openhiker.android.data.repository.WaypointRepository
import com.openhiker.core.formats.SyncManifest
import com.openhiker.core.formats.Tombstone
import com.openhiker.core.model.PlannedRoute
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Result of a sync operation.
 *
 * @property uploaded Number of entities uploaded to the cloud drive.
 * @property downloaded Number of entities downloaded from the cloud drive.
 * @property deleted Number of entities deleted (tombstone replication).
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
 * The sync protocol uses a `manifest.json` file ([SyncManifest]) in the
 * cloud folder root to track last sync timestamps and tombstones
 * (deletion records). Delta sync: only entities modified since the last
 * sync timestamp are transferred.
 *
 * File layout in cloud folder:
 * ```
 * OpenHiker/
 *   manifest.json
 *   planned_routes/
 *     {uuid}.json
 *   saved_routes/
 *     {uuid}.json
 *   waypoints/
 *     {uuid}.json
 * ```
 *
 * @param context Application context for SAF file operations.
 * @param plannedRouteRepository Local planned route storage.
 * @param routeRepository Local saved route (hike) storage.
 * @param waypointRepository Local waypoint storage.
 */
@Singleton
class CloudDriveSyncEngine @Inject constructor(
    @ApplicationContext private val context: Context,
    private val plannedRouteRepository: PlannedRouteRepository,
    private val routeRepository: RouteRepository,
    private val waypointRepository: WaypointRepository
) {
    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
    }

    /**
     * Runs a full bidirectional sync cycle with the cloud drive folder.
     *
     * Steps:
     * 1. Read the cloud manifest (or create a default one)
     * 2. Upload locally-modified entities to the cloud
     * 3. Download cloud-modified entities to the local device
     * 4. Replicate tombstones (deletions) in both directions
     * 5. Update the manifest with the new sync timestamp
     * 6. Prune expired tombstones
     *
     * @param cloudFolderUri The SAF URI of the cloud sync directory.
     * @return A [SyncResult] describing the outcome.
     */
    suspend fun sync(cloudFolderUri: Uri): SyncResult = withContext(Dispatchers.IO) {
        val errors = mutableListOf<String>()
        var uploaded = 0
        var downloaded = 0
        var deleted = 0

        try {
            val cloudFolder = DocumentFile.fromTreeUri(context, cloudFolderUri)
                ?: return@withContext SyncResult(errors = listOf("Cannot access cloud folder"))

            // Ensure subdirectories exist
            val plannedDir = ensureSubDir(cloudFolder, PLANNED_ROUTES_DIR)
            val savedDir = ensureSubDir(cloudFolder, SAVED_ROUTES_DIR)
            val waypointsDir = ensureSubDir(cloudFolder, WAYPOINTS_DIR)

            if (plannedDir == null || savedDir == null || waypointsDir == null) {
                return@withContext SyncResult(
                    errors = listOf("Failed to create sync subdirectories")
                )
            }

            // Read manifest
            val manifest = readManifest(cloudFolder) ?: SyncManifest()
            val lastSync = manifest.lastSyncTimestamp
            val currentTime = System.currentTimeMillis()
            val newTombstones = mutableListOf<Tombstone>()

            // ── Upload planned routes ────────────────────────────
            try {
                val localRoutes = plannedRouteRepository.routes.value
                for (route in localRoutes) {
                    if (shouldUpload(route.modifiedAt, lastSync)) {
                        writeJsonToCloud(plannedDir, "${route.id}.json", json.encodeToString(route))
                        uploaded++
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error uploading planned routes", e)
                errors.add("Planned routes upload: ${e.message}")
            }

            // ── Download planned routes from cloud ───────────────
            try {
                val cloudFiles = plannedDir.listFiles()
                for (file in cloudFiles) {
                    if (file.name?.endsWith(".json") != true) continue
                    val cloudJson = readFileFromCloud(file) ?: continue
                    try {
                        val cloudRoute = json.decodeFromString<PlannedRoute>(cloudJson)
                        val localRoute = plannedRouteRepository.getById(cloudRoute.id)
                        if (localRoute == null || isNewer(cloudRoute.modifiedAt, localRoute.modifiedAt)) {
                            plannedRouteRepository.save(cloudRoute)
                            downloaded++
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Skipping corrupted cloud planned route: ${file.name}", e)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error downloading planned routes", e)
                errors.add("Planned routes download: ${e.message}")
            }

            // ── Upload/download saved routes ─────────────────────
            // TODO: Saved route sync requires entity-model conversion
            //  (SavedRouteEntity has trackData: ByteArray that needs
            //  Base64 encoding for JSON cloud storage). Planned for a
            //  follow-up once entity-to-model mappers are established.
            //  Directories are pre-created above for forward compatibility.

            // ── Upload/download waypoints ────────────────────────
            // TODO: Waypoint sync requires entity-model conversion
            //  (WaypointEntity has photo/thumbnail BLOBs and stores
            //  category as String vs WaypointCategory enum). Planned
            //  for a follow-up once entity-to-model mappers exist.

            // ── Replicate tombstones ─────────────────────────────
            for (tombstone in manifest.tombstones) {
                if (tombstone.deletedAt > lastSync) {
                    try {
                        plannedRouteRepository.delete(tombstone.uuid)
                        routeRepository.delete(tombstone.uuid)
                        waypointRepository.delete(tombstone.uuid)
                        deleted++
                    } catch (e: Exception) {
                        Log.w(TAG, "Error applying tombstone: ${tombstone.uuid}", e)
                    }
                }
            }

            // ── Update manifest ──────────────────────────────────
            val allTombstones = manifest.tombstones + newTombstones
            val updatedManifest = SyncManifest(
                version = SyncManifest.CURRENT_VERSION,
                lastSyncTimestamp = currentTime,
                tombstones = allTombstones
            ).pruneExpiredTombstones(currentTime)

            writeManifest(cloudFolder, updatedManifest)

        } catch (e: Exception) {
            Log.e(TAG, "Sync failed", e)
            errors.add("Sync failed: ${e.message}")
        }

        SyncResult(
            uploaded = uploaded,
            downloaded = downloaded,
            deleted = deleted,
            errors = errors
        )
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
        writeJsonToCloud(cloudFolder, MANIFEST_FILENAME, json.encodeToString(manifest))
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
     * Creates the file if it doesn't exist, overwrites if it does.
     *
     * @param dir The directory to write in.
     * @param filename The file name.
     * @param content The JSON content to write.
     */
    private fun writeJsonToCloud(dir: DocumentFile, filename: String, content: String) {
        val existing = dir.findFile(filename)
        val file = existing ?: dir.createFile("application/json", filename)
        file?.let {
            context.contentResolver.openOutputStream(it.uri, "wt")?.use { stream ->
                stream.write(content.toByteArray(Charsets.UTF_8))
            }
        }
    }

    /**
     * Checks whether a local entity should be uploaded based on its modification time.
     *
     * Parses the ISO-8601 [modifiedAt] timestamp and compares it against the
     * last sync epoch millis. Uploads if modified after last sync, on first
     * sync, or if the timestamp cannot be parsed (fail-open).
     *
     * @param modifiedAt ISO-8601 modification timestamp, or null if never modified.
     * @param lastSyncTimestamp Epoch milliseconds of the last sync.
     * @return True if the entity was modified after the last sync.
     */
    private fun shouldUpload(modifiedAt: String?, lastSyncTimestamp: Long): Boolean {
        if (lastSyncTimestamp == 0L) return true
        if (modifiedAt == null) return true
        return try {
            val modifiedEpoch = java.time.Instant.parse(modifiedAt).toEpochMilli()
            modifiedEpoch > lastSyncTimestamp
        } catch (e: Exception) {
            true // Upload if timestamp cannot be parsed (fail-open)
        }
    }

    /**
     * Compares two ISO-8601 timestamps to determine if the cloud version is newer.
     *
     * @param cloudModifiedAt The cloud entity's modification timestamp.
     * @param localModifiedAt The local entity's modification timestamp.
     * @return True if the cloud version is newer (or local has no timestamp).
     */
    private fun isNewer(cloudModifiedAt: String?, localModifiedAt: String?): Boolean {
        if (localModifiedAt == null) return true
        if (cloudModifiedAt == null) return false
        return cloudModifiedAt > localModifiedAt
    }

    companion object {
        private const val TAG = "CloudDriveSync"
        private const val MANIFEST_FILENAME = "manifest.json"
        private const val PLANNED_ROUTES_DIR = "planned_routes"
        private const val SAVED_ROUTES_DIR = "saved_routes"
        private const val WAYPOINTS_DIR = "waypoints"
    }
}
