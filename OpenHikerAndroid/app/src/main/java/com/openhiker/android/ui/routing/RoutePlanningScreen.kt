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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.DirectionsBike
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Loop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.openhiker.core.model.HikeStatsFormatter
import com.openhiker.core.model.RoutingMode
import com.openhiker.core.model.TurnInstruction

/**
 * Route planning screen.
 *
 * Users select a region, then place sequential waypoints on the map.
 * Two route computation modes are available:
 * - "Start → End": routes through waypoints in order (1→2→3→4→5)
 * - "Back to Start": routes through all waypoints and returns to the first (1→2→3→4→5→1)
 *
 * @param onStartNavigation Callback to navigate to the navigation screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RoutePlanningScreen(
    onStartNavigation: ((String) -> Unit)? = null,
    viewModel: RoutePlanningViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val regions by viewModel.regions.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
    ) {
        // Region selector
        RegionSelector(
            regions = regions,
            selectedRegionId = uiState.selectedRegionId,
            onSelectRegion = viewModel::selectRegion
        )

        Spacer(modifier = Modifier.height(12.dp))

        // Mode selector (hiking/cycling)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = uiState.routingMode == RoutingMode.HIKING,
                onClick = { viewModel.setRoutingMode(RoutingMode.HIKING) },
                label = { Text("Hiking") },
                leadingIcon = {
                    Icon(Icons.Default.DirectionsWalk, contentDescription = null)
                }
            )
            FilterChip(
                selected = uiState.routingMode == RoutingMode.CYCLING,
                onClick = { viewModel.setRoutingMode(RoutingMode.CYCLING) },
                label = { Text("Cycling") },
                leadingIcon = {
                    Icon(Icons.Default.DirectionsBike, contentDescription = null)
                }
            )
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Waypoint info
        WaypointInfo(uiState = uiState)

        Spacer(modifier = Modifier.height(12.dp))

        // Route computation buttons
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            // Start → End button
            OutlinedButton(
                onClick = { viewModel.computeRoute(loop = false) },
                enabled = uiState.waypoints.size >= 2 &&
                    !uiState.isComputing &&
                    uiState.selectedRegionId != null,
                modifier = Modifier.weight(1f)
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowForward,
                    contentDescription = null,
                    modifier = Modifier.height(18.dp)
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text("Start \u2192 End")
            }

            // Back to Start button
            OutlinedButton(
                onClick = { viewModel.computeRoute(loop = true) },
                enabled = uiState.waypoints.size >= 2 &&
                    !uiState.isComputing &&
                    uiState.selectedRegionId != null,
                modifier = Modifier.weight(1f)
            ) {
                Icon(
                    Icons.Default.Loop,
                    contentDescription = null,
                    modifier = Modifier.height(18.dp)
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text("Back to Start")
            }

            // Clear button
            IconButton(onClick = viewModel::clearRoute) {
                Icon(Icons.Default.Clear, contentDescription = "Clear")
            }
        }

        // Computing indicator
        if (uiState.isComputing) {
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.height(20.dp).width(20.dp),
                    strokeWidth = 2.dp
                )
                Text("Computing route\u2026", style = MaterialTheme.typography.bodySmall)
            }
        }

        // Error message
        uiState.errorMessage?.let { error ->
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = error,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall
            )
        }

        // Route result
        uiState.computedRoute?.let { route ->
            Spacer(modifier = Modifier.height(16.dp))
            RouteResultCard(
                distance = route.totalDistance,
                elevationGain = route.elevationGain,
                elevationLoss = route.elevationLoss,
                estimatedDuration = route.estimatedDuration,
                instructions = uiState.instructions,
                onSave = viewModel::showSaveDialog,
                onStartNavigation = {
                    onStartNavigation?.invoke(uiState.selectedRegionId ?: "")
                }
            )
        }

        // Instruction text when no route computed
        if (uiState.selectedRegionId != null && uiState.computedRoute == null && !uiState.isComputing) {
            Spacer(modifier = Modifier.height(16.dp))
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                contentAlignment = Alignment.Center
            ) {
                val hint = when {
                    uiState.waypoints.isEmpty() -> "Tap on the map to place waypoints"
                    uiState.waypoints.size == 1 -> "Tap to add more waypoints (need at least 2)"
                    else -> "Tap to add waypoints, or compute your route"
                }
                Text(
                    text = hint,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }

    // Save dialog
    if (uiState.isSaveDialogVisible) {
        SaveRouteDialog(
            onDismiss = viewModel::dismissSaveDialog,
            onSave = viewModel::saveRoute
        )
    }
}

/**
 * Region selector dropdown.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RegionSelector(
    regions: List<com.openhiker.core.model.RegionMetadata>,
    selectedRegionId: String?,
    onSelectRegion: (String) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedName = regions.find { it.id == selectedRegionId }?.name ?: "Select a region"

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it }
    ) {
        OutlinedTextField(
            value = selectedName,
            onValueChange = {},
            readOnly = true,
            label = { Text("Region") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor()
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            regions.forEach { region ->
                DropdownMenuItem(
                    text = { Text(region.name) },
                    onClick = {
                        onSelectRegion(region.id)
                        expanded = false
                    }
                )
            }
            if (regions.isEmpty()) {
                DropdownMenuItem(
                    text = { Text("No regions downloaded") },
                    onClick = { expanded = false },
                    enabled = false
                )
            }
        }
    }
}

/**
 * Shows the current waypoint count and instruction hint.
 */
