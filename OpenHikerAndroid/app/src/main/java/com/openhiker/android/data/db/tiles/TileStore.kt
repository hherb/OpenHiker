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

package com.openhiker.android.data.db.tiles

import android.database.sqlite.SQLiteDatabase
import com.openhiker.core.formats.MbTilesSchema
import com.openhiker.core.geo.BoundingBox
import com.openhiker.core.geo.TileCoordinate
import java.io.Closeable
import java.io.File

/**
 * Errors that can occur during MBTiles tile operations.
 */
sealed class TileStoreError(message: String) : Exception(message) {
    class DatabaseNotOpen : TileStoreError("MBTiles database is not open")
    class DatabaseError(detail: String) : TileStoreError("MBTiles error: $detail")
    class TileNotFound : TileStoreError("Tile not found in database")
    class FileNotFound(path: String) : TileStoreError("MBTiles file not found: $path")
}

/**
 * MBTiles metadata parsed from the metadata table.
 *
 * @property name Tileset name.
 * @property format Tile image format ("png", "jpg", or "pbf").
 * @property minZoom Minimum available zoom level.
 * @property maxZoom Maximum available zoom level.
 * @property bounds Geographic extent, or null if not specified.
 * @property center Default view centre, or null if not specified.
 */
data class MbTilesMetadata(
    val name: String? = null,
    val format: String = "png",
    val minZoom: Int = 0,
    val maxZoom: Int = 22,
    val bounds: BoundingBox? = null,
    val center: Triple<Double, Double, Int>? = null // lat, lon, zoom
)

/**
 * Read-only access to an MBTiles (SQLite) tile database.
 *
 * Uses the Android [SQLiteDatabase] API directly (not Room) because
 * MBTiles has a pre-existing schema defined by the MBTiles specification.
 * The database is opened read-only for offline map display.
 *
 * Important: MBTiles uses TMS Y-coordinate convention where y=0 is
 * at the bottom (south). This class handles the Y-flip automatically
 * using [TileCoordinate.tmsY].
 *
 * @property path Absolute filesystem path to the .mbtiles file.
 */
class TileStore(private val path: String) : Closeable {

    private var db: SQLiteDatabase? = null

    /** Cached metadata from the MBTiles metadata table. */
    var metadata: MbTilesMetadata? = null
        private set

    /** Whether the database is currently open. */
    val isOpen: Boolean get() = db?.isOpen == true

    /**
     * Opens the MBTiles database in read-only mode and loads metadata.
     *
     * @throws TileStoreError.FileNotFound If the file does not exist.
     * @throws TileStoreError.DatabaseError If the database cannot be opened.
     */
    fun open() {
        if (!File(path).exists()) {
            throw TileStoreError.FileNotFound(path)
        }
        try {
            db = SQLiteDatabase.openDatabase(
                path,
                null,
                SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS
            )
            metadata = loadMetadata()
        } catch (e: Exception) {
            throw TileStoreError.DatabaseError(e.message ?: "Failed to open database")
        }
    }

    /**
     * Retrieves tile image data for the given tile coordinate.
     *
     * Converts the slippy map Y-coordinate to TMS convention before querying.
     *
     * @param coordinate The tile coordinate (slippy map convention).
     * @return The tile image data as a byte array.
     * @throws TileStoreError.DatabaseNotOpen If the database is not open.
     * @throws TileStoreError.TileNotFound If no tile exists at this coordinate.
     */
    fun getTile(coordinate: TileCoordinate): ByteArray {
        val database = db ?: throw TileStoreError.DatabaseNotOpen()

        val cursor = database.rawQuery(
            MbTilesSchema.QUERY_TILE,
            arrayOf(
                coordinate.z.toString(),
                coordinate.x.toString(),
                coordinate.tmsY.toString()
            )
        )

        return cursor.use {
            if (it.moveToFirst()) {
                it.getBlob(0)
            } else {
                throw TileStoreError.TileNotFound()
            }
        }
    }

    /**
     * Checks whether a tile exists in the database.
     *
     * @param coordinate The tile coordinate (slippy map convention).
     * @return True if the tile exists.
     */
    fun hasTile(coordinate: TileCoordinate): Boolean {
        val database = db ?: return false

        val cursor = database.rawQuery(
            MbTilesSchema.QUERY_TILE_EXISTS,
            arrayOf(
                coordinate.z.toString(),
                coordinate.x.toString(),
                coordinate.tmsY.toString()
            )
        )

        return cursor.use {
            it.moveToFirst() && it.getInt(0) > 0
        }
    }

    /**
     * Closes the database connection.
     *
     * Safe to call multiple times. After closing, no tile queries can be made
     * until [open] is called again.
     */
    override fun close() {
        db?.close()
        db = null
    }

    /**
     * Loads metadata from the MBTiles metadata table.
     *
     * Parses the key-value pairs into a structured [MbTilesMetadata] object.
     * The bounds string format is "west,south,east,north" and the center
     * string format is "lon,lat,zoom".
     */
    private fun loadMetadata(): MbTilesMetadata {
        val database = db ?: throw TileStoreError.DatabaseNotOpen()
        val metadataMap = mutableMapOf<String, String>()

        val cursor = database.rawQuery(MbTilesSchema.QUERY_ALL_METADATA, null)
        cursor.use {
            while (it.moveToNext()) {
                val key = it.getString(0)
                val value = it.getString(1)
                metadataMap[key] = value
            }
        }

        val bounds = metadataMap[MbTilesSchema.META_KEY_BOUNDS]?.let { boundsStr ->
            val parts = boundsStr.split(",").map { it.trim().toDoubleOrNull() }
            if (parts.size == 4 && parts.all { it != null }) {
                BoundingBox(
                    west = parts[0]!!,
                    south = parts[1]!!,
                    east = parts[2]!!,
                    north = parts[3]!!
                )
            } else null
        }

        val center = metadataMap[MbTilesSchema.META_KEY_CENTER]?.let { centerStr ->
            val parts = centerStr.split(",").map { it.trim() }
            if (parts.size == 3) {
                val lon = parts[0].toDoubleOrNull()
                val lat = parts[1].toDoubleOrNull()
                val zoom = parts[2].toIntOrNull()
                if (lon != null && lat != null && zoom != null) {
                    Triple(lat, lon, zoom)
                } else null
            } else null
        }

        return MbTilesMetadata(
            name = metadataMap[MbTilesSchema.META_KEY_NAME],
            format = metadataMap[MbTilesSchema.META_KEY_FORMAT] ?: "png",
            minZoom = metadataMap[MbTilesSchema.META_KEY_MIN_ZOOM]?.toIntOrNull() ?: 0,
            maxZoom = metadataMap[MbTilesSchema.META_KEY_MAX_ZOOM]?.toIntOrNull() ?: 22,
            bounds = bounds,
            center = center
        )
    }
}
