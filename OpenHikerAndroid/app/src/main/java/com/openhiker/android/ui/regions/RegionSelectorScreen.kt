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

package com.openhiker.android.ui.regions

import android.graphics.PointF
import android.view.MotionEvent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Download
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.BottomSheetScaffold
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RangeSlider
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberBottomSheetScaffoldState
import androidx.compose.material3.rememberStandardBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInteropFilter
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.openhiker.android.ui.components.TileSourceSelector
import com.openhiker.core.geo.BoundingBox
import com.openhiker.core.model.DownloadStatus
import com.openhiker.core.model.TileServer
import org.maplibre.android.MapLibre
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import androidx.compose.ui.viewinterop.AndroidView

/** Minimum selection size in dp before snapping to default region. */
private const val MIN_SELECTION_SIZE_DP = 50f

/** Fraction of visible map region used for default snap selection. */
private const val DEFAULT_SELECTION_FRACTION = 0.6

/**
 * Region selection screen with interactive map and drag-to-select.
 *
 * Displays a full-screen MapLibre map where the user can:
 * 1. Browse the map and pick a tile source
 * 2. Drag to draw a selection rectangle defining the download area
 * 3. Configure zoom range and region name
 * 4. View tile count estimate and start download
 * 5. Monitor download progress with cancel option
 *
 * The selection rectangle is drawn as a blue stroke with semi-transparent
 * blue fill. Areas outside the selection get a dark overlay.
 * Small selections (< 50dp) snap to 60% of the visible map region.
 *
 * @param onNavigateBack Callback to navigate back when done.
 * @param viewModel The region selector ViewModel.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
fun RegionSelectorScreen(
    onNavigateBack: () -> Unit,
    viewModel: RegionSelectorViewModel = hiltViewModel()
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val density = LocalDensity.current

    val uiState by viewModel.uiState.collectAsState()
    val downloadProgress by viewModel.downloadProgress.collectAsState()
    val isDownloading by viewModel.isDownloading.collectAsState()

    // Drag state for selection rectangle
    var dragStart by remember { mutableStateOf<Offset?>(null) }
    var dragEnd by remember { mutableStateOf<Offset?>(null) }
    var selectionRect by remember { mutableStateOf<Rect?>(null) }

    var mapLibreMap by remember { mutableStateOf<MapLibreMap?>(null) }

    // Initialize MapLibre
    LaunchedEffect(Unit) {
        MapLibre.getInstance(context)
    }

    val mapView = remember { MapView(context) }

    // MapView lifecycle
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_CREATE -> mapView.onCreate(null)
                Lifecycle.Event.ON_START -> mapView.onStart()
                Lifecycle.Event.ON_RESUME -> mapView.onResume()
                Lifecycle.Event.ON_PAUSE -> mapView.onPause()
                Lifecycle.Event.ON_STOP -> mapView.onStop()
                Lifecycle.Event.ON_DESTROY -> mapView.onDestroy()
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    // Setup map
    LaunchedEffect(Unit) {
        val styleUri = "asset://styles/${TileServer.OPEN_TOPO_MAP.id}.json"
        mapView.getMapAsync { map ->
            mapLibreMap = map
            map.setStyle(Style.Builder().fromUri(styleUri))
        }
    }

    // Confirmation dialog
    if (uiState.showConfirmDialog) {
        AlertDialog(
            onDismissRequest = { viewModel.dismissConfirmDialog() },
            title = { Text("Download Region") },
            text = {
                Column {
                    Text("Name: ${uiState.regionName.ifBlank { "Region" }}")
                    Text("Tiles: ${uiState.estimatedTileCount}")
                    Text("Estimated size: ${uiState.estimatedSizeFormatted}")
                    Text("Zoom levels: ${uiState.minZoom} – ${uiState.maxZoom}")
                }
            },
            confirmButton = {
                Button(onClick = { viewModel.startDownload() }) {
                    Text("Download")
                }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.dismissConfirmDialog() }) {
                    Text("Cancel")
                }
            }
        )
    }

    val scaffoldState = rememberBottomSheetScaffoldState(
        bottomSheetState = rememberStandardBottomSheetState(
            initialValue = SheetValue.PartiallyExpanded
        )
    )

    BottomSheetScaffold(
        scaffoldState = scaffoldState,
        sheetPeekHeight = 200.dp,
        sheetContent = {
            RegionSelectorSheet(
                uiState = uiState,
                downloadProgress = downloadProgress,
                isDownloading = isDownloading,
                onZoomRangeChanged = { min, max -> viewModel.updateZoomRange(min, max) },
                onNameChanged = { viewModel.updateRegionName(it) },
                onTileServerSelected = { viewModel.updateTileServer(it) },
                onDownloadClicked = { viewModel.showConfirmDialog() },
                onCancelDownload = { viewModel.cancelDownload() },
                onNavigateBack = onNavigateBack
            )
        }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            // Map layer
            AndroidView(
                factory = { mapView },
                modifier = Modifier.fillMaxSize()
            )

            // Drag-to-select overlay
            Canvas(
                modifier = Modifier
                    .fillMaxSize()
                    .pointerInteropFilter { event ->
                        if (isDownloading) return@pointerInteropFilter false

                        when (event.action) {
                            MotionEvent.ACTION_DOWN -> {
                                dragStart = Offset(event.x, event.y)
                                dragEnd = null
                                selectionRect = null
                                true
                            }
                            MotionEvent.ACTION_MOVE -> {
                                dragEnd = Offset(event.x, event.y)
                                true
                            }
                            MotionEvent.ACTION_UP -> {
                                val start = dragStart
                                val end = Offset(event.x, event.y)
                                if (start != null) {
                                    val minSelectionPx = with(density) {
                                        MIN_SELECTION_SIZE_DP.dp.toPx()
                                    }
                                    val width = kotlin.math.abs(end.x - start.x)
                                    val height = kotlin.math.abs(end.y - start.y)

                                    val map = mapLibreMap
                                    if (map != null) {
                                        if (width < minSelectionPx || height < minSelectionPx) {
                                            // Snap to default: 60% of visible region
                                            snapToDefaultSelection(map, viewModel)
                                        } else {
                                            // Convert screen rect to geographic bounds
                                            convertSelectionToBounds(
                                                map, start, end, viewModel
                                            )
                                        }
                                        selectionRect = Rect(
                                            left = minOf(start.x, end.x),
                                            top = minOf(start.y, end.y),
                                            right = maxOf(start.x, end.x),
                                            bottom = maxOf(start.y, end.y)
                                        )
                                    }
                                }
                                dragStart = null
                                dragEnd = null
                                true
                            }
                            else -> false
                        }
                    }
            ) {
                // Draw active drag rectangle
                val start = dragStart
                val end = dragEnd
                if (start != null && end != null) {
                    val rect = Rect(
                        left = minOf(start.x, end.x),
                        top = minOf(start.y, end.y),
                        right = maxOf(start.x, end.x),
                        bottom = maxOf(start.y, end.y)
                    )

                    // Dark overlay outside selection (30% opacity)
                    drawRect(
                        color = Color.Black.copy(alpha = 0.3f),
                        topLeft = Offset.Zero,
                        size = Size(size.width, rect.top)
                    )
                    drawRect(
                        color = Color.Black.copy(alpha = 0.3f),
                        topLeft = Offset(0f, rect.bottom),
                        size = Size(size.width, size.height - rect.bottom)
                    )
                    drawRect(
                        color = Color.Black.copy(alpha = 0.3f),
                        topLeft = Offset(0f, rect.top),
                        size = Size(rect.left, rect.height)
                    )
                    drawRect(
                        color = Color.Black.copy(alpha = 0.3f),
                        topLeft = Offset(rect.right, rect.top),
                        size = Size(size.width - rect.right, rect.height)
                    )

                    // Selection rectangle fill (10% opacity blue)
                    drawRect(
                        color = Color(0x1A2196F3),
                        topLeft = Offset(rect.left, rect.top),
                        size = Size(rect.width, rect.height)
                    )

                    // Selection rectangle stroke (blue, 3dp)
                    drawRect(
                        color = Color(0xFF2196F3),
                        topLeft = Offset(rect.left, rect.top),
                        size = Size(rect.width, rect.height),
                        style = Stroke(width = with(density) { 3.dp.toPx() })
                    )
                }

                // Draw confirmed selection rectangle
                val confirmed = selectionRect
                if (confirmed != null && start == null) {
                    drawRect(
                        color = Color(0x1A2196F3),
                        topLeft = Offset(confirmed.left, confirmed.top),
                        size = Size(confirmed.width, confirmed.height)
                    )
                    drawRect(
                        color = Color(0xFF2196F3),
                        topLeft = Offset(confirmed.left, confirmed.top),
                        size = Size(confirmed.width, confirmed.height),
                        style = Stroke(width = with(density) { 3.dp.toPx() })
                    )
                }
            }
        }
    }
}

/**
 * Snaps the selection to 60% of the currently visible map region.
 *
 * Used when the user's drag selection is too small (< 50dp).
 * Calculates the visible bounds and shrinks them by [DEFAULT_SELECTION_FRACTION].
 *
 * @param map The MapLibre map instance for projection.
 * @param viewModel The ViewModel to update with the computed bounds.
 */
