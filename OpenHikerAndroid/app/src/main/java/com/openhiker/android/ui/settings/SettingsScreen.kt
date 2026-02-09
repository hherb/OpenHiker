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

package com.openhiker.android.ui.settings

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.openhiker.android.data.repository.GpsAccuracyMode
import com.openhiker.android.data.repository.UnitSystem
import com.openhiker.core.model.TileServer
import com.openhiker.core.util.FormatUtils
import kotlin.math.roundToInt

/**
 * Settings screen for user preferences and app configuration.
 *
 * Provides seven settings sections:
 * - Map: Default tile server selection
 * - GPS: Accuracy mode (high/balanced/low power)
 * - Navigation: Units, haptics, audio cues, screen-on
 * - Downloads: Default zoom range, concurrent download limit
 * - Cloud Sync: Folder selection, enable/disable, manual sync
 * - Storage: Cache sizes and clear buttons
 * - About: Version, license, and attribution
 *
 * All settings are persisted via Jetpack DataStore through the ViewModel
 * and propagated reactively to services that consume them.
 *
 * @param viewModel The Hilt-injected ViewModel managing settings state.
 */
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val prefs = uiState.preferences
    val snackbarHostState = remember { SnackbarHostState() }

    // SAF folder picker launcher for cloud sync
    val folderPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree()
    ) { uri ->
        uri?.let { viewModel.setSyncFolder(it) }
    }

    LaunchedEffect(uiState.error) {
        val message = uiState.error ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(message)
        viewModel.clearError()
    }

    LaunchedEffect(uiState.lastSyncResult) {
        val message = uiState.lastSyncResult ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(message)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp)
            .testTag("settings_screen")
    ) {
        // ── Map Section ──────────────────────────────────────────
        SectionHeader(icon = Icons.Default.Map, title = "Map")
        MapSettingsCard(
            currentServerId = prefs.defaultTileServerId,
            onServerSelected = viewModel::setDefaultTileServer
        )

        Spacer(modifier = Modifier.height(16.dp))

        // ── GPS Section ──────────────────────────────────────────
        SectionHeader(icon = Icons.Default.MyLocation, title = "GPS")
        GpsSettingsCard(
            currentMode = prefs.gpsAccuracyMode,
            onModeSelected = viewModel::setGpsAccuracyMode
        )

        Spacer(modifier = Modifier.height(16.dp))

        // ── Navigation Section ───────────────────────────────────
        SectionHeader(icon = Icons.Default.Navigation, title = "Navigation")
        NavigationSettingsCard(
            unitSystem = prefs.unitSystem,
            hapticEnabled = prefs.hapticFeedbackEnabled,
            audioCuesEnabled = prefs.audioCuesEnabled,
            keepScreenOn = prefs.keepScreenOnDuringNavigation,
            onUnitSystemSelected = viewModel::setUnitSystem,
            onHapticToggled = viewModel::setHapticFeedbackEnabled,
            onAudioCuesToggled = viewModel::setAudioCuesEnabled,
            onKeepScreenOnToggled = viewModel::setKeepScreenOnDuringNavigation
        )

        Spacer(modifier = Modifier.height(16.dp))

        // ── Downloads Section ────────────────────────────────────
        SectionHeader(icon = Icons.Default.Download, title = "Downloads")
        DownloadSettingsCard(
            minZoom = prefs.defaultMinZoom,
            maxZoom = prefs.defaultMaxZoom,
            concurrentDownloads = prefs.concurrentDownloadLimit,
            onMinZoomChanged = viewModel::setDefaultMinZoom,
            onMaxZoomChanged = viewModel::setDefaultMaxZoom,
            onConcurrentDownloadsChanged = viewModel::setConcurrentDownloadLimit
        )

        Spacer(modifier = Modifier.height(16.dp))

        // ── Cloud Sync Section ───────────────────────────────────
        SectionHeader(icon = Icons.Default.Cloud, title = "Cloud Sync")
        CloudSyncCard(
            syncEnabled = prefs.syncEnabled,
            syncFolderName = uiState.syncFolderDisplayName,
            isSyncing = uiState.isSyncing,
            hasSyncFolder = prefs.syncFolderUri != null,
            onSyncToggled = viewModel::setSyncEnabled,
            onSelectFolder = { folderPicker.launch(null) },
            onSyncNow = viewModel::syncNow
        )

        Spacer(modifier = Modifier.height(16.dp))

        // ── Storage Section ──────────────────────────────────────
        SectionHeader(icon = Icons.Default.Storage, title = "Storage")
        StorageCard(
            totalRegionSize = uiState.totalRegionSizeBytes,
            elevationCacheSize = uiState.elevationCacheSizeBytes,
            osmCacheSize = uiState.osmCacheSizeBytes,
            onClearElevationCache = viewModel::clearElevationCache,
            onClearOsmCache = viewModel::clearOsmCache
        )

        Spacer(modifier = Modifier.height(16.dp))

        // ── About Section ────────────────────────────────────────
        SectionHeader(icon = Icons.Default.Info, title = "About")
        AboutCard()

        Spacer(modifier = Modifier.height(16.dp))

        SnackbarHost(snackbarHostState)
    }
}

