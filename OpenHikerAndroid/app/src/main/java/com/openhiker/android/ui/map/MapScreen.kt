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

import android.annotation.SuppressLint
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Public
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.LifecycleEventObserver
import com.openhiker.android.ui.components.RequestLocationPermission
import com.openhiker.android.ui.components.TileSourceSelector
import com.openhiker.android.ui.components.hasLocationPermission
import com.openhiker.core.model.TileServer
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.location.LocationComponentActivationOptions
import org.maplibre.android.location.modes.CameraMode
import org.maplibre.android.location.modes.RenderMode
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.layers.FillLayer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.sources.GeoJsonSource

/** Source ID for region boundary overlays. */
private const val BOUNDARY_SOURCE_ID = "region-boundaries"

/** Layer ID for region boundary fill. */
private const val BOUNDARY_FILL_LAYER_ID = "region-boundaries-fill"

/** Layer ID for region boundary stroke. */
private const val BOUNDARY_LINE_LAYER_ID = "region-boundaries-line"

/**
 * Main map display screen using MapLibre Native.
 *
 * Shows an interactive map with:
 * - Online tile sources (OpenTopoMap, CyclOSM, OSM Standard) or offline MBTiles
 * - GPS position overlay with compass heading (when permission granted)
 * - Region boundary indicators for downloaded areas
 * - Tile source selector dropdown
 * - Camera position persistence across app restarts
 *
 * The MapLibre MapView is wrapped in an [AndroidView] composable with
 * proper lifecycle management. Camera position changes are debounced
 * and persisted to DataStore.
 */
