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

package com.openhiker.android.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Layers
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.openhiker.core.model.TileServer

/**
 * Dropdown button for selecting the active tile source.
 *
 * Displays a button showing the current tile server name with a layers icon.
 * Tapping opens a dropdown menu listing all available tile sources.
 * The selected source is highlighted and changes trigger a callback.
 *
 * @param currentServer The currently selected tile server.
 * @param servers List of available tile servers to display.
 * @param onServerSelected Callback invoked when the user selects a different server.
 * @param modifier Optional Compose modifier.
 */
@Composable
fun TileSourceSelector(
    currentServer: TileServer,
    servers: List<TileServer> = TileServer.ALL,
    onServerSelected: (TileServer) -> Unit,
    modifier: Modifier = Modifier
) {
    var expanded by remember { mutableStateOf(false) }

    Box(modifier = modifier) {
        FilledTonalButton(onClick = { expanded = true }) {
            Icon(
                imageVector = Icons.Default.Layers,
                contentDescription = "Map layers"
            )
            Text(text = " ${currentServer.displayName}")
        }

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            servers.forEach { server ->
                DropdownMenuItem(
                    text = { Text(server.displayName) },
                    onClick = {
                        onServerSelected(server)
                        expanded = false
                    },
                    leadingIcon = if (server.id == currentServer.id) {
                        {
                            Icon(
                                imageVector = Icons.Default.Layers,
                                contentDescription = "Selected"
                            )
                        }
                    } else null
                )
            }
        }
    }
}
