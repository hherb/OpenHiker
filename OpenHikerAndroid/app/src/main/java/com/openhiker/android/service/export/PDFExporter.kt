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

package com.openhiker.android.service.export

import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.pdf.PdfDocument
import android.net.Uri
import android.util.Log
import androidx.core.content.FileProvider
import com.openhiker.android.data.db.routes.SavedRouteEntity
import com.openhiker.android.util.sanitizeFileName
import com.openhiker.core.compression.TrackCompression
import com.openhiker.core.compression.TrackPoint
import com.openhiker.core.model.ElevationPoint
import com.openhiker.core.model.HikeStatsFormatter
import com.openhiker.core.model.PlannedRoute
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Android PDF export service for hiking routes and recorded hikes.
 *
 * Uses [android.graphics.pdf.PdfDocument] to generate a two-page PDF report:
 * - **Page 1**: Title, date, and a statistics table showing distance,
 *   elevation gain/loss, walking/resting time, and speed data.
 * - **Page 2**: A simplified elevation profile chart rendered using
 *   [Canvas] drawing operations.
 *
 * PDF output uses US Letter size (612 x 792 points). All drawing is done
 * with the Android Canvas API -- no external PDF libraries are required.
 *
 * Supports two input types:
 * - [SavedRouteEntity]: Recorded hikes with compressed GPS track data.
 * - [PlannedRoute]: Planned routes with pre-computed elevation profiles.
 *
 * @param context Application context for cache directory and FileProvider access.
 */
