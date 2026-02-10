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

package com.openhiker.android.service.download

import android.util.Log
import com.openhiker.android.data.db.tiles.WritableTileStore
import com.openhiker.android.data.repository.RegionRepository
import com.openhiker.android.di.TileDownloadClient
import com.openhiker.android.service.osm.OSMDataDownloader
import com.openhiker.android.service.routing.RoutingGraphBuilder
import com.openhiker.core.geo.BoundingBox
import com.openhiker.core.geo.TileCoordinate
import com.openhiker.core.geo.TileRange
import com.openhiker.core.model.DownloadStatus
import com.openhiker.core.model.RegionDownloadProgress
import com.openhiker.core.model.RegionMetadata
import com.openhiker.core.model.TileServer
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.File
import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Service for downloading map tiles from a tile server into an MBTiles database.
 *
 * Downloads tiles in batches with rate limiting to comply with OSM tile usage
 * policy. Supports cancellation, exponential backoff retry, and real-time
 * progress reporting via [StateFlow].
 *
 * Key design decisions:
 * - Rate limiting: 50ms delay between tile requests to respect OSM policy
 * - Batch processing: Commits to database every [TILES_PER_BATCH] tiles
 * - Retry: [MAX_RETRY_ATTEMPTS] attempts with exponential backoff (2s, 4s, 8s, 16s)
 * - Subdomain distribution: Deterministic hash for HTTP cache coherence
 */
