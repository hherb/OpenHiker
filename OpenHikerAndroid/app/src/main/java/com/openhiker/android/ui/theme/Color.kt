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

package com.openhiker.android.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Color palette for the OpenHiker app.
 *
 * Organized by semantic purpose: primary trail/nature colors,
 * map overlay colors, status colors, and waypoint category colors.
 */

// Primary palette — earthy hiking tones
val TrailGreen = Color(0xFF2E7D32)
val TrailGreenLight = Color(0xFF4CAF50)
val TrailGreenDark = Color(0xFF1B5E20)

val EarthBrown = Color(0xFF5D4037)
val EarthBrownLight = Color(0xFF8D6E63)

val SkyBlue = Color(0xFF1976D2)
val SkyBlueLight = Color(0xFF42A5F5)

// Map overlay colors
val RouteOrange = Color(0xFFFF9800)
val RouteOrangeLight = Color(0xFFFFB74D)
val SelectionBlue = Color(0xFF2196F3)
val SelectionBlueFill = Color(0x1A2196F3)
val OverlayDark = Color(0x4D000000)

// GPS marker colors
val GpsMarkerBlue = Color(0xFF1565C0)
val GpsAccuracyCircle = Color(0x331565C0)

// Status colors
val OffRouteRed = Color(0xFFD32F2F)
val ArrivedGreen = Color(0xFF388E3C)

// Start/end/via marker colors
val StartMarkerGreen = Color(0xFF4CAF50)
val EndMarkerRed = Color(0xFFF44336)
val ViaMarkerBlue = Color(0xFF2196F3)

// Waypoint category colors (matching iOS hex values)
val WaypointTrailMarker = Color(0xFF8B4513)
val WaypointViewpoint = Color(0xFF4169E1)
val WaypointWaterSource = Color(0xFF1E90FF)
val WaypointCampsite = Color(0xFF228B22)
val WaypointDanger = Color(0xFFFF4500)
val WaypointFood = Color(0xFFFF8C00)
val WaypointShelter = Color(0xFF708090)
val WaypointParking = Color(0xFF4682B4)
val WaypointCustom = Color(0xFF9370DB)

// Elevation profile gradient
val ElevationLow = Color(0xFF4CAF50)
val ElevationHigh = Color(0xFF8D6E63)
