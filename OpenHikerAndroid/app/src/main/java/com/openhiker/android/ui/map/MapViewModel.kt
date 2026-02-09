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

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.openhiker.android.data.repository.RegionRepository
import com.openhiker.android.data.repository.UserPreferencesRepository
import com.openhiker.android.service.map.OfflineStyleGenerator
import com.openhiker.core.model.RegionMetadata
import com.openhiker.core.model.TileServer
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/** DataStore instance for persisting map camera position and preferences. */
private val Context.mapDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "map_preferences"
)

/**
 * Camera position state for the map view.
 *
 * @property latitude Camera center latitude in degrees.
 * @property longitude Camera center longitude in degrees.
 * @property zoom Camera zoom level (0 = world, 18 = street level).
 */
data class CameraState(
    val latitude: Double = DEFAULT_LATITUDE,
    val longitude: Double = DEFAULT_LONGITUDE,
    val zoom: Double = DEFAULT_ZOOM
) {
    companion object {
        /** Default latitude: Innsbruck, Austria (project origin). */
        const val DEFAULT_LATITUDE = 47.26
        /** Default longitude: Innsbruck, Austria. */
        const val DEFAULT_LONGITUDE = 11.39
        /** Default zoom level showing a hiking-scale area. */
        const val DEFAULT_ZOOM = 13.0
    }
}

/**
 * Represents the current map display mode.
 *
 * The map can show online tiles from a tile server or offline tiles
 * from a downloaded MBTiles region.
 */
sealed class MapMode {
    /** Online mode: tiles loaded from a remote tile server. */
    data class Online(val tileServer: TileServer) : MapMode()

    /** Offline mode: tiles loaded from a local MBTiles file. */
    data class Offline(val region: RegionMetadata, val mbtilesPath: String) : MapMode()
}

/**
 * ViewModel for the main map screen.
 *
 * Manages:
 * - Camera position persistence via Jetpack DataStore
 * - Tile source selection (online servers or offline regions)
 * - Online/offline mode switching
 * - Region boundary overlay data
 * - GPS location permission state
 *
 * Camera position is saved to DataStore whenever the user pans or zooms,
 * and restored when the app restarts. This matches the iOS behavior
 * of persisting map position via @AppStorage.
 */
