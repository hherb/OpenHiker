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

package com.openhiker.android.data.db.routes

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

/**
 * Room database for saved routes (recorded hikes).
 *
 * Stores hike metadata and compressed GPS track data in a single SQLite
 * database. The track data column uses zlib-compressed binary BLOBs
 * in the cross-platform TrackCompression format.
 */
@Database(
    entities = [SavedRouteEntity::class],
    version = 1,
    exportSchema = true
)
abstract class RouteDatabase : RoomDatabase() {

    /** Provides access to saved route data operations. */
    abstract fun routeDao(): RouteDao

    companion object {
        /** Database filename in the app's internal storage. */
        private const val DATABASE_NAME = "openhiker_routes.db"

        /**
         * Creates the Room database instance.
         *
         * Called from the Hilt [com.openhiker.android.di.DatabaseModule].
         *
         * @param context Application context.
         * @return A configured [RouteDatabase] instance.
         */
        fun create(context: Context): RouteDatabase {
            return Room.databaseBuilder(
                context.applicationContext,
                RouteDatabase::class.java,
                DATABASE_NAME
            ).build()
        }
    }
}
