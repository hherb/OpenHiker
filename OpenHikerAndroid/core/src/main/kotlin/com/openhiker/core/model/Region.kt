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

package com.openhiker.core.model

import com.openhiker.core.geo.BoundingBox
import com.openhiker.core.util.FormatUtils
import kotlinx.serialization.Serializable

/**
 * A downloaded map region with its associated metadata.
 *
 * Represents an offline map area stored as an MBTiles file with optional
 * routing data. The [id] is used as the filename stem for both the
 * `.mbtiles` and `.routing.db` files in the regions directory.
 *
 * @property id Unique identifier (UUID string) for this region.
 * @property name User-editable display name.
 * @property boundingBox Geographic extent of the downloaded tiles.
 * @property minZoom Minimum zoom level of downloaded tiles.
 * @property maxZoom Maximum zoom level of downloaded tiles.
 * @property createdAt ISO-8601 timestamp of when the region was downloaded.
 * @property tileCount Total number of tiles across all zoom levels.
 * @property fileSizeBytes Size of the MBTiles file on disk.
 * @property hasRoutingData Whether a routing database exists for this region.
 */
@Serializable
data class Region(
    val id: String,
    val name: String,
    val boundingBox: BoundingBox,
    val minZoom: Int,
    val maxZoom: Int,
    val createdAt: String,
    val tileCount: Int,
    val fileSizeBytes: Long,
    val hasRoutingData: Boolean = false
) {
    /** Filename for the MBTiles tile storage file. */
    val mbtilesFilename: String get() = "$id.mbtiles"

    /** Filename for the routing graph database file. */
    val routingDbFilename: String get() = "$id.routing.db"

    /** Zoom level range as an IntRange for iteration. */
    val zoomLevels: IntRange get() = minZoom..maxZoom

    /**
     * Approximate area covered by this region in square kilometres.
     * Delegates to the bounding box area calculation.
     */
    val areaCoveredKm2: Double get() = boundingBox.areaKm2

    /**
     * Human-readable file size string.
     *
     * Delegates to [FormatUtils.formatBytes] for consistent formatting
     * across the entire application.
     *
     * @return Formatted size like "15.2 MB" or "1.3 GB".
     */
    fun fileSizeFormatted(): String = FormatUtils.formatBytes(fileSizeBytes)
}

/**
 * Metadata for a downloaded region, used for persistence and transfer.
 *
 * A lightweight subset of [Region] that can be serialised to JSON for
 * storage in `regions_metadata.json`. Matches the iOS RegionMetadata
 * struct for cross-platform file compatibility.
 *
 * @property id Unique identifier matching the Region and filename stem.
 * @property name User-editable display name.
 * @property boundingBox Geographic extent.
 * @property minZoom Minimum zoom level.
 * @property maxZoom Maximum zoom level.
 * @property tileCount Total tiles across all zoom levels.
 * @property hasRoutingData Whether a routing database exists.
 */
@Serializable
data class RegionMetadata(
    val id: String,
    val name: String,
    val boundingBox: BoundingBox,
    val minZoom: Int,
    val maxZoom: Int,
    val tileCount: Int,
    val hasRoutingData: Boolean = false
) {
    /** Zoom level range as an IntRange. */
    val zoomLevels: IntRange get() = minZoom..maxZoom

    /**
     * Checks whether a coordinate falls within this region's bounding box.
     *
     * @param coordinate The geographic coordinate to test.
     * @return True if the coordinate is within the region bounds.
     */
    fun contains(coordinate: Coordinate): Boolean =
        boundingBox.contains(coordinate)

    companion object {
        /**
         * Creates metadata from a full [Region] instance.
         *
         * @param region The region to extract metadata from.
         * @return A [RegionMetadata] with the same identifying fields.
         */
        fun fromRegion(region: Region): RegionMetadata = RegionMetadata(
            id = region.id,
            name = region.name,
            boundingBox = region.boundingBox,
            minZoom = region.minZoom,
            maxZoom = region.maxZoom,
            tileCount = region.tileCount,
            hasRoutingData = region.hasRoutingData
        )
    }
}

/**
 * Progress state for an ongoing region download.
 *
 * Emitted by the tile download service as a StateFlow to update
 * the UI with real-time progress information.
 *
 * @property regionId The UUID of the region being downloaded.
 * @property totalTiles Total tiles to download across all zoom levels.
 * @property downloadedTiles Number of tiles successfully downloaded so far.
 * @property currentZoom The zoom level currently being processed.
 * @property status Current download phase.
 */
@Serializable
data class RegionDownloadProgress(
    val regionId: String,
    val totalTiles: Int,
    val downloadedTiles: Int,
    val currentZoom: Int,
    val status: DownloadStatus
) {
    /** Download progress as a fraction (0.0 to 1.0). */
    val progress: Double
        get() = if (totalTiles > 0) downloadedTiles.toDouble() / totalTiles else 0.0

    /** Whether the download has completed successfully. */
    val isComplete: Boolean get() = status == DownloadStatus.COMPLETED

    /** Whether the download has failed. */
    val hasFailed: Boolean get() = status is DownloadStatus.FAILED
}

/**
 * Status of a region download operation.
 *
 * Tracks the download through multiple phases: tile downloading,
 * OSM data fetching, elevation data, and routing graph construction.
 */
@Serializable
sealed class DownloadStatus {
    @Serializable data object PENDING : DownloadStatus()
    @Serializable data object DOWNLOADING : DownloadStatus()
    @Serializable data object DOWNLOADING_TRAIL_DATA : DownloadStatus()
    @Serializable data object DOWNLOADING_ELEVATION : DownloadStatus()
    @Serializable data object BUILDING_ROUTING_GRAPH : DownloadStatus()
    @Serializable data object COMPLETED : DownloadStatus()
    @Serializable data class FAILED(val message: String) : DownloadStatus()
}