// ── Map Settings Card ────────────────────────────────────────────

/**
 * Card for selecting the default tile server used for map display.
 *
 * @param currentServerId The currently selected tile server ID.
 * @param onServerSelected Callback when a new tile server is chosen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MapSettingsCard(
    currentServerId: String,
    onServerSelected: (TileServer) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val currentServer = TileServer.ALL.find { it.id == currentServerId } ?: TileServer.OPEN_TOPO_MAP

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("map_settings_card"),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Default Tile Server",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = "Used for online map browsing and new downloads",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(8.dp))

            ExposedDropdownMenuBox(
                expanded = expanded,
                onExpandedChange = { expanded = it }
            ) {
                TextField(
                    value = currentServer.displayName,
                    onValueChange = {},
                    readOnly = true,
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                    modifier = Modifier
                        .menuAnchor(MenuAnchorType.PrimaryNotEditable)
                        .fillMaxWidth()
                        .semantics {
                            contentDescription = "Tile server: ${currentServer.displayName}"
                        }
                )
                ExposedDropdownMenu(
                    expanded = expanded,
                    onDismissRequest = { expanded = false }
                ) {
                    TileServer.ALL.forEach { server ->
                        DropdownMenuItem(
                            text = { Text(server.displayName) },
                            onClick = {
                                onServerSelected(server)
                                expanded = false
                            },
                            modifier = Modifier.semantics {
                                contentDescription = "Select ${server.displayName}"
                            }
                        )
                    }
                }
            }
        }
    }
}

// ── GPS Settings Card ────────────────────────────────────────────

/**
 * Card for selecting the GPS accuracy mode.
 *
 * @param currentMode The currently selected GPS accuracy mode.
 * @param onModeSelected Callback when a new mode is chosen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GpsSettingsCard(
    currentMode: GpsAccuracyMode,
    onModeSelected: (GpsAccuracyMode) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("gps_settings_card"),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Accuracy Mode",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = "Higher accuracy uses more battery",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(8.dp))

            ExposedDropdownMenuBox(
                expanded = expanded,
                onExpandedChange = { expanded = it }
            ) {
                TextField(
                    value = currentMode.displayName,
                    onValueChange = {},
                    readOnly = true,
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                    modifier = Modifier
                        .menuAnchor(MenuAnchorType.PrimaryNotEditable)
                        .fillMaxWidth()
                        .semantics {
                            contentDescription = "GPS accuracy: ${currentMode.displayName}"
                        }
                )
                ExposedDropdownMenu(
                    expanded = expanded,
                    onDismissRequest = { expanded = false }
                ) {
                    GpsAccuracyMode.entries.forEach { mode ->
                        DropdownMenuItem(
                            text = {
                                Column {
                                    Text(mode.displayName)
                                    Text(
                                        text = "${mode.intervalMs / 1000}s interval, ${mode.minDisplacementMetres.toInt()}m displacement",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            },
                            onClick = {
                                onModeSelected(mode)
                                expanded = false
                            }
                        )
                    }
                }
            }
        }
    }
}

// ── Navigation Settings Card ─────────────────────────────────────

/**
 * Card for navigation-related settings: units, haptics, audio, screen-on.
 *
 * @param unitSystem Current unit system (metric/imperial).
 * @param hapticEnabled Whether haptic feedback is on.
 * @param audioCuesEnabled Whether audio cues are on.
 * @param keepScreenOn Whether screen stays on during navigation.
 * @param onUnitSystemSelected Callback for unit system change.
 * @param onHapticToggled Callback for haptic toggle.
 * @param onAudioCuesToggled Callback for audio cues toggle.
 * @param onKeepScreenOnToggled Callback for screen-on toggle.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NavigationSettingsCard(
    unitSystem: UnitSystem,
    hapticEnabled: Boolean,
    audioCuesEnabled: Boolean,
    keepScreenOn: Boolean,
    onUnitSystemSelected: (UnitSystem) -> Unit,
    onHapticToggled: (Boolean) -> Unit,
    onAudioCuesToggled: (Boolean) -> Unit,
    onKeepScreenOnToggled: (Boolean) -> Unit
) {
    var unitExpanded by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("navigation_settings_card"),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Unit system
            Text(
                text = "Unit System",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(4.dp))

            ExposedDropdownMenuBox(
                expanded = unitExpanded,
                onExpandedChange = { unitExpanded = it }
            ) {
                TextField(
                    value = unitSystem.displayName,
                    onValueChange = {},
                    readOnly = true,
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = unitExpanded) },
                    modifier = Modifier
                        .menuAnchor(MenuAnchorType.PrimaryNotEditable)
                        .fillMaxWidth()
                        .semantics {
                            contentDescription = "Unit system: ${unitSystem.displayName}"
                        }
                )
                ExposedDropdownMenu(
                    expanded = unitExpanded,
                    onDismissRequest = { unitExpanded = false }
                ) {
                    UnitSystem.entries.forEach { system ->
                        DropdownMenuItem(
                            text = { Text(system.displayName) },
                            onClick = {
                                onUnitSystemSelected(system)
                                unitExpanded = false
                            }
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))
            HorizontalDivider()
            Spacer(modifier = Modifier.height(12.dp))

            // Haptic feedback toggle
            SettingsToggleRow(
                title = "Haptic Feedback",
                subtitle = "Vibrate on turns, off-route, and arrival",
                checked = hapticEnabled,
                onCheckedChange = onHapticToggled,
                testTag = "haptic_toggle"
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Audio cues toggle
            SettingsToggleRow(
                title = "Audio Cues",
                subtitle = "Play sounds for navigation events (accessibility)",
                checked = audioCuesEnabled,
                onCheckedChange = onAudioCuesToggled,
                testTag = "audio_cues_toggle"
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Keep screen on toggle
            SettingsToggleRow(
                title = "Keep Screen On",
                subtitle = "Prevent screen sleep during active navigation",
                checked = keepScreenOn,
                onCheckedChange = onKeepScreenOnToggled,
                testTag = "keep_screen_on_toggle"
            )
        }
    }
}

// ── Download Settings Card ───────────────────────────────────────

/**
 * Card for tile download defaults: zoom range and concurrency.
 *
 * @param minZoom Current default minimum zoom level.
 * @param maxZoom Current default maximum zoom level.
 * @param concurrentDownloads Current concurrent download limit.
 * @param onMinZoomChanged Callback when min zoom changes.
 * @param onMaxZoomChanged Callback when max zoom changes.
 * @param onConcurrentDownloadsChanged Callback when concurrent limit changes.
 */
