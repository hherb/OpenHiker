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
import android.widget.Toast
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Hiking
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Map
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.openhiker.android.data.db.waypoints.WaypointEntity
import com.openhiker.core.model.WaypointCategory

/**
 * Detail screen for a single waypoint.
 *
 * Displays all waypoint information including:
 * - **Full-resolution photo** at the top (if available), decoded from the JPEG BLOB.
 * - **Name and category** with a coloured category badge.
 * - **Coordinates** (latitude, longitude, altitude) with a copy-to-clipboard button
 *   that copies the coordinates in "lat, lon" format.
 * - **Notes** section showing the user's text notes.
 * - **Associated hike link** (if [WaypointEntity.hikeId] is not null) with a
 *   navigation prompt. Currently shows the hike ID; full navigation will be
 *   added when the hike detail screen is implemented.
 * - **Mini-map placeholder** for future integration showing the waypoint on a map.
 * - **Edit button** that opens an inline edit dialog to change name, category, and notes.
 * - **Delete button** with confirmation dialog.
 *
 * The screen loads the full waypoint entity (including photo BLOBs) via
 * [WaypointViewModel.loadWaypointDetail] and clears it on disposal to
 * free memory.
 *
 * @param waypointId The UUID of the waypoint to display.
 * @param onNavigateBack Callback to navigate back (e.g., pop the back stack).
 * @param onNavigateToHike Optional callback to navigate to an associated hike detail.
 *   Receives the hike UUID. If null, the hike link is not clickable.
 * @param viewModel The shared [WaypointViewModel] providing waypoint data and actions.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun WaypointDetailScreen(
    waypointId: String,
    onNavigateBack: () -> Unit,
    onNavigateToHike: ((String) -> Unit)? = null,
    viewModel: WaypointViewModel = hiltViewModel()
) {
    val waypoint by viewModel.detailWaypoint.collectAsState()
    val isLoading by viewModel.detailLoading.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()

    val snackbarHostState = remember { SnackbarHostState() }
    val clipboardManager = LocalClipboardManager.current
    val context = LocalContext.current

    var showEditDialog by remember { mutableStateOf(false) }
    var showDeleteDialog by remember { mutableStateOf(false) }

    // Load waypoint detail on first composition
    LaunchedEffect(waypointId) {
        viewModel.loadWaypointDetail(waypointId)
    }

    // Clear detail when leaving the screen to free photo BLOB memory
    DisposableEffect(Unit) {
        onDispose {
            viewModel.clearWaypointDetail()
        }
    }

    // Show errors in snackbar
    LaunchedEffect(errorMessage) {
        errorMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearError()
        }
    }

    // Edit dialog
    if (showEditDialog) {
        waypoint?.let { wp ->
            EditWaypointDialog(
                currentLabel = wp.label,
                currentCategory = resolveCategory(wp.category),
                currentNote = wp.note,
                onConfirm = { label, category, note ->
                    viewModel.updateWaypoint(
                        waypointId = wp.id,
                        label = label,
                        category = category,
                        note = note
                    )
                    showEditDialog = false
                },
                onDismiss = { showEditDialog = false }
            )
        }
    }

    // Delete confirmation dialog
    if (showDeleteDialog) {
        AlertDialog(
            onDismissRequest = { showDeleteDialog = false },
            title = { Text("Delete Waypoint") },
            text = {
                Text(
                    "Delete \"${waypoint?.label ?: "this waypoint"}\"? " +
                        "This will permanently remove the waypoint and any associated photos."
                )
            },
            confirmButton = {
                Button(onClick = {
                    viewModel.deleteWaypoint(waypointId) {
                        onNavigateBack()
                    }
                    showDeleteDialog = false
                }) {
                    Text("Delete")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text(waypoint?.label ?: "Waypoint") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Navigate back"
                        )
                    }
                },
                actions = {
                    IconButton(onClick = { showEditDialog = true }) {
                        Icon(Icons.Default.Edit, contentDescription = "Edit waypoint")
                    }
                    IconButton(onClick = { showDeleteDialog = true }) {
                        Icon(
                            Icons.Default.Delete,
                            contentDescription = "Delete waypoint",
                            tint = MaterialTheme.colorScheme.error
                        )
                    }
                }
            )
        }
    ) { innerPadding ->
        when {
            isLoading -> {
                // Loading state
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            }

            waypoint == null -> {
                // Not found state
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "Waypoint not found",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            else -> {
                val wp = waypoint!!
                val category = resolveCategory(wp.category)
                val categoryColor = parseCategoryColor(category)

                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding)
                        .verticalScroll(rememberScrollState())
                ) {
                    // Full-resolution photo (if available)
                    WaypointPhoto(photoBytes = wp.photo)

                    Column(
                        modifier = Modifier.padding(16.dp)
                    ) {
                        // Category badge
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                modifier = Modifier
                                    .size(12.dp)
                                    .clip(RoundedCornerShape(6.dp))
                                    .background(categoryColor)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = category.displayName,
                                style = MaterialTheme.typography.labelLarge,
                                color = categoryColor,
                                fontWeight = FontWeight.SemiBold
                            )
                        }

                        Spacer(modifier = Modifier.height(16.dp))

                        // Coordinates section
                        CoordinatesSection(
                            latitude = wp.latitude,
                            longitude = wp.longitude,
                            altitude = wp.altitude,
                            onCopyCoordinates = {
                                val coordText = "%.6f, %.6f".format(wp.latitude, wp.longitude)
                                clipboardManager.setText(AnnotatedString(coordText))
                                Toast.makeText(
                                    context,
                                    "Coordinates copied",
                                    Toast.LENGTH_SHORT
                                ).show()
                            }
                        )

                        Spacer(modifier = Modifier.height(16.dp))

                        // Notes section
                        if (wp.note.isNotBlank()) {
                            NotesSection(note = wp.note)
                            Spacer(modifier = Modifier.height(16.dp))
                        }

                        // Associated hike link
                        if (wp.hikeId != null) {
                            HikeLinkSection(
                                hikeId = wp.hikeId,
                                onNavigateToHike = onNavigateToHike
                            )
                            Spacer(modifier = Modifier.height(16.dp))
                        }

                        // Mini-map placeholder
                        MiniMapPlaceholder(
                            latitude = wp.latitude,
                            longitude = wp.longitude
                        )

                        // Metadata footer
                        Spacer(modifier = Modifier.height(16.dp))
                        wp.modifiedAt?.let { modifiedAt ->
                            Text(
                                text = "Last modified: $modifiedAt",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        Text(
                            text = "Created: ${wp.timestamp}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
}

/**
 * Displays the full-resolution waypoint photo.
 *
 * Decodes the JPEG [ByteArray] into a Bitmap and renders it at full width
 * with a 4:3 aspect ratio. If no photo data is available, this composable
 * renders nothing.
 *
 * @param photoBytes The JPEG photo data, or null if no photo is attached.
 */
