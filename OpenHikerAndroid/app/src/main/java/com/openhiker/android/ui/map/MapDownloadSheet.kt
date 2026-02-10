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

package com.openhiker.android.ui.map

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Download
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RangeSlider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.openhiker.android.ui.components.TileSourceSelector
import com.openhiker.core.geo.BoundingBox
import com.openhiker.core.geo.TileRange
import com.openhiker.core.model.DownloadStatus
import com.openhiker.core.model.RegionDownloadProgress
import com.openhiker.core.model.TileServer

/** Average tile size in bytes for download size estimation. */
private const val AVERAGE_TILE_SIZE_BYTES = 30_000L

/**
 * Bottom sheet content for configuring a map region download from the Navigate screen.
 *
 * Displays a region name field, zoom range slider, tile count and size estimate,
 * tile server selector, and download/cancel controls. Mirrors the layout of
 * [com.openhiker.android.ui.regions.RegionSelectorScreen]'s bottom sheet but is
 * tailored for the "download what I see" workflow on the map screen.
 *
 * @param regionName Current region name entered by the user.
 * @param minZoom Current minimum zoom level for download.
 * @param maxZoom Current maximum zoom level for download.
 * @param tileServer Currently selected tile server.
 * @param visibleBounds The visible map bounds to download, or null if not yet captured.
 * @param downloadProgress Current download progress, or null if not downloading.
 * @param isDownloading Whether a download is currently active.
 * @param onNameChanged Callback when the region name changes.
 * @param onZoomRangeChanged Callback when the zoom range changes.
 * @param onTileServerSelected Callback when a different tile server is selected.
 * @param onDownloadClicked Callback to start the download.
 * @param onCancelDownload Callback to cancel the active download.
 * @param onDismiss Callback to dismiss the sheet.
 */
@Composable
fun MapDownloadSheet(
    regionName: String,
    minZoom: Int,
    maxZoom: Int,
    tileServer: TileServer,
    visibleBounds: BoundingBox?,
    downloadProgress: RegionDownloadProgress?,
    isDownloading: Boolean,
    onNameChanged: (String) -> Unit,
    onZoomRangeChanged: (Int, Int) -> Unit,
    onTileServerSelected: (TileServer) -> Unit,
    onDownloadClicked: () -> Unit,
    onCancelDownload: () -> Unit,
    onDismiss: () -> Unit
) {
    val estimatedTileCount = visibleBounds?.let {
        TileRange.estimateTileCount(it, minZoom..maxZoom)
    } ?: 0

    val estimatedSizeMb = estimatedTileCount * AVERAGE_TILE_SIZE_BYTES / (1024.0 * 1024.0)
    val sizeFormatted = if (estimatedSizeMb >= 1024) {
        "%.1f GB".format(estimatedSizeMb / 1024.0)
    } else {
        "%.1f MB".format(estimatedSizeMb)
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        Text(
            text = "Download Current View",
            style = MaterialTheme.typography.titleLarge
        )

        Spacer(modifier = Modifier.height(12.dp))

        // Region name
        OutlinedTextField(
            value = regionName,
            onValueChange = onNameChanged,
            label = { Text("Region name") },
            placeholder = { Text("e.g., My Hike Area") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            enabled = !isDownloading
        )

        Spacer(modifier = Modifier.height(12.dp))

        // Zoom range slider
        Text(
            text = "Zoom levels: $minZoom \u2013 $maxZoom",
            style = MaterialTheme.typography.bodyMedium
        )
        RangeSlider(
            value = minZoom.toFloat()..maxZoom.toFloat(),
            onValueChange = { range ->
                onZoomRangeChanged(range.start.toInt(), range.endInclusive.toInt())
            },
            valueRange = 8f..18f,
            steps = 9,
            enabled = !isDownloading
        )

        Spacer(modifier = Modifier.height(8.dp))

        // Tile count and size estimate
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = "$estimatedTileCount tiles",
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                text = "~$sizeFormatted",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Tile server selector
        TileSourceSelector(
            currentServer = tileServer,
            onServerSelected = onTileServerSelected
        )

        Spacer(modifier = Modifier.height(12.dp))

        // Download progress or download button
        if (isDownloading && downloadProgress != null) {
            Column {
                val statusText = when (downloadProgress.status) {
                    DownloadStatus.DOWNLOADING ->
                        "${downloadProgress.downloadedTiles}/${downloadProgress.totalTiles} tiles (z${downloadProgress.currentZoom})"
                    DownloadStatus.DOWNLOADING_TRAIL_DATA ->
                        "Downloading trail data\u2026"
                    DownloadStatus.DOWNLOADING_ELEVATION ->
                        "Downloading elevation data\u2026"
                    DownloadStatus.BUILDING_ROUTING_GRAPH ->
                        "Building routing graph\u2026"
                    else ->
                        "${downloadProgress.downloadedTiles}/${downloadProgress.totalTiles} tiles"
                }

                val showTileProgress = downloadProgress.status == DownloadStatus.DOWNLOADING
                if (showTileProgress) {
                    LinearProgressIndicator(
                        progress = { downloadProgress.progress.toFloat() },
                        modifier = Modifier.fillMaxWidth()
                    )
                } else {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                }
                Spacer(modifier = Modifier.height(4.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = statusText,
                        style = MaterialTheme.typography.bodySmall
                    )
                    if (showTileProgress) {
                        Text(
                            text = "${(downloadProgress.progress * 100).toInt()}%",
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }
                Spacer(modifier = Modifier.height(8.dp))
                OutlinedButton(
                    onClick = onCancelDownload,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Cancel Download")
                }
            }
        } else if (downloadProgress?.isComplete == true) {
            Column {
                Text(
                    text = "Download complete!",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.height(8.dp))
                Button(
                    onClick = onDismiss,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Done")
                }
            }
        } else if (downloadProgress?.hasFailed == true) {
            val failMessage = (downloadProgress.status as? DownloadStatus.FAILED)?.message
                ?: "Unknown error"
            Column {
                Text(
                    text = "Download failed: $failMessage",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error
                )
                Spacer(modifier = Modifier.height(8.dp))
                Button(
                    onClick = onDownloadClicked,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = visibleBounds != null
                ) {
                    Icon(Icons.Default.Download, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Retry Download")
                }
            }
        } else {
            Button(
                onClick = onDownloadClicked,
                modifier = Modifier.fillMaxWidth(),
                enabled = visibleBounds != null
            ) {
                Icon(Icons.Default.Download, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Download $estimatedTileCount Tiles")
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
    }
}
