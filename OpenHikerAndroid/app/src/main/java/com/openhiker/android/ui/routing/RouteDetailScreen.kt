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

package com.openhiker.android.ui.routing

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.openhiker.android.ui.components.ElevationProfileChart
import com.openhiker.android.ui.export.ExportSheet
import com.openhiker.core.model.ElevationPoint
import com.openhiker.core.model.HikeStatsFormatter
import com.openhiker.core.model.TurnInstruction

/**
 * Route detail screen for viewing a planned route.
 *
 * Displays a comprehensive overview of a planned route including:
 * - A map placeholder with a note about route polyline rendering
 * - Turn-by-turn instruction list (scrollable)
 * - Elevation profile chart
 * - Statistics: total distance, elevation gain/loss, estimated time
 * - "Start Navigation" button to begin turn-by-turn guidance
 * - Overflow menu with rename, delete, and export options
 *
 * This screen loads a planned route by its ID via [RouteDetailViewModel].
 *
 * @param onStartNavigation Callback invoked with the route ID when the user
 *        taps "Start Navigation". The caller should navigate to the NavigationScreen.
 * @param onNavigateBack Callback invoked when the user taps the back button
 *        or after a successful delete.
 * @param viewModel The Hilt-injected ViewModel managing route data and operations.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RouteDetailScreen(
    onStartNavigation: (String) -> Unit,
    onNavigateBack: () -> Unit,
    viewModel: RouteDetailViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val instructions by viewModel.instructions.collectAsState()
    val elevationProfile by viewModel.elevationProfile.collectAsState()

    var showOverflowMenu by remember { mutableStateOf(false) }
    var showRenameDialog by remember { mutableStateOf(false) }
    var showDeleteDialog by remember { mutableStateOf(false) }
    var showExportSheet by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = uiState.routeName,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Navigate back"
                        )
                    }
                },
                actions = {
                    // Export button
                    IconButton(onClick = { showExportSheet = true }) {
                        Icon(
                            imageVector = Icons.Default.Share,
                            contentDescription = "Export route"
                        )
                    }
                    // Overflow menu
                    Box {
                        IconButton(onClick = { showOverflowMenu = true }) {
                            Icon(
                                imageVector = Icons.Default.MoreVert,
                                contentDescription = "More options"
                            )
                        }
                        DropdownMenu(
                            expanded = showOverflowMenu,
                            onDismissRequest = { showOverflowMenu = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text("Rename") },
                                onClick = {
                                    showOverflowMenu = false
                                    showRenameDialog = true
                                },
                                leadingIcon = {
                                    Icon(
                                        imageVector = Icons.Default.Edit,
                                        contentDescription = null
                                    )
                                }
                            )
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        "Delete",
                                        color = MaterialTheme.colorScheme.error
                                    )
                                },
                                onClick = {
                                    showOverflowMenu = false
                                    showDeleteDialog = true
                                },
                                leadingIcon = {
                                    Icon(
                                        imageVector = Icons.Default.Delete,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.error
                                    )
                                }
                            )
                        }
                    }
                }
            )
        }
    ) { paddingValues ->
        when {
            uiState.isLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(paddingValues),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            }

            uiState.errorMessage != null -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(paddingValues),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = uiState.errorMessage ?: "Unknown error",
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodyLarge
                    )
                }
            }

            else -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(paddingValues)
                        .padding(horizontal = SCREEN_HORIZONTAL_PADDING.dp),
                    verticalArrangement = Arrangement.spacedBy(SECTION_SPACING.dp)
                ) {
                    // Map placeholder
                    item {
                        Spacer(modifier = Modifier.height(SECTION_SPACING.dp))
                        RouteMapPlaceholder()
                    }

                    // Statistics card
                    item {
                        RouteStatisticsCard(
                            distance = uiState.totalDistance,
                            elevationGain = uiState.elevationGain,
                            elevationLoss = uiState.elevationLoss,
                            estimatedDuration = uiState.estimatedDuration,
                            mode = uiState.routingMode
                        )
                    }

                    // Start Navigation button
                    item {
                        Button(
                            onClick = { onStartNavigation(uiState.routeId) },
                            modifier = Modifier.fillMaxWidth(),
                            enabled = uiState.routeId.isNotBlank()
                        ) {
                            Icon(
                                imageVector = Icons.Default.Navigation,
                                contentDescription = null
                            )
                            Spacer(modifier = Modifier.width(BUTTON_ICON_SPACING.dp))
                            Text("Start Navigation")
                        }
                    }

                    // Elevation profile
                    if (elevationProfile.isNotEmpty()) {
                        item {
                            ElevationProfileSection(elevationProfile = elevationProfile)
                        }
                    }

                    // Turn-by-turn instructions header
                    if (instructions.isNotEmpty()) {
                        item {
                            Text(
                                text = "Turn-by-Turn Instructions (${instructions.size})",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold
                            )
                        }

                        // Turn instruction rows
                        itemsIndexed(
                            items = instructions,
                            key = { _, instruction -> instruction.id }
                        ) { index, instruction ->
                            TurnInstructionRow(
                                index = index + 1,
                                instruction = instruction
                            )
                            if (index < instructions.lastIndex) {
                                HorizontalDivider(
                                    modifier = Modifier.padding(
                                        vertical = DIVIDER_VERTICAL_PADDING.dp
                                    )
                                )
                            }
                        }

                        // Bottom spacer for scrolling clearance
                        item {
                            Spacer(modifier = Modifier.height(BOTTOM_SPACER_HEIGHT.dp))
                        }
                    }
                }
            }
        }
    }

    // Rename dialog
    if (showRenameDialog) {
        RenameRouteDialog(
            currentName = uiState.routeName,
            onDismiss = { showRenameDialog = false },
            onConfirm = { newName ->
                viewModel.renameRoute(newName)
                showRenameDialog = false
            }
        )
    }

    // Delete confirmation dialog
    if (showDeleteDialog) {
        DeleteRouteDialog(
            routeName = uiState.routeName,
            onDismiss = { showDeleteDialog = false },
            onConfirm = {
                viewModel.deleteRoute()
                showDeleteDialog = false
                onNavigateBack()
            }
        )
    }

    // Export bottom sheet
    if (showExportSheet) {
        ExportSheet(
            onDismiss = { showExportSheet = false },
            routeId = uiState.routeId,
            hikeId = null
        )
    }
}

/**
 * Map placeholder showing where the route polyline will be rendered.
 *
 * Displays a placeholder box with a map icon and a note about future
 * map integration with route polyline overlay.
 */
