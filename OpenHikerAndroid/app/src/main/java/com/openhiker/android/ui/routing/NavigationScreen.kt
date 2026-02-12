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

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.openhiker.android.R
import com.openhiker.core.model.HikeStatsFormatter
import com.openhiker.core.navigation.NavigationState

/**
 * Turn-by-turn navigation screen.
 *
 * Displays the current turn instruction, distance to next turn,
 * route progress, real-time stats (distance, time, elevation),
 * off-route warnings, and a stop button with confirmation.
 *
 * The map integration (MapLibre with live GPS tracking and route
 * overlay) is a placeholder for now and will be connected when the
 * MapLibre Compose wrapper is available.
 *
 * @param onNavigationStopped Callback invoked when navigation ends (e.g., pop back).
 * @param viewModel The navigation ViewModel, injected by Hilt.
 */
@Composable
fun NavigationScreen(
    onNavigationStopped: (() -> Unit)? = null,
    viewModel: NavigationViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val navState by viewModel.navigationState.collectAsState()
    val offRouteState by viewModel.offRouteState.collectAsState()
    val isNavigating by viewModel.isNavigating.collectAsState()
    val distanceWalked by viewModel.distanceWalked.collectAsState()

    Box(modifier = Modifier.fillMaxSize()) {
        // Map placeholder (full screen)
        MapPlaceholder()

        // Navigation UI overlay
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            // Top: Current instruction card
            if (isNavigating) {
                InstructionCard(navState = navState)
            }

            Spacer(modifier = Modifier.weight(1f))

            Column {
                // Off-route warning banner
                AnimatedVisibility(
                    visible = offRouteState.isOffRoute,
                    enter = slideInVertically { -it },
                    exit = slideOutVertically { -it }
                ) {
                    OffRouteWarning(
                        distanceFromRoute = offRouteState.distanceFromRoute
                    )
                }

                // Arrived banner
                AnimatedVisibility(
                    visible = navState.hasArrived,
                    enter = slideInVertically { it },
                    exit = slideOutVertically { it }
                ) {
                    ArrivedBanner()
                }

                Spacer(modifier = Modifier.height(8.dp))

                // Progress bar
                if (isNavigating) {
                    LinearProgressIndicator(
                        progress = { navState.progress },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(6.dp)
                            .clip(RoundedCornerShape(3.dp)),
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))

                // Bottom: Stats and stop button
                if (isNavigating) {
                    NavigationStatsCard(
                        distanceWalked = distanceWalked,
                        remainingDistance = navState.remainingDistance,
                        elapsedSeconds = uiState.elapsedSeconds,
                        routeName = uiState.routeName
                    )

                    Spacer(modifier = Modifier.height(8.dp))

                    Button(
                        onClick = viewModel::showStopDialog,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.error
                        ),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Default.Close, contentDescription = null)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(stringResource(R.string.nav_stop_navigation))
                    }
                }
            }
        }
    }

    // Stop navigation confirmation dialog
    if (uiState.isStopDialogVisible) {
        StopNavigationDialog(
            onDismiss = viewModel::dismissStopDialog,
            onConfirm = {
                viewModel.stopNavigation()
                onNavigationStopped?.invoke()
            }
        )
    }
}

/**
 * Placeholder for the MapLibre map view.
 *
 * Will be replaced with live GPS tracking map with route overlay and
 * camera following user heading once MapLibre Compose integration
 * is available.
 */
@Composable
private fun MapPlaceholder() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surfaceVariant),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = Icons.Default.Navigation,
                contentDescription = null,
                modifier = Modifier.size(48.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = stringResource(R.string.nav_map_placeholder),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

/**
 * Card showing the current turn instruction and distance.
 *
 * Displays the turn direction verb (e.g., "Turn left"), the
 * instruction description (e.g., "onto Forest Trail"), and the
 * distance to the next turn in large text.
 *
 * @param navState Current navigation state from the route follower.
 */
@Composable
private fun InstructionCard(navState: NavigationState) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            val instruction = navState.currentInstruction

            if (instruction != null) {
                Text(
                    text = instruction.direction.verb,
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onPrimaryContainer
                )

                if (instruction.description.isNotBlank()) {
                    Text(
                        text = instruction.description,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))

                // Distance to next turn (large)
                Text(
                    text = formatTurnDistance(navState.distanceToNextTurn),
                    style = MaterialTheme.typography.displaySmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onPrimaryContainer
                )
            } else {
                Text(
                    text = stringResource(R.string.nav_following_route),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer
                )
            }
        }
    }
}