@Composable
private fun DownloadSettingsCard(
    minZoom: Int,
    maxZoom: Int,
    concurrentDownloads: Int,
    onMinZoomChanged: (Int) -> Unit,
    onMaxZoomChanged: (Int) -> Unit,
    onConcurrentDownloadsChanged: (Int) -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("download_settings_card"),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Min zoom slider
            Text(
                text = "Default Minimum Zoom: $minZoom",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Slider(
                value = minZoom.toFloat(),
                onValueChange = { onMinZoomChanged(it.roundToInt()) },
                valueRange = 1f..18f,
                steps = 16,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics {
                        contentDescription = "Minimum zoom level: $minZoom"
                    }
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Max zoom slider
            Text(
                text = "Default Maximum Zoom: $maxZoom",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Slider(
                value = maxZoom.toFloat(),
                onValueChange = { onMaxZoomChanged(it.roundToInt()) },
                valueRange = 1f..18f,
                steps = 16,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics {
                        contentDescription = "Maximum zoom level: $maxZoom"
                    }
            )

            Spacer(modifier = Modifier.height(8.dp))
            HorizontalDivider()
            Spacer(modifier = Modifier.height(8.dp))

            // Concurrent downloads slider
            Text(
                text = "Concurrent Downloads: $concurrentDownloads",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = "Higher values download faster but use more bandwidth",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Slider(
                value = concurrentDownloads.toFloat(),
                onValueChange = { onConcurrentDownloadsChanged(it.roundToInt()) },
                valueRange = 2f..12f,
                steps = 9,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics {
                        contentDescription = "Concurrent downloads: $concurrentDownloads"
                    }
            )
        }
    }
}

// ── Cloud Sync Card ──────────────────────────────────────────────

/**
 * Card for cloud sync configuration: folder selection, toggle, manual sync.
 *
 * @param syncEnabled Whether automatic sync is enabled.
 * @param syncFolderName Display name of the sync folder.
 * @param isSyncing Whether a manual sync is in progress.
 * @param hasSyncFolder Whether a sync folder has been configured.
 * @param onSyncToggled Callback for sync enable/disable.
 * @param onSelectFolder Callback to launch folder picker.
 * @param onSyncNow Callback for manual sync.
 */
@Composable
private fun CloudSyncCard(
    syncEnabled: Boolean,
    syncFolderName: String,
    isSyncing: Boolean,
    hasSyncFolder: Boolean,
    onSyncToggled: (Boolean) -> Unit,
    onSelectFolder: () -> Unit,
    onSyncNow: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("cloud_sync_card"),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Enable/disable toggle
            SettingsToggleRow(
                title = "Auto Sync",
                subtitle = "Sync routes and waypoints every 15 minutes",
                checked = syncEnabled,
                onCheckedChange = onSyncToggled,
                testTag = "sync_toggle"
            )

            Spacer(modifier = Modifier.height(12.dp))
            HorizontalDivider()
            Spacer(modifier = Modifier.height(12.dp))

            // Sync folder selection
            Text(
                text = "Sync Folder",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Default.Folder,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text(
                    text = syncFolderName,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedButton(
                onClick = onSelectFolder,
                modifier = Modifier.semantics {
                    contentDescription = "Select cloud sync folder"
                }
            ) {
                Text("Select Cloud Folder")
            }

            Spacer(modifier = Modifier.height(12.dp))
            HorizontalDivider()
            Spacer(modifier = Modifier.height(12.dp))

            // Manual sync button
            Button(
                onClick = onSyncNow,
                enabled = !isSyncing && hasSyncFolder,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics {
                        contentDescription = if (isSyncing) "Syncing in progress" else "Sync now"
                    }
            ) {
                if (isSyncing) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Syncing...")
                } else {
                    Icon(Icons.Default.Sync, contentDescription = null, modifier = Modifier.size(20.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Sync Now")
                }
            }
        }
    }
}

// ── Storage Card ─────────────────────────────────────────────────

/**
 * Card displaying storage usage with clear-cache buttons.
 *
 * @param totalRegionSize Total size of all downloaded map regions in bytes.
 * @param elevationCacheSize Size of the elevation data cache in bytes.
 * @param osmCacheSize Size of the OSM data cache in bytes.
 * @param onClearElevationCache Callback to clear elevation cache.
 * @param onClearOsmCache Callback to clear OSM cache.
 */
@Composable
private fun StorageCard(
    totalRegionSize: Long,
    elevationCacheSize: Long,
    osmCacheSize: Long,
    onClearElevationCache: () -> Unit,
    onClearOsmCache: () -> Unit
) {
    val totalSize = totalRegionSize + elevationCacheSize + osmCacheSize

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("storage_card"),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Total Storage Used: ${FormatUtils.formatBytes(totalSize)}",
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold
            )

            Spacer(modifier = Modifier.height(12.dp))

            StorageRow(
                label = "Map Regions",
                size = totalRegionSize,
                showClearButton = false,
                onClear = {}
            )

            Spacer(modifier = Modifier.height(8.dp))

            StorageRow(
                label = "Elevation Cache",
                size = elevationCacheSize,
                showClearButton = elevationCacheSize > 0,
                onClear = onClearElevationCache
            )

            Spacer(modifier = Modifier.height(8.dp))

            StorageRow(
                label = "OSM Data Cache",
                size = osmCacheSize,
                showClearButton = osmCacheSize > 0,
                onClear = onClearOsmCache
            )
        }
    }
}