@Composable
private fun RouteMapPlaceholder() {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .height(MAP_PLACEHOLDER_HEIGHT.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    imageVector = Icons.Default.Map,
                    contentDescription = null,
                    modifier = Modifier.size(MAP_ICON_SIZE.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(ICON_TEXT_SPACING.dp))
                Text(
                    text = "Map with route polyline",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = "MapLibre integration pending",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(
                        alpha = SECONDARY_TEXT_ALPHA
                    )
                )
            }
        }
    }
}

/**
 * Card displaying route statistics: distance, elevation, estimated time.
 *
 * Shows a 2x2 grid of key route metrics with labels and formatted values.
 *
 * @param distance Total route distance in metres.
 * @param elevationGain Cumulative elevation gain in metres.
 * @param elevationLoss Cumulative elevation loss in metres.
 * @param estimatedDuration Estimated travel time in seconds.
 * @param mode Routing mode (hiking or cycling) for display context.
 */
@Composable
private fun RouteStatisticsCard(
    distance: Double,
    elevationGain: Double,
    elevationLoss: Double,
    estimatedDuration: Double,
    mode: String
) {
    Card(
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(CARD_PADDING.dp)) {
            Text(
                text = "Route Statistics",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = "Mode: ${mode.replaceFirstChar { it.uppercase() }}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(modifier = Modifier.height(STATS_VERTICAL_SPACING.dp))

            // First row: Distance and Estimated Time
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                StatisticItem(
                    label = "Distance",
                    value = HikeStatsFormatter.formatDistance(distance, true),
                    modifier = Modifier.weight(1f)
                )
                StatisticItem(
                    label = "Est. Time",
                    value = HikeStatsFormatter.formatDuration(estimatedDuration),
                    modifier = Modifier.weight(1f)
                )
            }

            Spacer(modifier = Modifier.height(STATS_VERTICAL_SPACING.dp))

            // Second row: Elevation Gain and Loss
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                StatisticItem(
                    label = "Elevation Gain",
                    value = HikeStatsFormatter.formatElevation(elevationGain, true),
                    modifier = Modifier.weight(1f)
                )
                StatisticItem(
                    label = "Elevation Loss",
                    value = HikeStatsFormatter.formatElevation(elevationLoss, true),
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

/**
 * Single statistic label+value pair for the statistics card.
 *
 * @param label Description label (e.g., "Distance").
 * @param value Formatted value (e.g., "12.3 km").
 * @param modifier Modifier for layout.
 */
@Composable
private fun StatisticItem(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier) {
        Text(
            text = value,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

/**
 * Elevation profile section with chart.
 *
 * Wraps the [ElevationProfileChart] composable in a section with a title.
 * The chart renders the elevation data along the route distance.
 *
 * @param elevationProfile Pre-computed elevation profile data points.
 */
@Composable
private fun ElevationProfileSection(elevationProfile: List<ElevationPoint>) {
    Column {
        Text(
            text = "Elevation Profile",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(ICON_TEXT_SPACING.dp))
        ElevationProfileChart(
            elevationProfile = elevationProfile,
            modifier = Modifier
                .fillMaxWidth()
                .height(ELEVATION_CHART_HEIGHT.dp)
        )
    }
}

/**
 * A single row in the turn-by-turn instruction list.
 *
 * Displays the instruction index, direction verb, description text,
 * and the distance from the previous instruction.
 *
 * @param index The 1-based instruction number for display.
 * @param instruction The turn instruction data.
 */
@Composable
private fun TurnInstructionRow(
    index: Int,
    instruction: TurnInstruction
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = INSTRUCTION_ROW_VERTICAL_PADDING.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Step number badge
        Box(
            modifier = Modifier
                .size(STEP_BADGE_SIZE.dp)
                .background(
                    color = MaterialTheme.colorScheme.primaryContainer,
                    shape = MaterialTheme.shapes.small
                ),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "$index",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
                fontWeight = FontWeight.Bold
            )
        }

        Spacer(modifier = Modifier.width(INSTRUCTION_HORIZONTAL_SPACING.dp))

        // Direction verb and description
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = instruction.direction.verb,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            if (instruction.description.isNotBlank()) {
                Text(
                    text = instruction.description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Spacer(modifier = Modifier.width(INSTRUCTION_HORIZONTAL_SPACING.dp))

        // Distance from previous instruction
        Text(
            text = HikeStatsFormatter.formatDistance(
                instruction.distanceFromPrevious, true
            ),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

/**
 * Dialog for renaming a planned route.
 *
 * Presents a text field pre-filled with the current route name. The confirm
 * button is disabled when the input is blank to prevent empty names.
 *
 * @param currentName The current route name to pre-fill.
 * @param onDismiss Called when the dialog is cancelled.
 * @param onConfirm Called with the new name when the user confirms.
 */
@Composable
private fun RenameRouteDialog(
    currentName: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit
) {
    var newName by remember { mutableStateOf(currentName) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Rename Route") },
        text = {
            OutlinedTextField(
                value = newName,
                onValueChange = { newName = it },
                label = { Text("Route name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(newName) },
                enabled = newName.isNotBlank()
            ) {
                Text("Rename")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

/**
 * Confirmation dialog for deleting a planned route.
 *
 * Warns the user that the action is irreversible and shows the route name
 * for confirmation.
 *
 * @param routeName The name of the route to be deleted.
 * @param onDismiss Called when the dialog is cancelled.
 * @param onConfirm Called when the user confirms deletion.
 */
@Composable
private fun DeleteRouteDialog(
    routeName: String,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Delete Route?") },
        text = {
            Text("Are you sure you want to delete \"$routeName\"? This action cannot be undone.")
        },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text("Delete", color = MaterialTheme.colorScheme.error)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

// --- Layout Constants ---

/** Horizontal padding for the screen content. */
private const val SCREEN_HORIZONTAL_PADDING = 16

/** Vertical spacing between sections in the LazyColumn. */
private const val SECTION_SPACING = 16

/** Height of the map placeholder card in dp. */
private const val MAP_PLACEHOLDER_HEIGHT = 200

/** Size of the map icon in the placeholder. */
private const val MAP_ICON_SIZE = 48

/** Spacing between icon and text. */
private const val ICON_TEXT_SPACING = 8

/** Alpha value for secondary/hint text. */
private const val SECONDARY_TEXT_ALPHA = 0.7f

/** Padding inside cards. */
private const val CARD_PADDING = 16

/** Vertical spacing between statistic rows. */
private const val STATS_VERTICAL_SPACING = 12

/** Height of the elevation profile chart. */
private const val ELEVATION_CHART_HEIGHT = 180

/** Vertical padding for instruction rows. */
private const val INSTRUCTION_ROW_VERTICAL_PADDING = 8

/** Size of the step number badge. */
private const val STEP_BADGE_SIZE = 28

/** Horizontal spacing in instruction rows. */
private const val INSTRUCTION_HORIZONTAL_SPACING = 12

/** Vertical padding for dividers between instructions. */
private const val DIVIDER_VERTICAL_PADDING = 2

/** Bottom spacer height for scroll clearance. */
private const val BOTTOM_SPACER_HEIGHT = 32

/** Spacing between button icon and text. */
private const val BUTTON_ICON_SPACING = 8