/**
 * Red warning banner displayed when the user is off-route.
 *
 * @param distanceFromRoute Distance from the route in metres.
 */
@Composable
private fun OffRouteWarning(distanceFromRoute: Double) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.errorContainer
        )
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.Warning,
                contentDescription = stringResource(R.string.nav_off_route),
                tint = MaterialTheme.colorScheme.onErrorContainer
            )
            Spacer(modifier = Modifier.width(8.dp))
            Column {
                Text(
                    text = stringResource(R.string.nav_off_route),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onErrorContainer
                )
                Text(
                    text = stringResource(R.string.nav_off_route_distance, distanceFromRoute.toInt()),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onErrorContainer
                )
            }
        }
    }
}

/**
 * Green banner displayed when the user has arrived at the destination.
 */
@Composable
private fun ArrivedBanner() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.tertiaryContainer
        )
    ) {
        Text(
            text = stringResource(R.string.nav_arrived),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onTertiaryContainer,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        )
    }
}

/**
 * Card displaying real-time navigation statistics.
 *
 * @param distanceWalked Cumulative distance walked in metres.
 * @param remainingDistance Remaining route distance in metres.
 * @param elapsedSeconds Elapsed navigation time in seconds.
 * @param routeName Display name of the route.
 */
@Composable
private fun NavigationStatsCard(
    distanceWalked: Double,
    remainingDistance: Double,
    elapsedSeconds: Long,
    routeName: String
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp)) {
            if (routeName.isNotBlank()) {
                Text(
                    text = routeName,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(4.dp))
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                StatItem(
                    label = stringResource(R.string.nav_stat_walked),
                    value = HikeStatsFormatter.formatDistance(distanceWalked, true)
                )
                StatItem(
                    label = stringResource(R.string.nav_stat_remaining),
                    value = HikeStatsFormatter.formatDistance(remainingDistance, true)
                )
                StatItem(
                    label = stringResource(R.string.nav_stat_time),
                    value = HikeStatsFormatter.formatDuration(elapsedSeconds.toDouble())
                )
            }
        }
    }
}

/**
 * Single stat label+value pair for the stats card.
 *
 * @param label Description label (e.g., "Walked").
 * @param value Formatted value (e.g., "2.4 km").
 */
@Composable
private fun StatItem(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
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
 * Confirmation dialog before stopping navigation.
 *
 * @param onDismiss Called when the dialog is dismissed (cancel).
 * @param onConfirm Called when the user confirms stopping navigation.
 */
@Composable
private fun StopNavigationDialog(
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.nav_stop_title)) },
        text = { Text(stringResource(R.string.nav_stop_message)) },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(stringResource(R.string.stop), color = MaterialTheme.colorScheme.error)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.continue_label))
            }
        }
    )
}

/**
 * Formats a turn distance for large display.
 *
 * Shows metres when close (< 1000m), kilometres when far.
 *
 * @param metres Distance in metres.
 * @return Formatted string like "250 m" or "1.2 km".
 */
private fun formatTurnDistance(metres: Double): String {
    return if (metres < KILOMETRE_THRESHOLD_METRES) {
        "${metres.toInt()} m"
    } else {
        "%.1f km".format(metres / METRES_PER_KILOMETRE)
    }
}

/** Distance threshold for switching from metres to kilometres display. */
private const val KILOMETRE_THRESHOLD_METRES = 1000.0

/** Conversion factor from metres to kilometres. */
private const val METRES_PER_KILOMETRE = 1000.0
