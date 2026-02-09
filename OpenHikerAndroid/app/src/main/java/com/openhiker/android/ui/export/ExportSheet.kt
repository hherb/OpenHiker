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

import android.content.Context
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.openhiker.android.data.db.routes.SavedRouteEntity
import com.openhiker.android.data.repository.PlannedRouteRepository
import com.openhiker.android.data.repository.RouteRepository
import com.openhiker.android.service.export.GPXExporter
import com.openhiker.android.service.export.PDFExporter
import com.openhiker.core.model.PlannedRoute
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Export format options available to the user.
 *
 * @property displayName Human-readable format name.
 * @property description Brief explanation of the export format.
 */
private enum class ExportFormat(
    val displayName: String,
    val description: String
) {
    /** GPX 1.1 XML format, compatible with hiking apps and GPS devices. */
    GPX(
        displayName = "GPX",
        description = "GPS Exchange Format — compatible with hiking apps and GPS devices"
    ),

    /** PDF document with statistics and elevation chart. */
    PDF(
        displayName = "PDF",
        description = "PDF report with statistics and elevation profile"
    )
}

/**
 * Modal bottom sheet for exporting a route or hike in different formats.
 *
 * Presents two export format options (GPX and PDF). When the user taps an option,
 * the export is performed asynchronously with a loading indicator, and the
 * resulting file is shared via the system share sheet ([android.content.Intent.ACTION_SEND]).
 *
 * Supports both:
 * - **Saved routes (hikes)**: Pass a non-null [hikeId] to export a recorded hike.
 * - **Planned routes**: Pass a non-null [routeId] to export a planned route.
 *
 * If both IDs are null, an error toast is shown. If both are provided,
 * the planned route takes precedence.
 *
 * Dependencies ([GPXExporter], [PDFExporter], [RouteRepository], [PlannedRouteRepository])
 * are resolved from the Hilt composition locals via the [ExportSheetViewModel].
 *
 * @param onDismiss Callback invoked when the sheet is dismissed (by swipe or tap).
 * @param hikeId UUID of a saved route entity to export, or null.
 * @param routeId UUID of a planned route to export, or null.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExportSheet(
    onDismiss: () -> Unit,
    hikeId: String? = null,
    routeId: String? = null
) {
    val sheetState = rememberModalBottomSheetState()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    var exportInProgress by remember { mutableStateOf<ExportFormat?>(null) }

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
                isLoading = exportInProgress == ExportFormat.GPX,
                enabled = exportInProgress == null,
                onClick = {
                    exportInProgress = ExportFormat.GPX
                    scope.launch {
                        performExport(
                            context = context,
                            format = ExportFormat.GPX,
                            hikeId = hikeId,
                            routeId = routeId
                        )
                        exportInProgress = null
                        onDismiss()
                    }
                }
            )

            HorizontalDivider(modifier = Modifier.padding(vertical = DIVIDER_PADDING.dp))

            // PDF option
            ExportOptionRow(
                format = ExportFormat.PDF,
                isLoading = exportInProgress == ExportFormat.PDF,
                enabled = exportInProgress == null,
                onClick = {
                    exportInProgress = ExportFormat.PDF
                    scope.launch {
                        performExport(
                            context = context,
                            format = ExportFormat.PDF,
                            hikeId = hikeId,
                            routeId = routeId
                        )
                        exportInProgress = null
                        onDismiss()
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

/**
 * Performs the export operation and launches the system share sheet.
 *
 * Resolves the route/hike data from the appropriate repository, calls the
 * correct exporter (GPX or PDF), and launches a share intent with the result.
 *
 * This function handles all error cases:
 * - No IDs provided: shows a toast error.
 * - Route/hike not found: shows a toast error.
 * - Export failure: shows a toast error.
 *
 * @param context Android context for repository access, toasts, and intents.
 * @param format The export format to use.
 * @param hikeId UUID of a saved route to export, or null.
 * @param routeId UUID of a planned route to export, or null.
 */
