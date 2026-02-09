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
import android.database.sqlite.SQLiteStatement
import com.openhiker.core.formats.MbTilesSchema
import com.openhiker.core.geo.BoundingBox
import com.openhiker.core.geo.TileCoordinate
import java.io.Closeable

/**
 * Read-write MBTiles database for downloading and storing map tiles.
 *
 * Creates a new MBTiles file with the standard schema (metadata + tiles tables),
 * then supports batch tile insertion with transaction control. Uses compiled
 * [SQLiteStatement] for efficient bulk inserts.
 *
 * After downloads are complete, the file can be opened with [TileStore] for
 * read-only display on the map.
 *
 * @property path Absolute filesystem path for the new .mbtiles file.
 */
class WritableTileStore(private val path: String) : Closeable {

    private var db: SQLiteDatabase? = null
    private var insertStatement: SQLiteStatement? = null

    /** Whether the database is currently open. */
    val isOpen: Boolean get() = db?.isOpen == true

    /**
     * Creates the MBTiles database file with the standard schema.
     *
     * Creates the metadata and tiles tables, plus the tiles index.
     * Writes initial metadata entries for the tileset.
     *
     * @param name Display name for the tileset.
     * @param bounds Geographic extent of the region.
     * @param minZoom Minimum zoom level being downloaded.
     * @param maxZoom Maximum zoom level being downloaded.
     * @throws TileStoreError.DatabaseError If the database cannot be created.
     */
    fun create(name: String, bounds: BoundingBox, minZoom: Int, maxZoom: Int) {
        try {
            db = SQLiteDatabase.openOrCreateDatabase(path, null)
            val database = db!!

            database.execSQL(MbTilesSchema.CREATE_METADATA_TABLE)
            database.execSQL(MbTilesSchema.CREATE_TILES_TABLE)
            database.execSQL(MbTilesSchema.CREATE_TILES_INDEX)

            insertMetadata(MbTilesSchema.META_KEY_NAME, name)
            insertMetadata(MbTilesSchema.META_KEY_FORMAT, "png")
            insertMetadata(MbTilesSchema.META_KEY_MIN_ZOOM, minZoom.toString())
            insertMetadata(MbTilesSchema.META_KEY_MAX_ZOOM, maxZoom.toString())
            insertMetadata(
                MbTilesSchema.META_KEY_BOUNDS,
                "${bounds.west},${bounds.south},${bounds.east},${bounds.north}"
            )
            insertMetadata(
                MbTilesSchema.META_KEY_CENTER,
                "${bounds.center.longitude},${bounds.center.latitude},$minZoom"
            )

            // Pre-compile the insert statement for batch performance
            insertStatement = database.compileStatement(MbTilesSchema.INSERT_TILE)
        } catch (e: Exception) {
            throw TileStoreError.DatabaseError(e.message ?: "Failed to create MBTiles database")
        }
    }

    /**
     * Inserts a tile into the database.
     *
     * Converts the slippy map Y-coordinate to TMS convention before inserting.
     * Uses a pre-compiled statement for batch insertion performance.
     *
     * @param coordinate The tile coordinate (slippy map convention).
     * @param data The tile image data (PNG bytes).
     * @throws TileStoreError.DatabaseNotOpen If the database is not open.
     */
    fun insertTile(coordinate: TileCoordinate, data: ByteArray) {
        val statement = insertStatement ?: throw TileStoreError.DatabaseNotOpen()

        statement.bindLong(1, coordinate.z.toLong())
        statement.bindLong(2, coordinate.x.toLong())
        statement.bindLong(3, coordinate.tmsY.toLong())
        statement.bindBlob(4, data)
        statement.executeInsert()
    }

    /**
     * Begins a database transaction for batch tile inserts.
     *
     * Wrapping multiple [insertTile] calls in a transaction dramatically
     * improves write performance (100+ tiles per transaction recommended).
     */
    fun beginTransaction() {
        db?.beginTransaction() ?: throw TileStoreError.DatabaseNotOpen()
    }

    /**
     * Commits the current transaction, persisting all inserted tiles.
     */
    fun commitTransaction() {
        db?.let {
            it.setTransactionSuccessful()
            it.endTransaction()
        } ?: throw TileStoreError.DatabaseNotOpen()
    }

    /**
     * Rolls back the current transaction, discarding all inserted tiles.
     */
    fun rollbackTransaction() {
        db?.endTransaction() ?: throw TileStoreError.DatabaseNotOpen()
    }

    /**
     * Closes the database connection and releases resources.
     *
     * Safe to call multiple times.
     */
    override fun close() {
        insertStatement?.close()
        insertStatement = null
        db?.close()
        db = null
    }

    /**
     * Inserts a metadata key-value pair.
     */
    private fun insertMetadata(key: String, value: String) {
        val database = db ?: throw TileStoreError.DatabaseNotOpen()
        val statement = database.compileStatement(MbTilesSchema.INSERT_METADATA)
        statement.bindString(1, key)
        statement.bindString(2, value)
        statement.executeInsert()
        statement.close()
    }
}