@Singleton
class PDFExporter @Inject constructor(
    @ApplicationContext private val context: Context
) {

    /**
     * Exports a saved route (recorded hike) to a two-page PDF file.
     *
     * Decompresses the GPS track data to extract elevation information,
     * then renders statistics and an elevation profile chart.
     *
     * @param savedRoute The saved route entity with compressed track data.
     * @return A [Result] containing the PDF [File] on success, or the exception on failure.
     */
    suspend fun exportSavedRoute(savedRoute: SavedRouteEntity): Result<File> =
        withContext(Dispatchers.IO) {
            val document = PdfDocument()
            try {
                val trackPoints = TrackCompression.decompress(savedRoute.trackData)
                val elevationPoints = buildElevationFromTrackPoints(trackPoints)

                // Page 1: Statistics
                renderStatisticsPage(
                    document = document,
                    title = savedRoute.name,
                    date = savedRoute.startTime,
                    distance = savedRoute.totalDistance,
                    elevationGain = savedRoute.elevationGain,
                    elevationLoss = savedRoute.elevationLoss,
                    walkingTime = savedRoute.walkingTime,
                    restingTime = savedRoute.restingTime,
                    averageSpeed = calculateAverageSpeed(
                        savedRoute.totalDistance, savedRoute.walkingTime
                    ),
                    maxSpeed = null
                )

                // Page 2: Elevation Profile
                if (elevationPoints.isNotEmpty()) {
                    renderElevationPage(
                        document = document,
                        title = savedRoute.name,
                        elevationPoints = elevationPoints
                    )
                }

                val file = writeDocumentToFile(
                    document = document,
                    fileName = sanitizeFileName(savedRoute.name)
                )
                Result.success(file)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to export saved route as PDF: ${savedRoute.id}", e)
                Result.failure(e)
            } finally {
                document.close()
            }
        }

    /**
     * Exports a planned route to a two-page PDF file.
     *
     * Uses the pre-computed elevation profile (if available) for the
     * elevation chart on page 2.
     *
     * @param plannedRoute The planned route to export.
     * @return A [Result] containing the PDF [File] on success, or the exception on failure.
     */
    suspend fun exportPlannedRoute(plannedRoute: PlannedRoute): Result<File> =
        withContext(Dispatchers.IO) {
            val document = PdfDocument()
            try {
                // Page 1: Statistics
                renderStatisticsPage(
                    document = document,
                    title = plannedRoute.name,
                    date = plannedRoute.createdAt,
                    distance = plannedRoute.totalDistance,
                    elevationGain = plannedRoute.elevationGain,
                    elevationLoss = plannedRoute.elevationLoss,
                    walkingTime = plannedRoute.estimatedDuration,
                    restingTime = null,
                    averageSpeed = calculateAverageSpeed(
                        plannedRoute.totalDistance, plannedRoute.estimatedDuration
                    ),
                    maxSpeed = null
                )

                // Page 2: Elevation Profile
                val elevationPoints = plannedRoute.elevationProfile
                if (!elevationPoints.isNullOrEmpty()) {
                    renderElevationPage(
                        document = document,
                        title = plannedRoute.name,
                        elevationPoints = elevationPoints
                    )
                }

                val file = writeDocumentToFile(
                    document = document,
                    fileName = sanitizeFileName(plannedRoute.name)
                )
                Result.success(file)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to export planned route as PDF: ${plannedRoute.id}", e)
                Result.failure(e)
            } finally {
                document.close()
            }
        }

    /**
     * Creates a share [Intent] for a PDF file.
     *
     * Generates a content URI via [FileProvider] so that the receiving app
     * can read the file. Uses [Intent.ACTION_SEND] with the PDF MIME type.
     *
     * @param file The PDF file to share.
     * @return A configured share intent, or null if URI generation fails.
     */
    fun createShareIntent(file: File): Intent? {
        return try {
            val uri: Uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file
            )

            Intent(Intent.ACTION_SEND).apply {
                type = PDF_MIME_TYPE
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, file.nameWithoutExtension)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create share intent for PDF: ${file.name}", e)
            null
        }
    }

    // --- Page Rendering ---

    /**
     * Renders the first page of the PDF: title, date, and statistics table.
     *
     * Draws a title header, a date subtitle, and a two-column statistics table
     * with labeled rows for distance, elevation gain/loss, walking time,
     * resting time, and average/max speed.
     *
     * @param document The PdfDocument to add the page to.
     * @param title Route or hike name.
     * @param date ISO-8601 date string.
     * @param distance Total distance in metres.
     * @param elevationGain Cumulative elevation gain in metres.
     * @param elevationLoss Cumulative elevation loss in metres.
     * @param walkingTime Walking/active time in seconds.
     * @param restingTime Resting/stationary time in seconds, or null if not available.
     * @param averageSpeed Average speed in m/s, or null.
     * @param maxSpeed Maximum speed in m/s, or null.
     */
    private fun renderStatisticsPage(
        document: PdfDocument,
        title: String,
        date: String,
        distance: Double,
        elevationGain: Double,
        elevationLoss: Double,
        walkingTime: Double,
        restingTime: Double?,
        averageSpeed: Double?,
        maxSpeed: Double?
    ) {
        val pageInfo = PdfDocument.PageInfo.Builder(
            PAGE_WIDTH, PAGE_HEIGHT, STATS_PAGE_NUMBER
        ).create()
        val page = document.startPage(pageInfo)
        val canvas = page.canvas

        val titlePaint = Paint().apply {
            color = Color.BLACK
            textSize = TITLE_TEXT_SIZE
            isFakeBoldText = true
            isAntiAlias = true
        }

        val subtitlePaint = Paint().apply {
            color = Color.DKGRAY
            textSize = SUBTITLE_TEXT_SIZE
            isAntiAlias = true
        }

        val labelPaint = Paint().apply {
            color = Color.DKGRAY
            textSize = BODY_TEXT_SIZE
            isAntiAlias = true
        }

        val valuePaint = Paint().apply {
            color = Color.BLACK
            textSize = BODY_TEXT_SIZE
            isFakeBoldText = true
            isAntiAlias = true
        }

        val linePaint = Paint().apply {
            color = Color.LTGRAY
            strokeWidth = TABLE_LINE_WIDTH
            isAntiAlias = true
        }

        var yPosition = PAGE_MARGIN + TITLE_TEXT_SIZE

        // Title
        canvas.drawText(title, PAGE_MARGIN, yPosition, titlePaint)
        yPosition += TITLE_BOTTOM_SPACING

        // Date
        val displayDate = formatDisplayDate(date)
        canvas.drawText(displayDate, PAGE_MARGIN, yPosition, subtitlePaint)
        yPosition += DATE_BOTTOM_SPACING

        // Separator line
        canvas.drawLine(
            PAGE_MARGIN, yPosition,
            PAGE_WIDTH - PAGE_MARGIN, yPosition,
            linePaint
        )
        yPosition += SEPARATOR_BOTTOM_SPACING

        // Section header
        canvas.drawText("Route Statistics", PAGE_MARGIN, yPosition, titlePaint.apply {
            textSize = SECTION_HEADER_TEXT_SIZE
        })
        yPosition += SECTION_HEADER_BOTTOM_SPACING

        // Statistics table
        val stats = buildList {
            add("Distance" to HikeStatsFormatter.formatDistance(distance, true))
            add("Elevation Gain" to HikeStatsFormatter.formatElevation(elevationGain, true))
            add("Elevation Loss" to HikeStatsFormatter.formatElevation(elevationLoss, true))
            add("Walking Time" to HikeStatsFormatter.formatDuration(walkingTime))
            if (restingTime != null) {
                add("Resting Time" to HikeStatsFormatter.formatDuration(restingTime))
            }
            if (averageSpeed != null && averageSpeed > 0.0) {
                add("Avg Speed" to HikeStatsFormatter.formatSpeed(averageSpeed, true))
            }
            if (maxSpeed != null && maxSpeed > 0.0) {
                add("Max Speed" to HikeStatsFormatter.formatSpeed(maxSpeed, true))
            }
        }

        val labelX = PAGE_MARGIN + TABLE_LABEL_INDENT
        val valueX = PAGE_MARGIN + TABLE_VALUE_OFFSET

        for ((label, value) in stats) {
            // Row background alternation
            canvas.drawText(label, labelX, yPosition, labelPaint)
            canvas.drawText(value, valueX, yPosition, valuePaint)
            yPosition += TABLE_ROW_HEIGHT

            // Subtle row separator
            canvas.drawLine(
                PAGE_MARGIN, yPosition - TABLE_ROW_SEPARATOR_OFFSET,
                PAGE_WIDTH - PAGE_MARGIN, yPosition - TABLE_ROW_SEPARATOR_OFFSET,
                linePaint
            )
        }

        // Footer
        yPosition = PAGE_HEIGHT - PAGE_MARGIN
        val footerPaint = Paint().apply {
            color = Color.GRAY
            textSize = FOOTER_TEXT_SIZE
            isAntiAlias = true
        }
        canvas.drawText(
            "Generated by OpenHiker",
            PAGE_MARGIN,
            yPosition,
            footerPaint
        )

        document.finishPage(page)
    }

    /**
     * Renders the second page of the PDF: elevation profile chart.
     *
     * Draws a simplified line chart showing elevation (Y-axis) against
     * cumulative distance (X-axis). Includes axis labels, grid lines,
     * and a filled area under the elevation curve.
     *
     * @param document The PdfDocument to add the page to.
     * @param title Route name for the page header.
     * @param elevationPoints The elevation profile data to chart.
     */
    private fun renderElevationPage(
        document: PdfDocument,
        title: String,
        elevationPoints: List<ElevationPoint>
    ) {
        val pageInfo = PdfDocument.PageInfo.Builder(
            PAGE_WIDTH, PAGE_HEIGHT, ELEVATION_PAGE_NUMBER
        ).create()
        val page = document.startPage(pageInfo)
        val canvas = page.canvas

        val titlePaint = Paint().apply {
            color = Color.BLACK
            textSize = SECTION_HEADER_TEXT_SIZE
            isFakeBoldText = true
            isAntiAlias = true
        }

        // Page title
        canvas.drawText(
            "Elevation Profile — $title",
            PAGE_MARGIN, PAGE_MARGIN + SECTION_HEADER_TEXT_SIZE,
            titlePaint
        )

        // Chart area bounds
        val chartLeft = PAGE_MARGIN + CHART_LEFT_PADDING
        val chartRight = PAGE_WIDTH - PAGE_MARGIN
        val chartTop = PAGE_MARGIN + CHART_TOP_OFFSET
        val chartBottom = PAGE_HEIGHT - PAGE_MARGIN - CHART_BOTTOM_PADDING
        val chartWidth = chartRight - chartLeft
        val chartHeight = chartBottom - chartTop

        // Calculate data ranges
        val minElevation = elevationPoints.minOf { it.elevation }
        val maxElevation = elevationPoints.maxOf { it.elevation }
        val elevationRange = (maxElevation - minElevation).coerceAtLeast(MIN_ELEVATION_RANGE)
        val elevationPadding = elevationRange * ELEVATION_PADDING_FACTOR
        val displayMinElev = minElevation - elevationPadding
        val displayMaxElev = maxElevation + elevationPadding
        val displayElevRange = displayMaxElev - displayMinElev

        val maxDistance = elevationPoints.maxOf { it.distance }.coerceAtLeast(MIN_DISTANCE_RANGE)

        // Axis paints
        val axisPaint = Paint().apply {
            color = Color.DKGRAY
            strokeWidth = AXIS_LINE_WIDTH
            isAntiAlias = true
        }
        val gridPaint = Paint().apply {
            color = Color.LTGRAY
            strokeWidth = GRID_LINE_WIDTH
            isAntiAlias = true
        }
        val axisLabelPaint = Paint().apply {
            color = Color.DKGRAY
            textSize = AXIS_LABEL_TEXT_SIZE
            isAntiAlias = true
        }

        // Draw axes
        canvas.drawLine(chartLeft, chartTop, chartLeft, chartBottom, axisPaint)
        canvas.drawLine(chartLeft, chartBottom, chartRight, chartBottom, axisPaint)

        // Y-axis grid lines and labels (elevation)
        val elevGridCount = ELEVATION_GRID_LINES
        for (i in 0..elevGridCount) {
            val fraction = i.toFloat() / elevGridCount
            val y = chartBottom - (fraction * chartHeight)
            val elevation = displayMinElev + (fraction * displayElevRange)

            canvas.drawLine(chartLeft, y, chartRight, y, gridPaint)
            canvas.drawText(
                "${elevation.toInt()} m",
                PAGE_MARGIN,
                y + AXIS_LABEL_VERTICAL_OFFSET,
                axisLabelPaint
            )
        }

        // X-axis labels (distance)
        val distGridCount = DISTANCE_GRID_LINES
        for (i in 0..distGridCount) {
            val fraction = i.toFloat() / distGridCount
            val x = chartLeft + (fraction * chartWidth)
            val distance = fraction * maxDistance

            canvas.drawLine(x, chartTop, x, chartBottom, gridPaint)
            canvas.drawText(
                String.format(Locale.US, "%.1f km", distance / METRES_PER_KILOMETRE),
                x - DISTANCE_LABEL_HORIZONTAL_OFFSET,
                chartBottom + DISTANCE_LABEL_VERTICAL_OFFSET,
                axisLabelPaint
            )
        }

        // Draw elevation fill (area under curve)
        val fillPaint = Paint().apply {
            color = Color.argb(
                FILL_ALPHA, FILL_RED, FILL_GREEN, FILL_BLUE
            )
            style = Paint.Style.FILL
            isAntiAlias = true
        }

        val fillPath = Path()
        var started = false

        for (point in elevationPoints) {
            val x = chartLeft + ((point.distance / maxDistance) * chartWidth).toFloat()
            val y = chartBottom - (
                ((point.elevation - displayMinElev) / displayElevRange) * chartHeight
                ).toFloat()

            if (!started) {
                fillPath.moveTo(x, chartBottom)
                fillPath.lineTo(x, y)
                started = true
            } else {
                fillPath.lineTo(x, y)
            }
        }
        if (started) {
            val lastPoint = elevationPoints.last()
            val lastX = chartLeft + (
                (lastPoint.distance / maxDistance) * chartWidth
                ).toFloat()
            fillPath.lineTo(lastX, chartBottom)
            fillPath.close()
            canvas.drawPath(fillPath, fillPaint)
        }

        // Draw elevation line
        val linePaint = Paint().apply {
            color = Color.rgb(LINE_RED, LINE_GREEN, LINE_BLUE)
            strokeWidth = ELEVATION_LINE_WIDTH
            style = Paint.Style.STROKE
            isAntiAlias = true
        }

        val linePath = Path()
        for ((index, point) in elevationPoints.withIndex()) {
            val x = chartLeft + ((point.distance / maxDistance) * chartWidth).toFloat()
            val y = chartBottom - (
                ((point.elevation - displayMinElev) / displayElevRange) * chartHeight
                ).toFloat()

            if (index == 0) {
                linePath.moveTo(x, y)
            } else {
                linePath.lineTo(x, y)
            }
        }
        canvas.drawPath(linePath, linePaint)

        // Min/max elevation annotations
        val annotationPaint = Paint().apply {
            color = Color.BLACK
            textSize = ANNOTATION_TEXT_SIZE
            isFakeBoldText = true
            isAntiAlias = true
        }
        canvas.drawText(
            "Min: ${minElevation.toInt()} m",
            chartLeft + ANNOTATION_HORIZONTAL_OFFSET,
            chartBottom - ANNOTATION_VERTICAL_OFFSET,
            annotationPaint
        )
        canvas.drawText(
            "Max: ${maxElevation.toInt()} m",
            chartLeft + ANNOTATION_HORIZONTAL_OFFSET,
            chartTop + ANNOTATION_TOP_VERTICAL_OFFSET,
            annotationPaint
        )

        // Footer
        val footerPaint = Paint().apply {
            color = Color.GRAY
            textSize = FOOTER_TEXT_SIZE
            isAntiAlias = true
        }
        canvas.drawText(
            "Generated by OpenHiker",
            PAGE_MARGIN,
            PAGE_HEIGHT - PAGE_MARGIN,
            footerPaint
        )

        document.finishPage(page)
    }

    // --- Utility Functions ---

    /**
     * Builds an elevation profile from raw GPS track points.
     *
     * Computes cumulative Haversine distance between consecutive track points
     * and pairs each distance with the point's altitude to create an
     * [ElevationPoint] list suitable for charting.
     *
     * @param trackPoints The decompressed GPS track points.
     * @return Elevation profile as a list of distance-elevation pairs.
     */
    private fun buildElevationFromTrackPoints(
        trackPoints: List<TrackPoint>
    ): List<ElevationPoint> {
        if (trackPoints.isEmpty()) return emptyList()

        val result = mutableListOf<ElevationPoint>()
        var cumulativeDistance = 0.0

        result.add(ElevationPoint(0.0, trackPoints[0].altitude))

        for (i in 1 until trackPoints.size) {
            val prev = trackPoints[i - 1]
            val curr = trackPoints[i]
            cumulativeDistance += com.openhiker.core.geo.Haversine.distance(
                com.openhiker.core.model.Coordinate(prev.latitude, prev.longitude),
                com.openhiker.core.model.Coordinate(curr.latitude, curr.longitude)
            )
            result.add(ElevationPoint(cumulativeDistance, curr.altitude))
        }

        return result
    }

    /**
     * Calculates average speed from distance and time.
     *
     * @param distanceMetres Total distance in metres.
     * @param durationSeconds Total time in seconds.
     * @return Average speed in metres per second, or null if duration is zero.
     */
    private fun calculateAverageSpeed(
        distanceMetres: Double,
        durationSeconds: Double
    ): Double? {
        return if (durationSeconds > 0) distanceMetres / durationSeconds else null
    }

    /**
     * Writes a [PdfDocument] to a temporary file in the export cache directory.
     *
     * Cleans stale exports before writing to prevent unbounded cache growth.
     *
     * @param document The PdfDocument to write.
     * @param fileName The base file name (without extension).
     * @return The written [File].
     */
    private fun writeDocumentToFile(document: PdfDocument, fileName: String): File {
        val exportDir = File(context.cacheDir, EXPORT_DIR).also { it.mkdirs() }
        cleanStaleExports(exportDir)

        val file = File(exportDir, "$fileName.pdf")
        FileOutputStream(file).use { outputStream ->
            document.writeTo(outputStream)
        }
        return file
    }

    /**
     * Removes export files older than [STALE_FILE_AGE_MS] from the directory.
     *
     * @param directory The export cache directory.
     */
    private fun cleanStaleExports(directory: File) {
        val cutoff = System.currentTimeMillis() - STALE_FILE_AGE_MS
        directory.listFiles()?.forEach { file ->
            if (file.lastModified() < cutoff) {
                file.delete()
            }
        }
    }

    /**
     * Formats an ISO-8601 timestamp for display on the PDF.
     *
     * Extracts the date portion from an ISO-8601 string. If parsing fails,
     * returns the raw string as a fallback.
     *
     * @param isoDate ISO-8601 timestamp string.
     * @return A human-readable date string (e.g., "2025-06-15").
     */
    private fun formatDisplayDate(isoDate: String): String {
        return try {
            // Extract date portion from ISO-8601 (e.g., "2025-06-15T14:30:00Z" -> "2025-06-15")
            isoDate.substringBefore("T")
        } catch (_: Exception) {
            isoDate
        }
    }

    companion object {
        private const val TAG = "PDFExporter"

        // --- Page Dimensions (US Letter: 612 x 792 points) ---

        /** US Letter page width in points. */
        private const val PAGE_WIDTH = 612

        /** US Letter page height in points. */
        private const val PAGE_HEIGHT = 792

        /** Page margin in points. */
        private const val PAGE_MARGIN = 50f

        /** Page number for the statistics page. */
        private const val STATS_PAGE_NUMBER = 1

        /** Page number for the elevation profile page. */
        private const val ELEVATION_PAGE_NUMBER = 2

        // --- Text Sizes ---

        /** Title text size in points. */
        private const val TITLE_TEXT_SIZE = 24f

        /** Subtitle/date text size in points. */
        private const val SUBTITLE_TEXT_SIZE = 14f

        /** Body text size in points. */
        private const val BODY_TEXT_SIZE = 12f

        /** Section header text size in points. */
        private const val SECTION_HEADER_TEXT_SIZE = 18f

        /** Footer text size in points. */
        private const val FOOTER_TEXT_SIZE = 10f

        /** Axis label text size in points. */
        private const val AXIS_LABEL_TEXT_SIZE = 9f

        /** Annotation text size in points. */
        private const val ANNOTATION_TEXT_SIZE = 10f

        // --- Spacing ---

        /** Spacing below the title. */
        private const val TITLE_BOTTOM_SPACING = 24f

        /** Spacing below the date. */
        private const val DATE_BOTTOM_SPACING = 20f

        /** Spacing below the separator line. */
        private const val SEPARATOR_BOTTOM_SPACING = 24f

        /** Spacing below the section header. */
        private const val SECTION_HEADER_BOTTOM_SPACING = 28f

        /** Height of each row in the statistics table. */
        private const val TABLE_ROW_HEIGHT = 28f

        /** Indent for labels in the statistics table. */
        private const val TABLE_LABEL_INDENT = 10f

        /** Horizontal offset for values in the statistics table. */
        private const val TABLE_VALUE_OFFSET = 200f

        /** Offset for row separators relative to row bottom. */
        private const val TABLE_ROW_SEPARATOR_OFFSET = 8f

        // --- Line Widths ---

        /** Width of table separator lines. */
        private const val TABLE_LINE_WIDTH = 0.5f

        /** Width of chart axis lines. */
        private const val AXIS_LINE_WIDTH = 1.5f

        /** Width of chart grid lines. */
        private const val GRID_LINE_WIDTH = 0.5f

        /** Width of the elevation profile line. */
        private const val ELEVATION_LINE_WIDTH = 2f

        // --- Chart Layout ---

        /** Left padding for chart (for Y-axis labels). */
        private const val CHART_LEFT_PADDING = 50f

        /** Top offset for chart below page header. */
        private const val CHART_TOP_OFFSET = 80f

        /** Bottom padding for chart (for X-axis labels). */
        private const val CHART_BOTTOM_PADDING = 40f

        /** Number of horizontal grid lines for elevation. */
        private const val ELEVATION_GRID_LINES = 5

        /** Number of vertical grid lines for distance. */
        private const val DISTANCE_GRID_LINES = 5

        /** Vertical offset for Y-axis labels relative to grid line. */
        private const val AXIS_LABEL_VERTICAL_OFFSET = 4f

        /** Horizontal offset for X-axis distance labels. */
        private const val DISTANCE_LABEL_HORIZONTAL_OFFSET = 15f

        /** Vertical offset for X-axis distance labels below axis. */
        private const val DISTANCE_LABEL_VERTICAL_OFFSET = 20f

        /** Horizontal offset for min/max annotations. */
        private const val ANNOTATION_HORIZONTAL_OFFSET = 10f

        /** Vertical offset for min annotation from chart bottom. */
        private const val ANNOTATION_VERTICAL_OFFSET = 10f

        /** Vertical offset for max annotation from chart top. */
        private const val ANNOTATION_TOP_VERTICAL_OFFSET = 20f

        // --- Chart Colours ---

        /** Alpha component for the elevation fill area. */
        private const val FILL_ALPHA = 60

        /** Red component for the elevation fill area. */
        private const val FILL_RED = 76

        /** Green component for the elevation fill area. */
        private const val FILL_GREEN = 175

        /** Blue component for the elevation fill area. */
        private const val FILL_BLUE = 80

        /** Red component for the elevation line. */
        private const val LINE_RED = 46

        /** Green component for the elevation line. */
        private const val LINE_GREEN = 125

        /** Blue component for the elevation line. */
        private const val LINE_BLUE = 50

        // --- Data Ranges ---

        /** Minimum elevation range to prevent flat-line charts (10 metres). */
        private const val MIN_ELEVATION_RANGE = 10.0

        /** Minimum distance range to prevent division by zero (100 metres). */
        private const val MIN_DISTANCE_RANGE = 100.0

        /** Padding factor above/below elevation extremes for visual breathing room. */
        private const val ELEVATION_PADDING_FACTOR = 0.1

        /** Metres per kilometre for distance label formatting. */
        private const val METRES_PER_KILOMETRE = 1000.0

        // --- Cache Management ---

        /** Subdirectory within the app cache for temporary PDF export files. */
        private const val EXPORT_DIR = "pdf_exports"

        /** Maximum age of cached export files before cleanup (1 hour). */
        private const val STALE_FILE_AGE_MS = 60 * 60 * 1000L

        /** MIME type for PDF files. */
        private const val PDF_MIME_TYPE = "application/pdf"
    }
}