@Singleton
class TileDownloadService @Inject constructor(
    @TileDownloadClient private val httpClient: OkHttpClient,
    private val regionRepository: RegionRepository,
    private val osmDataDownloader: OSMDataDownloader,
    private val routingGraphBuilder: RoutingGraphBuilder
) {

    private val _progress = MutableStateFlow<RegionDownloadProgress?>(null)

    /** Observable download progress. Null when no download is active. */
    val progress: StateFlow<RegionDownloadProgress?> = _progress.asStateFlow()

    private val _isDownloading = MutableStateFlow(false)

    /** Whether a download is currently in progress. */
    val isDownloading: StateFlow<Boolean> = _isDownloading.asStateFlow()

    /**
     * Downloads all tiles for a region and saves them to an MBTiles file.
     *
     * Creates a new MBTiles database at the region's file path, downloads
     * all tiles within the bounding box across the specified zoom levels,
     * and saves the region metadata on completion.
     *
     * @param name Display name for the region.
     * @param boundingBox Geographic extent to download.
     * @param minZoom Minimum zoom level to download (inclusive).
     * @param maxZoom Maximum zoom level to download (inclusive).
     * @param tileServer The tile server to download from.
     * @return The ID of the newly created region, or null if download failed.
     */
    suspend fun downloadRegion(
        name: String,
        boundingBox: BoundingBox,
        minZoom: Int,
        maxZoom: Int,
        tileServer: TileServer
    ): String? = withContext(Dispatchers.IO) {
        val regionId = UUID.randomUUID().toString()
        val mbtilesPath = regionRepository.mbtilesPath(regionId)

        _isDownloading.value = true

        val store = WritableTileStore(mbtilesPath)
        try {
            store.create(name, boundingBox, minZoom, maxZoom)

            val allTiles = mutableListOf<TileCoordinate>()
            for (zoom in minZoom..maxZoom) {
                val range = TileRange.fromBoundingBox(boundingBox, zoom)
                allTiles.addAll(range.allTiles())
            }
            val totalTiles = allTiles.size

            _progress.value = RegionDownloadProgress(
                regionId = regionId,
                totalTiles = totalTiles,
                downloadedTiles = 0,
                currentZoom = minZoom,
                status = DownloadStatus.DOWNLOADING
            )

            var downloadedCount = 0
            var batchCount = 0
            store.beginTransaction()

            for (tile in allTiles) {
                ensureActive()

                val tileData = downloadTileWithRetry(tile, tileServer)
                if (tileData != null) {
                    store.insertTile(tile, tileData)
                    downloadedCount++
                    batchCount++

                    if (batchCount >= TILES_PER_BATCH) {
                        store.commitTransaction()
                        store.beginTransaction()
                        batchCount = 0
                    }

                    _progress.value = RegionDownloadProgress(
                        regionId = regionId,
                        totalTiles = totalTiles,
                        downloadedTiles = downloadedCount,
                        currentZoom = tile.z,
                        status = DownloadStatus.DOWNLOADING
                    )
                }

                delay(RATE_LIMIT_DELAY_MS)
            }

            // Commit any remaining tiles in the final batch
            if (batchCount > 0) {
                store.commitTransaction()
            }

            store.close()

            // Build routing graph (OSM trail data + elevation + routing database)
            val routingDataBuilt = buildRoutingGraph(
                regionId = regionId,
                boundingBox = boundingBox,
                totalTiles = totalTiles,
                downloadedTiles = downloadedCount
            )

            // Save region metadata
            val metadata = RegionMetadata(
                id = regionId,
                name = name,
                boundingBox = boundingBox,
                minZoom = minZoom,
                maxZoom = maxZoom,
                tileCount = downloadedCount,
                hasRoutingData = routingDataBuilt
            )
            regionRepository.save(metadata)

            _progress.value = RegionDownloadProgress(
                regionId = regionId,
                totalTiles = totalTiles,
                downloadedTiles = downloadedCount,
                currentZoom = maxZoom,
                status = DownloadStatus.COMPLETED
            )

            regionId
        } catch (e: CancellationException) {
            // Clean up on cancellation
            try {
                store.rollbackTransaction()
            } catch (_: Exception) { }
            store.close()
            File(mbtilesPath).delete()
            File(regionRepository.routingDbPath(regionId)).delete()
            _progress.value = null
            throw e
        } catch (e: Exception) {
            try {
                store.rollbackTransaction()
            } catch (_: Exception) { }
            store.close()

            _progress.value = RegionDownloadProgress(
                regionId = regionId,
                totalTiles = 0,
                downloadedTiles = 0,
                currentZoom = minZoom,
                status = DownloadStatus.FAILED(e.message ?: "Unknown download error")
            )
            null
        } finally {
            _isDownloading.value = false
        }
    }

    /**
     * Downloads a single tile with exponential backoff retry.
     *
     * Uses OkHttp's async [Call.enqueue] wrapped in [suspendCancellableCoroutine]
     * so the coroutine doesn't block an IO dispatcher thread while waiting for the
     * network response. The OkHttp call is cancelled if the coroutine is cancelled.
     *
     * Attempts the download up to [MAX_RETRY_ATTEMPTS] times with
     * increasing delays (2s, 4s, 8s, 16s) between retries.
     *
     * @param tile The tile coordinate to download.
     * @param server The tile server configuration.
     * @return The tile image data, or null if all retries failed.
     */
    private suspend fun downloadTileWithRetry(
        tile: TileCoordinate,
        server: TileServer
    ): ByteArray? {
        val url = server.buildTileUrl(tile.x, tile.y, tile.z)

        repeat(MAX_RETRY_ATTEMPTS) { attempt ->
            try {
                val request = Request.Builder()
                    .url(url)
                    .build()

                val response = executeAsync(httpClient.newCall(request))
                response.use {
                    if (it.isSuccessful) {
                        return it.body?.bytes()
                    }
                }
            } catch (_: IOException) {
                // Will retry
            }

            if (attempt < MAX_RETRY_ATTEMPTS - 1) {
                val backoffMs = INITIAL_BACKOFF_MS * (1L shl attempt)
                delay(backoffMs)
            }
        }
        return null
    }

    /**
     * Downloads OSM trail data and builds a routing graph for the region.
     *
     * Called after tile download completes. Downloads trail data from the
     * Overpass API, then builds the routing graph (with elevation lookup).
     * If routing build fails, the error is logged but the download is not
     * considered failed — the user still gets their map tiles.
     *
     * @param regionId The UUID of the region being downloaded.
     * @param boundingBox The geographic area for trail data and routing.
     * @param totalTiles Total tile count for progress reporting.
     * @param downloadedTiles Downloaded tile count for progress reporting.
     * @return `true` if the routing graph was built successfully, `false` otherwise.
     */
    private suspend fun buildRoutingGraph(
        regionId: String,
        boundingBox: BoundingBox,
        totalTiles: Int,
        downloadedTiles: Int
    ): Boolean {
        val routingDbPath = regionRepository.routingDbPath(regionId)

        try {
            // Step 1: Download and parse OSM trail data
            _progress.value = RegionDownloadProgress(
                regionId = regionId,
                totalTiles = totalTiles,
                downloadedTiles = downloadedTiles,
                currentZoom = 0,
                status = DownloadStatus.DOWNLOADING_TRAIL_DATA
            )

            val osmData = osmDataDownloader.download(boundingBox, regionId)

            // Step 2: Build routing graph (elevation is fetched internally by the builder)
            _progress.value = RegionDownloadProgress(
                regionId = regionId,
                totalTiles = totalTiles,
                downloadedTiles = downloadedTiles,
                currentZoom = 0,
                status = DownloadStatus.BUILDING_ROUTING_GRAPH
            )

            routingGraphBuilder.buildGraph(
                osmData = osmData,
                outputPath = routingDbPath,
                regionId = regionId
            )

            Log.d(TAG, "Routing graph built successfully for region $regionId")
            return true
        } catch (e: CancellationException) {
            File(routingDbPath).delete()
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "Routing graph build failed (non-fatal): ${e.message}")
            File(routingDbPath).delete()
            return false
        }
    }

    /**
     * Executes an OkHttp [Call] asynchronously, suspending the coroutine
     * instead of blocking a thread. Cancels the HTTP call if the coroutine
     * is cancelled.
     */
    private suspend fun executeAsync(call: Call): Response =
        suspendCancellableCoroutine { continuation ->
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onResponse(call: Call, response: Response) {
                    continuation.resume(response)
                }
                override fun onFailure(call: Call, e: IOException) {
                    continuation.resumeWithException(e)
                }
            })
        }

    companion object {
        private const val TAG = "TileDownloadService"

        /** Delay between tile requests in milliseconds (OSM policy compliance). */
        private const val RATE_LIMIT_DELAY_MS = 50L

        /** Number of tiles to insert before committing a database transaction. */
        private const val TILES_PER_BATCH = 150

        /** Maximum number of retry attempts for a failed tile download. */
        private const val MAX_RETRY_ATTEMPTS = 4

        /** Initial backoff delay in milliseconds (doubles each retry). */
        private const val INITIAL_BACKOFF_MS = 2000L
    }
}
