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

package com.openhiker.android.service.elevation

import android.content.Context
import android.util.Log
import android.util.LruCache
import com.openhiker.android.di.GeneralClient
import com.openhiker.core.elevation.BilinearInterpolator
import com.openhiker.core.elevation.HgtGrid
import com.openhiker.core.elevation.HgtParser
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.zip.GZIPInputStream
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.floor

/**
 * Manages SRTM/ASTER elevation data download, caching, and lookup.
 *
 * Downloads HGT tiles on demand from the Tilezen Skadi S3 bucket,
 * decompresses them (gzip), and caches parsed grids in an LRU cache.
 * Downloaded files are persisted to disk for offline use.
 *
 * Typical usage:
 * ```kotlin
 * val elevation = elevationDataManager.getElevation(47.267, 11.393)
 * ```
 *
 * @param context Application context for file storage.
 * @param httpClient OkHttp client for downloads.
 */
@Singleton
class ElevationDataManager @Inject constructor(
    @ApplicationContext private val context: Context,
    @GeneralClient private val httpClient: OkHttpClient
) {
    /** In-memory LRU cache of parsed HGT grids. Max 4 tiles (~100 MB). */
    private val gridCache = LruCache<String, HgtGrid>(MAX_CACHED_GRIDS)

    /** Base directory for persisted HGT files on disk. */
    private val storageDir: File
        get() = File(context.filesDir, ELEVATION_DIR).also { it.mkdirs() }

    /**
     * Looks up the elevation at a geographic coordinate.
     *
     * Loads the HGT grid from cache, disk, or downloads it if needed.
     * Returns null if the elevation data is unavailable (void cell or
     * download failure).
     *
     * @param latitude WGS84 latitude in degrees.
     * @param longitude WGS84 longitude in degrees.
     * @return Elevation in metres above sea level, or null if unavailable.
     */
    suspend fun getElevation(latitude: Double, longitude: Double): Double? {
        val grid = getGrid(latitude, longitude) ?: return null
        return BilinearInterpolator.interpolate(grid, latitude, longitude)
    }

    /**
     * Pre-downloads HGT tiles for a bounding box to ensure offline availability.
     *
     * Determines which 1-degree tiles overlap the bounding box and downloads
     * any that are not already cached on disk.
     *
     * @param south Minimum latitude.
     * @param west Minimum longitude.
     * @param north Maximum latitude.
     * @param east Maximum longitude.
     * @return The number of tiles downloaded (0 if all were cached).
     */
    suspend fun predownload(
        south: Double,
        west: Double,
        north: Double,
        east: Double
    ): Int = withContext(Dispatchers.IO) {
        var downloaded = 0
        val latMin = floor(south).toInt()
        val latMax = floor(north).toInt()
        val lonMin = floor(west).toInt()
        val lonMax = floor(east).toInt()

        for (lat in latMin..latMax) {
            for (lon in lonMin..lonMax) {
                val filename = HgtParser.hgtFilename(lat + 0.5, lon + 0.5)
                val file = File(storageDir, "$filename.gz")
                if (!file.exists()) {
                    try {
                        downloadHgtFile(lat + 0.5, lon + 0.5)
                        downloaded++
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to download elevation tile $filename: ${e.message}")
                    }
                }
            }
        }
        downloaded
    }

    /**
     * Retrieves or loads the HGT grid for a coordinate.
     *
     * Checks: (1) in-memory LRU cache, (2) disk cache, (3) downloads from server.
     *
     * @param latitude WGS84 latitude.
     * @param longitude WGS84 longitude.
     * @return The parsed HGT grid, or null if unavailable.
     */
    private suspend fun getGrid(latitude: Double, longitude: Double): HgtGrid? {
        val cacheKey = HgtParser.hgtFilename(latitude, longitude)

        // Check in-memory cache
        gridCache.get(cacheKey)?.let { return it }

        // Check disk cache
        val grid = loadFromDisk(latitude, longitude)
            ?: downloadAndParse(latitude, longitude)

        if (grid != null) {
            gridCache.put(cacheKey, grid)
        }
        return grid
    }

    /**
     * Loads and parses an HGT file from disk cache.
     *
     * @return The parsed grid, or null if the file doesn't exist.
     */
    private suspend fun loadFromDisk(
        latitude: Double,
        longitude: Double
    ): HgtGrid? = withContext(Dispatchers.IO) {
        val filename = HgtParser.hgtFilename(latitude, longitude)
        val gzFile = File(storageDir, "$filename.gz")

        if (!gzFile.exists()) return@withContext null

        try {
            val bytes = GZIPInputStream(gzFile.inputStream()).use { it.readBounded() }
            val lat = floor(latitude).toInt()
            val lon = floor(longitude).toInt()
            HgtParser.parse(bytes, lat, lon)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse cached HGT file $filename: ${e.message}")
            null
        }
    }

    /**
     * Downloads an HGT file from the Skadi server and parses it.
     *
     * Retries up to [MAX_RETRY_ATTEMPTS] times with exponential backoff.
     *
     * @return The parsed grid, or null if download fails.
     */
    private suspend fun downloadAndParse(
        latitude: Double,
        longitude: Double
    ): HgtGrid? = withContext(Dispatchers.IO) {
        try {
            val bytes = downloadHgtFile(latitude, longitude)
            val lat = floor(latitude).toInt()
            val lon = floor(longitude).toInt()
            HgtParser.parse(bytes, lat, lon)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to download HGT tile: ${e.message}")
            null
        }
    }

    /**
     * Downloads an HGT .gz file from the Skadi server.
     *
     * Tries the primary endpoint first, then falls back to the fallback.
     * Retries with exponential backoff on transient failures.
     *
     * @return The decompressed HGT bytes.
     * @throws IOException if all attempts fail.
     */
    private suspend fun downloadHgtFile(
        latitude: Double,
        longitude: Double
    ): ByteArray {
        val skadiPath = HgtParser.skadiPath(latitude, longitude)
        val filename = HgtParser.hgtFilename(latitude, longitude)
        val endpoints = listOf(PRIMARY_ENDPOINT, FALLBACK_ENDPOINT)

        var lastException: Exception? = null

        for (attempt in 0 until MAX_RETRY_ATTEMPTS) {
            val endpoint = endpoints[attempt % endpoints.size]
            val url = "$endpoint/$skadiPath"

            try {
                val gzBytes = httpGet(url)

                // Save to disk cache
                val gzFile = File(storageDir, "$filename.gz")
                gzFile.writeBytes(gzBytes)

                // Decompress with size limit to prevent OOM from corrupted files
                return GZIPInputStream(gzBytes.inputStream()).use { it.readBounded() }
            } catch (e: IOException) {
                lastException = e
                Log.w(TAG, "Download attempt ${attempt + 1} failed for $url: ${e.message}")
                if (attempt < MAX_RETRY_ATTEMPTS - 1) {
                    val delayMs = INITIAL_RETRY_DELAY_MS * (1L shl attempt)
                    delay(delayMs)
                }
            }
        }

        throw IOException(
            "Failed to download elevation tile after $MAX_RETRY_ATTEMPTS attempts",
            lastException
        )
    }

    /**
     * Performs an HTTP GET request and returns the response body bytes.
     */
    private suspend fun httpGet(url: String): ByteArray =
        suspendCancellableCoroutine { continuation ->
            val request = Request.Builder().url(url).build()
            val call = httpClient.newCall(request)

            continuation.invokeOnCancellation { call.cancel() }

            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (!continuation.isCancelled) {
                        continuation.resumeWithException(e)
                    }
                }

                override fun onResponse(call: Call, response: Response) {
                    response.use {
                        if (!it.isSuccessful) {
                            continuation.resumeWithException(
                                IOException("HTTP ${it.code}: ${it.message}")
                            )
                            return
                        }
                        val bytes = it.body?.bytes()
                            ?: throw IOException("Empty response body")
                        continuation.resume(bytes)
                    }
                }
            })
        }

    companion object {
        private const val TAG = "ElevationDataManager"
        private const val ELEVATION_DIR = "elevation"
        private const val MAX_CACHED_GRIDS = 4
        private const val MAX_RETRY_ATTEMPTS = 4
        private const val INITIAL_RETRY_DELAY_MS = 2000L

        /** Tilezen Skadi S3 elevation tile endpoint. */
        private const val PRIMARY_ENDPOINT =
            "https://elevation-tiles-prod.s3.amazonaws.com/skadi"

        /** OpenTopography SRTM fallback endpoint. */
        private const val FALLBACK_ENDPOINT =
            "https://opentopography.s3.sdsc.edu/raster/SRTM_GL1/SRTM_GL1_srtm"
    }
}

/**
 * Maximum decompressed HGT file size in bytes (30 MB).
 *
 * SRTM1 (3601x3601 x 2 bytes) is ~25.9 MB. This limit prevents OOM
 * from corrupted or malicious .hgt.gz files producing unbounded output.
 */
private const val MAX_DECOMPRESSED_HGT_BYTES = 30L * 1024 * 1024

/**
 * Reads all bytes from an [InputStream] with a size limit to prevent OOM.
 *
 * @throws IOException if the decompressed data exceeds [MAX_DECOMPRESSED_HGT_BYTES].
 */
private fun InputStream.readBounded(): ByteArray {
    val buffer = ByteArray(8192)
    val output = ByteArrayOutputStream()
    var totalRead = 0L
    while (true) {
        val bytesRead = read(buffer)
        if (bytesRead == -1) break
        totalRead += bytesRead
        if (totalRead > MAX_DECOMPRESSED_HGT_BYTES) {
            throw IOException(
                "Decompressed HGT file exceeds size limit of $MAX_DECOMPRESSED_HGT_BYTES bytes"
            )
        }
        output.write(buffer, 0, bytesRead)
    }
    return output.toByteArray()
}