@Composable
fun MapScreen(
    viewModel: MapViewModel = hiltViewModel()
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    val cameraState by viewModel.cameraState.collectAsState()
    val mapMode by viewModel.mapMode.collectAsState()
    val locationGranted by viewModel.locationPermissionGranted.collectAsState()
    val regions by viewModel.regions.collectAsState()

    // Track whether we need to request location permission
    var shouldRequestPermission by remember { mutableStateOf(false) }

    // Track the MapLibreMap instance for programmatic control
    var mapLibreMap by remember { mutableStateOf<MapLibreMap?>(null) }

    // Initialize MapLibre
    LaunchedEffect(Unit) {
        MapLibre.getInstance(context)
        // Check if we already have location permission
        if (hasLocationPermission(context)) {
            viewModel.onLocationPermissionResult(true)
        } else {
            shouldRequestPermission = true
        }
    }

    // Request location permission if needed
    if (shouldRequestPermission) {
        RequestLocationPermission { granted ->
            viewModel.onLocationPermissionResult(granted)
            shouldRequestPermission = false
        }
    }

    // Create and remember the MapView
    val mapView = remember {
        MapView(context)
    }

    // Manage MapView lifecycle
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

    // Load style when map mode changes
    LaunchedEffect(mapMode) {
        val styleUri = viewModel.getStyleUri()
        mapView.getMapAsync { map ->
            mapLibreMap = map

            // Determine style loading method
            val isOfflineJson = mapMode is MapMode.Offline
            val styleBuilder = if (isOfflineJson) {
                Style.Builder().fromJson(styleUri)
            } else {
                Style.Builder().fromUri(styleUri)
            }

            map.setStyle(styleBuilder) { style ->
                // Enable location component if permission granted
                if (locationGranted) {
                    enableLocationComponent(map, style, context)
                }

                // Add region boundary overlays
                addBoundaryOverlays(style, viewModel.getRegionBoundariesGeoJson())
            }

            // Set initial camera position
            map.cameraPosition = CameraPosition.Builder()
                .target(LatLng(cameraState.latitude, cameraState.longitude))
                .zoom(cameraState.zoom)
                .build()

            // Listen for camera changes to persist position
            map.addOnCameraIdleListener {
                val target = map.cameraPosition.target
                if (target != null) {
                    viewModel.saveCameraPosition(
                        latitude = target.latitude,
                        longitude = target.longitude,
                        zoom = map.cameraPosition.zoom
                    )
                }
            }
        }
    }

    // Update location component when permission changes
    LaunchedEffect(locationGranted) {
        if (locationGranted) {
            mapLibreMap?.let { map ->
                map.style?.let { style ->
                    enableLocationComponent(map, style, context)
                }
            }
        }
    }

    // Update boundaries when regions change
    LaunchedEffect(regions) {
        mapLibreMap?.style?.let { style ->
            addBoundaryOverlays(style, viewModel.getRegionBoundariesGeoJson())
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        // MapView fills the screen
        AndroidView(
            factory = { mapView },
            modifier = Modifier.fillMaxSize()
        )

        // Tile source selector (top-right)
        val currentServer = when (val mode = mapMode) {
            is MapMode.Online -> mode.tileServer
            is MapMode.Offline -> null
        }

        if (currentServer != null) {
            TileSourceSelector(
                currentServer = currentServer,
                onServerSelected = { server ->
                    viewModel.selectTileSource(server)
                },
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(8.dp)
            )
        }

        // Switch to online mode button (shown only in offline mode)
        if (mapMode is MapMode.Offline) {
            SmallFloatingActionButton(
                onClick = { viewModel.switchToOnlineMode() },
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(8.dp)
            ) {
                Icon(Icons.Default.Public, contentDescription = "Switch to online")
            }
        }

        // My Location FAB (bottom-right)
        if (locationGranted) {
            FloatingActionButton(
                onClick = {
                    mapLibreMap?.let { map ->
                        val locationComponent = map.locationComponent
                        val lastLocation = locationComponent.lastKnownLocation
                        if (lastLocation != null) {
                            map.animateCamera(
                                CameraUpdateFactory.newLatLngZoom(
                                    LatLng(lastLocation.latitude, lastLocation.longitude),
                                    15.0
                                )
                            )
                        }
                    }
                },
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(16.dp)
            ) {
                Icon(Icons.Default.MyLocation, contentDescription = "My location")
            }
        }
    }
}

/**
 * Enables the MapLibre location component for GPS position display.
 *
 * Activates the blue dot with compass heading arrow (COMPASS render mode).
 * Camera tracks the user position without auto-centering (NONE camera mode)
 * to avoid interrupting manual map browsing.
 *
 * @param map The MapLibre map instance.
 * @param style The loaded map style.
 * @param context Android context for location permissions.
 */
@SuppressLint("MissingPermission")
private fun enableLocationComponent(
    map: MapLibreMap,
    style: Style,
    context: android.content.Context
) {
    val locationComponent = map.locationComponent

    val activationOptions = LocationComponentActivationOptions
        .builder(context, style)
        .build()

    locationComponent.activateLocationComponent(activationOptions)
    locationComponent.isLocationComponentEnabled = true
    locationComponent.cameraMode = CameraMode.NONE
    locationComponent.renderMode = RenderMode.COMPASS
}

/**
 * Adds or updates region boundary overlay layers on the map.
 *
 * Creates a GeoJSON source and two layers (fill + line) for rendering
 * downloaded region boundaries with semi-transparent blue fill and
 * solid blue stroke.
 *
 * @param style The loaded map style.
 * @param geoJson GeoJSON FeatureCollection string, or null to remove overlays.
 */
private fun addBoundaryOverlays(style: Style, geoJson: String?) {
    // Remove existing layers and source
    style.removeLayer(BOUNDARY_FILL_LAYER_ID)
    style.removeLayer(BOUNDARY_LINE_LAYER_ID)
    style.removeSource(BOUNDARY_SOURCE_ID)

    if (geoJson == null) return

    // Add GeoJSON source
    val source = GeoJsonSource(BOUNDARY_SOURCE_ID, geoJson)
    style.addSource(source)

    // Fill layer (semi-transparent blue)
    val fillLayer = FillLayer(BOUNDARY_FILL_LAYER_ID, BOUNDARY_SOURCE_ID).apply {
        setProperties(
            PropertyFactory.fillColor("#2196F3"),
            PropertyFactory.fillOpacity(0.1f)
        )
    }
    style.addLayer(fillLayer)

    // Line layer (solid blue stroke)
    val lineLayer = LineLayer(BOUNDARY_LINE_LAYER_ID, BOUNDARY_SOURCE_ID).apply {
        setProperties(
            PropertyFactory.lineColor("#2196F3"),
            PropertyFactory.lineWidth(3f)
        )
    }
    style.addLayer(lineLayer)
}