@Composable
private fun WaypointPhoto(photoBytes: ByteArray?) {
    if (photoBytes == null) return

    val bitmap = remember(photoBytes) {
        BitmapFactory.decodeByteArray(photoBytes, 0, photoBytes.size)
    }

    if (bitmap != null) {
        Image(
            bitmap = bitmap.asImageBitmap(),
            contentDescription = "Waypoint photo",
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(PHOTO_ASPECT_RATIO)
                .clip(RoundedCornerShape(bottomStart = 16.dp, bottomEnd = 16.dp)),
            contentScale = ContentScale.Crop
        )
    }
}

/**
 * Coordinates display section with latitude, longitude, altitude, and copy button.
 *
 * Shows coordinates formatted to 6 decimal places (sub-metre precision).
 * Altitude is shown in metres if available.
 *
 * @param latitude The waypoint latitude in decimal degrees.
 * @param longitude The waypoint longitude in decimal degrees.
 * @param altitude The waypoint altitude in metres, or null if unavailable.
 * @param onCopyCoordinates Callback when the copy button is tapped.
 */
@Composable
private fun CoordinatesSection(
    latitude: Double,
    longitude: Double,
    altitude: Double?,
    onCopyCoordinates: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                Icons.Default.LocationOn,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(24.dp)
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "%.6f, %.6f".format(latitude, longitude),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium
                )
                if (altitude != null) {
                    Text(
                        text = "%.0f m altitude".format(altitude),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            IconButton(onClick = onCopyCoordinates) {
                Icon(
                    Icons.Default.ContentCopy,
                    contentDescription = "Copy coordinates to clipboard",
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
}

/**
 * Notes section displaying the user's text note for the waypoint.
 *
 * @param note The note text to display.
 */
@Composable
private fun NotesSection(note: String) {
    Text(
        text = "Notes",
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold
    )
    Spacer(modifier = Modifier.height(4.dp))
    Text(
        text = note,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

/**
 * Associated hike link section.
 *
 * Displays a clickable card that navigates to the hike detail screen
 * if [onNavigateToHike] is provided. Otherwise shows a non-interactive
 * card indicating the hike association.
 *
 * @param hikeId The UUID of the associated hike.
 * @param onNavigateToHike Optional callback to navigate to the hike detail screen.
 */
@Composable
private fun HikeLinkSection(
    hikeId: String,
    onNavigateToHike: ((String) -> Unit)?
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (onNavigateToHike != null) {
                    Modifier.clip(RoundedCornerShape(12.dp))
                } else {
                    Modifier
                }
            ),
        onClick = { onNavigateToHike?.invoke(hikeId) },
        enabled = onNavigateToHike != null,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.secondaryContainer
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                Icons.Default.Hiking,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSecondaryContainer
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column {
                Text(
                    text = "Associated Hike",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSecondaryContainer
                )
                Text(
                    text = "Hike ID: $hikeId",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.7f)
                )
            }
        }
    }
}

/**
 * Mini-map placeholder showing where the waypoint is located.
 *
 * This is a placeholder UI for future map integration. Currently displays
 * a bordered box with a map icon and coordinates. Will be replaced with
 * an actual map tile rendering when the map display component is ready.
 *
 * @param latitude The waypoint latitude in decimal degrees.
 * @param longitude The waypoint longitude in decimal degrees.
 */
@Composable
private fun MiniMapPlaceholder(
    latitude: Double,
    longitude: Double
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(MINI_MAP_HEIGHT_DP.dp)
                .border(
                    width = 1.dp,
                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                    shape = RoundedCornerShape(12.dp)
                ),
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    Icons.Default.Map,
                    contentDescription = null,
                    modifier = Modifier.size(32.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Map view placeholder",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                )
                Text(
                    text = "%.4f, %.4f".format(latitude, longitude),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                )
            }
        }
    }
}