@Composable
private fun WaypointInfo(uiState: RoutePlanningUiState) {
    Column {
        if (uiState.waypoints.isEmpty()) {
            Text(
                text = "No waypoints placed",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            Text(
                text = "${uiState.waypoints.size} waypoint${if (uiState.waypoints.size != 1) "s" else ""} placed",
                style = MaterialTheme.typography.bodySmall
            )
            uiState.waypoints.forEachIndexed { index, coordinate ->
                val label = when {
                    index == 0 -> "WP 1 (start)"
                    index == uiState.waypoints.size - 1 -> "WP ${index + 1} (end)"
                    else -> "WP ${index + 1}"
                }
                Text(
                    text = "$label: ${coordinate.formatted()}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

/**
 * Card displaying computed route statistics and turn-by-turn instructions.
 */
@Composable
private fun RouteResultCard(
    distance: Double,
    elevationGain: Double,
    elevationLoss: Double,
    estimatedDuration: Double,
    instructions: List<TurnInstruction>,
    onSave: () -> Unit,
    onStartNavigation: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("Route Computed", style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.height(8.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(HikeStatsFormatter.formatDistance(distance, true))
                Text("${elevationGain.toInt()}m up / ${elevationLoss.toInt()}m down")
            }
            Text(
                "Est. ${HikeStatsFormatter.formatDuration(estimatedDuration)}",
                style = MaterialTheme.typography.bodySmall
            )

            Spacer(modifier = Modifier.height(12.dp))

            // Action buttons
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Button(onClick = onSave, modifier = Modifier.weight(1f)) {
                    Icon(Icons.Default.Save, contentDescription = null)
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Save")
                }
                Button(onClick = onStartNavigation, modifier = Modifier.weight(1f)) {
                    Icon(Icons.Default.Navigation, contentDescription = null)
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Navigate")
                }
            }

            // Turn instructions
            if (instructions.isNotEmpty()) {
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    "${instructions.size} turn instructions",
                    style = MaterialTheme.typography.titleSmall
                )
                Spacer(modifier = Modifier.height(4.dp))
                LazyColumn(
                    modifier = Modifier.height(200.dp)
                ) {
                    itemsIndexed(instructions) { _, instruction ->
                        TurnInstructionItem(instruction)
                    }
                }
            }
        }
    }
}

/**
 * Single turn instruction list item.
 */
@Composable
private fun TurnInstructionItem(instruction: TurnInstruction) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = instruction.direction.verb,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.width(100.dp)
        )
        Text(
            text = instruction.description,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.weight(1f)
        )
        Text(
            text = HikeStatsFormatter.formatDistance(instruction.distanceFromPrevious, true),
            style = MaterialTheme.typography.labelSmall
        )
    }
}

/**
 * Dialog for entering a route name before saving.
 */
@Composable
private fun SaveRouteDialog(
    onDismiss: () -> Unit,
    onSave: (String) -> Unit
) {
    var routeName by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Save Route") },
        text = {
            OutlinedTextField(
                value = routeName,
                onValueChange = { routeName = it },
                label = { Text("Route name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(routeName) },
                enabled = routeName.isNotBlank()
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
