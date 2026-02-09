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

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AddAPhoto
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.openhiker.core.model.WaypointCategory

/**
 * Screen for creating a new waypoint.
 *
 * Provides a form with the following fields:
 * - **Category picker**: a chip group showing all 9 [WaypointCategory] values.
 *   Exactly one category must be selected (defaults to [WaypointCategory.CUSTOM]).
 * - **Name text field**: the label for the waypoint (required, must not be blank).
 * - **Notes text field**: multiline free-text notes (optional).
 * - **GPS coordinates**: latitude and longitude fields auto-filled from the device's
 *   current GPS location via [WaypointViewModel.currentLocation]. The fields are
 *   editable so the user can manually correct or enter coordinates. A "Use current
 *   location" button re-fills the fields from the latest GPS reading.
 * - **Photo placeholder**: buttons for "Take Photo" and "Choose from Library" with
 *   a preview area. The actual photo picker/camera integration is not implemented
 *   here -- only the UI buttons and preview area are shown as placeholders.
 * - **Save button**: validates that name and coordinates are provided, then calls
 *   [WaypointViewModel.saveWaypoint] and navigates back on success.
 *
 * @param onNavigateBack Callback to navigate back after saving or cancelling.
 * @param viewModel The shared [WaypointViewModel] providing location and save actions.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun AddWaypointScreen(
    onNavigateBack: () -> Unit,
    viewModel: WaypointViewModel = hiltViewModel()
) {
    val currentLocation by viewModel.currentLocation.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()

    val snackbarHostState = remember { SnackbarHostState() }

    // Form state (survives configuration changes via rememberSaveable)
    var selectedCategory by rememberSaveable { mutableStateOf(WaypointCategory.CUSTOM) }
    var label by rememberSaveable { mutableStateOf("") }
    var note by rememberSaveable { mutableStateOf("") }
    var latitudeText by rememberSaveable { mutableStateOf("") }
    var longitudeText by rememberSaveable { mutableStateOf("") }
    var hasAutoFilledLocation by rememberSaveable { mutableStateOf(false) }

    // Auto-fill GPS coordinates from current location on first load
    LaunchedEffect(currentLocation) {
        if (!hasAutoFilledLocation && currentLocation != null) {
            latitudeText = "%.6f".format(currentLocation!!.latitude)
            longitudeText = "%.6f".format(currentLocation!!.longitude)
            hasAutoFilledLocation = true
        }
    }

    // Show errors in snackbar
    LaunchedEffect(errorMessage) {
        errorMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearError()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text("Add Waypoint") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Navigate back"
                        )
                    }
                }
            )
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Category picker
            CategoryPickerSection(
                selectedCategory = selectedCategory,
                onCategorySelected = { selectedCategory = it }
            )

            // Name field
            OutlinedTextField(
                value = label,
                onValueChange = { label = it },
                label = { Text("Waypoint name") },
                placeholder = { Text("e.g., Summit viewpoint") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )

            // Notes field
            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                label = { Text("Notes (optional)") },
                placeholder = { Text("Add any details about this waypoint...") },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(NOTE_FIELD_HEIGHT_DP.dp),
                maxLines = NOTE_MAX_LINES
            )

            // GPS coordinates
            CoordinatesInputSection(
                latitudeText = latitudeText,
                longitudeText = longitudeText,
                onLatitudeChange = { latitudeText = it },
                onLongitudeChange = { longitudeText = it },
                onUseCurrentLocation = {
                    currentLocation?.let { location ->
                        latitudeText = "%.6f".format(location.latitude)
                        longitudeText = "%.6f".format(location.longitude)
                    }
                },
                isLocationAvailable = currentLocation != null
            )

            // Photo placeholder
            PhotoPlaceholderSection()

            // Save button
            val isFormValid = label.isNotBlank() &&
                latitudeText.toDoubleOrNull() != null &&
                longitudeText.toDoubleOrNull() != null

            Button(
                onClick = {
                    val latitude = latitudeText.toDoubleOrNull() ?: return@Button
                    val longitude = longitudeText.toDoubleOrNull() ?: return@Button
                    val altitude = currentLocation?.altitude

                    viewModel.saveWaypoint(
                        label = label.trim(),
                        category = selectedCategory,
                        latitude = latitude,
                        longitude = longitude,
                        altitude = altitude,
                        note = note.trim(),
                        onSuccess = onNavigateBack
                    )
                },
                enabled = isFormValid,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Save Waypoint")
            }

            // Bottom padding for keyboard clearance
            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

/**
 * Category picker section with a chip group for all 9 waypoint categories.
 *
 * Displays the categories as a flow row of [FilterChip]s. Exactly one chip
 * is selected at a time (single-select). Each chip is coloured with the
 * category's [WaypointCategory.colorHex].
 *
 * @param selectedCategory The currently selected category.
 * @param onCategorySelected Callback when a category chip is tapped.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CategoryPickerSection(
    selectedCategory: WaypointCategory,
    onCategorySelected: (WaypointCategory) -> Unit
) {
    Column {
        Text(
            text = "Category",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(8.dp))
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            WaypointCategory.entries.forEach { category ->
                val isSelected = selectedCategory == category
                val chipColor = try {
                    Color(android.graphics.Color.parseColor("#${category.colorHex}"))
                } catch (e: IllegalArgumentException) {
                    MaterialTheme.colorScheme.primary
                }

                FilterChip(
                    selected = isSelected,
                    onClick = { onCategorySelected(category) },
                    label = { Text(category.displayName) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = chipColor.copy(alpha = 0.2f),
                        selectedLabelColor = chipColor
                    )
                )
            }
        }
    }
}

/**
 * GPS coordinate input section with latitude and longitude text fields.
 *
 * Features:
 * - Two numeric text fields for latitude and longitude (decimal degrees).
 * - Fields are pre-filled from the device's current GPS location.
 * - A "Use current location" button to re-fill from the latest GPS reading.
 * - Validation: values must be parseable as [Double].
 *
 * @param latitudeText The current latitude text value.
 * @param longitudeText The current longitude text value.
 * @param onLatitudeChange Callback when the latitude text changes.
 * @param onLongitudeChange Callback when the longitude text changes.
 * @param onUseCurrentLocation Callback to re-fill from the current GPS location.
 * @param isLocationAvailable Whether the device's GPS location is currently available.
 */
