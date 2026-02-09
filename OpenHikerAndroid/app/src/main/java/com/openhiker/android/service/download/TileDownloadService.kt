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

import com.openhiker.android.data.db.tiles.WritableTileStore
import com.openhiker.android.data.repository.RegionRepository
import com.openhiker.android.di.TileDownloadClient
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
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
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
    private val regionRepository: RegionRepository
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

            // Save region metadata
            val metadata = RegionMetadata(
                id = regionId,
                name = name,
                boundingBox = boundingBox,
                minZoom = minZoom,
                maxZoom = maxZoom,
                tileCount = downloadedCount
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
            java.io.File(mbtilesPath).delete()
            _progress.value = null
            throw e
        } catch (e: Exception) {
            try {
                store.rollbackTransaction()
            } catch (_: Exception) { }

            _progress.value = RegionDownloadProgress(
                regionId = regionId,
                totalTiles = 0,
                downloadedTiles = 0,
                currentZoom = minZoom,
                status = DownloadStatus.FAILED(e.message ?: "Unknown download error")
            )
            null
        } finally {
            store.close()
            _isDownloading.value = false
        }
    }

    /**
     * Downloads a single tile with exponential backoff retry.
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

                val response = httpClient.newCall(request).execute()
                if (response.isSuccessful) {
                    return response.body?.bytes()
                }
                response.close()
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

    companion object {
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
