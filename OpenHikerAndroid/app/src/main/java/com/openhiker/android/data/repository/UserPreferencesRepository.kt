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

package com.openhiker.android.data.repository

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/** DataStore instance for user preferences. */
private val Context.userPreferencesDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "user_preferences"
)

/**
 * GPS accuracy mode controlling location update frequency and power usage.
 *
 * Maps to Android LocationRequest priorities. Higher accuracy uses
 * more battery but provides more precise position updates.
 *
 * @property id Persistence key for DataStore storage.
 * @property displayName Human-readable name for the settings UI.
 * @property intervalMs Time between GPS updates in milliseconds.
 * @property minDisplacementMetres Minimum distance between accepted updates.
 */
enum class GpsAccuracyMode(
    val id: String,
    val displayName: String,
    val intervalMs: Long,
    val minDisplacementMetres: Float
) {
    /** High accuracy: 2s updates, 5m displacement. Best for active navigation. */
    HIGH("high", "High Accuracy", 2000L, 5f),

    /** Balanced: 5s updates, 10m displacement. Good for casual hiking. */
    BALANCED("balanced", "Balanced", 5000L, 10f),

    /** Low power: 10s updates, 50m displacement. Battery saver mode. */
    LOW_POWER("low_power", "Low Power", 10000L, 50f);

    companion object {
        /** Finds a mode by its persistence ID, defaulting to [HIGH]. */
        fun fromId(id: String): GpsAccuracyMode =
            entries.find { it.id == id } ?: HIGH
    }
}

/**
 * Unit system for distance and elevation display.
 *
 * @property id Persistence key for DataStore storage.
 * @property displayName Human-readable name for the settings UI.
 */
enum class UnitSystem(val id: String, val displayName: String) {
    /** Metric: kilometres, metres. */
    METRIC("metric", "Metric (km, m)"),

    /** Imperial: miles, feet. */
    IMPERIAL("imperial", "Imperial (mi, ft)");

    companion object {
        /** Finds a unit system by its persistence ID, defaulting to [METRIC]. */
        fun fromId(id: String): UnitSystem =
            entries.find { it.id == id } ?: METRIC
    }
}

/**
 * Immutable snapshot of all user preferences.
 *
 * Collected from the DataStore [Flow] and consumed by ViewModels
 * and services to configure their behaviour. Default values match
 * the most common hiking use case.
 *
 * @property defaultTileServerId Tile server ID for map display (e.g., "opentopomap").
 * @property gpsAccuracyMode GPS accuracy/power trade-off setting.
 * @property unitSystem Metric or imperial display units.
 * @property hapticFeedbackEnabled Whether navigation vibrations are active.
 * @property audioCuesEnabled Whether audio cues play for navigation events.
 * @property defaultMinZoom Default minimum zoom level for tile downloads.
 * @property defaultMaxZoom Default maximum zoom level for tile downloads.
 * @property concurrentDownloadLimit Maximum parallel tile downloads.
 * @property syncEnabled Whether automatic cloud sync is enabled.
 * @property syncFolderUri SAF tree URI for the cloud sync folder, or null.
 * @property keepScreenOnDuringNavigation Whether to prevent screen sleep during active navigation.
 */
data class UserPreferences(
    val defaultTileServerId: String = DEFAULT_TILE_SERVER_ID,
    val gpsAccuracyMode: GpsAccuracyMode = GpsAccuracyMode.HIGH,
    val unitSystem: UnitSystem = UnitSystem.METRIC,
    val hapticFeedbackEnabled: Boolean = true,
    val audioCuesEnabled: Boolean = false,
    val defaultMinZoom: Int = DEFAULT_MIN_ZOOM,
    val defaultMaxZoom: Int = DEFAULT_MAX_ZOOM,
    val concurrentDownloadLimit: Int = DEFAULT_CONCURRENT_DOWNLOADS,
    val syncEnabled: Boolean = false,
    val syncFolderUri: String? = null,
    val keepScreenOnDuringNavigation: Boolean = true
) {
    companion object {
        /** Default tile server: OpenTopoMap. */
        const val DEFAULT_TILE_SERVER_ID = "opentopomap"

        /** Default minimum zoom for downloads. */
        const val DEFAULT_MIN_ZOOM = 12

        /** Default maximum zoom for downloads. */
        const val DEFAULT_MAX_ZOOM = 16

        /** Default number of concurrent tile downloads. */
        const val DEFAULT_CONCURRENT_DOWNLOADS = 6
    }
}

/**
 * Repository for persisting and observing user preferences via Jetpack DataStore.
 *
 * Replaces the previous SharedPreferences usage in SettingsViewModel with a
 * reactive, coroutine-native approach. All preferences are exposed as a single
 * [Flow] of [UserPreferences] so consumers automatically react to changes.
 *
 * Thread safety is guaranteed by DataStore's internal serialisation.
 *
 * @param context Application context for DataStore access.
 */
