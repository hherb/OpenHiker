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

package com.openhiker.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass
import com.openhiker.android.ui.navigation.AppNavigation
import com.openhiker.android.ui.theme.OpenHikerTheme
import dagger.hilt.android.AndroidEntryPoint

/**
 * Single-activity entry point for the OpenHiker Android app.
 *
 * Uses Jetpack Compose for the entire UI. All screens are rendered
 * within the Compose navigation graph managed by [AppNavigation].
 * Annotated with [AndroidEntryPoint] for Hilt dependency injection.
 *
 * Calculates the [WindowSizeClass] to support adaptive layouts:
 * - Compact width: phone (bottom navigation bar)
 * - Medium/Expanded width: tablet/foldable (navigation rail)
 */
@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    @OptIn(ExperimentalMaterial3WindowSizeClassApi::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            OpenHikerTheme {
                val windowSizeClass = calculateWindowSizeClass(this)
                AppNavigation(windowSizeClass = windowSizeClass)
            }
        }
    }
}
