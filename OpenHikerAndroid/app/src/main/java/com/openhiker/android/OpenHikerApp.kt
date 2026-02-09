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
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import dagger.hilt.android.HiltAndroidApp
import org.maplibre.android.MapLibre
import javax.inject.Inject

/**
 * Application class for OpenHiker Android.
 *
 * Annotated with [HiltAndroidApp] to enable Hilt dependency injection
 * throughout the application. This triggers Hilt's code generation and
 * sets up the base application-level dependency container.
 *
 * Implements [Configuration.Provider] to supply a custom [HiltWorkerFactory]
 * to WorkManager, enabling @HiltWorker-annotated workers to receive
 * injected dependencies. The default WorkManager initializer is removed
 * in AndroidManifest.xml to avoid double-initialization.
 *
 * MapLibre is initialized in [onCreate] so the map rendering engine
 * is ready before any MapView is created.
 */
@HiltAndroidApp
class OpenHikerApp : Application(), Configuration.Provider {

    /** Hilt-provided worker factory for @HiltWorker dependency injection. */
    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    override fun onCreate() {
        super.onCreate()
        MapLibre.getInstance(this)
    }

    /**
     * Provides the WorkManager configuration with a Hilt-aware [WorkerFactory].
     *
     * Called by WorkManager when the default initializer is disabled.
     * This allows @HiltWorker-annotated workers (e.g., [SyncWorker])
     * to receive constructor-injected dependencies.
     */
    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()
}
