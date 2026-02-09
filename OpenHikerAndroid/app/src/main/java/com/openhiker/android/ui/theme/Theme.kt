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

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

/**
 * Material 3 color schemes for OpenHiker.
 *
 * Uses earthy trail-themed colors as primary/secondary, with
 * dynamic color support on Android 12+ devices. Falls back to
 * the static trail-themed palette on older devices.
 */
private val LightColorScheme = lightColorScheme(
    primary = TrailGreen,
    onPrimary = Color.White,
    primaryContainer = TrailGreenLight,
    onPrimaryContainer = TrailGreenDark,
    secondary = EarthBrown,
    onSecondary = Color.White,
    secondaryContainer = EarthBrownLight,
    onSecondaryContainer = Color(0xFF3E2723),
    tertiary = SkyBlue,
    onTertiary = Color.White,
    tertiaryContainer = SkyBlueLight,
    error = OffRouteRed,
    background = Color(0xFFFFFBFE),
    onBackground = Color(0xFF1C1B1F),
    surface = Color(0xFFFFFBFE),
    onSurface = Color(0xFF1C1B1F),
    surfaceVariant = Color(0xFFE7E0EC),
    onSurfaceVariant = Color(0xFF49454F)
)

private val DarkColorScheme = darkColorScheme(
    primary = TrailGreenLight,
    onPrimary = TrailGreenDark,
    primaryContainer = TrailGreen,
    onPrimaryContainer = Color(0xFFC8E6C9),
    secondary = EarthBrownLight,
    onSecondary = Color(0xFF3E2723),
    secondaryContainer = EarthBrown,
    onSecondaryContainer = Color(0xFFD7CCC8),
    tertiary = SkyBlueLight,
    onTertiary = Color(0xFF0D47A1),
    tertiaryContainer = SkyBlue,
    error = Color(0xFFEF9A9A),
    background = Color(0xFF1C1B1F),
    onBackground = Color(0xFFE6E1E5),
    surface = Color(0xFF1C1B1F),
    onSurface = Color(0xFFE6E1E5),
    surfaceVariant = Color(0xFF49454F),
    onSurfaceVariant = Color(0xFFCAC4D0)
)

/**
 * OpenHiker Material 3 theme composable.
 *
 * Supports dynamic color on Android 12+ (Material You) and falls back
 * to the trail-themed static palette on older devices. Automatically
 * switches between light and dark modes based on system preference.
 *
 * @param darkTheme Whether to use dark theme. Defaults to system setting.
 * @param dynamicColor Whether to use Material You dynamic colors on Android 12+.
 * @param content The composable content to theme.
 */
@Composable
fun OpenHikerTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context)
            else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = OpenHikerTypography,
        content = content
    )
}
