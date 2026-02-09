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

package com.openhiker.core.overpass

import com.openhiker.core.geo.BoundingBox
import com.openhiker.core.routing.RoutingCostConfig
import java.net.URLEncoder

/**
 * Builds Overpass QL queries for fetching routable OSM trail and road data.
 *
 * The generated query fetches all ways with highway tags that are included
 * in [RoutingCostConfig.ROUTABLE_HIGHWAY_VALUES], plus their referenced nodes
 * (using the recurse-down operator `(._;>;)`).
 *
 * Pure functions — no network calls, no state.
 */
object OverpassQueryBuilder {

    /** Overpass query timeout in seconds (sent in the query, not HTTP timeout). */
    const val QUERY_TIMEOUT_SECONDS = 300

    /** Maximum region area in square kilometres for routing data download. */
    const val MAX_REGION_AREA_KM2 = 10_000.0

    /** Primary Overpass API endpoint. */
    const val PRIMARY_ENDPOINT = "https://overpass-api.de/api/interpreter"

    /** Fallback Overpass API endpoint. */
    const val FALLBACK_ENDPOINT = "https://overpass.kumi.systems/api/interpreter"

    /**
     * Builds a complete Overpass QL query string for a bounding box.
     *
     * The query fetches all routable ways (highway types defined in
     * RoutingCostConfig) within the bounding box, plus all referenced
     * nodes via the recurse-down operator.
     *
     * @param boundingBox Geographic area to query.
     * @return The Overpass QL query string (not URL-encoded).
     */
    fun buildQuery(boundingBox: BoundingBox): String {
        val highwayRegex = RoutingCostConfig.ROUTABLE_HIGHWAY_VALUES.joinToString("|")
        val bbox = "${boundingBox.south},${boundingBox.west},${boundingBox.north},${boundingBox.east}"

        return """
            [out:xml][timeout:$QUERY_TIMEOUT_SECONDS];
            way["highway"~"^($highwayRegex)$"]($bbox);
            (._;>;);
            out body;
        """.trimIndent()
    }

    /**
     * Builds the URL-encoded POST body for an Overpass API request.
     *
     * The Overpass API expects the query in a POST body with
     * Content-Type: application/x-www-form-urlencoded.
     *
     * @param boundingBox Geographic area to query.
     * @return URL-encoded POST body string (e.g., "data=%5Bout%3Axml%5D...").
     */
    fun buildPostBody(boundingBox: BoundingBox): String {
        val query = buildQuery(boundingBox)
        return "data=${URLEncoder.encode(query, "UTF-8")}"
    }

    /**
     * Validates that a bounding box is within the size limit for routing data.
     *
     * Large regions (> 10,000 km2) would produce excessive data volumes
     * and should be rejected with a user-friendly error message.
     *
     * @param boundingBox The region to validate.
     * @return True if the region is within the size limit.
     */
    fun isRegionSizeValid(boundingBox: BoundingBox): Boolean {
        return boundingBox.areaKm2 <= MAX_REGION_AREA_KM2
    }
}