@Composable
private fun CoordinatesInputSection(
    latitudeText: String,
    longitudeText: String,
    onLatitudeChange: (String) -> Unit,
    onLongitudeChange: (String) -> Unit,
    onUseCurrentLocation: () -> Unit,
    isLocationAvailable: Boolean
) {
    Column {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Coordinates",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            OutlinedButton(
                onClick = onUseCurrentLocation,
                enabled = isLocationAvailable
            ) {
                Icon(
                    Icons.Default.MyLocation,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text(
                    text = "Use current location",
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            OutlinedTextField(
                value = latitudeText,
                onValueChange = onLatitudeChange,
                label = { Text("Latitude") },
                placeholder = { Text("e.g., 47.3769") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                isError = latitudeText.isNotBlank() && latitudeText.toDoubleOrNull() == null,
                supportingText = {
                    if (latitudeText.isNotBlank() && latitudeText.toDoubleOrNull() == null) {
                        Text("Invalid number")
                    }
                },
                modifier = Modifier.weight(1f)
            )

            OutlinedTextField(
                value = longitudeText,
                onValueChange = onLongitudeChange,
                label = { Text("Longitude") },
                placeholder = { Text("e.g., 11.3948") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                isError = longitudeText.isNotBlank() && longitudeText.toDoubleOrNull() == null,
                supportingText = {
                    if (longitudeText.isNotBlank() && longitudeText.toDoubleOrNull() == null) {
                        Text("Invalid number")
                    }
                },
                modifier = Modifier.weight(1f)
            )
        }
    }
}

/**
 * Photo placeholder section with camera and library buttons.
 *
 * Displays a bordered preview area and two action buttons:
 * - **Take Photo**: placeholder for camera capture integration.
 * - **Choose from Library**: placeholder for gallery picker integration.
 *
 * The actual photo picker and camera functionality is not implemented here.
 * This section provides the UI structure for future integration with
 * Android's photo picker APIs.
 */
@Composable
private fun PhotoPlaceholderSection() {
    Column {
        Text(
            text = "Photo (optional)",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold
        )

        Spacer(modifier = Modifier.height(8.dp))

        // Photo preview area
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(PHOTO_PREVIEW_HEIGHT_DP.dp)
                .clip(RoundedCornerShape(12.dp))
                .border(
                    width = 2.dp,
                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                    shape = RoundedCornerShape(12.dp)
                )
                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)),
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    Icons.Default.AddAPhoto,
                    contentDescription = null,
                    modifier = Modifier.size(32.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "No photo attached",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                )
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Photo action buttons
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            OutlinedButton(
                onClick = { /* Photo capture integration placeholder */ },
                modifier = Modifier.weight(1f)
            ) {
                Icon(
                    Icons.Default.AddAPhoto,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text("Take Photo")
            }

            OutlinedButton(
                onClick = { /* Photo picker integration placeholder */ },
                modifier = Modifier.weight(1f)
            ) {
                Icon(
                    Icons.Default.PhotoLibrary,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text("Library")
            }
        }
    }
}

/** Height of the note text field in density-independent pixels. */
private const val NOTE_FIELD_HEIGHT_DP = 120

/** Maximum number of visible lines in the note text field. */
private const val NOTE_MAX_LINES = 5

/** Height of the photo preview placeholder in density-independent pixels. */
private const val PHOTO_PREVIEW_HEIGHT_DP = 150
