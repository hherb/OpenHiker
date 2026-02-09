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

package com.openhiker.android.ui.waypoints

import android.graphics.BitmapFactory
import android.location.Location
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.openhiker.android.data.db.waypoints.WaypointSummary
import com.openhiker.core.geo.Haversine
import com.openhiker.core.model.WaypointCategory

/**
 * Waypoint list screen displaying all saved waypoints with category filtering.
 *
 * Features:
 * - **Category filter chips**: multi-select chips at the top for filtering by [WaypointCategory].
 *   When no chips are selected, all waypoints are shown.
 * - **Scrollable waypoint list**: each row shows thumbnail (or category icon fallback),
 *   waypoint name, category badge, and distance from current location.
 * - **Tap to navigate**: tapping a waypoint row navigates to [WaypointDetailScreen].
 * - **Swipe-to-delete**: swiping a row left reveals a red delete background.
 *   A confirmation dialog is shown before the waypoint is permanently deleted.
 * - **FAB**: floating action button navigates to [AddWaypointScreen].
 * - **Empty state**: displayed when no waypoints exist (or none match the filter).
 *
 * @param onNavigateToDetail Callback to navigate to the detail screen for a waypoint.
 *   Receives the waypoint UUID as a [String].
 * @param onNavigateToAdd Callback to navigate to the add waypoint screen.
 * @param viewModel The shared [WaypointViewModel] providing waypoint data and actions.
 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun WaypointListScreen(
    onNavigateToDetail: (String) -> Unit,
    onNavigateToAdd: () -> Unit = {},
    viewModel: WaypointViewModel = hiltViewModel()
) {
    val waypoints by viewModel.filteredWaypoints.collectAsState()
    val selectedCategories by viewModel.selectedCategories.collectAsState()
    val currentLocation by viewModel.currentLocation.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()

    val snackbarHostState = remember { SnackbarHostState() }

    // Show error messages as snackbar
    LaunchedEffect(errorMessage) {
        errorMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearError()
        }
    }

    // Deletion confirmation dialog state
    var waypointPendingDelete by remember { mutableStateOf<WaypointSummary?>(null) }

    // Delete confirmation dialog
    waypointPendingDelete?.let { waypoint ->
        DeleteWaypointDialog(
            waypointLabel = waypoint.label,
            onConfirm = {
                viewModel.deleteWaypoint(waypoint.id)
                waypointPendingDelete = null
            },
            onDismiss = { waypointPendingDelete = null }
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        floatingActionButton = {
            FloatingActionButton(onClick = onNavigateToAdd) {
                Icon(Icons.Default.Add, contentDescription = "Add waypoint")
            }
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            // Category filter chips
            CategoryFilterChips(
                selectedCategories = selectedCategories,
                onToggleCategory = { viewModel.toggleCategory(it) },
                onClearAll = { viewModel.clearCategoryFilter() },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp)
            )

            if (waypoints.isEmpty()) {
                // Empty state
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(16.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            Icons.Default.LocationOn,
                            contentDescription = null,
                            modifier = Modifier
                                .size(48.dp)
                                .padding(bottom = 16.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            text = if (selectedCategories.isEmpty()) {
                                "No waypoints saved"
                            } else {
                                "No waypoints match the selected categories"
                            },
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = if (selectedCategories.isEmpty()) {
                                "Tap + to add a waypoint at your current location"
                            } else {
                                "Try clearing the category filter"
                            },
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            } else {
                // Waypoint list
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(waypoints, key = { it.id }) { waypoint ->
                        SwipeToDeleteWaypointRow(
                            waypoint = waypoint,
                            currentLocation = currentLocation,
                            onClick = { onNavigateToDetail(waypoint.id) },
                            onDelete = { waypointPendingDelete = waypoint }
                        )
                    }

                    // FAB clearance
                    item { Spacer(modifier = Modifier.height(80.dp)) }
                }
            }
        }
    }
}

/**
 * Multi-select category filter chips displayed as a flow row.
 *
 * Each chip represents a [WaypointCategory]. Tapping a chip toggles its
 * selection. When at least one chip is selected, a "Clear" chip appears
 * to deselect all categories at once.
 *
 * @param selectedCategories The currently selected categories.
 * @param onToggleCategory Callback when a category chip is tapped.
 * @param onClearAll Callback to clear all selected categories.
 * @param modifier Modifier for the flow row container.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CategoryFilterChips(
    selectedCategories: Set<WaypointCategory>,
    onToggleCategory: (WaypointCategory) -> Unit,
    onClearAll: () -> Unit,
    modifier: Modifier = Modifier
) {
    FlowRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        // Show "Clear" chip when filters are active
        if (selectedCategories.isNotEmpty()) {
            FilterChip(
                selected = false,
                onClick = onClearAll,
                label = { Text("Clear") },
                colors = FilterChipDefaults.filterChipColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer,
                    labelColor = MaterialTheme.colorScheme.onErrorContainer
                )
            )
        }

        WaypointCategory.entries.forEach { category ->
            val isSelected = selectedCategories.contains(category)
            val chipColor = try {
                Color(android.graphics.Color.parseColor("#${category.colorHex}"))
            } catch (e: IllegalArgumentException) {
                MaterialTheme.colorScheme.primary
            }

            FilterChip(
                selected = isSelected,
                onClick = { onToggleCategory(category) },
                label = { Text(category.displayName) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = chipColor.copy(alpha = 0.2f),
                    selectedLabelColor = chipColor
                )
            )
        }
    }
}

/**
 * A waypoint row wrapped in a swipe-to-dismiss container.
 *
 * Swiping the row to the left reveals a red delete background. When the
 * swipe completes, the [onDelete] callback fires (which should show a
 * confirmation dialog rather than immediately deleting).
 *
 * @param waypoint The waypoint summary to display.
 * @param currentLocation The user's current GPS location for distance calculation, or null.
 * @param onClick Callback when the row is tapped (navigate to detail).
 * @param onDelete Callback when the row is swiped to delete.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeToDeleteWaypointRow(
    waypoint: WaypointSummary,
    currentLocation: Location?,
    onClick: () -> Unit,
    onDelete: () -> Unit
) {
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { dismissValue ->
            if (dismissValue == SwipeToDismissBoxValue.EndToStart) {
                onDelete()
                false // Don't auto-dismiss; wait for confirmation dialog
            } else {
                false
            }
        }
    )

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            // Red delete background revealed on swipe
            val backgroundColor by animateColorAsState(
                targetValue = if (dismissState.targetValue == SwipeToDismissBoxValue.EndToStart) {
                    MaterialTheme.colorScheme.error
                } else {
                    Color.Transparent
                },
                label = "swipe_bg_color"
            )
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clip(RoundedCornerShape(12.dp))
                    .background(backgroundColor)
                    .padding(horizontal = 20.dp),
                contentAlignment = Alignment.CenterEnd
            ) {
                Icon(
                    Icons.Default.Delete,
                    contentDescription = "Delete",
                    tint = MaterialTheme.colorScheme.onError
                )
            }
        },
        enableDismissFromStartToEnd = false
    ) {
        WaypointRow(
            waypoint = waypoint,
            currentLocation = currentLocation,
            onClick = onClick
        )
    }
}

/**
 * A single waypoint row displayed in the list.
 *
 * Shows:
 * - Thumbnail image if available, otherwise a coloured category icon placeholder.
 * - Waypoint label (name).
 * - Category display name with its associated colour.
 * - Distance from the user's current location (if available).
 *
 * @param waypoint The waypoint summary data to display.
 * @param currentLocation The user's current GPS location, or null if unavailable.
 * @param onClick Callback when the row is tapped.
 */