@Singleton
class UserPreferencesRepository @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val dataStore = context.userPreferencesDataStore

    /**
     * Observable stream of the current user preferences.
     *
     * Emits a new [UserPreferences] snapshot whenever any preference changes.
     * Services and ViewModels should collect this flow to react to settings changes.
     */
    val preferencesFlow: Flow<UserPreferences> = dataStore.data.map { prefs ->
        UserPreferences(
            defaultTileServerId = prefs[KEY_DEFAULT_TILE_SERVER]
                ?: UserPreferences.DEFAULT_TILE_SERVER_ID,
            gpsAccuracyMode = GpsAccuracyMode.fromId(
                prefs[KEY_GPS_ACCURACY_MODE] ?: GpsAccuracyMode.HIGH.id
            ),
            unitSystem = UnitSystem.fromId(
                prefs[KEY_UNIT_SYSTEM] ?: UnitSystem.METRIC.id
            ),
            hapticFeedbackEnabled = prefs[KEY_HAPTIC_FEEDBACK] ?: true,
            audioCuesEnabled = prefs[KEY_AUDIO_CUES] ?: false,
            defaultMinZoom = prefs[KEY_DEFAULT_MIN_ZOOM]
                ?: UserPreferences.DEFAULT_MIN_ZOOM,
            defaultMaxZoom = prefs[KEY_DEFAULT_MAX_ZOOM]
                ?: UserPreferences.DEFAULT_MAX_ZOOM,
            concurrentDownloadLimit = prefs[KEY_CONCURRENT_DOWNLOADS]
                ?: UserPreferences.DEFAULT_CONCURRENT_DOWNLOADS,
            syncEnabled = prefs[KEY_SYNC_ENABLED] ?: false,
            syncFolderUri = prefs[KEY_SYNC_FOLDER_URI],
            keepScreenOnDuringNavigation = prefs[KEY_KEEP_SCREEN_ON] ?: true
        )
    }

    /**
     * Updates the default tile server.
     *
     * @param serverId Tile server ID (e.g., "opentopomap", "cyclosm", "osm").
     */
    suspend fun setDefaultTileServer(serverId: String) {
        dataStore.edit { it[KEY_DEFAULT_TILE_SERVER] = serverId }
    }

    /**
     * Updates the GPS accuracy mode.
     *
     * @param mode The desired GPS accuracy/power trade-off.
     */
    suspend fun setGpsAccuracyMode(mode: GpsAccuracyMode) {
        dataStore.edit { it[KEY_GPS_ACCURACY_MODE] = mode.id }
    }

    /**
     * Updates the unit system for distance and elevation display.
     *
     * @param unitSystem Metric or imperial.
     */
    suspend fun setUnitSystem(unitSystem: UnitSystem) {
        dataStore.edit { it[KEY_UNIT_SYSTEM] = unitSystem.id }
    }

    /**
     * Toggles haptic feedback during navigation.
     *
     * @param enabled True to enable vibrations, false to disable.
     */
    suspend fun setHapticFeedbackEnabled(enabled: Boolean) {
        dataStore.edit { it[KEY_HAPTIC_FEEDBACK] = enabled }
    }

    /**
     * Toggles audio cues for navigation events.
     *
     * @param enabled True to enable audio cues, false to disable.
     */
    suspend fun setAudioCuesEnabled(enabled: Boolean) {
        dataStore.edit { it[KEY_AUDIO_CUES] = enabled }
    }

    /**
     * Updates the default minimum zoom level for tile downloads.
     *
     * @param zoom Minimum zoom level (typically 10-14).
     */
    suspend fun setDefaultMinZoom(zoom: Int) {
        dataStore.edit { it[KEY_DEFAULT_MIN_ZOOM] = zoom }
    }

    /**
     * Updates the default maximum zoom level for tile downloads.
     *
     * @param zoom Maximum zoom level (typically 14-18).
     */
    suspend fun setDefaultMaxZoom(zoom: Int) {
        dataStore.edit { it[KEY_DEFAULT_MAX_ZOOM] = zoom }
    }

    /**
     * Updates the concurrent tile download limit.
     *
     * @param limit Number of parallel downloads (2-12).
     */
    suspend fun setConcurrentDownloadLimit(limit: Int) {
        dataStore.edit { it[KEY_CONCURRENT_DOWNLOADS] = limit.coerceIn(2, 12) }
    }

    /**
     * Toggles automatic cloud sync.
     *
     * @param enabled True to enable periodic sync, false to disable.
     */
    suspend fun setSyncEnabled(enabled: Boolean) {
        dataStore.edit { it[KEY_SYNC_ENABLED] = enabled }
    }

    /**
     * Updates the cloud sync folder URI.
     *
     * @param uri SAF tree URI string, or null to clear.
     */
    suspend fun setSyncFolderUri(uri: String?) {
        dataStore.edit { prefs ->
            if (uri != null) {
                prefs[KEY_SYNC_FOLDER_URI] = uri
            } else {
                prefs.remove(KEY_SYNC_FOLDER_URI)
            }
        }
    }

    /**
     * Toggles the keep-screen-on setting during navigation.
     *
     * @param enabled True to keep screen awake during active navigation.
     */
    suspend fun setKeepScreenOnDuringNavigation(enabled: Boolean) {
        dataStore.edit { it[KEY_KEEP_SCREEN_ON] = enabled }
    }

    companion object {
        private val KEY_DEFAULT_TILE_SERVER = stringPreferencesKey("default_tile_server")
        private val KEY_GPS_ACCURACY_MODE = stringPreferencesKey("gps_accuracy_mode")
        private val KEY_UNIT_SYSTEM = stringPreferencesKey("unit_system")
        private val KEY_HAPTIC_FEEDBACK = booleanPreferencesKey("haptic_feedback")
        private val KEY_AUDIO_CUES = booleanPreferencesKey("audio_cues")
        private val KEY_DEFAULT_MIN_ZOOM = intPreferencesKey("default_min_zoom")
        private val KEY_DEFAULT_MAX_ZOOM = intPreferencesKey("default_max_zoom")
        private val KEY_CONCURRENT_DOWNLOADS = intPreferencesKey("concurrent_downloads")
        private val KEY_SYNC_ENABLED = booleanPreferencesKey("sync_enabled")
        private val KEY_SYNC_FOLDER_URI = stringPreferencesKey("sync_folder_uri")
        private val KEY_KEEP_SCREEN_ON = booleanPreferencesKey("keep_screen_on_navigation")
    }
}
