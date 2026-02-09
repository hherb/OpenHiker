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

package com.openhiker.android.service.map

import com.openhiker.core.geo.BoundingBox
import org.json.JSONArray
import org.json.JSONObject

/**
 * Generates MapLibre style JSON documents for different map display modes.
 *
 * MapLibre requires a style JSON to render tiles. For online browsing, the
 * styles are loaded from bundled asset files. For offline display, this
 * generator creates a style pointing to a local MBTiles file via the
 * `mbtiles://` URI scheme.
 *
 * Region boundary overlays are added as GeoJSON polygon layers with
 * semi-transparent blue fill and solid blue stroke.
 */
object OfflineStyleGenerator {

    /** Stroke width for region boundary lines in density-independent pixels. */
    private const val BOUNDARY_LINE_WIDTH = 3.0

    /** Fill opacity for region boundary polygons (10%). */
    private const val BOUNDARY_FILL_OPACITY = 0.1

    /** Stroke color for region boundaries (Material Blue 500). */
    private const val BOUNDARY_STROKE_COLOR = "#2196F3"

    /** Fill color for region boundaries (Material Blue 500). */
    private const val BOUNDARY_FILL_COLOR = "#2196F3"

    /**
     * Generates a MapLibre style JSON for rendering tiles from a local MBTiles file.
     *
     * The style uses the `mbtiles://` URI scheme which MapLibre Android natively
     * supports for reading tiles directly from SQLite MBTiles databases.
     *
     * @param mbtilesPath Absolute filesystem path to the .mbtiles file.
     * @return A complete MapLibre style JSON string.
     */
    fun generateOfflineStyle(mbtilesPath: String): String {
        val style = JSONObject().apply {
            put("version", 8)
            put("sources", JSONObject().apply {
                put("offline", JSONObject().apply {
                    put("type", "raster")
                    put("url", "mbtiles://$mbtilesPath")
                    put("tileSize", 256)
                })
            })
            put("layers", JSONArray().apply {
                put(JSONObject().apply {
                    put("id", "offline")
                    put("type", "raster")
                    put("source", "offline")
                })
            })
        }
        return style.toString()
    }

    /**
     * Generates a GeoJSON polygon feature for a region's bounding box.
     *
     * Creates a rectangular polygon following the GeoJSON specification
     * (RFC 7946) with coordinates in [longitude, latitude] order.
     * The polygon ring is closed (first and last points are identical).
     *
     * @param bbox The geographic bounding box of the region.
     * @return A GeoJSON Feature string containing the polygon.
     */
    fun generateBoundaryGeoJson(bbox: BoundingBox): String {
        val feature = JSONObject().apply {
            put("type", "Feature")
            put("geometry", JSONObject().apply {
                put("type", "Polygon")
                put("coordinates", JSONArray().apply {
                    put(JSONArray().apply {
                        // GeoJSON uses [longitude, latitude] order
                        put(JSONArray().apply { put(bbox.west); put(bbox.south) })
                        put(JSONArray().apply { put(bbox.east); put(bbox.south) })
                        put(JSONArray().apply { put(bbox.east); put(bbox.north) })
                        put(JSONArray().apply { put(bbox.west); put(bbox.north) })
                        put(JSONArray().apply { put(bbox.west); put(bbox.south) }) // Close ring
                    })
                })
            })
            put("properties", JSONObject())
        }
        return feature.toString()
    }

    /**
     * Generates a GeoJSON FeatureCollection containing boundary polygons
     * for multiple regions.
     *
     * @param bboxes List of bounding boxes to include.
     * @return A GeoJSON FeatureCollection string.
     */
    fun generateBoundaryCollection(bboxes: List<BoundingBox>): String {
        val collection = JSONObject().apply {
            put("type", "FeatureCollection")
            put("features", JSONArray().apply {
                bboxes.forEach { bbox ->
                    put(JSONObject(generateBoundaryGeoJson(bbox)))
                }
            })
        }
        return collection.toString()
    }
}