private fun snapToDefaultSelection(
    map: MapLibreMap,
    viewModel: RegionSelectorViewModel
) {
    val visibleRegion = map.projection.visibleRegion
    val bounds = visibleRegion.latLngBounds

    val centerLat = (bounds.latNorth + bounds.latSouth) / 2.0
    val centerLon = (bounds.lonEast + bounds.lonWest) / 2.0
    val latSpan = (bounds.latNorth - bounds.latSouth) * DEFAULT_SELECTION_FRACTION
    val lonSpan = (bounds.lonEast - bounds.lonWest) * DEFAULT_SELECTION_FRACTION

    val bbox = BoundingBox(
        north = centerLat + latSpan / 2,
        south = centerLat - latSpan / 2,
        east = centerLon + lonSpan / 2,
        west = centerLon - lonSpan / 2
    )
    viewModel.updateBounds(bbox)
}

/**
 * Converts a screen-space selection rectangle to geographic coordinates.
 *
 * Uses MapLibre's camera projection to convert the four corners of the
 * screen rectangle to latitude/longitude coordinates.
 *
 * @param map The MapLibre map instance for projection.
 * @param start Top-left corner of the selection in screen pixels.
 * @param end Bottom-right corner of the selection in screen pixels.
 * @param viewModel The ViewModel to update with the computed bounds.
 */
