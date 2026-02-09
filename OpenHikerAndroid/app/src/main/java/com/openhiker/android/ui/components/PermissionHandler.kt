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

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat

/**
 * Composable that requests fine location permission at first composition.
 *
 * Follows Android's three-stage permission model:
 * 1. Check if already granted
 * 2. Request if not granted
 * 3. Invoke callback with the result
 *
 * Fine location is needed for GPS position display on the map.
 * Background location and notification permissions are requested
 * separately when their respective features are activated (hike
 * recording and foreground service).
 *
 * @param onPermissionResult Callback with true if location permission was granted.
 */
@Composable
fun RequestLocationPermission(
    onPermissionResult: (Boolean) -> Unit
) {
    var hasRequested by remember { mutableStateOf(false) }

    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val fineGranted = permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true
        val coarseGranted = permissions[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        onPermissionResult(fineGranted || coarseGranted)
    }

    LaunchedEffect(Unit) {
        if (!hasRequested) {
            hasRequested = true
            launcher.launch(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                )
            )
        }
    }
}

/**
 * Checks whether fine location permission is currently granted.
 *
 * @param context The Android context to check permissions against.
 * @return True if [Manifest.permission.ACCESS_FINE_LOCATION] is granted.
 */
fun hasLocationPermission(context: Context): Boolean {
    return ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.ACCESS_FINE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED
}

/**
 * Checks whether notification permission is needed and not yet granted.
 *
 * On Android 13+ (API 33), the POST_NOTIFICATIONS permission must be
 * explicitly granted. On older versions, notifications are allowed by default.
 *
 * @param context The Android context to check permissions against.
 * @return True if notification permission is granted or not needed.
 */
fun hasNotificationPermission(context: Context): Boolean {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    } else {
        true
    }
}
