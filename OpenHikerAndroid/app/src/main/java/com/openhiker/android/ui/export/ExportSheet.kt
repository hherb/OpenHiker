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

package com.openhiker.android.ui.export

import android.content.Intent
import android.util.Log
import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import kotlinx.coroutines.launch

/**
 * Modal bottom sheet for exporting a route or hike in different formats.
 *
 * Presents two export format options (GPX and PDF). When the user taps an option,
 * the export is performed asynchronously with a loading indicator, and the
 * resulting file is shared via the system share sheet ([Intent.ACTION_SEND]).
 *
 * Supports both:
 * - **Saved routes (hikes)**: Pass a non-null [hikeId] to export a recorded hike.
 * - **Planned routes**: Pass a non-null [routeId] to export a planned route.
 *
 * If both IDs are null, an error is shown. If both are provided,
 * the planned route takes precedence.
 *
 * Dependencies ([GPXExporter], [PDFExporter], [RouteRepository], [PlannedRouteRepository])
 * are resolved via the Hilt-injected [ExportSheetViewModel].
 *
 * @param onDismiss Callback invoked when the sheet is dismissed (by swipe or tap).
 * @param hikeId UUID of a saved route entity to export, or null.
 * @param routeId UUID of a planned route to export, or null.
 * @param viewModel The Hilt-injected ViewModel handling export logic.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExportSheet(
    onDismiss: () -> Unit,
    hikeId: String? = null,
    routeId: String? = null,
    viewModel: ExportSheetViewModel = hiltViewModel()
) {
    val sheetState = rememberModalBottomSheetState()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()

    // Show error messages via Toast using applicationContext to avoid lifecycle issues
    LaunchedEffect(uiState.errorMessage) {
        val message = uiState.errorMessage ?: return@LaunchedEffect
        Toast.makeText(context.applicationContext, message, Toast.LENGTH_LONG).show()
        viewModel.clearError()
    }

    // Launch share intent when ready
    LaunchedEffect(uiState.shareIntent) {
        val intent = uiState.shareIntent ?: return@LaunchedEffect
        try {
            val chooser = Intent.createChooser(intent, "Share Route")
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(chooser)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch share intent", e)
            Toast.makeText(
                context.applicationContext,
                "No app available to share this file.",
                Toast.LENGTH_SHORT
            ).show()
        }
        viewModel.clearShareIntent()
        onDismiss()
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = SHEET_HORIZONTAL_PADDING.dp)
                .padding(bottom = SHEET_BOTTOM_PADDING.dp)
        ) {
            // Sheet title
            Text(
                text = "Export Route",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(bottom = TITLE_BOTTOM_PADDING.dp)
            )

            // GPX option
            ExportOptionRow(
                format = ExportFormat.GPX,
                isLoading = uiState.exportInProgress == ExportFormat.GPX,
                enabled = uiState.exportInProgress == null,
                onClick = {
                    scope.launch {
                        viewModel.performExport(
                            format = ExportFormat.GPX,
                            hikeId = hikeId,
                            routeId = routeId
                        )
                    }
                }
            )

            HorizontalDivider(modifier = Modifier.padding(vertical = DIVIDER_PADDING.dp))

            // PDF option
            ExportOptionRow(
                format = ExportFormat.PDF,
                isLoading = uiState.exportInProgress == ExportFormat.PDF,
                enabled = uiState.exportInProgress == null,
                onClick = {
                    scope.launch {
                        viewModel.performExport(
                            format = ExportFormat.PDF,
                            hikeId = hikeId,
                            routeId = routeId
                        )
                    }
                }
            )

            Spacer(modifier = Modifier.height(SHEET_BOTTOM_SPACER.dp))
        }
    }
}

/**
 * A single export format option row in the bottom sheet.
 *
 * Shows an icon (GPX = document icon, PDF = PDF icon), the format name,
 * a description, and optionally a loading indicator while export is in progress.
 *
 * @param format The export format to display.
 * @param isLoading True if this format's export is currently in progress.
 * @param enabled True if the row is tappable (false when another export is running).
 * @param onClick Callback invoked when the row is tapped.
 */
@Composable
private fun ExportOptionRow(
    format: ExportFormat,
    isLoading: Boolean,
    enabled: Boolean,
    onClick: () -> Unit
) {
    val icon = when (format) {
        ExportFormat.GPX -> Icons.Default.Description
        ExportFormat.PDF -> Icons.Default.PictureAsPdf
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled && !isLoading, onClick = onClick)
            .padding(vertical = OPTION_ROW_VERTICAL_PADDING.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = format.displayName,
            modifier = Modifier.size(OPTION_ICON_SIZE.dp),
            tint = if (enabled) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            }
        )

        Spacer(modifier = Modifier.width(OPTION_ICON_TEXT_SPACING.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = format.displayName,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = format.description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        if (isLoading) {
            Spacer(modifier = Modifier.width(OPTION_ICON_TEXT_SPACING.dp))
            CircularProgressIndicator(
                modifier = Modifier.size(LOADING_INDICATOR_SIZE.dp),
                strokeWidth = LOADING_INDICATOR_STROKE.dp
            )
        }
    }
}

/** Log tag for this file. */
private const val TAG = "ExportSheet"

// --- Layout Constants ---

/** Horizontal padding for the bottom sheet content. */
private const val SHEET_HORIZONTAL_PADDING = 24

/** Bottom padding for the bottom sheet content. */
private const val SHEET_BOTTOM_PADDING = 16

/** Bottom padding below the sheet title. */
private const val TITLE_BOTTOM_PADDING = 16

/** Vertical padding for dividers between options. */
private const val DIVIDER_PADDING = 4

/** Bottom spacer height for sheet dismissal handle clearance. */
private const val SHEET_BOTTOM_SPACER = 16

/** Vertical padding for each option row. */
private const val OPTION_ROW_VERTICAL_PADDING = 12

/** Size of the format icon in each option row. */
private const val OPTION_ICON_SIZE = 32

/** Spacing between the icon and text in each option row. */
private const val OPTION_ICON_TEXT_SPACING = 16

/** Size of the loading indicator shown during export. */
private const val LOADING_INDICATOR_SIZE = 24

/** Stroke width of the loading indicator. */
private const val LOADING_INDICATOR_STROKE = 2
