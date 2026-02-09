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

package com.openhiker.android.data.db.routing

import android.database.sqlite.SQLiteDatabase
import com.openhiker.core.formats.RoutingDbSchema
import com.openhiker.core.routing.RoutingEdge
import com.openhiker.core.routing.RoutingGraph
import com.openhiker.core.routing.RoutingNode
import java.io.Closeable
import java.io.File

/**
 * SQLite-backed implementation of [RoutingGraph] for per-region routing data.
 *
 * Each downloaded region that includes routing data gets a `.routing.db`
 * file. This class opens the file as a read-only SQLite database and
 * implements the [RoutingGraph] interface for use by the A* router.
 *
 * Unlike the saved routes and waypoints databases (which use Room),
 * the routing database uses the Android [SQLiteDatabase] API directly
 * because the schema is pre-defined by [RoutingDbSchema] and shared
 * with the iOS app.
 *
 * @property path Absolute filesystem path to the .routing.db file.
 */
class RoutingStore(private val path: String) : RoutingGraph, Closeable {

    private var db: SQLiteDatabase? = null

    /** Whether the database is currently open. */
    val isOpen: Boolean get() = db?.isOpen == true

    /**
     * Opens the routing database in read-only mode.
     *
     * @throws RoutingStoreError.FileNotFound if the file does not exist.
     * @throws RoutingStoreError.DatabaseError if the database cannot be opened.
     */
    fun open() {
        if (!File(path).exists()) {
            throw RoutingStoreError.FileNotFound(path)
        }
        try {
            db = SQLiteDatabase.openDatabase(
                path,
                null,
                SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS
            )
        } catch (e: Exception) {
            throw RoutingStoreError.DatabaseError(e.message ?: "Failed to open routing database")
        }
    }

    /**
     * Retrieves a routing node by its OSM node ID.
     *
     * @param id The OSM node ID.
     * @return The node if found, or null.
     */
    override fun getNode(id: Long): RoutingNode? {
        val database = db ?: throw RoutingStoreError.DatabaseNotOpen()

        val cursor = database.rawQuery(
            RoutingDbSchema.QUERY_NODE_BY_ID,
            arrayOf(id.toString())
        )

        return cursor.use {
            if (it.moveToFirst()) {
                RoutingNode(
                    id = it.getLong(it.getColumnIndexOrThrow(RoutingDbSchema.COL_NODE_ID)),
                    latitude = it.getDouble(it.getColumnIndexOrThrow(RoutingDbSchema.COL_NODE_LATITUDE)),
                    longitude = it.getDouble(it.getColumnIndexOrThrow(RoutingDbSchema.COL_NODE_LONGITUDE)),
                    elevation = it.getDoubleOrNull(RoutingDbSchema.COL_NODE_ELEVATION)
                )
            } else {
                null
            }
        }
    }

    /**
     * Retrieves all outgoing edges from a given node.
     *
     * Returns edges where [RoutingDbSchema.COL_EDGE_FROM_NODE] matches
     * the given node ID. For bidirectional ways, edges are stored in both
     * directions during graph building.
     *
     * @param nodeId The OSM node ID to query edges from.
     * @return List of edges originating from this node (may be empty).
     */
    override fun getEdgesFrom(nodeId: Long): List<RoutingEdge> {
        val database = db ?: throw RoutingStoreError.DatabaseNotOpen()

        val cursor = database.rawQuery(
            RoutingDbSchema.QUERY_EDGES_FROM_NODE,
            arrayOf(nodeId.toString())
        )

        val edges = mutableListOf<RoutingEdge>()
        cursor.use {
            while (it.moveToNext()) {
                edges.add(
                    RoutingEdge(
                        id = it.getLong(it.getColumnIndexOrThrow(RoutingDbSchema.COL_EDGE_ID)),
                        fromNode = it.getLong(it.getColumnIndexOrThrow(RoutingDbSchema.COL_EDGE_FROM_NODE)),
                        toNode = it.getLong(it.getColumnIndexOrThrow(RoutingDbSchema.COL_EDGE_TO_NODE)),
                        distance = it.getDouble(it.getColumnIndexOrThrow(RoutingDbSchema.COL_EDGE_DISTANCE)),
                        elevationGain = it.getDouble(it.getColumnIndexOrThrow(RoutingDbSchema.COL_EDGE_ELEVATION_GAIN)),
                        elevationLoss = it.getDouble(it.getColumnIndexOrThrow(RoutingDbSchema.COL_EDGE_ELEVATION_LOSS)),
                        surface = it.getStringOrNull(RoutingDbSchema.COL_EDGE_SURFACE),
                        highwayType = it.getStringOrNull(RoutingDbSchema.COL_EDGE_HIGHWAY_TYPE),
                        sacScale = it.getStringOrNull(RoutingDbSchema.COL_EDGE_SAC_SCALE),
                        trailVisibility = it.getStringOrNull(RoutingDbSchema.COL_EDGE_TRAIL_VISIBILITY),
                        name = it.getStringOrNull(RoutingDbSchema.COL_EDGE_NAME),
                        osmWayId = it.getLongOrNull(RoutingDbSchema.COL_EDGE_OSM_WAY_ID),
                        cost = it.getDouble(it.getColumnIndexOrThrow(RoutingDbSchema.COL_EDGE_COST)),
                        reverseCost = it.getDouble(it.getColumnIndexOrThrow(RoutingDbSchema.COL_EDGE_REVERSE_COST)),
                        isOneway = it.getInt(it.getColumnIndexOrThrow(RoutingDbSchema.COL_EDGE_IS_ONEWAY)) != 0
                    )
                )
            }
        }
        return edges
    }

