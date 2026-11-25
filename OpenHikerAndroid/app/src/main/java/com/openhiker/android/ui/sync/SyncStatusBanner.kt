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

package com.openhiker.android.ui.sync

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.SyncProblem
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

/**
 * Banner above every tab while the last cloud sync failed, or after the sync records were
 * reset (#72). Shows nothing otherwise.
 *
 * "Retry" runs the sync again and turns into a spinner while any sync runs; the close button
 * hides the banner until a later sync fails again. When planned-route files cannot be read,
 * "Delete unreadable route files" deletes them after a confirmation (#77).
 *
 * @param viewModel Supplies the banner content and handles Retry, Dismiss and the delete.
 */
@Composable
fun SyncStatusBanner(viewModel: SyncStatusViewModel = hiltViewModel()) {
    val state by viewModel.bannerState.collectAsState()
    var confirmDelete by remember { mutableStateOf(false) }
    if (state.messages.isEmpty()) return

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.errorContainer)
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .testTag("sync_status_banner"),
        verticalAlignment = Alignment.Top
    ) {
        Icon(
            Icons.Default.SyncProblem,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onErrorContainer,
            modifier = Modifier.padding(top = 2.dp, end = 8.dp)
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = state.messages.joinToString("\n"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer
            )
            if (state.unreadableRouteFiles.isNotEmpty()) {
                TextButton(onClick = { confirmDelete = true }) {
                    Text("Delete unreadable route files")
                }
            }
        }
        if (state.isSyncing) {
            CircularProgressIndicator(
                modifier = Modifier
                    .padding(8.dp)
                    .size(20.dp)
                    .semantics { contentDescription = "Syncing" },
                strokeWidth = 2.dp
            )
        } else if (state.canRetry) {
            TextButton(onClick = viewModel::retry) { Text("Retry") }
        }
        IconButton(onClick = viewModel::dismiss) {
            Icon(
                Icons.Default.Close,
                contentDescription = "Dismiss",
                tint = MaterialTheme.colorScheme.onErrorContainer
            )
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete unreadable route files?") },
            text = {
                Text(
                    "These planned-route files on this device cannot be read:\n" +
                        state.unreadableRouteFiles.joinToString("\n") +
                        "\n\nDeleting them cannot be undone. If the sync folder holds a copy " +
                        "of a route, the next sync brings it back."
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    viewModel.deleteUnreadableRouteFiles()
                }) { Text("Delete") }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text("Cancel") }
            }
        )
    }
}
