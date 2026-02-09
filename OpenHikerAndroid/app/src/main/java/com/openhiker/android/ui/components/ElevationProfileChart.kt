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

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.openhiker.android.ui.theme.ElevationHigh
import com.openhiker.android.ui.theme.ElevationLow
import com.openhiker.core.model.ElevationPoint
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.roundToInt

// ──────────────────────────────────────────────────────────────────────────────
// Configuration constants
// ──────────────────────────────────────────────────────────────────────────────

/** Minimum vertical padding (metres) above max elevation and below min elevation. */
private const val ELEVATION_PADDING_FACTOR = 0.05

/** Minimum number of data points required to render the chart. */
private const val MIN_DATA_POINTS = 2

/** Metres in one kilometre, used for distance axis conversion. */
private const val METRES_PER_KM = 1_000.0

/** Desired approximate number of tick marks on the X axis. */
private const val TARGET_X_TICKS = 5

/** Desired approximate number of tick marks on the Y axis. */
private const val TARGET_Y_TICKS = 5

/** Length of axis tick marks in density-independent pixels. */
private val TICK_LENGTH = 4.dp

/** Radius of the current-position indicator dot in density-independent pixels. */
private val POSITION_DOT_RADIUS = 6.dp

/** Width of the elevation profile line stroke in density-independent pixels. */
private val LINE_STROKE_WIDTH = 2.dp

/** Width of the crosshair stroke in density-independent pixels. */
private val CROSSHAIR_STROKE_WIDTH = 1.dp

/** Radius within which a touch point snaps to the nearest data point, in pixels. */
private const val TOUCH_SNAP_RADIUS_PX = 40f

/** Alpha value for the gradient fill under the elevation line. */
private const val GRADIENT_FILL_ALPHA = 0.35f

/** Alpha value for the min/max elevation label backgrounds. */
private const val LABEL_BACKGROUND_ALPHA = 0.7f

/** Corner radius for the crosshair tooltip background in density-independent pixels. */
private val TOOLTIP_CORNER_RADIUS = 4.dp

/** Duration of the current-position animation in milliseconds. */
private const val POSITION_ANIMATION_DURATION_MS = 600

// ──────────────────────────────────────────────────────────────────────────────
// Public composable
// ──────────────────────────────────────────────────────────────────────────────

/**
 * A reusable Jetpack Compose component that renders an elevation profile chart.
 *
 * The chart is drawn entirely using Compose [Canvas] (no third-party charting library).
 * It displays the elevation profile as a line with a gradient fill underneath,
 * transitioning from green at low elevations to brown at high elevations.
 *
 * **Features:**
 * - X-axis showing distance in kilometres, Y-axis showing elevation in metres.
 * - Gradient fill under the elevation line (green at bottom, brown at top).
 * - Min and max elevation labels rendered on the chart.
 * - Touch/drag crosshair interaction showing the elevation and distance at the touch point.
 * - Optional animated current-position indicator for use during active navigation.
 *
 * **Usage example:**
 * ```kotlin
 * ElevationProfileChart(
 *     points = route.elevationProfile,
 *     currentDistanceMetres = navigationState.distanceTravelled,
 *     modifier = Modifier
 *         .fillMaxWidth()
 *         .height(200.dp)
 * )
 * ```
 *
 * @param points The elevation profile data as a list of [ElevationPoint] values.
 *   Each point contains a cumulative distance (metres) and elevation (metres).
 *   Must contain at least [MIN_DATA_POINTS] entries to render. If the list is
 *   too small, a placeholder message is displayed instead.
 * @param currentDistanceMetres Optional distance (in metres) from route start indicating
 *   the user's current position along the route. When non-null, an animated position
 *   indicator (coloured dot with vertical line) is drawn at the corresponding point
 *   on the profile. Pass `null` when not navigating.
 * @param modifier Compose [Modifier] applied to the chart container. Callers should
 *   supply sizing constraints (e.g. `Modifier.fillMaxWidth().height(200.dp)`).
 * @param lineColor Color of the main elevation profile line. Defaults to [ElevationLow].
 * @param gradientTopColor Top colour of the vertical gradient fill. Defaults to [ElevationHigh].
 * @param gradientBottomColor Bottom colour of the vertical gradient fill. Defaults to [ElevationLow].
 * @param positionIndicatorColor Colour of the current-position dot. Defaults to [Color.Blue].
 * @param crosshairColor Colour of the touch crosshair lines. Defaults to dark grey.
 */
