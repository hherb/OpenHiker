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
 * SQL constants for the per-region routing graph database.
 *
 * Each downloaded region that includes routing data gets a `.routing.db`
 * SQLite file with these tables. The schema is identical to the iOS
 * routing database for cross-platform file compatibility.
 *
 * Tables:
 * - `routing_nodes`: Graph vertices (OSM nodes at trail junctions)
 * - `routing_edges`: Graph edges (trail segments between junctions)
 * - `routing_metadata`: Region-level metadata about the routing graph
 */
object RoutingDbSchema {

    // ── Table names ────────────────────────────────────────────────

    const val TABLE_NODES = "routing_nodes"
    const val TABLE_EDGES = "routing_edges"
    const val TABLE_METADATA = "routing_metadata"

    // ── Node columns ───────────────────────────────────────────────

    const val COL_NODE_ID = "id"
    const val COL_NODE_LATITUDE = "latitude"
    const val COL_NODE_LONGITUDE = "longitude"
    const val COL_NODE_ELEVATION = "elevation"

    // ── Edge columns ───────────────────────────────────────────────

    const val COL_EDGE_ID = "id"
    const val COL_EDGE_FROM_NODE = "from_node"
    const val COL_EDGE_TO_NODE = "to_node"
    const val COL_EDGE_DISTANCE = "distance"
    const val COL_EDGE_ELEVATION_GAIN = "elevation_gain"
    const val COL_EDGE_ELEVATION_LOSS = "elevation_loss"
    const val COL_EDGE_SURFACE = "surface"
    const val COL_EDGE_HIGHWAY_TYPE = "highway_type"
    const val COL_EDGE_SAC_SCALE = "sac_scale"
    const val COL_EDGE_TRAIL_VISIBILITY = "trail_visibility"
    const val COL_EDGE_NAME = "name"
    const val COL_EDGE_OSM_WAY_ID = "osm_way_id"
    const val COL_EDGE_COST = "cost"
    const val COL_EDGE_REVERSE_COST = "reverse_cost"
    const val COL_EDGE_IS_ONEWAY = "is_oneway"
    const val COL_EDGE_GEOMETRY = "geometry"

    // ── Metadata columns ───────────────────────────────────────────

    const val COL_META_KEY = "key"
    const val COL_META_VALUE = "value"

    // ── DDL statements ─────────────────────────────────────────────

    const val CREATE_NODES_TABLE = """
        CREATE TABLE IF NOT EXISTS $TABLE_NODES (
            $COL_NODE_ID INTEGER PRIMARY KEY,
            $COL_NODE_LATITUDE REAL NOT NULL,
            $COL_NODE_LONGITUDE REAL NOT NULL,
            $COL_NODE_ELEVATION REAL
        )
    """

    const val CREATE_EDGES_TABLE = """
        CREATE TABLE IF NOT EXISTS $TABLE_EDGES (
            $COL_EDGE_ID INTEGER PRIMARY KEY AUTOINCREMENT,
            $COL_EDGE_FROM_NODE INTEGER NOT NULL,
            $COL_EDGE_TO_NODE INTEGER NOT NULL,
            $COL_EDGE_DISTANCE REAL NOT NULL,
            $COL_EDGE_ELEVATION_GAIN REAL DEFAULT 0,
            $COL_EDGE_ELEVATION_LOSS REAL DEFAULT 0,
            $COL_EDGE_SURFACE TEXT,
            $COL_EDGE_HIGHWAY_TYPE TEXT,
            $COL_EDGE_SAC_SCALE TEXT,
            $COL_EDGE_TRAIL_VISIBILITY TEXT,
            $COL_EDGE_NAME TEXT,
            $COL_EDGE_OSM_WAY_ID INTEGER,
            $COL_EDGE_COST REAL NOT NULL,
            $COL_EDGE_REVERSE_COST REAL NOT NULL,
            $COL_EDGE_IS_ONEWAY INTEGER DEFAULT 0,
            $COL_EDGE_GEOMETRY BLOB,
            FOREIGN KEY ($COL_EDGE_FROM_NODE) REFERENCES $TABLE_NODES($COL_NODE_ID),
            FOREIGN KEY ($COL_EDGE_TO_NODE) REFERENCES $TABLE_NODES($COL_NODE_ID)
        )
    """

    const val CREATE_METADATA_TABLE = """
        CREATE TABLE IF NOT EXISTS $TABLE_METADATA (
            $COL_META_KEY TEXT PRIMARY KEY,
            $COL_META_VALUE TEXT
        )
    """

    /** Index for fast edge lookups by source node. */
    const val CREATE_EDGES_FROM_INDEX = """
        CREATE INDEX IF NOT EXISTS idx_edges_from
        ON $TABLE_EDGES ($COL_EDGE_FROM_NODE)
    """

    /** Index for fast edge lookups by destination node. */
    const val CREATE_EDGES_TO_INDEX = """
        CREATE INDEX IF NOT EXISTS idx_edges_to
        ON $TABLE_EDGES ($COL_EDGE_TO_NODE)
    """

    /** Spatial index approximation: index by latitude for nearest-node queries. */
    const val CREATE_NODES_LAT_INDEX = """
        CREATE INDEX IF NOT EXISTS idx_nodes_lat
        ON $TABLE_NODES ($COL_NODE_LATITUDE)
    """

    // ── Query templates ────────────────────────────────────────────

    const val QUERY_NODE_BY_ID = """
        SELECT * FROM $TABLE_NODES WHERE $COL_NODE_ID = ?
    """

    const val QUERY_EDGES_FROM_NODE = """
        SELECT * FROM $TABLE_EDGES WHERE $COL_EDGE_FROM_NODE = ?
    """

    /** Find nearest node within a lat/lon bounding box (approximate spatial query). */
    const val QUERY_NEAREST_NODE = """
        SELECT *,
            (($COL_NODE_LATITUDE - ?) * ($COL_NODE_LATITUDE - ?) +
             ($COL_NODE_LONGITUDE - ?) * ($COL_NODE_LONGITUDE - ?)) AS dist_sq
        FROM $TABLE_NODES
        WHERE $COL_NODE_LATITUDE BETWEEN ? AND ?
          AND $COL_NODE_LONGITUDE BETWEEN ? AND ?
        ORDER BY dist_sq ASC
        LIMIT 1
    """
}