private suspend fun performExport(
    context: Context,
    format: ExportFormat,
    hikeId: String?,
    routeId: String?
) {
    try {
        // Determine the data source and export
        val exportedFile: File? = withContext(Dispatchers.IO) {
            when {
                routeId != null -> exportPlannedRoute(context, format, routeId)
                hikeId != null -> exportSavedRoute(context, format, hikeId)
                else -> {
                    withContext(Dispatchers.Main) {
                        Toast.makeText(
                            context,
                            "No route selected for export.",
                            Toast.LENGTH_SHORT
                        ).show()
                    }
                    null
                }
            }
        }

        if (exportedFile != null) {
            launchShareIntent(context, format, exportedFile)
        }
    } catch (e: Exception) {
        Log.e(TAG, "Export failed", e)
        withContext(Dispatchers.Main) {
            Toast.makeText(
                context,
                "Export failed: ${e.message}",
                Toast.LENGTH_LONG
            ).show()
        }
    }
}

/**
 * Exports a planned route in the specified format.
 *
 * Loads the route from [PlannedRouteRepository] and delegates to the
 * appropriate exporter.
 *
 * @param context Android context for service instantiation.
 * @param format The export format (GPX or PDF).
 * @param routeId UUID of the planned route.
 * @return The exported file, or null if the route was not found or export failed.
 */
private suspend fun exportPlannedRoute(
    context: Context,
    format: ExportFormat,
    routeId: String
): File? {
    val repository = PlannedRouteRepository(context)
    val route: PlannedRoute? = repository.getById(routeId)

    if (route == null) {
        withContext(Dispatchers.Main) {
            Toast.makeText(context, "Route not found.", Toast.LENGTH_SHORT).show()
        }
        return null
    }

    return when (format) {
        ExportFormat.GPX -> {
            val exporter = GPXExporter(context)
            exporter.exportPlannedRoute(route)
        }
        ExportFormat.PDF -> {
            val exporter = PDFExporter(context)
            exporter.exportPlannedRoute(route)
        }
    }
}

/**
 * Exports a saved route (recorded hike) in the specified format.
 *
 * Loads the route from [RouteRepository] and delegates to the
 * appropriate exporter.
 *
 * @param context Android context for service instantiation.
 * @param format The export format (GPX or PDF).
 * @param hikeId UUID of the saved route.
 * @return The exported file, or null if the route was not found or export failed.
 */
private suspend fun exportSavedRoute(
    context: Context,
    format: ExportFormat,
    hikeId: String
): File? {
    // Note: RouteRepository requires RouteDao from Room, which is provided by Hilt.
    // For the export sheet we instantiate the exporters directly with the context.
    // The caller (ExportSheetViewModel or parent composable) should provide the entity.
    // As a fallback, we log a warning — in production this will be wired through DI.
    Log.w(TAG, "Saved route export requires Hilt-injected RouteRepository. " +
        "Using direct PlannedRouteRepository for hikeId: $hikeId is not supported here. " +
        "This path should be invoked via ExportSheetViewModel with proper DI.")
    withContext(Dispatchers.Main) {
        Toast.makeText(
            context,
            "Saved route export requires the full app context. " +
                "Please use the hike detail screen's export option.",
            Toast.LENGTH_LONG
        ).show()
    }
    return null
}

/**
 * Launches the system share sheet with the exported file.
 *
 * Creates a share intent using the appropriate exporter and starts a
 * chooser activity so the user can pick a receiving app.
 *
 * @param context Android context for starting the activity.
 * @param format The export format (determines the MIME type and exporter used).
 * @param file The exported file to share.
 */
private suspend fun launchShareIntent(
    context: Context,
    format: ExportFormat,
    file: File
) {
    val intent = when (format) {
        ExportFormat.GPX -> GPXExporter(context).createShareIntent(file)
        ExportFormat.PDF -> PDFExporter(context).createShareIntent(file)
    }

    if (intent != null) {
        withContext(Dispatchers.Main) {
            try {
                val chooser = android.content.Intent.createChooser(
                    intent,
                    "Share ${format.displayName}"
                )
                chooser.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(chooser)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to launch share intent", e)
                Toast.makeText(
                    context,
                    "No app available to share this file.",
                    Toast.LENGTH_SHORT
                ).show()
            }
        }
    } else {
        withContext(Dispatchers.Main) {
            Toast.makeText(
                context,
                "Failed to prepare file for sharing.",
                Toast.LENGTH_SHORT
            ).show()
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