private fun convertSelectionToBounds(
    map: MapLibreMap,
    start: Offset,
    end: Offset,
    viewModel: RegionSelectorViewModel
) {
    val topLeft = PointF(minOf(start.x, end.x), minOf(start.y, end.y))
    val bottomRight = PointF(maxOf(start.x, end.x), maxOf(start.y, end.y))

    val nw = map.projection.fromScreenLocation(topLeft)
    val se = map.projection.fromScreenLocation(bottomRight)

    val bbox = BoundingBox(
        north = nw.latitude,
        south = se.latitude,
        east = se.longitude,
        west = nw.longitude
    )
    viewModel.updateBounds(bbox)
}

/**
 * Bottom sheet content for region selection configuration.
 *
 * Displays:
 * - Region name text field
 * - Zoom range slider (12-16)
 * - Tile count estimate and download size
 * - Tile server selector
 * - Download/cancel buttons
 * - Download progress indicator
 */
@Composable
private fun RegionSelectorSheet(
    uiState: RegionSelectorUiState,
    downloadProgress: com.openhiker.core.model.RegionDownloadProgress?,
    isDownloading: Boolean,
    onZoomRangeChanged: (Int, Int) -> Unit,
    onNameChanged: (String) -> Unit,
    onTileServerSelected: (TileServer) -> Unit,
    onDownloadClicked: () -> Unit,
    onCancelDownload: () -> Unit,
    onNavigateBack: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        // Header with close button
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Download Region",
                style = MaterialTheme.typography.titleLarge
            )
            IconButton(onClick = onNavigateBack) {
                Icon(Icons.Default.Close, contentDescription = "Close")
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Region name
        OutlinedTextField(
            value = uiState.regionName,
            onValueChange = onNameChanged,
            label = { Text("Region name") },
            placeholder = { Text("e.g., Innsbruck Alps") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            enabled = !isDownloading
        )

        Spacer(modifier = Modifier.height(12.dp))

        // Zoom range slider
        Text(
            text = "Zoom levels: ${uiState.minZoom} – ${uiState.maxZoom}",
            style = MaterialTheme.typography.bodyMedium
        )
        RangeSlider(
            value = uiState.minZoom.toFloat()..uiState.maxZoom.toFloat(),
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
                text = if (uiState.selectedBounds != null) {
                    "${uiState.estimatedTileCount} tiles"
                } else {
                    "Drag on map to select area"
                },
                style = MaterialTheme.typography.bodyMedium
            )
            if (uiState.selectedBounds != null) {
                Text(
                    text = "~${uiState.estimatedSizeFormatted}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Tile server selector
        TileSourceSelector(
            currentServer = uiState.tileServer,
            onServerSelected = onTileServerSelected
        )

        Spacer(modifier = Modifier.height(12.dp))

        // Download progress or download button
        if (isDownloading && downloadProgress != null) {
            Column {
                LinearProgressIndicator(
                    progress = { downloadProgress.progress.toFloat() },
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(4.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "${downloadProgress.downloadedTiles}/${downloadProgress.totalTiles} tiles (z${downloadProgress.currentZoom})",
                        style = MaterialTheme.typography.bodySmall
                    )
                    Text(
                        text = "${(downloadProgress.progress * 100).toInt()}%",
                        style = MaterialTheme.typography.bodySmall
                    )
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
                    onClick = onNavigateBack,
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
                    enabled = uiState.selectedBounds != null
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
                enabled = uiState.selectedBounds != null
            ) {
                Icon(Icons.Default.Download, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Download ${uiState.estimatedTileCount} Tiles")
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
    }
}
