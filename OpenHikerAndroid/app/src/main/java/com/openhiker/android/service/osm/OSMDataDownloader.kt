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

package com.openhiker.android.service.osm

import android.content.Context
import android.util.Log
import com.openhiker.android.di.GeneralClient
import com.openhiker.core.geo.BoundingBox
import com.openhiker.core.overpass.OsmData
import com.openhiker.core.overpass.OsmXmlParser
import com.openhiker.core.overpass.OverpassQueryBuilder
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.File
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Downloads OSM trail data from the Overpass API and parses the XML response.
 *
 * Implements the download strategy from the implementation plan:
 * - POST request with URL-encoded body
 * - Primary + fallback Overpass endpoints
 * - Exponential backoff retry (4 attempts: 2s, 4s, 8s, 16s)
 * - HTTP 429 (rate limited): longer delay
 * - HTTP 504 (gateway timeout): skip to fallback endpoint
 * - Region size limit: 10,000 km2
 * - XML response cached to disk for offline re-parsing
 *
 * @param context Application context for file caching.
 * @param httpClient OkHttp client for network requests.
 */
@Singleton
class OSMDataDownloader @Inject constructor(
    @ApplicationContext private val context: Context,
    @GeneralClient private val httpClient: OkHttpClient
) {
    /** Directory for caching downloaded OSM XML files. */
    private val cacheDir: File
        get() = File(context.filesDir, OSM_CACHE_DIR).also { it.mkdirs() }

    /**
     * Downloads and parses OSM trail data for a bounding box.
     *
     * Validates the region size, builds the Overpass query, downloads
     * the XML response (with retry), parses it, and caches the raw XML.
     *
     * @param boundingBox The geographic area to download.
     * @param regionId Identifier for caching (typically the region UUID).
     * @return Parsed [OsmData] containing nodes and ways.
     * @throws OSMDownloadError.RegionTooLarge if the area exceeds the limit.
     * @throws OSMDownloadError.DownloadFailed if all download attempts fail.
     * @throws OSMDownloadError.ParseFailed if the XML cannot be parsed.
     */
    suspend fun download(
        boundingBox: BoundingBox,
        regionId: String
    ): OsmData = withContext(Dispatchers.IO) {
        // Validate region size
        if (!OverpassQueryBuilder.isRegionSizeValid(boundingBox)) {
            throw OSMDownloadError.RegionTooLarge(boundingBox.areaKm2)
        }

        // Check for cached XML
        val cacheFile = File(cacheDir, "$regionId.osm.xml")
        if (cacheFile.exists()) {
            try {
                return@withContext OsmXmlParser.parse(cacheFile.inputStream())
            } catch (e: Exception) {
                Log.w(TAG, "Cached OSM XML parse failed, re-downloading: ${e.message}")
                cacheFile.delete()
            }
        }

        // Download from Overpass API
        val postBody = OverpassQueryBuilder.buildPostBody(boundingBox)
        val xmlBytes = downloadWithRetry(postBody)

        // Cache the raw XML
        cacheFile.writeBytes(xmlBytes)

        // Parse the XML
        try {
            OsmXmlParser.parse(xmlBytes.inputStream())
        } catch (e: Exception) {
            throw OSMDownloadError.ParseFailed(e.message ?: "XML parse error")
        }
    }

    /**
     * Downloads the Overpass XML response with retry and fallback.
     *
     * Strategy:
     * 1. Try primary endpoint
     * 2. On 504: skip to fallback immediately
     * 3. On 429: wait longer, then retry
     * 4. On 5xx/network error: exponential backoff, alternate endpoints
     * 5. On 4xx (except 429): fail immediately (client error, no point retrying)
     *
     * @param postBody URL-encoded POST body containing the Overpass query.
     * @return The response body as bytes.
     * @throws OSMDownloadError.DownloadFailed if all attempts fail.
     */
    private suspend fun downloadWithRetry(postBody: String): ByteArray {
        val endpoints = listOf(
            OverpassQueryBuilder.PRIMARY_ENDPOINT,
            OverpassQueryBuilder.FALLBACK_ENDPOINT
        )
        var currentEndpointIndex = 0
        var lastException: Exception? = null

        for (attempt in 0 until MAX_RETRY_ATTEMPTS) {
            val endpoint = endpoints[currentEndpointIndex % endpoints.size]

            try {
                val response = httpPost(endpoint, postBody)
                return response
            } catch (e: HttpStatusException) {
                lastException = e
                Log.w(TAG, "Overpass attempt ${attempt + 1} HTTP ${e.statusCode}: ${e.message}")

                when {
                    e.statusCode == HTTP_GATEWAY_TIMEOUT -> {
                        // Skip to fallback immediately
                        currentEndpointIndex++
                        continue
                    }
                    e.statusCode == HTTP_TOO_MANY_REQUESTS -> {
                        // Rate limited: longer delay
                        val delayMs = INITIAL_RETRY_DELAY_MS * (1L shl (attempt + 1))
                        delay(delayMs)
                        currentEndpointIndex++
                    }
                    e.statusCode in 400..499 -> {
                        // Client error (not 429): don't retry
                        throw OSMDownloadError.DownloadFailed(
                            "Client error: HTTP ${e.statusCode}"
                        )
                    }
                    else -> {
                        // 5xx: exponential backoff
                        val delayMs = INITIAL_RETRY_DELAY_MS * (1L shl attempt)
                        delay(delayMs)
                        currentEndpointIndex++
                    }
                }
            } catch (e: IOException) {
                lastException = e
                Log.w(TAG, "Overpass attempt ${attempt + 1} network error: ${e.message}")
                val delayMs = INITIAL_RETRY_DELAY_MS * (1L shl attempt)
                delay(delayMs)
                currentEndpointIndex++
            }
        }

        throw OSMDownloadError.DownloadFailed(
            "Failed after $MAX_RETRY_ATTEMPTS attempts: ${lastException?.message}"
        )
    }

    /**
     * Performs an HTTP POST and returns the response body bytes.
     *
     * @throws HttpStatusException for non-2xx responses.
     * @throws IOException for network errors.
     */
    private suspend fun httpPost(endpoint: String, body: String): ByteArray =
        suspendCancellableCoroutine { continuation ->
            val requestBody = body.toRequestBody(CONTENT_TYPE)
            val request = Request.Builder()
                .url(endpoint)
                .post(requestBody)
                .build()

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
                                HttpStatusException(it.code, it.message)
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
        private const val TAG = "OSMDataDownloader"
        private const val OSM_CACHE_DIR = "osm"
        private const val MAX_RETRY_ATTEMPTS = 4
        private const val INITIAL_RETRY_DELAY_MS = 2000L
        private const val HTTP_TOO_MANY_REQUESTS = 429
        private const val HTTP_GATEWAY_TIMEOUT = 504
        private val CONTENT_TYPE = "application/x-www-form-urlencoded".toMediaType()
    }
}

/**
 * Exception for HTTP responses with non-2xx status codes.
 *
 * @property statusCode The HTTP status code.
 */
class HttpStatusException(
    val statusCode: Int,
    message: String
) : IOException("HTTP $statusCode: $message")

/**
 * Errors that can occur during OSM data download.
 */
sealed class OSMDownloadError(message: String) : Exception(message) {

    /** The requested region exceeds the 10,000 km2 size limit. */
    class RegionTooLarge(areaKm2: Double) : OSMDownloadError(
        "Region too large: %.0f km2 (max: %.0f km2)".format(
            areaKm2,
            OverpassQueryBuilder.MAX_REGION_AREA_KM2
        )
    )

    /** All download attempts failed. */
    class DownloadFailed(detail: String) : OSMDownloadError(
        "OSM data download failed: $detail"
    )

    /** The downloaded XML could not be parsed. */
    class ParseFailed(detail: String) : OSMDownloadError(
        "OSM XML parse error: $detail"
    )
}
