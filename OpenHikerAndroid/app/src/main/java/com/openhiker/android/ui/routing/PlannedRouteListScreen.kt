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

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.DirectionsBike
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.openhiker.android.data.repository.SkippedRouteFile
import com.openhiker.android.ui.sync.DeleteUnreadableRouteFilesDialog
import com.openhiker.core.model.HikeStatsFormatter
import com.openhiker.core.model.PlannedRoute
import com.openhiker.core.model.RoutingMode

/**
 * The Routes tab: the saved planned routes, newest first (#102).
 *
 * Tapping a route opens its detail screen (rename, delete, export, navigate). "Plan route" opens
 * the planner. Route files that cannot be read, and a folder that cannot be read, show in a card
 * above the routes, with a delete action for the files. The empty state is hidden while that card
 * shows, so a read failure never looks like "no routes", as on Apple.
 *
 * @param onOpenRoute Opens the detail screen for the route with this id.
 * @param onPlanRoute Opens the route planner.
 * @param onDeleteUnreadableFiles Deletes the confirmed unreadable files, then syncs if a sync
 *   folder is set; its errors show in the sync banner. Wired to the app-wide
 *   `SyncStatusViewModel`.
 * @param viewModel Supplies the routes and the unreadable files.
 */
@Composable
fun PlannedRouteListScreen(
    onOpenRoute: (String) -> Unit,
    onPlanRoute: () -> Unit,
    onDeleteUnreadableFiles: (List<String>) -> Unit,
    viewModel: PlannedRouteListViewModel = hiltViewModel()
) {
    val routes by viewModel.routes.collectAsState()
    val unreadable by viewModel.unreadableFiles.collectAsState()
    val loadError by viewModel.loadError.collectAsState()
    var filesToDelete by remember { mutableStateOf<List<String>?>(null) }

    // Each return to the tab (from the planner, the detail screen) reads the folder again.
    LaunchedEffect(Unit) { viewModel.refresh() }

    Scaffold(
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = onPlanRoute,
                icon = { Icon(Icons.Default.Add, contentDescription = null) },
                text = { Text("Plan route") }
            )
        }
    ) { innerPadding ->
        if (showsEmptyState(routes, unreadable, loadError)) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
                    .padding(EMPTY_STATE_PADDING.dp),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        "No planned routes",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "Tap Plan route to plan one in a downloaded region.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize().padding(innerPadding)) {
                if (loadError != null || unreadable.isNotEmpty()) {
                    item {
                        RouteLoadProblemsCard(
                            loadError = loadError,
                            unreadableFiles = unreadable.map { it.message },
                            onDelete = { filesToDelete = unreadable.map { it.fileName } }
                        )
                    }
                }
                items(routes, key = { it.id }) { route ->
                    PlannedRouteRow(route = route, onClick = { onOpenRoute(route.id) })
                    HorizontalDivider()
                }
                // Keeps the last row clear of the floating button.
                item { Spacer(modifier = Modifier.height(FAB_CLEARANCE.dp)) }
            }
        }
    }

    filesToDelete?.let { names ->
        DeleteUnreadableRouteFilesDialog(
            fileNames = names,
            onConfirm = {
                filesToDelete = null
                onDeleteUnreadableFiles(names)
            },
            onDismiss = { filesToDelete = null }
        )
    }
}

/**
 * Red card above the list naming why some routes are missing from it.
 *
 * @param loadError Why the folder could not be read, or null.
 * @param unreadableFiles "file: reason" lines for the files that could not be read.
 * @param onDelete Asks to delete the unreadable files; shown only when there are any.
 */
@Composable
private fun RouteLoadProblemsCard(
    loadError: String?,
    unreadableFiles: List<String>,
    onDelete: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth().padding(CARD_PADDING.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)
    ) {
        Column(modifier = Modifier.padding(CARD_PADDING.dp)) {
            val lines = listOfNotNull(loadError) +
                if (unreadableFiles.isEmpty()) emptyList()
                else listOf("These route files cannot be read:") + unreadableFiles
            Text(
                lines.joinToString("\n"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer
            )
            if (unreadableFiles.isNotEmpty()) {
                TextButton(onClick = onDelete) { Text("Delete unreadable route files") }
            }
        }
    }
}

/**
 * One saved route: its name, then distance, estimated time and ascent.
 *
 * @param route The route to show.
 * @param onClick Opens the route.
 */
@Composable
private fun PlannedRouteRow(route: PlannedRoute, onClick: () -> Unit) {
    ListItem(
        modifier = Modifier.clickable(onClick = onClick),
        leadingContent = {
            Icon(
                if (route.mode == RoutingMode.CYCLING) Icons.Default.DirectionsBike
                else Icons.Default.DirectionsWalk,
                contentDescription = route.mode.name.lowercase()
            )
        },
        headlineContent = { Text(route.name) },
        supportingContent = {
            // Metric, as on the route detail screen.
            Text(
                listOf(
                    HikeStatsFormatter.formatDistance(route.totalDistance, true),
                    HikeStatsFormatter.formatDuration(route.estimatedDuration),
                    "↑ " + HikeStatsFormatter.formatElevation(route.elevationGain, true)
                ).joinToString(" · ")
            )
        }
    )
}

/**
 * Whether the list shows "No planned routes": only when nothing was read and nothing failed, so a
 * read failure never looks like an empty list.
 *
 * @param routes The readable routes.
 * @param unreadable The route files that could not be read.
 * @param loadError Why the folder could not be read, or null.
 */
internal fun showsEmptyState(
    routes: List<PlannedRoute>,
    unreadable: List<SkippedRouteFile>,
    loadError: String?
): Boolean = routes.isEmpty() && unreadable.isEmpty() && loadError == null

/** Padding around the empty-state text. */
private const val EMPTY_STATE_PADDING = 16

/** Padding around and inside the load-problems card. */
private const val CARD_PADDING = 12

/** Space below the last row so the floating button does not cover it. */
private const val FAB_CLEARANCE = 88