/**
 * Dialog for editing a waypoint's label, category, and note.
 *
 * Provides:
 * - A text field for the waypoint name.
 * - A flow row of category chips for single-select category change.
 * - A multiline text field for the note.
 * - Confirm and Cancel buttons.
 *
 * The Save button is disabled if the label is blank.
 *
 * @param currentLabel The current waypoint label (pre-filled in the text field).
 * @param currentCategory The current [WaypointCategory] (pre-selected chip).
 * @param currentNote The current note text (pre-filled in the text field).
 * @param onConfirm Callback with the updated (label, category, note) when confirmed.
 * @param onDismiss Callback when the dialog is dismissed without saving.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun EditWaypointDialog(
    currentLabel: String,
    currentCategory: WaypointCategory,
    currentNote: String,
    onConfirm: (String, WaypointCategory, String) -> Unit,
    onDismiss: () -> Unit
) {
    var label by remember { mutableStateOf(currentLabel) }
    var selectedCategory by remember { mutableStateOf(currentCategory) }
    var note by remember { mutableStateOf(currentNote) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Edit Waypoint") },
        text = {
            Column {
                OutlinedTextField(
                    value = label,
                    onValueChange = { label = it },
                    label = { Text("Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(modifier = Modifier.height(12.dp))

                Text(
                    text = "Category",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(4.dp))
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    WaypointCategory.entries.forEach { category ->
                        val isSelected = selectedCategory == category
                        val chipColor = parseCategoryColor(category)

                        FilterChip(
                            selected = isSelected,
                            onClick = { selectedCategory = category },
                            label = {
                                Text(
                                    text = category.displayName,
                                    style = MaterialTheme.typography.bodySmall
                                )
                            },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = chipColor.copy(alpha = 0.2f),
                                selectedLabelColor = chipColor
                            )
                        )
                    }
                }

                Spacer(modifier = Modifier.height(12.dp))

                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text("Notes") },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(NOTE_FIELD_HEIGHT_DP.dp),
                    maxLines = NOTE_MAX_LINES
                )
            }
        },
        confirmButton = {
            Button(
                onClick = { onConfirm(label, selectedCategory, note) },
                enabled = label.isNotBlank()
            ) {
                Text("Save")
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
 * Resolves a category string (from the database) to a [WaypointCategory] enum value.
 *
 * Falls back to [WaypointCategory.CUSTOM] if the string does not match any known category.
 * This is a local copy to avoid cross-file internal visibility issues.
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
 * This is a local copy to avoid cross-file internal visibility issues.
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

/** Aspect ratio for the full-resolution waypoint photo (4:3 landscape). */
private const val PHOTO_ASPECT_RATIO = 4f / 3f

/** Height of the mini-map placeholder in density-independent pixels. */
private const val MINI_MAP_HEIGHT_DP = 150

/** Height of the note text field in the edit dialog in density-independent pixels. */
private const val NOTE_FIELD_HEIGHT_DP = 120

/** Maximum number of visible lines in the note text field. */
private const val NOTE_MAX_LINES = 5
