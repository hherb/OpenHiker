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

package com.openhiker.android.di

import android.content.Context
import android.location.LocationManager
import android.os.Vibrator
import android.os.VibratorManager
import android.os.Build
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * Hilt module providing location and sensor-related system service dependencies.
 *
 * Provides Android system services needed for GPS tracking, compass heading,
 * and haptic feedback during navigation. These are scaffolded for Phase 2
 * (GPS service and turn-by-turn navigation).
 */
@Module
@InstallIn(SingletonComponent::class)
object LocationModule {

    /**
     * Provides the Android [LocationManager] system service.
     *
     * Used as a fallback GPS provider when Google Play Services
     * (FusedLocationProviderClient) is not available on the device.
     */
    @Provides
    @Singleton
    fun provideLocationManager(@ApplicationContext context: Context): LocationManager {
        return context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    }

    /**
     * Provides the Android [Vibrator] system service for haptic feedback.
     *
     * On Android 12+ (API 31), uses [VibratorManager] to get the default vibrator.
     * On older versions, uses the legacy [Vibrator] service directly.
     * Used for navigation turn alerts, off-route warnings, and arrival notifications.
     */
    @Provides
    @Singleton
    @Suppress("DEPRECATION")
    fun provideVibrator(@ApplicationContext context: Context): Vibrator {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager =
                context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vibratorManager.defaultVibrator
        } else {
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
    }
}
