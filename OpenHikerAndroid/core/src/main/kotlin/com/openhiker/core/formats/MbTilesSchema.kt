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

package com.openhiker.core.formats

/**
 * SQL constants for the MBTiles file format (SQLite-based tile storage).
 *
 * MBTiles is the standard format for storing map tiles in a single
 * SQLite database. These constants define the table schemas, column names,
 * and common queries used by both [TileStore] (read-only) and
 * [WritableTileStore] (read-write) in the Android app module.
 *
 * Important: MBTiles uses the TMS Y-coordinate convention where y=0
 * is at the bottom (south pole). Use [com.openhiker.core.geo.TileCoordinate.tmsY]
 * to convert from the slippy map (XYZ) convention where y=0 is at the top.
 *
 * @see <a href="https://github.com/mapbox/mbtiles-spec/blob/master/1.3/spec.md">MBTiles Spec 1.3</a>
 */
object MbTilesSchema {

    // ── Table names ────────────────────────────────────────────────

    /** Metadata table storing key-value pairs about the tileset. */
    const val TABLE_METADATA = "metadata"

    /** Tiles table storing the actual tile image data. */
    const val TABLE_TILES = "tiles"

    // ── Column names (metadata table) ──────────────────────────────

    /** Column for the metadata key (TEXT PRIMARY KEY). */
    const val COL_METADATA_NAME = "name"

    /** Column for the metadata value (TEXT). */
    const val COL_METADATA_VALUE = "value"

    // ── Column names (tiles table) ─────────────────────────────────

    /** Column for the tile zoom level (INTEGER). */
    const val COL_ZOOM_LEVEL = "zoom_level"

    /** Column for the tile column index (INTEGER, same as slippy map X). */
    const val COL_TILE_COLUMN = "tile_column"

    /** Column for the tile row index (INTEGER, TMS Y convention). */
    const val COL_TILE_ROW = "tile_row"

    /** Column for the tile image data (BLOB, typically PNG or JPEG). */
    const val COL_TILE_DATA = "tile_data"

    // ── Metadata keys ──────────────────────────────────────────────

    /** Tileset name metadata key. */
    const val META_KEY_NAME = "name"

    /** Tile image format metadata key (e.g., "png", "jpg", "pbf"). */
    const val META_KEY_FORMAT = "format"

    /** Minimum zoom level metadata key. */
    const val META_KEY_MIN_ZOOM = "minzoom"

    /** Maximum zoom level metadata key. */
    const val META_KEY_MAX_ZOOM = "maxzoom"

    /** Geographic bounds metadata key (format: "west,south,east,north"). */
    const val META_KEY_BOUNDS = "bounds"

    /** Default view centre metadata key (format: "lon,lat,zoom"). */
    const val META_KEY_CENTER = "center"

    // ── DDL statements ─────────────────────────────────────────────

    /** SQL to create the metadata table. */
    const val CREATE_METADATA_TABLE = """
        CREATE TABLE IF NOT EXISTS $TABLE_METADATA (
            $COL_METADATA_NAME TEXT PRIMARY KEY,
            $COL_METADATA_VALUE TEXT
        )
    """

    /** SQL to create the tiles table. */
    const val CREATE_TILES_TABLE = """
        CREATE TABLE IF NOT EXISTS $TABLE_TILES (
            $COL_ZOOM_LEVEL INTEGER,
            $COL_TILE_COLUMN INTEGER,
            $COL_TILE_ROW INTEGER,
            $COL_TILE_DATA BLOB
        )
    """

    /** SQL to create the index on the tiles table for fast lookups. */
    const val CREATE_TILES_INDEX = """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_tiles
        ON $TABLE_TILES ($COL_ZOOM_LEVEL, $COL_TILE_COLUMN, $COL_TILE_ROW)
    """

    // ── Query templates ────────────────────────────────────────────

    /** SQL to retrieve a single tile by zoom, column, and row. */
    const val QUERY_TILE = """
        SELECT $COL_TILE_DATA FROM $TABLE_TILES
        WHERE $COL_ZOOM_LEVEL = ? AND $COL_TILE_COLUMN = ? AND $COL_TILE_ROW = ?
    """

    /** SQL to check if a tile exists. */
    const val QUERY_TILE_EXISTS = """
        SELECT COUNT(*) FROM $TABLE_TILES
        WHERE $COL_ZOOM_LEVEL = ? AND $COL_TILE_COLUMN = ? AND $COL_TILE_ROW = ?
    """

    /** SQL to insert or replace a tile. */
    const val INSERT_TILE = """
        INSERT OR REPLACE INTO $TABLE_TILES
        ($COL_ZOOM_LEVEL, $COL_TILE_COLUMN, $COL_TILE_ROW, $COL_TILE_DATA)
        VALUES (?, ?, ?, ?)
    """

    /** SQL to insert a metadata key-value pair. */
    const val INSERT_METADATA = """
        INSERT OR REPLACE INTO $TABLE_METADATA ($COL_METADATA_NAME, $COL_METADATA_VALUE)
        VALUES (?, ?)
    """

    /** SQL to read all metadata. */
    const val QUERY_ALL_METADATA = """
        SELECT $COL_METADATA_NAME, $COL_METADATA_VALUE FROM $TABLE_METADATA
    """
}