/**
 * A single row in the storage card showing a label, size, and optional clear button.
 *
 * @param label Category name (e.g., "Elevation Cache").
 * @param size Size in bytes.
 * @param showClearButton Whether to show the clear (delete) icon.
 * @param onClear Callback when the clear button is tapped.
 */
@Composable
private fun StorageRow(
    label: String,
    size: Long,
    showClearButton: Boolean,
    onClear: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                text = FormatUtils.formatBytes(size),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (showClearButton) {
            Icon(
                Icons.Default.Delete,
                contentDescription = "Clear $label",
                modifier = Modifier
                    .size(24.dp)
                    .clickable(onClick = onClear),
                tint = MaterialTheme.colorScheme.error
            )
        }
    }
}

// ── About Card ───────────────────────────────────────────────────

/**
 * Card showing app version, license, and attribution information.
 */
@Composable
private fun AboutCard() {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("about_card"),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "OpenHiker",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Version 1.0.0",
                style = MaterialTheme.typography.bodyMedium
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "License: GNU Affero General Public License v3.0 (AGPL-3.0)",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Copyright \u00a9 2024 - 2026 Dr Horst Herb",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(8.dp))
            HorizontalDivider()
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Source Code: github.com/hherb/OpenHiker",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Map Data",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "\u00a9 OpenStreetMap contributors\n" +
                    "\u00a9 OpenTopoMap (CC-BY-SA)\n" +
                    "CyclOSM \u2022 Elevation: SRTM/Mapzen Skadi",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

// ── Reusable Components ──────────────────────────────────────────

/**
 * Section header with an icon and title for settings groups.
 *
 * @param icon The Material icon to display.
 * @param title The section title text.
 */
@Composable
private fun SectionHeader(
    icon: ImageVector,
    title: String
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.padding(vertical = 8.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.primary
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold
        )
    }
}

/**
 * Reusable row with a title, subtitle, and toggle switch.
 *
 * @param title Primary text label.
 * @param subtitle Secondary description text.
 * @param checked Current toggle state.
 * @param onCheckedChange Callback when the toggle changes.
 * @param testTag Optional test tag for UI testing.
 */
@Composable
private fun SettingsToggleRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    testTag: String = ""
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (testTag.isNotEmpty()) Modifier.testTag(testTag) else Modifier),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge
            )
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            modifier = Modifier.semantics {
                contentDescription = "$title: ${if (checked) "enabled" else "disabled"}"
            }
        )
    }
}
