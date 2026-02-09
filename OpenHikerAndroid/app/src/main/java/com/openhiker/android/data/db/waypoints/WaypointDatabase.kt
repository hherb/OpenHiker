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

package com.openhiker.android.data.db.waypoints

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

/**
 * Room database for waypoints (points of interest with photos).
 *
 * Stores waypoint metadata, coordinates, categories, notes, and
 * photo BLOBs (full resolution + 100x100 thumbnail).
 */
@Database(
    entities = [WaypointEntity::class],
    version = 1,
    exportSchema = true
)
abstract class WaypointDatabase : RoomDatabase() {

    /** Provides access to waypoint data operations. */
    abstract fun waypointDao(): WaypointDao

    companion object {
        /** Database filename in the app's internal storage. */
        private const val DATABASE_NAME = "openhiker_waypoints.db"

        /**
         * Creates the Room database instance.
         *
         * Called from the Hilt [com.openhiker.android.di.DatabaseModule].
         *
         * @param context Application context.
         * @return A configured [WaypointDatabase] instance.
         */
        fun create(context: Context): WaypointDatabase {
            return Room.databaseBuilder(
                context.applicationContext,
                WaypointDatabase::class.java,
                DATABASE_NAME
            ).build()
        }
    }
}
