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

package com.openhiker.android.service.export

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.core.content.FileProvider
import com.openhiker.android.data.db.routes.SavedRouteEntity
import com.openhiker.core.compression.TrackCompression
import com.openhiker.core.formats.GpxSerializer
import com.openhiker.core.model.PlannedRoute
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Android wrapper around the core [GpxSerializer] for exporting routes as GPX files.
 *
 * Handles the Android-specific concerns of file I/O, cache directory management,
 * and content URI generation via [FileProvider] so that exported GPX files can be
 * shared with other apps using [Intent.ACTION_SEND].
 *
 * Supports two export modes:
 * - **Saved routes (hikes)**: Decompresses the binary track data from [SavedRouteEntity]
 *   and serializes it as a GPX track (`<trk>`) with timestamps and elevation.
 * - **Planned routes**: Serializes the route polyline as a GPX route (`<rte>`)
 *   with optional elevation profile data.
 *
 * All file operations run on [Dispatchers.IO] via suspend functions.
 *
 * @param context Application context for cache directory and FileProvider access.
 */
@Singleton
class GPXExporter @Inject constructor(
    @ApplicationContext private val context: Context
) {

    /**
     * Exports a saved route (recorded hike) to a GPX file.
     *
     * Decompresses the GPS track data stored in [SavedRouteEntity.trackData]
     * using [TrackCompression], then delegates to [GpxSerializer.serializeTrack]
     * to produce GPX 1.1 XML. The result is written to a temporary file in
     * the app's cache directory.
     *
     * @param savedRoute The saved route entity containing compressed track data.
     * @return A [Result] containing the GPX [File] on success, or the exception on failure.
     */
    suspend fun exportSavedRoute(savedRoute: SavedRouteEntity): Result<File> =
        withContext(Dispatchers.IO) {
            try {
                val trackPoints = TrackCompression.decompress(savedRoute.trackData)

                if (trackPoints.isEmpty()) {
                    Log.w(TAG, "No track points after decompression for route: ${savedRoute.id}")
                    return@withContext Result.failure(
                        IllegalStateException("No track points found in route data")
                    )
                }

                val gpxXml = GpxSerializer.serializeTrack(
                    name = savedRoute.name,
                    description = savedRoute.comment,
                    trackPoints = trackPoints,
                    timestampToIso = ::timestampToIso8601
                )

                Result.success(
                    writeToFile(
                        content = gpxXml,
                        fileName = sanitizeFileName(savedRoute.name)
                    )
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed to export saved route as GPX: ${savedRoute.id}", e)
                Result.failure(e)
            }
        }

    /**
     * Exports a planned route to a GPX file.
     *
     * Delegates to [GpxSerializer.serializeRoute] to produce GPX 1.1 XML
     * from the route's coordinate polyline and optional elevation profile.
     * The result is written to a temporary file in the app's cache directory.
     *
     * @param plannedRoute The planned route to export.
     * @return A [Result] containing the GPX [File] on success, or the exception on failure.
     */
    suspend fun exportPlannedRoute(plannedRoute: PlannedRoute): Result<File> =
        withContext(Dispatchers.IO) {
            try {
                val gpxXml = GpxSerializer.serializeRoute(
                    name = plannedRoute.name,
                    description = "Planned ${plannedRoute.mode.name.lowercase()} route — " +
                        plannedRoute.formattedDistance(),
                    coordinates = plannedRoute.coordinates,
                    elevationProfile = plannedRoute.elevationProfile
                )

                Result.success(
                    writeToFile(
                        content = gpxXml,
                        fileName = sanitizeFileName(plannedRoute.name)
                    )
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed to export planned route as GPX: ${plannedRoute.id}", e)
                Result.failure(e)
            }
        }

    /**
     * Creates a share [Intent] for a GPX file.
     *
     * Generates a content URI via [FileProvider] so that the receiving app
     * can read the file without direct file system access. The intent uses
     * [Intent.ACTION_SEND] with the GPX MIME type.
     *
     * @param file The GPX file to share.
     * @return A configured share intent, or null if URI generation fails.
     */
    fun createShareIntent(file: File): Intent? {
        return try {
            val uri: Uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file
            )

            Intent(Intent.ACTION_SEND).apply {
                type = GPX_MIME_TYPE
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, file.nameWithoutExtension)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create share intent for GPX file: ${file.name}", e)
            null
        }
    }

    /**
     * Writes GPX XML content to a temporary file in the export cache directory.
     *
     * The export directory is cleaned of stale files before writing to prevent
     * unbounded cache growth.
     *
     * @param content The GPX XML string to write.
     * @param fileName The base file name (without extension).
     * @return The written [File].
     */
    private fun writeToFile(content: String, fileName: String): File {
        val exportDir = File(context.cacheDir, EXPORT_DIR).also { it.mkdirs() }
        cleanStaleExports(exportDir)

        val file = File(exportDir, "$fileName.gpx")
        file.writeText(content, Charsets.UTF_8)
        return file
    }

    /**
     * Removes export files older than [STALE_FILE_AGE_MS] from the directory.
     *
     * Prevents the cache directory from growing indefinitely with old exports.
     *
     * @param directory The export cache directory.
     */
    private fun cleanStaleExports(directory: File) {
        val cutoff = System.currentTimeMillis() - STALE_FILE_AGE_MS
        directory.listFiles()?.forEach { file ->
            if (file.lastModified() < cutoff) {
                file.delete()
            }
        }
    }

    /**
     * Converts a track point timestamp (seconds since Unix epoch) to ISO-8601 format.
     *
     * Android track points use Unix epoch timestamps (seconds since 1970-01-01).
     * This function formats them as ISO-8601 UTC strings for GPX `<time>` elements.
     *
     * @param timestamp Seconds since Unix epoch.
     * @return ISO-8601 formatted timestamp string (e.g., "2025-06-15T14:30:00Z").
     */
    private fun timestampToIso8601(timestamp: Double): String {
        val date = Date((timestamp * MILLIS_PER_SECOND).toLong())
        return isoDateFormat.format(date)
    }

    /**
     * Sanitizes a string for use as a file name.
     *
     * Replaces characters that are invalid in file names with underscores,
     * trims whitespace, and falls back to a default name if the result is empty.
     *
     * @param name The raw name to sanitize.
     * @return A file-system-safe name string.
     */
    private fun sanitizeFileName(name: String): String {
        val sanitized = name.replace(Regex("[^a-zA-Z0-9._\\- ]"), "_").trim()
        return sanitized.ifBlank { DEFAULT_EXPORT_NAME }
    }

    companion object {
        private const val TAG = "GPXExporter"

        /** Subdirectory within the app cache for temporary export files. */
        private const val EXPORT_DIR = "gpx_exports"

        /** MIME type for GPX files. */
        private const val GPX_MIME_TYPE = "application/gpx+xml"

        /** Maximum age of cached export files before cleanup (1 hour). */
        private const val STALE_FILE_AGE_MS = 60 * 60 * 1000L

        /** Milliseconds per second for timestamp conversion. */
        private const val MILLIS_PER_SECOND = 1000.0

        /** Default file name when the route name is empty or invalid. */
        private const val DEFAULT_EXPORT_NAME = "openhiker_route"

        /** Thread-safe ISO-8601 date formatter for GPX timestamps. */
        private val isoDateFormat: SimpleDateFormat
            get() = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
    }
}
