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
import com.openhiker.android.data.db.routes.RouteDao
import com.openhiker.android.data.db.routes.RouteDatabase
import com.openhiker.android.data.db.waypoints.WaypointDao
import com.openhiker.android.data.db.waypoints.WaypointDatabase
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * Hilt module providing database-related dependencies.
 *
 * Provides singleton instances of Room databases and their DAOs.
 * The routing database is not included here because it is per-region
 * and opened dynamically based on the selected region file path.
 */
@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    /**
     * Provides the singleton [RouteDatabase] instance for saved and planned routes.
     *
     * The database is stored in the app's internal storage and persists
     * across app restarts. Uses Room's default migration strategy.
     */
    @Provides
    @Singleton
    fun provideRouteDatabase(@ApplicationContext context: Context): RouteDatabase {
        return RouteDatabase.create(context)
    }

    /**
     * Provides the [RouteDao] for accessing saved and planned route data.
     */
    @Provides
    fun provideRouteDao(database: RouteDatabase): RouteDao {
        return database.routeDao()
    }

    /**
     * Provides the singleton [WaypointDatabase] instance for waypoint storage.
     *
     * Stores waypoint metadata, coordinates, and photo BLOBs.
     */
    @Provides
    @Singleton
    fun provideWaypointDatabase(@ApplicationContext context: Context): WaypointDatabase {
        return WaypointDatabase.create(context)
    }

    /**
     * Provides the [WaypointDao] for accessing waypoint data.
     */
    @Provides
    fun provideWaypointDao(database: WaypointDatabase): WaypointDao {
        return database.waypointDao()
    }
}