@HiltViewModel
class MapViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val regionRepository: RegionRepository,
    private val userPreferencesRepository: UserPreferencesRepository
) : ViewModel() {

    private val dataStore = context.mapDataStore

    private val _cameraState = MutableStateFlow(CameraState())
    /** Current camera position. */
    val cameraState: StateFlow<CameraState> = _cameraState.asStateFlow()

    private val _mapMode = MutableStateFlow<MapMode>(MapMode.Online(TileServer.OPEN_TOPO_MAP))
    /** Current map display mode (online or offline). */
    val mapMode: StateFlow<MapMode> = _mapMode.asStateFlow()

    private val _locationPermissionGranted = MutableStateFlow(false)
    /** Whether fine location permission is currently granted. */
    val locationPermissionGranted: StateFlow<Boolean> = _locationPermissionGranted.asStateFlow()

    /** Observable list of all downloaded regions for boundary overlays. */
    val regions: StateFlow<List<RegionMetadata>> = regionRepository.regions
        .stateIn(viewModelScope, SharingStarted.Lazily, emptyList())

    init {
        viewModelScope.launch {
            restoreCameraPosition()
            regionRepository.loadAll()
        }
        observeDefaultTileServer()
    }

    /**
     * Observes the default tile server preference and switches the map
     * mode when it changes (only in online mode).
     */
    private fun observeDefaultTileServer() {
        viewModelScope.launch {
            userPreferencesRepository.preferencesFlow.collect { prefs ->
                val currentMode = _mapMode.value
                if (currentMode is MapMode.Online) {
                    val preferred = TileServer.ALL.find { it.id == prefs.defaultTileServerId }
                    if (preferred != null && preferred.id != currentMode.tileServer.id) {
                        _mapMode.value = MapMode.Online(preferred)
                    }
                }
            }
        }
    }

    /**
     * Saves the current camera position to persistent DataStore.
     *
     * Called by the MapScreen when the user moves the map. Debouncing
     * is handled by the caller to avoid excessive writes.
     *
     * @param latitude Camera center latitude.
     * @param longitude Camera center longitude.
     * @param zoom Camera zoom level.
     */
    fun saveCameraPosition(latitude: Double, longitude: Double, zoom: Double) {
        _cameraState.value = CameraState(latitude, longitude, zoom)
        viewModelScope.launch {
            dataStore.edit { prefs ->
                prefs[KEY_LATITUDE] = latitude
                prefs[KEY_LONGITUDE] = longitude
                prefs[KEY_ZOOM] = zoom
            }
        }
    }

    /**
     * Switches to a different online tile source.
     *
     * Updates the map mode and persists the selection in DataStore.
     *
     * @param server The tile server to switch to.
     */
    fun selectTileSource(server: TileServer) {
        _mapMode.value = MapMode.Online(server)
        viewModelScope.launch {
            dataStore.edit { prefs ->
                prefs[KEY_TILE_SOURCE] = server.id
            }
        }
    }

    /**
     * Switches to offline mode for a specific downloaded region.
     *
     * Generates an offline MapLibre style JSON pointing to the region's
     * MBTiles file and centers the camera on the region.
     *
     * @param region The downloaded region to display.
     */
    fun selectOfflineRegion(region: RegionMetadata) {
        val mbtilesPath = regionRepository.mbtilesPath(region.id)
        _mapMode.value = MapMode.Offline(region, mbtilesPath)

        val center = region.boundingBox.center
        _cameraState.value = CameraState(
            latitude = center.latitude,
            longitude = center.longitude,
            zoom = region.minZoom.toDouble() + 1
        )
    }

    /**
     * Switches back to online browsing mode.
     */
    fun switchToOnlineMode() {
        val currentServer = when (val mode = _mapMode.value) {
            is MapMode.Online -> mode.tileServer
            is MapMode.Offline -> TileServer.OPEN_TOPO_MAP
        }
        _mapMode.value = MapMode.Online(currentServer)
    }

    /**
     * Updates the location permission state.
     *
     * @param granted Whether fine location permission is granted.
     */
    fun onLocationPermissionResult(granted: Boolean) {
        _locationPermissionGranted.value = granted
    }

    /**
     * Returns the MapLibre style URI for the current map mode.
     *
     * For online mode: `asset://styles/<server-id>.json`
     * For offline mode: generated JSON string from OfflineStyleGenerator
     *
     * @return A style URI string or JSON string.
     */
    fun getStyleUri(): String {
        return when (val mode = _mapMode.value) {
            is MapMode.Online -> "asset://styles/${mode.tileServer.id}.json"
            is MapMode.Offline -> OfflineStyleGenerator.generateOfflineStyle(mode.mbtilesPath)
        }
    }

    /**
     * Returns GeoJSON for rendering all region boundaries as map overlays.
     *
     * @return A GeoJSON FeatureCollection string, or null if no regions exist.
     */
    fun getRegionBoundariesGeoJson(): String? {
        val regionList = regions.value
        if (regionList.isEmpty()) return null
        return OfflineStyleGenerator.generateBoundaryCollection(
            regionList.map { it.boundingBox }
        )
    }

    /**
     * Restores camera position and tile source from DataStore.
     */
    private suspend fun restoreCameraPosition() {
        val prefs = dataStore.data.first()
        val latitude = prefs[KEY_LATITUDE] ?: CameraState.DEFAULT_LATITUDE
        val longitude = prefs[KEY_LONGITUDE] ?: CameraState.DEFAULT_LONGITUDE
        val zoom = prefs[KEY_ZOOM] ?: CameraState.DEFAULT_ZOOM
        _cameraState.value = CameraState(latitude, longitude, zoom)

        val tileSourceId = prefs[KEY_TILE_SOURCE]
        if (tileSourceId != null) {
            val server = TileServer.ALL.find { it.id == tileSourceId }
            if (server != null) {
                _mapMode.value = MapMode.Online(server)
            }
        }
    }

    companion object {
        private val KEY_LATITUDE = doublePreferencesKey("lastLatitude")
        private val KEY_LONGITUDE = doublePreferencesKey("lastLongitude")
        private val KEY_ZOOM = doublePreferencesKey("lastZoom")
        private val KEY_TILE_SOURCE = stringPreferencesKey("tileSourceId")
    }
}