    /**
     * Finds the nearest routing node to a given coordinate.
     *
     * Uses a bounding-box pre-filter on latitude for efficiency, then
     * selects the closest node by approximate Euclidean distance on
     * the degree grid. The search radius is limited to
     * [com.openhiker.core.routing.RoutingCostConfig.NEAREST_NODE_SEARCH_RADIUS_METRES].
     *
     * @param lat Latitude in degrees.
     * @param lon Longitude in degrees.
     * @return The nearest node, or null if no node is within the search radius.
     */
    override fun findNearestNode(lat: Double, lon: Double): RoutingNode? {
        val database = db ?: throw RoutingStoreError.DatabaseNotOpen()

        // Convert search radius to approximate degrees (generous estimate)
        val radiusDeg = SEARCH_RADIUS_DEGREES

        val cursor = database.rawQuery(
            RoutingDbSchema.QUERY_NEAREST_NODE,
            arrayOf(
                lat.toString(), lat.toString(),         // (lat - ?)^2
                lon.toString(), lon.toString(),         // (lon - ?)^2
                (lat - radiusDeg).toString(),           // lat BETWEEN min
                (lat + radiusDeg).toString(),           // AND max
                (lon - radiusDeg).toString(),           // lon BETWEEN min
                (lon + radiusDeg).toString()            // AND max
            )
        )

        return cursor.use {
            if (it.moveToFirst()) {
                RoutingNode(
                    id = it.getLong(it.getColumnIndexOrThrow(RoutingDbSchema.COL_NODE_ID)),
                    latitude = it.getDouble(it.getColumnIndexOrThrow(RoutingDbSchema.COL_NODE_LATITUDE)),
                    longitude = it.getDouble(it.getColumnIndexOrThrow(RoutingDbSchema.COL_NODE_LONGITUDE)),
                    elevation = it.getDoubleOrNull(RoutingDbSchema.COL_NODE_ELEVATION)
                )
            } else {
                null
            }
        }
    }

    /**
     * Returns the total number of nodes in the routing graph.
     *
     * Useful for diagnostics and progress reporting.
     */
    fun nodeCount(): Int {
        val database = db ?: throw RoutingStoreError.DatabaseNotOpen()
        val cursor = database.rawQuery(
            "SELECT COUNT(*) FROM ${RoutingDbSchema.TABLE_NODES}", null
        )
        return cursor.use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
    }

    /**
     * Returns the total number of edges in the routing graph.
     */
    fun edgeCount(): Int {
        val database = db ?: throw RoutingStoreError.DatabaseNotOpen()
        val cursor = database.rawQuery(
            "SELECT COUNT(*) FROM ${RoutingDbSchema.TABLE_EDGES}", null
        )
        return cursor.use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
    }

    /**
     * Closes the database connection.
     */
    override fun close() {
        db?.close()
        db = null
    }

    companion object {
        /**
         * Approximate search radius in degrees for nearest-node queries.
         *
         * 500 metres / ~111,000 m per degree of latitude = ~0.0045 degrees.
         * We use 0.005 for a small safety margin.
         */
        private const val SEARCH_RADIUS_DEGREES = 0.005
    }
}

/**
 * Cursor extension to get a nullable Double column.
 */
private fun android.database.Cursor.getDoubleOrNull(columnName: String): Double? {
    val idx = getColumnIndexOrThrow(columnName)
    return if (isNull(idx)) null else getDouble(idx)
}

/**
 * Cursor extension to get a nullable String column.
 */
private fun android.database.Cursor.getStringOrNull(columnName: String): String? {
    val idx = getColumnIndexOrThrow(columnName)
    return if (isNull(idx)) null else getString(idx)
}

/**
 * Cursor extension to get a nullable Long column.
 */
private fun android.database.Cursor.getLongOrNull(columnName: String): Long? {
    val idx = getColumnIndexOrThrow(columnName)
    return if (isNull(idx)) null else getLong(idx)
}

/**
 * Errors that can occur during routing store operations.
 */
sealed class RoutingStoreError(message: String) : Exception(message) {
    class FileNotFound(path: String) : RoutingStoreError("Routing database not found: $path")
    class DatabaseNotOpen : RoutingStoreError("Routing database is not open")
    class DatabaseError(detail: String) : RoutingStoreError("Routing database error: $detail")
}
