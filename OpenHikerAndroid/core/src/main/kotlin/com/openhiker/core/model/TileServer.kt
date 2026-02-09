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

package com.openhiker.core.model

import kotlinx.serialization.Serializable
import kotlin.math.abs

/**
 * Configuration for a raster tile server.
 *
 * Defines the URL pattern, subdomain rotation, and attribution for
 * a map tile source. Tile URLs follow the {z}/{x}/{y} convention
 * standard across all major tile servers.
 *
 * @property id Unique identifier for this server (e.g., "opentopomap").
 * @property displayName Human-readable name shown in the tile source selector.
 * @property urlTemplate URL template with {s}, {z}, {x}, {y} placeholders.
 * @property subdomains List of subdomain characters for load balancing (e.g., ["a", "b", "c"]).
 * @property attribution Copyright/attribution text for display on the map.
 * @property tileSize Pixel dimension of each tile (always 256 for raster tiles).
 */
@Serializable
data class TileServer(
    val id: String,
    val displayName: String,
    val urlTemplate: String,
    val subdomains: List<String>,
    val attribution: String,
    val tileSize: Int = TILE_SIZE_PIXELS
) {
    companion object {
        /** Standard raster tile size in pixels. */
        const val TILE_SIZE_PIXELS = 256

        /** OpenTopoMap — topographic contour map with hiking trails. */
        val OPEN_TOPO_MAP = TileServer(
            id = "opentopomap",
            displayName = "OpenTopoMap",
            urlTemplate = "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png",
            subdomains = listOf("a", "b", "c"),
            attribution = "\u00a9 OpenStreetMap contributors, SRTM | \u00a9 OpenTopoMap (CC-BY-SA)"
        )

        /** CyclOSM — cycling-optimised map with elevation shading. */
        val CYCLOSM = TileServer(
            id = "cyclosm",
            displayName = "CyclOSM",
            urlTemplate = "https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
            subdomains = listOf("a", "b", "c"),
            attribution = "\u00a9 OpenStreetMap contributors | CyclOSM"
        )

        /** OpenStreetMap Standard — the default OSM rendering. */
        val OSM_STANDARD = TileServer(
            id = "osm",
            displayName = "OpenStreetMap",
            urlTemplate = "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
            subdomains = emptyList(),
            attribution = "\u00a9 OpenStreetMap contributors"
        )

        /** All available tile servers, ordered by preference. */
        val ALL = listOf(OPEN_TOPO_MAP, CYCLOSM, OSM_STANDARD)
    }

    /**
     * Builds the full tile URL for a specific tile coordinate.
     *
     * Uses deterministic subdomain distribution: the subdomain is selected
     * by hashing the tile coordinates to ensure the same tile always maps
     * to the same subdomain. This improves HTTP cache coherence and matches
     * the iOS implementation's subdomain rotation formula.
     *
     * Formula: subdomains[abs(tile.x + tile.y) % subdomains.size]
     *
     * @param x Tile column index.
     * @param y Tile row index (slippy map convention, NOT TMS).
     * @param z Zoom level.
     * @return The fully-qualified URL for the tile image.
     */
    fun buildTileUrl(x: Int, y: Int, z: Int): String {
        var url = urlTemplate
            .replace("{z}", z.toString())
            .replace("{x}", x.toString())
            .replace("{y}", y.toString())

        if (subdomains.isNotEmpty()) {
            val subdomainIndex = abs(x + y) % subdomains.size
            url = url.replace("{s}", subdomains[subdomainIndex])
        }

        return url
    }
}
