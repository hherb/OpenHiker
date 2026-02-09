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

package com.openhiker.android.ui.hikes

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Hiking
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Sort
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Snackbar
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

/**
 * Hike history list screen.
 *
 * Displays all saved hikes with name, date, distance, elevation gain,
 * and duration. Supports sorting by date/distance/elevation/duration,
 * text search by name, and swipe-to-delete with confirmation.
 *
 * Tapping a hike card navigates to the [HikeDetailScreen].
 *
 * @param onNavigateToDetail Callback to navigate to the hike detail screen with hike ID.
 * @param viewModel The Hilt-injected ViewModel managing the list state.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HikeListScreen(
    onNavigateToDetail: ((String) -> Unit)? = null,
    viewModel: HikeListViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // Show error in snackbar when delete or other operations fail
    LaunchedEffect(uiState.error) {
        val message = uiState.error ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(message)
        viewModel.clearError()
    }

    Box(modifier = Modifier.fillMaxSize()) {
    Column(modifier = Modifier.fillMaxSize()) {
        // Search bar and sort button
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedTextField(
                value = uiState.searchQuery,
                onValueChange = viewModel::setSearchQuery,
                placeholder = { Text("Search hikes...") },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = "Search") },
                singleLine = true,
                modifier = Modifier.weight(1f)
            )
            Spacer(modifier = Modifier.width(8.dp))
            SortButton(
                currentSort = uiState.sortOption,
                onSortSelected = viewModel::setSortOption
            )
        }

        // Content
        when {
            uiState.isLoading -> {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            }
            uiState.isEmpty -> {
                EmptyHikeList()
            }
            uiState.hikes.isEmpty() && uiState.searchQuery.isNotEmpty() -> {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "No hikes matching \"${uiState.searchQuery}\"",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            else -> {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(
                        horizontal = 16.dp, vertical = 8.dp
                    )
                ) {
                    items(
                        items = uiState.hikes,
                        key = { it.id }
                    ) { hike ->
                        SwipeToDeleteHikeCard(
                            hike = hike,
                            onClick = { onNavigateToDetail?.invoke(hike.id) },
                            onDelete = { viewModel.requestDelete(hike) }
                        )
                    }
                }
            }
        }
    }

    // Delete confirmation dialog
    uiState.deleteConfirmationHike?.let { hike ->
        DeleteHikeDialog(
            hikeName = hike.name,
            onDismiss = viewModel::dismissDelete,
            onConfirm = { viewModel.confirmDelete() }
        )
    }

    SnackbarHost(
        hostState = snackbarHostState,
        modifier = Modifier.align(Alignment.BottomCenter)
    )
    } // Box
}

/**
 * Empty state shown when no hikes have been recorded.
 */
@Composable
private fun EmptyHikeList() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = Icons.Default.Hiking,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "No hikes recorded yet",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Start a hike from the Navigate tab to begin recording",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

/**
 * Sort button with dropdown menu showing available sort criteria.
 *
 * @param currentSort The currently active sort option (shown as selected).
 * @param onSortSelected Callback when a sort option is tapped.
 */
@Composable
private fun SortButton(
    currentSort: HikeSortOption,
    onSortSelected: (HikeSortOption) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Box {
        IconButton(onClick = { expanded = true }) {
            Icon(Icons.Default.Sort, contentDescription = "Sort")
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            HikeSortOption.entries.forEach { option ->
                DropdownMenuItem(
                    text = {
                        Text(
                            text = sortOptionLabel(option),
                            fontWeight = if (option == currentSort) FontWeight.Bold else FontWeight.Normal
                        )
                    },
                    onClick = {
                        onSortSelected(option)
                        expanded = false
                    }
                )
            }
        }
    }
}

/**
 * Returns a human-readable label for a sort option.
 *
 * @param option The sort option.
 * @return Display label like "Date (newest first)".
 */
private fun sortOptionLabel(option: HikeSortOption): String = when (option) {
    HikeSortOption.DATE -> "Date (newest first)"
    HikeSortOption.DISTANCE -> "Distance (longest first)"
    HikeSortOption.ELEVATION -> "Elevation (highest first)"
    HikeSortOption.DURATION -> "Duration (longest first)"
}

/**
 * A hike card wrapped in a swipe-to-dismiss container for delete.
 *
 * Swiping end-to-start reveals a red delete background and triggers
 * the delete callback when the swipe completes.
 *
 * @param hike The hike display item.
 * @param onClick Tap callback to navigate to detail.
 * @param onDelete Called when swipe-to-delete completes.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeToDeleteHikeCard(
    hike: HikeListItem,
    onClick: () -> Unit,
    onDelete: () -> Unit
) {
    val dismissState = rememberSwipeToDismissBoxState()

    LaunchedEffect(dismissState.currentValue) {
        if (dismissState.currentValue == SwipeToDismissBoxValue.EndToStart) {
            onDelete()
            dismissState.snapTo(SwipeToDismissBoxValue.Settled)
        }
    }

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            val color by animateColorAsState(
                targetValue = if (dismissState.targetValue == SwipeToDismissBoxValue.EndToStart) {
                    MaterialTheme.colorScheme.errorContainer
                } else {
                    MaterialTheme.colorScheme.surface
                },
                label = "deleteBackground"
            )
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(color)
                    .padding(end = 24.dp),
                contentAlignment = Alignment.CenterEnd
            ) {
                Icon(
                    imageVector = Icons.Default.Delete,
                    contentDescription = "Delete",
                    tint = MaterialTheme.colorScheme.onErrorContainer
                )
            }
        },
        enableDismissFromStartToEnd = false
    ) {
        HikeCard(hike = hike, onClick = onClick)
    }
}

/**
 * Card displaying a single hike summary.
 *
 * Shows the hike name, start date, distance, elevation gain, and duration
 * in a compact card layout.
 *
 * @param hike The hike display item with pre-formatted statistics.
 * @param onClick Tap callback.
 */
@Composable
private fun HikeCard(
    hike: HikeListItem,
    onClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = hike.name,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = hike.startTime.take(DATE_DISPLAY_LENGTH),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                StatChip(label = "Distance", value = hike.formattedDistance)
                StatChip(label = "Elevation", value = hike.formattedElevationGain)
                StatChip(label = "Duration", value = hike.formattedDuration)
            }
        }
    }
}

/**
 * Small label+value pair for displaying a statistic in a card.
 *
 * @param label Description text (e.g. "Distance").
 * @param value Formatted value text (e.g. "12.4 km").
 */
@Composable
private fun StatChip(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

/**
 * Confirmation dialog for deleting a hike.
 *
 * @param hikeName The name of the hike being deleted.
 * @param onDismiss Called when the dialog is dismissed (cancel).
 * @param onConfirm Called when the user confirms the deletion.
 */
@Composable
private fun DeleteHikeDialog(
    hikeName: String,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Delete Hike?") },
        text = { Text("Are you sure you want to delete \"$hikeName\"? This cannot be undone.") },
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

/** Number of characters from the ISO-8601 timestamp to show as the date. */
private const val DATE_DISPLAY_LENGTH = 10