@Composable
private fun WaypointRow(
    waypoint: WaypointSummary,
    currentLocation: Location?,
    onClick: () -> Unit
) {
    val category = resolveCategory(waypoint.category)
    val categoryColor = parseCategoryColor(category)
    val distanceText = formatDistanceFromLocation(
        currentLocation = currentLocation,
        waypointLat = waypoint.latitude,
        waypointLon = waypoint.longitude
    )

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Thumbnail or category icon placeholder
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(categoryColor.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Default.LocationOn,
                    contentDescription = category.displayName,
                    tint = categoryColor,
                    modifier = Modifier.size(24.dp)
                )
            }

            Spacer(modifier = Modifier.width(12.dp))

            // Waypoint info
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = waypoint.label,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = category.displayName,
                    style = MaterialTheme.typography.bodySmall,
                    color = categoryColor
                )
            }

            // Distance from current location
            if (distanceText != null) {
                Text(
                    text = distanceText,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

/**
 * Confirmation dialog shown before permanently deleting a waypoint.
 *
 * @param waypointLabel The name of the waypoint to delete.
 * @param onConfirm Callback when the user confirms deletion.
 * @param onDismiss Callback when the dialog is dismissed.
 */
@Composable
private fun DeleteWaypointDialog(
    waypointLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Delete Waypoint") },
        text = {
            Text("Delete \"$waypointLabel\"? This will permanently remove the waypoint and any associated photos.")
        },
        confirmButton = {
            Button(onClick = onConfirm) {
                Text("Delete")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

// ── Utility functions ───────────────────────────────────────────────

/**
 * Resolves a category string (from the database) to a [WaypointCategory] enum value.
 *
 * Falls back to [WaypointCategory.CUSTOM] if the string does not match any known category.
 *
 * @param categoryName The raw category name from the database.
 * @return The matching [WaypointCategory], or [WaypointCategory.CUSTOM] as fallback.
 */
private fun resolveCategory(categoryName: String): WaypointCategory {
    return try {
        WaypointCategory.valueOf(categoryName)
    } catch (e: IllegalArgumentException) {
        WaypointCategory.CUSTOM
    }
}

/**
 * Parses the hex colour code from a [WaypointCategory] into a Compose [Color].
 *
 * Falls back to medium grey if the hex code is invalid.
 *
 * @param category The waypoint category with a [WaypointCategory.colorHex] field.
 * @return The parsed [Color].
 */
private fun parseCategoryColor(category: WaypointCategory): Color {
    return try {
        Color(android.graphics.Color.parseColor("#${category.colorHex}"))
    } catch (e: IllegalArgumentException) {
        Color.Gray
    }
}

/**
 * Formats the distance from the user's current location to a waypoint.
 *
 * Returns a human-readable string like "1.2 km" or "450 m". Returns null
 * if the current location is not available.
 *
 * @param currentLocation The user's current GPS location, or null.
 * @param waypointLat The waypoint latitude in decimal degrees.
 * @param waypointLon The waypoint longitude in decimal degrees.
 * @return Formatted distance string, or null if location is unavailable.
 */
private fun formatDistanceFromLocation(
    currentLocation: Location?,
    waypointLat: Double,
    waypointLon: Double
): String? {
    currentLocation ?: return null
    val distanceMetres = Haversine.distance(
        currentLocation.latitude, currentLocation.longitude,
        waypointLat, waypointLon
    )
    return if (distanceMetres >= METRES_PER_KILOMETRE) {
        "%.1f km".format(distanceMetres / METRES_PER_KILOMETRE)
    } else {
        "%.0f m".format(distanceMetres)
    }
}

/** Number of metres in one kilometre, used for distance formatting. */
private const val METRES_PER_KILOMETRE = 1000.0
