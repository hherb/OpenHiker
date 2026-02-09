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
import android.content.Intent
import android.util.Log
import androidx.lifecycle.ViewModel
import com.openhiker.android.data.repository.PlannedRouteRepository
import com.openhiker.android.data.repository.RouteRepository
import com.openhiker.android.service.export.GPXExporter
import com.openhiker.android.service.export.PDFExporter
import com.openhiker.core.model.PlannedRoute
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import java.io.File
import javax.inject.Inject

/**
 * Export format options available to the user.
 *
 * @property displayName Human-readable format name.
 * @property description Brief explanation of the export format.
 */
enum class ExportFormat(
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
 * UI state for the export sheet.
 *
 * @property exportInProgress The format currently being exported, or null if idle.
 * @property errorMessage An error message to display to the user, or null.
 * @property shareIntent A share intent ready to launch, or null.
 */
data class ExportUiState(
    val exportInProgress: ExportFormat? = null,
    val errorMessage: String? = null,
    val shareIntent: Intent? = null
)

/**
 * ViewModel for the export bottom sheet.
 *
 * Handles export operations with proper dependency injection via Hilt,
 * replacing the previous pattern of manually constructing exporters
 * and repositories inside composable functions.
 *
 * Exposes a single [StateFlow] of [ExportUiState] that the composable collects.
 * Error messages are surfaced in the UI state rather than via Toast to avoid
 * Activity context lifecycle issues.
 *
 * @param gpxExporter Hilt-injected GPX export service.
 * @param pdfExporter Hilt-injected PDF export service.
 * @param routeRepository Hilt-injected repository for saved routes (hikes).
 * @param plannedRouteRepository Hilt-injected repository for planned routes.
 * @param appContext Application context for share intent launching.
 */
@HiltViewModel
class ExportSheetViewModel @Inject constructor(
    private val gpxExporter: GPXExporter,
    private val pdfExporter: PDFExporter,
    private val routeRepository: RouteRepository,
    private val plannedRouteRepository: PlannedRouteRepository,
    @ApplicationContext private val appContext: Context
) : ViewModel() {

    private val _uiState = MutableStateFlow(ExportUiState())

    /** Observable UI state for the export sheet. */
    val uiState: StateFlow<ExportUiState> = _uiState.asStateFlow()

    /**
     * Performs the export operation for a route or hike.
     *
     * Resolves the route/hike data from the appropriate repository, calls the
     * correct exporter (GPX or PDF), and prepares a share intent with the result.
     * All errors are captured in [ExportUiState.errorMessage] for UI display.
     *
     * @param format The export format to use.
     * @param hikeId UUID of a saved route to export, or null.
     * @param routeId UUID of a planned route to export, or null.
     */
    suspend fun performExport(
        format: ExportFormat,
        hikeId: String?,
        routeId: String?
    ) {
        _uiState.update { it.copy(exportInProgress = format, errorMessage = null, shareIntent = null) }

        try {
            val exportResult: Result<File> = withContext(Dispatchers.IO) {
                when {
                    routeId != null -> exportPlannedRoute(format, routeId)
                    hikeId != null -> exportSavedRoute(format, hikeId)
                    else -> Result.failure(IllegalArgumentException("No route selected for export."))
                }
            }

            exportResult.fold(
                onSuccess = { file ->
                    val intent = createShareIntent(format, file)
                    if (intent != null) {
                        _uiState.update {
                            it.copy(exportInProgress = null, shareIntent = intent)
                        }
                    } else {
                        _uiState.update {
                            it.copy(
                                exportInProgress = null,
                                errorMessage = "Failed to prepare file for sharing."
                            )
                        }
                    }
                },
                onFailure = { error ->
                    _uiState.update {
                        it.copy(
                            exportInProgress = null,
                            errorMessage = "Export failed: ${error.message}"
                        )
                    }
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "Export failed", e)
            _uiState.update {
                it.copy(
                    exportInProgress = null,
                    errorMessage = "Export failed: ${e.message}"
                )
            }
        }
    }

    /**
     * Clears the error message from the UI state.
     *
     * Call this after the error has been displayed to the user (e.g. after
     * a Snackbar is shown) to prevent re-display on recomposition.
     */
    fun clearError() {
        _uiState.update { it.copy(errorMessage = null) }
    }

    /**
     * Clears the share intent from the UI state after it has been launched.
     */
    fun clearShareIntent() {
        _uiState.update { it.copy(shareIntent = null) }
    }

    /**
     * Exports a planned route in the specified format.
     *
     * @param format The export format (GPX or PDF).
     * @param routeId UUID of the planned route.
     * @return A [Result] with the exported file, or an error.
     */
    private suspend fun exportPlannedRoute(
        format: ExportFormat,
        routeId: String
    ): Result<File> {
        val route: PlannedRoute = plannedRouteRepository.getById(routeId)
            ?: return Result.failure(IllegalStateException("Route not found."))

        return when (format) {
            ExportFormat.GPX -> gpxExporter.exportPlannedRoute(route)
            ExportFormat.PDF -> pdfExporter.exportPlannedRoute(route)
        }
    }

    /**
     * Exports a saved route (recorded hike) in the specified format.
     *
     * @param format The export format (GPX or PDF).
     * @param hikeId UUID of the saved route.
     * @return A [Result] with the exported file, or an error.
     */
    private suspend fun exportSavedRoute(
        format: ExportFormat,
        hikeId: String
    ): Result<File> {
        val route = routeRepository.getById(hikeId)
            ?: return Result.failure(IllegalStateException("Hike not found."))

        return when (format) {
            ExportFormat.GPX -> gpxExporter.exportSavedRoute(route)
            ExportFormat.PDF -> pdfExporter.exportSavedRoute(route)
        }
    }

    /**
     * Creates a share intent for the exported file using the appropriate exporter.
     *
     * @param format The export format.
     * @param file The exported file.
     * @return A configured share intent, or null if URI generation fails.
     */
    private fun createShareIntent(format: ExportFormat, file: File): Intent? {
        return when (format) {
            ExportFormat.GPX -> gpxExporter.createShareIntent(file)
            ExportFormat.PDF -> pdfExporter.createShareIntent(file)
        }
    }

    companion object {
        private const val TAG = "ExportSheetVM"
    }
}
