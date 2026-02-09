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

import android.app.Application
import dagger.hilt.android.HiltAndroidApp
import org.maplibre.android.MapLibre

/**
 * Application class for OpenHiker Android.
 *
 * Annotated with [HiltAndroidApp] to enable Hilt dependency injection
 * throughout the application. This triggers Hilt's code generation and
 * sets up the base application-level dependency container.
 *
 * MapLibre is initialized in [onCreate] so the map rendering engine
 * is ready before any MapView is created.
 */
@HiltAndroidApp
class OpenHikerApp : Application() {

    override fun onCreate() {
        super.onCreate()
        MapLibre.getInstance(this)
    }
}