@Composable
fun ElevationProfileChart(
    points: List<ElevationPoint>,
    currentDistanceMetres: Double? = null,
    modifier: Modifier = Modifier,
    lineColor: Color = ElevationLow,
    gradientTopColor: Color = ElevationHigh,
    gradientBottomColor: Color = ElevationLow,
    positionIndicatorColor: Color = Color(0xFF1565C0),
    crosshairColor: Color = Color(0xFF424242)
) {
    if (points.size < MIN_DATA_POINTS) {
        EmptyChartPlaceholder(modifier)
        return
    }

    val sortedPoints = remember(points) { points.sortedBy { it.distance } }

    // Compute data bounds once when points change.
    val dataBounds = remember(sortedPoints) { computeDataBounds(sortedPoints) }

    // State for touch interaction: stores the pixel X coordinate of the touch, or null.
    var touchX by remember { mutableStateOf<Float?>(null) }

    // Animated progress for the current-position indicator (0f..1f).
    val positionAnimatable = remember { Animatable(0f) }

    // Drive the position indicator animation whenever currentDistanceMetres changes.
    LaunchedEffect(currentDistanceMetres, dataBounds) {
        if (currentDistanceMetres != null && dataBounds.distanceRange > 0.0) {
            val targetFraction = ((currentDistanceMetres - dataBounds.minDistance) /
                dataBounds.distanceRange).coerceIn(0.0, 1.0).toFloat()
            positionAnimatable.animateTo(
                targetValue = targetFraction,
                animationSpec = tween(durationMillis = POSITION_ANIMATION_DURATION_MS)
            )
        }
    }

    val textMeasurer = rememberTextMeasurer()
    val density = LocalDensity.current

    // Pre-compute pixel values that depend on density.
    val tickLengthPx = with(density) { TICK_LENGTH.toPx() }
    val lineStrokeWidthPx = with(density) { LINE_STROKE_WIDTH.toPx() }
    val crosshairStrokeWidthPx = with(density) { CROSSHAIR_STROKE_WIDTH.toPx() }
    val positionDotRadiusPx = with(density) { POSITION_DOT_RADIUS.toPx() }
    val tooltipCornerRadiusPx = with(density) { TOOLTIP_CORNER_RADIUS.toPx() }

    val axisLabelStyle = TextStyle(
        fontSize = 10.sp,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
    val tooltipTextStyle = TextStyle(
        fontSize = 11.sp,
        color = MaterialTheme.colorScheme.onSurface
    )
    val minMaxLabelStyle = TextStyle(
        fontSize = 10.sp,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )

    // Measure sample axis labels to compute chart padding.
    val sampleYLabel = textMeasurer.measure("8888 m", axisLabelStyle)
    val sampleXLabel = textMeasurer.measure("88.8", axisLabelStyle)

    val paddingLeft = sampleYLabel.size.width.toFloat() + tickLengthPx + 4f
    val paddingBottom = sampleXLabel.size.height.toFloat() + tickLengthPx + 14f
    val paddingTop = 16f
    val paddingRight = 16f

    Box(modifier = modifier) {
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(Unit) {
                    detectTapGestures { offset ->
                        touchX = if (offset.x in paddingLeft..(size.width - paddingRight)) {
                            offset.x
                        } else {
                            null
                        }
                    }
                }
                .pointerInput(Unit) {
                    detectDragGestures(
                        onDragStart = { offset ->
                            touchX = if (offset.x in paddingLeft..(size.width - paddingRight)) {
                                offset.x
                            } else {
                                null
                            }
                        },
                        onDrag = { change, _ ->
                            change.consume()
                            val x = change.position.x
                            touchX = if (x in paddingLeft..(size.width - paddingRight)) {
                                x
                            } else {
                                null
                            }
                        },
                        onDragEnd = { touchX = null },
                        onDragCancel = { touchX = null }
                    )
                }
        ) {
            val chartWidth = size.width - paddingLeft - paddingRight
            val chartHeight = size.height - paddingTop - paddingBottom

            if (chartWidth <= 0f || chartHeight <= 0f) return@Canvas

            val chartArea = ChartArea(
                left = paddingLeft,
                top = paddingTop,
                width = chartWidth,
                height = chartHeight
            )

            // Draw axes and tick labels.
            drawAxes(
                chartArea = chartArea,
                dataBounds = dataBounds,
                tickLengthPx = tickLengthPx,
                textMeasurer = textMeasurer,
                axisLabelStyle = axisLabelStyle,
                axisColor = crosshairColor.copy(alpha = 0.5f)
            )

            // Build the line path and the fill path.
            val (linePath, fillPath) = buildElevationPaths(
                sortedPoints = sortedPoints,
                chartArea = chartArea,
                dataBounds = dataBounds
            )

            // Draw gradient fill under the line.
            drawPath(
                path = fillPath,
                brush = Brush.verticalGradient(
                    colors = listOf(
                        gradientTopColor.copy(alpha = GRADIENT_FILL_ALPHA),
                        gradientBottomColor.copy(alpha = GRADIENT_FILL_ALPHA)
                    ),
                    startY = chartArea.top,
                    endY = chartArea.top + chartArea.height
                ),
                style = Fill
            )

            // Draw the elevation line.
            drawPath(
                path = linePath,
                color = lineColor,
                style = Stroke(
                    width = lineStrokeWidthPx,
                    cap = StrokeCap.Round,
                    join = StrokeJoin.Round
                )
            )

            // Draw min/max elevation labels.
            drawMinMaxLabels(
                sortedPoints = sortedPoints,
                chartArea = chartArea,
                dataBounds = dataBounds,
                textMeasurer = textMeasurer,
                labelStyle = minMaxLabelStyle,
                backgroundColor = MaterialTheme.colorScheme.surface
                    .copy(alpha = LABEL_BACKGROUND_ALPHA)
            )

            // Draw the current-position indicator if navigating.
            if (currentDistanceMetres != null) {
                drawPositionIndicator(
                    fractionAlongRoute = positionAnimatable.value,
                    sortedPoints = sortedPoints,
                    chartArea = chartArea,
                    dataBounds = dataBounds,
                    dotRadiusPx = positionDotRadiusPx,
                    indicatorColor = positionIndicatorColor
                )
            }

            // Draw crosshair if the user is touching the chart.
            val currentTouchX = touchX
            if (currentTouchX != null) {
                drawCrosshair(
                    touchXPx = currentTouchX,
                    sortedPoints = sortedPoints,
                    chartArea = chartArea,
                    dataBounds = dataBounds,
                    crosshairColor = crosshairColor,
                    crosshairStrokeWidthPx = crosshairStrokeWidthPx,
                    dotRadiusPx = positionDotRadiusPx,
                    tooltipCornerRadiusPx = tooltipCornerRadiusPx,
                    textMeasurer = textMeasurer,
                    tooltipTextStyle = tooltipTextStyle,
                    tooltipBackgroundColor = MaterialTheme.colorScheme.surfaceVariant
                )
            }

            // Draw "Distance (km)" axis title below the X axis.
            val xAxisTitle = textMeasurer.measure("Distance (km)", axisLabelStyle)
            drawText(
                textLayoutResult = xAxisTitle,
                topLeft = Offset(
                    x = chartArea.left + (chartArea.width - xAxisTitle.size.width) / 2f,
                    y = size.height - xAxisTitle.size.height.toFloat()
                )
            )
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// Placeholder for insufficient data
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Displays a centered message when the chart has insufficient data points.
 *
 * Shown in place of the chart when fewer than [MIN_DATA_POINTS] elevation points
 * are available.
 *
 * @param modifier Compose modifier forwarded from the parent.
 */
@Composable
private fun EmptyChartPlaceholder(modifier: Modifier) {
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Text(
            text = "Not enough elevation data to display chart",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// Internal data classes
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Pre-computed bounds of the elevation profile data.
 *
 * Used to map data-space values (distance in metres, elevation in metres) to
 * pixel-space coordinates within the chart area.
 *
 * @property minDistance The smallest distance value in metres.
 * @property maxDistance The largest distance value in metres.
 * @property minElevation The lowest elevation value in metres (with padding).
 * @property maxElevation The highest elevation value in metres (with padding).
 * @property distanceRange Span of distance values (maxDistance - minDistance).
 * @property elevationRange Span of elevation values (maxElevation - minElevation).
 * @property rawMinElevation Actual minimum elevation before padding, for labelling.
 * @property rawMaxElevation Actual maximum elevation before padding, for labelling.
 * @property minElevationIndex Index of the point with the lowest raw elevation.
 * @property maxElevationIndex Index of the point with the highest raw elevation.
 */
private data class DataBounds(
    val minDistance: Double,
    val maxDistance: Double,
    val minElevation: Double,
    val maxElevation: Double,
    val distanceRange: Double,
    val elevationRange: Double,
    val rawMinElevation: Double,
    val rawMaxElevation: Double,
    val minElevationIndex: Int,
    val maxElevationIndex: Int
)

/**
 * Describes the pixel-space rectangle in which the chart content is drawn.
 *
 * Excludes axis labels and padding.
 *
 * @property left X pixel coordinate of the chart area's left edge.
 * @property top Y pixel coordinate of the chart area's top edge.
 * @property width Width of the chart area in pixels.
 * @property height Height of the chart area in pixels.
 */
private data class ChartArea(
    val left: Float,
    val top: Float,
    val width: Float,
    val height: Float
)

// ──────────────────────────────────────────────────────────────────────────────
// Pure computation helpers
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Computes the data bounds from a sorted list of elevation points.
 *
 * Adds vertical padding of [ELEVATION_PADDING_FACTOR] times the raw elevation
 * range to both the top and bottom so the line does not touch the chart edges.
 * If the elevation range is zero (flat route), a minimum padding of 10 metres
 * is applied.
 *
 * @param sortedPoints Elevation points sorted by ascending distance.
 * @return A [DataBounds] instance containing all derived limits.
 */
private fun computeDataBounds(sortedPoints: List<ElevationPoint>): DataBounds {
    val minDist = sortedPoints.first().distance
    val maxDist = sortedPoints.last().distance

    var rawMinElev = Double.MAX_VALUE
    var rawMaxElev = Double.MIN_VALUE
    var minIdx = 0
    var maxIdx = 0

    sortedPoints.forEachIndexed { index, point ->
        if (point.elevation < rawMinElev) {
            rawMinElev = point.elevation
            minIdx = index
        }
        if (point.elevation > rawMaxElev) {
            rawMaxElev = point.elevation
            maxIdx = index
        }
    }

    val rawRange = rawMaxElev - rawMinElev
    val padding = if (rawRange > 0) rawRange * ELEVATION_PADDING_FACTOR else 10.0
    val paddedMin = rawMinElev - padding
    val paddedMax = rawMaxElev + padding

    return DataBounds(
        minDistance = minDist,
        maxDistance = maxDist,
        minElevation = paddedMin,
        maxElevation = paddedMax,
        distanceRange = maxDist - minDist,
        elevationRange = paddedMax - paddedMin,
        rawMinElevation = rawMinElev,
        rawMaxElevation = rawMaxElev,
        minElevationIndex = minIdx,
        maxElevationIndex = maxIdx
    )
}

/**
 * Maps a data-space distance (metres) to a pixel X coordinate within the chart area.
 *
 * @param distance Distance in metres.
 * @param chartArea The pixel-space chart rectangle.
 * @param dataBounds Pre-computed data bounds.
 * @return X coordinate in pixels.
 */
private fun distanceToPixelX(
    distance: Double,
    chartArea: ChartArea,
    dataBounds: DataBounds
): Float {
    if (dataBounds.distanceRange == 0.0) return chartArea.left + chartArea.width / 2f
    val fraction = (distance - dataBounds.minDistance) / dataBounds.distanceRange
    return chartArea.left + (fraction * chartArea.width).toFloat()
}

/**
 * Maps a data-space elevation (metres) to a pixel Y coordinate within the chart area.
 *
 * Y axis is inverted: higher elevation produces a smaller Y value (closer to top).
 *
 * @param elevation Elevation in metres.
 * @param chartArea The pixel-space chart rectangle.
 * @param dataBounds Pre-computed data bounds.
 * @return Y coordinate in pixels.
 */
private fun elevationToPixelY(
    elevation: Double,
    chartArea: ChartArea,
    dataBounds: DataBounds
): Float {
    if (dataBounds.elevationRange == 0.0) return chartArea.top + chartArea.height / 2f
    val fraction = (elevation - dataBounds.minElevation) / dataBounds.elevationRange
    return chartArea.top + chartArea.height - (fraction * chartArea.height).toFloat()
}

/**
 * Maps a pixel X coordinate back to a distance (metres) in data space.
 *
 * @param pixelX The X coordinate in pixels.
 * @param chartArea The pixel-space chart rectangle.
 * @param dataBounds Pre-computed data bounds.
 * @return Distance in metres.
 */
private fun pixelXToDistance(
    pixelX: Float,
    chartArea: ChartArea,
    dataBounds: DataBounds
): Double {
    val fraction = ((pixelX - chartArea.left) / chartArea.width).toDouble()
    return dataBounds.minDistance + fraction * dataBounds.distanceRange
}

/**
 * Finds the elevation point in [sortedPoints] closest to the given [targetDistance].
 *
 * Uses binary search for efficiency on large profiles.
 *
 * @param sortedPoints Elevation points sorted by ascending distance.
 * @param targetDistance The target distance in metres.
 * @return The [ElevationPoint] nearest to [targetDistance].
 */
private fun findNearestPoint(
    sortedPoints: List<ElevationPoint>,
    targetDistance: Double
): ElevationPoint {
    var low = 0
    var high = sortedPoints.lastIndex

    while (low < high) {
        val mid = (low + high) / 2
        if (sortedPoints[mid].distance < targetDistance) {
            low = mid + 1
        } else {
            high = mid
        }
    }

    // Check the candidate and its neighbour to find the true closest point.
    val candidate = sortedPoints[low]
    if (low > 0) {
        val previous = sortedPoints[low - 1]
        if (abs(previous.distance - targetDistance) < abs(candidate.distance - targetDistance)) {
            return previous
        }
    }
    return candidate
}

/**
 * Computes "nice" tick values for an axis given a data range and desired count.
 *
 * Produces evenly-spaced round numbers (multiples of 1, 2, 5, 10, 20, 50, etc.)
 * that cover the data range.
 *
 * @param min The minimum data value.
 * @param max The maximum data value.
 * @param targetCount Approximate number of ticks desired.
 * @return A list of tick values within [min]..[max].
 */
private fun computeNiceTicks(min: Double, max: Double, targetCount: Int): List<Double> {
    val range = max - min
    if (range <= 0.0) return listOf(min)

    val roughStep = range / targetCount
    val magnitude = Math.pow(10.0, floor(Math.log10(roughStep)))
    val fraction = roughStep / magnitude

    val niceStep = when {
        fraction <= 1.5 -> magnitude
        fraction <= 3.5 -> 2.0 * magnitude
        fraction <= 7.5 -> 5.0 * magnitude
        else -> 10.0 * magnitude
    }

    val start = ceil(min / niceStep) * niceStep
    val ticks = mutableListOf<Double>()
    var value = start
    while (value <= max + niceStep * 0.001) {
        ticks.add(value)
        value += niceStep
    }
    return ticks
}

// ──────────────────────────────────────────────────────────────────────────────
// Path builders
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Builds the line path and the closed gradient fill path from sorted elevation points.
 *
 * The line path traces the elevation profile from left to right. The fill path
 * is the same line closed along the bottom edge of the chart area, forming a
 * polygon suitable for gradient fill.
 *
 * @param sortedPoints Elevation points sorted by ascending distance.
 * @param chartArea The pixel-space chart rectangle.
 * @param dataBounds Pre-computed data bounds.
 * @return A [Pair] of (linePath, fillPath).
 */
private fun buildElevationPaths(
    sortedPoints: List<ElevationPoint>,
    chartArea: ChartArea,
    dataBounds: DataBounds
): Pair<Path, Path> {
    val linePath = Path()
    val fillPath = Path()

    val firstX = distanceToPixelX(sortedPoints.first().distance, chartArea, dataBounds)
    val firstY = elevationToPixelY(sortedPoints.first().elevation, chartArea, dataBounds)
    val bottomY = chartArea.top + chartArea.height

    linePath.moveTo(firstX, firstY)
    fillPath.moveTo(firstX, bottomY)
    fillPath.lineTo(firstX, firstY)

    for (i in 1 until sortedPoints.size) {
        val px = distanceToPixelX(sortedPoints[i].distance, chartArea, dataBounds)
        val py = elevationToPixelY(sortedPoints[i].elevation, chartArea, dataBounds)
        linePath.lineTo(px, py)
        fillPath.lineTo(px, py)
    }

    val lastX = distanceToPixelX(sortedPoints.last().distance, chartArea, dataBounds)
    fillPath.lineTo(lastX, bottomY)
    fillPath.close()

    return linePath to fillPath
}

// ──────────────────────────────────────────────────────────────────────────────
// Drawing helpers (DrawScope extensions)
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Draws the X and Y axes, tick marks, and tick labels.
 *
 * The Y axis is drawn on the left edge of the chart area with elevation labels (m).
 * The X axis is drawn on the bottom edge with distance labels (km).
 * Grid lines are drawn as faint dashed lines for each tick.
 *
 * @param chartArea The pixel-space chart rectangle.
 * @param dataBounds Pre-computed data bounds.
 * @param tickLengthPx Length of tick marks in pixels.
 * @param textMeasurer The Compose text measurer for rendering labels.
 * @param axisLabelStyle Text style for axis labels.
 * @param axisColor Color for axis lines and ticks.
 */
private fun DrawScope.drawAxes(
    chartArea: ChartArea,
    dataBounds: DataBounds,
    tickLengthPx: Float,
    textMeasurer: TextMeasurer,
    axisLabelStyle: TextStyle,
    axisColor: Color
) {
    val bottomY = chartArea.top + chartArea.height
    val rightX = chartArea.left + chartArea.width

    // Draw Y axis line.
    drawLine(
        color = axisColor,
        start = Offset(chartArea.left, chartArea.top),
        end = Offset(chartArea.left, bottomY),
        strokeWidth = 1f
    )

    // Draw X axis line.
    drawLine(
        color = axisColor,
        start = Offset(chartArea.left, bottomY),
        end = Offset(rightX, bottomY),
        strokeWidth = 1f
    )

    val dashEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 4f), 0f)

    // Y axis ticks (elevation in metres).
    val yTicks = computeNiceTicks(dataBounds.minElevation, dataBounds.maxElevation, TARGET_Y_TICKS)
    for (tickValue in yTicks) {
        val y = elevationToPixelY(tickValue, chartArea, dataBounds)
        if (y < chartArea.top || y > bottomY) continue

        // Tick mark.
        drawLine(
            color = axisColor,
            start = Offset(chartArea.left - tickLengthPx, y),
            end = Offset(chartArea.left, y),
            strokeWidth = 1f
        )

        // Grid line.
        drawLine(
            color = axisColor.copy(alpha = 0.15f),
            start = Offset(chartArea.left, y),
            end = Offset(rightX, y),
            strokeWidth = 1f,
            pathEffect = dashEffect
        )

        // Label.
        val label = "${tickValue.roundToInt()} m"
        val measured = textMeasurer.measure(label, axisLabelStyle)
        drawText(
            textLayoutResult = measured,
            topLeft = Offset(
                x = chartArea.left - tickLengthPx - measured.size.width - 2f,
                y = y - measured.size.height / 2f
            )
        )
    }

    // X axis ticks (distance in kilometres).
    val minDistKm = dataBounds.minDistance / METRES_PER_KM
    val maxDistKm = dataBounds.maxDistance / METRES_PER_KM
    val xTicks = computeNiceTicks(minDistKm, maxDistKm, TARGET_X_TICKS)
    for (tickValueKm in xTicks) {
        val tickValueM = tickValueKm * METRES_PER_KM
        val x = distanceToPixelX(tickValueM, chartArea, dataBounds)
        if (x < chartArea.left || x > rightX) continue

        // Tick mark.
        drawLine(
            color = axisColor,
            start = Offset(x, bottomY),
            end = Offset(x, bottomY + tickLengthPx),
            strokeWidth = 1f
        )

        // Grid line.
        drawLine(
            color = axisColor.copy(alpha = 0.15f),
            start = Offset(x, chartArea.top),
            end = Offset(x, bottomY),
            strokeWidth = 1f,
            pathEffect = dashEffect
        )

        // Label.
        val label = formatDistanceLabel(tickValueKm)
        val measured = textMeasurer.measure(label, axisLabelStyle)
        drawText(
            textLayoutResult = measured,
            topLeft = Offset(
                x = x - measured.size.width / 2f,
                y = bottomY + tickLengthPx + 2f
            )
        )
    }
}

/**
 * Draws min and max elevation labels near their respective points on the chart.
 *
 * Each label shows the elevation value with an "m" suffix, drawn with a semi-transparent
 * background for readability over the gradient fill.
 *
 * @param sortedPoints Elevation points sorted by ascending distance.
 * @param chartArea The pixel-space chart rectangle.
 * @param dataBounds Pre-computed data bounds (contains min/max indices).
 * @param textMeasurer The Compose text measurer.
 * @param labelStyle Text style for the labels.
 * @param backgroundColor Background colour behind the label text.
 */
private fun DrawScope.drawMinMaxLabels(
    sortedPoints: List<ElevationPoint>,
    chartArea: ChartArea,
    dataBounds: DataBounds,
    textMeasurer: TextMeasurer,
    labelStyle: TextStyle,
    backgroundColor: Color
) {
    // Draw max elevation label.
    val maxPoint = sortedPoints[dataBounds.maxElevationIndex]
    val maxX = distanceToPixelX(maxPoint.distance, chartArea, dataBounds)
    val maxY = elevationToPixelY(maxPoint.elevation, chartArea, dataBounds)
    val maxLabel = "${dataBounds.rawMaxElevation.roundToInt()} m"
    val maxMeasured = textMeasurer.measure(maxLabel, labelStyle)

    // Position label above the point; shift left if it would overflow the right edge.
    val maxLabelX = (maxX - maxMeasured.size.width / 2f)
        .coerceIn(chartArea.left, chartArea.left + chartArea.width - maxMeasured.size.width)
    val maxLabelY = (maxY - maxMeasured.size.height - 6f)
        .coerceAtLeast(chartArea.top)

    drawRoundRect(
        color = backgroundColor,
        topLeft = Offset(maxLabelX - 2f, maxLabelY - 1f),
        size = androidx.compose.ui.geometry.Size(
            maxMeasured.size.width + 4f,
            maxMeasured.size.height + 2f
        ),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(3f, 3f)
    )
    drawText(textLayoutResult = maxMeasured, topLeft = Offset(maxLabelX, maxLabelY))

    // Small triangle pointing down to the max point.
    drawCircle(
        color = labelStyle.color,
        radius = 2.5f,
        center = Offset(maxX, maxY)
    )

    // Draw min elevation label.
    val minPoint = sortedPoints[dataBounds.minElevationIndex]
    val minX = distanceToPixelX(minPoint.distance, chartArea, dataBounds)
    val minY = elevationToPixelY(minPoint.elevation, chartArea, dataBounds)
    val minLabel = "${dataBounds.rawMinElevation.roundToInt()} m"
    val minMeasured = textMeasurer.measure(minLabel, labelStyle)

    // Position label below the point.
    val minLabelX = (minX - minMeasured.size.width / 2f)
        .coerceIn(chartArea.left, chartArea.left + chartArea.width - minMeasured.size.width)
    val minLabelY = (minY + 6f)
        .coerceAtMost(chartArea.top + chartArea.height - minMeasured.size.height)

    drawRoundRect(
        color = backgroundColor,
        topLeft = Offset(minLabelX - 2f, minLabelY - 1f),
        size = androidx.compose.ui.geometry.Size(
            minMeasured.size.width + 4f,
            minMeasured.size.height + 2f
        ),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(3f, 3f)
    )
    drawText(textLayoutResult = minMeasured, topLeft = Offset(minLabelX, minLabelY))

    drawCircle(
        color = labelStyle.color,
        radius = 2.5f,
        center = Offset(minX, minY)
    )
}

/**
 * Draws an animated current-position indicator on the elevation profile.
 *
 * Renders a vertical dashed line from top to bottom of the chart area,
 * plus a filled circle at the elevation line, at the position corresponding
 * to the user's current distance along the route.
 *
 * @param fractionAlongRoute Animated fraction (0..1) representing how far along the route
 *   the user currently is.
 * @param sortedPoints Elevation points sorted by ascending distance.
 * @param chartArea The pixel-space chart rectangle.
 * @param dataBounds Pre-computed data bounds.
 * @param dotRadiusPx Radius of the position indicator dot in pixels.
 * @param indicatorColor Color of the indicator.
 */
private fun DrawScope.drawPositionIndicator(
    fractionAlongRoute: Float,
    sortedPoints: List<ElevationPoint>,
    chartArea: ChartArea,
    dataBounds: DataBounds,
    dotRadiusPx: Float,
    indicatorColor: Color
) {
    val currentDistance = dataBounds.minDistance +
        fractionAlongRoute * dataBounds.distanceRange
    val nearestPoint = findNearestPoint(sortedPoints, currentDistance)

    val x = distanceToPixelX(nearestPoint.distance, chartArea, dataBounds)
    val y = elevationToPixelY(nearestPoint.elevation, chartArea, dataBounds)
    val bottomY = chartArea.top + chartArea.height

    // Vertical line from the dot down to the X axis.
    drawLine(
        color = indicatorColor.copy(alpha = 0.5f),
        start = Offset(x, chartArea.top),
        end = Offset(x, bottomY),
        strokeWidth = 1.5f,
        pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 4f), 0f)
    )

    // Outer glow circle.
    drawCircle(
        color = indicatorColor.copy(alpha = 0.25f),
        radius = dotRadiusPx * 1.8f,
        center = Offset(x, y)
    )

    // Filled position dot.
    drawCircle(
        color = indicatorColor,
        radius = dotRadiusPx,
        center = Offset(x, y)
    )

    // White inner highlight.
    drawCircle(
        color = Color.White,
        radius = dotRadiusPx * 0.4f,
        center = Offset(x, y)
    )
}

/**
 * Draws a crosshair at the touch position with a tooltip showing elevation and distance.
 *
 * The crosshair consists of a vertical and a horizontal dashed line intersecting
 * at the nearest data point. A tooltip box above (or below) the intersection
 * displays the elevation and distance values.
 *
 * @param touchXPx The X pixel coordinate of the user's touch.
 * @param sortedPoints Elevation points sorted by ascending distance.
 * @param chartArea The pixel-space chart rectangle.
 * @param dataBounds Pre-computed data bounds.
 * @param crosshairColor Color of the crosshair lines.
 * @param crosshairStrokeWidthPx Width of the crosshair lines in pixels.
 * @param dotRadiusPx Radius of the dot at the crosshair intersection.
 * @param tooltipCornerRadiusPx Corner radius of the tooltip background.
 * @param textMeasurer The Compose text measurer.
 * @param tooltipTextStyle Text style for the tooltip content.
 * @param tooltipBackgroundColor Background colour of the tooltip box.
 */
private fun DrawScope.drawCrosshair(
    touchXPx: Float,
    sortedPoints: List<ElevationPoint>,
    chartArea: ChartArea,
    dataBounds: DataBounds,
    crosshairColor: Color,
    crosshairStrokeWidthPx: Float,
    dotRadiusPx: Float,
    tooltipCornerRadiusPx: Float,
    textMeasurer: TextMeasurer,
    tooltipTextStyle: TextStyle,
    tooltipBackgroundColor: Color
) {
    val targetDistance = pixelXToDistance(touchXPx, chartArea, dataBounds)
    val nearest = findNearestPoint(sortedPoints, targetDistance)

    val x = distanceToPixelX(nearest.distance, chartArea, dataBounds)
    val y = elevationToPixelY(nearest.elevation, chartArea, dataBounds)
    val bottomY = chartArea.top + chartArea.height

    val dashEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 3f), 0f)

    // Vertical crosshair line.
    drawLine(
        color = crosshairColor.copy(alpha = 0.6f),
        start = Offset(x, chartArea.top),
        end = Offset(x, bottomY),
        strokeWidth = crosshairStrokeWidthPx,
        pathEffect = dashEffect
    )

    // Horizontal crosshair line.
    drawLine(
        color = crosshairColor.copy(alpha = 0.6f),
        start = Offset(chartArea.left, y),
        end = Offset(chartArea.left + chartArea.width, y),
        strokeWidth = crosshairStrokeWidthPx,
        pathEffect = dashEffect
    )

    // Intersection dot.
    drawCircle(
        color = crosshairColor,
        radius = dotRadiusPx * 0.7f,
        center = Offset(x, y)
    )

    // Tooltip text.
    val distKm = nearest.distance / METRES_PER_KM
    val tooltipText = "${nearest.elevation.roundToInt()} m  |  ${formatDistanceLabel(distKm)} km"
    val tooltipMeasured = textMeasurer.measure(tooltipText, tooltipTextStyle)

    val tooltipPadH = 8f
    val tooltipPadV = 4f
    val tooltipWidth = tooltipMeasured.size.width + tooltipPadH * 2
    val tooltipHeight = tooltipMeasured.size.height + tooltipPadV * 2

    // Position tooltip above the dot; flip below if too close to top.
    val tooltipY = if (y - tooltipHeight - 12f > chartArea.top) {
        y - tooltipHeight - 12f
    } else {
        y + 12f
    }

    // Centre tooltip on the crosshair X, clamped to chart bounds.
    val tooltipX = (x - tooltipWidth / 2f)
        .coerceIn(chartArea.left, chartArea.left + chartArea.width - tooltipWidth)

    // Tooltip background.
    drawRoundRect(
        color = tooltipBackgroundColor,
        topLeft = Offset(tooltipX, tooltipY),
        size = androidx.compose.ui.geometry.Size(tooltipWidth, tooltipHeight),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(
            tooltipCornerRadiusPx,
            tooltipCornerRadiusPx
        )
    )

    // Tooltip border.
    drawRoundRect(
        color = crosshairColor.copy(alpha = 0.3f),
        topLeft = Offset(tooltipX, tooltipY),
        size = androidx.compose.ui.geometry.Size(tooltipWidth, tooltipHeight),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(
            tooltipCornerRadiusPx,
            tooltipCornerRadiusPx
        ),
        style = Stroke(width = 1f)
    )

    // Tooltip text.
    drawText(
        textLayoutResult = tooltipMeasured,
        topLeft = Offset(tooltipX + tooltipPadH, tooltipY + tooltipPadV)
    )
}

// ──────────────────────────────────────────────────────────────────────────────
// Formatting helpers
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Formats a distance value (in kilometres) as a compact string.
 *
 * Uses no decimal places for whole numbers, one decimal place otherwise.
 * For example: `0.0` -> "0", `1.0` -> "1", `3.7` -> "3.7", `12.0` -> "12".
 *
 * @param km Distance in kilometres.
 * @return Formatted distance string without a unit suffix.
 */
private fun formatDistanceLabel(km: Double): String {
    return if (km == floor(km) && km < 1_000) {
        km.roundToInt().toString()
    } else {
        "%.1f".format(km)
    }
}
