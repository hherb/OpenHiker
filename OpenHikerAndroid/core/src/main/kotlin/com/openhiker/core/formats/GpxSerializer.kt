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

import com.openhiker.core.compression.TrackPoint
import com.openhiker.core.model.Coordinate
import com.openhiker.core.model.ElevationPoint
import java.util.Locale

/**
 * Generates GPX 1.1 XML from route and track data.
 *
 * All functions are pure (no side effects, no state). Output conforms to
 * the GPX 1.1 schema (https://www.topografix.com/GPX/1/1/) and is
 * compatible with common hiking apps, Garmin devices, and web services.
 *
 * Two serialization modes:
 * - **Track (trk)**: For recorded hikes — includes timestamps and elevation
 *   from GPS data. Uses [TrackPoint] as input.
 * - **Route (rte)**: For planned routes — includes waypoints along the
 *   computed path. Uses [Coordinate] + optional [ElevationPoint] as input.
 */
object GpxSerializer {

    /** GPX XML namespace and schema location. */
    private const val GPX_HEADER = """<?xml version="1.0" encoding="UTF-8"?>
<gpx xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
     xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd"
     version="1.1"
     creator="OpenHiker">"""

    private const val GPX_FOOTER = "\n</gpx>"

    /**
     * Serializes a recorded hike (GPS track) to GPX 1.1 XML.
     *
     * Produces a `<trk>` element with a single `<trkseg>` containing all
     * track points. Each point includes latitude, longitude, elevation,
     * and an ISO-8601 timestamp.
     *
     * @param name Display name of the hike.
     * @param description Optional description text.
     * @param trackPoints Ordered list of GPS track points from the recording.
     * @param timestampToIso Function converting a track point timestamp (seconds
     *        since reference date) to an ISO-8601 string. The caller provides
     *        this because the reference epoch is platform-specific.
     * @return Complete GPX 1.1 XML string.
     */
    fun serializeTrack(
        name: String,
        description: String = "",
        trackPoints: List<TrackPoint>,
        timestampToIso: (Double) -> String
    ): String {
        val sb = StringBuilder()
        sb.append(GPX_HEADER)
        sb.append("\n  <metadata>")
        sb.append("\n    <name>").append(escapeXml(name)).append("</name>")
        if (description.isNotBlank()) {
            sb.append("\n    <desc>").append(escapeXml(description)).append("</desc>")
        }
        sb.append("\n  </metadata>")
        sb.append("\n  <trk>")
        sb.append("\n    <name>").append(escapeXml(name)).append("</name>")
        sb.append("\n    <trkseg>")

        for (point in trackPoints) {
            sb.append("\n      <trkpt lat=\"")
            sb.append(String.format(Locale.US, "%.7f", point.latitude))
            sb.append("\" lon=\"")
            sb.append(String.format(Locale.US, "%.7f", point.longitude))
            sb.append("\">")
            sb.append(String.format(Locale.US, "\n        <ele>%.1f</ele>", point.altitude))
            sb.append("\n        <time>")
            sb.append(timestampToIso(point.timestamp))
            sb.append("</time>")
            sb.append("\n      </trkpt>")
        }

        sb.append("\n    </trkseg>")
        sb.append("\n  </trk>")
        sb.append(GPX_FOOTER)
        return sb.toString()
    }

    /**
     * Serializes a planned route to GPX 1.1 XML.
     *
     * Produces an `<rte>` element with `<rtept>` entries for each coordinate.
     * Elevation is included if an elevation profile is provided and can be
     * matched by cumulative distance.
     *
     * @param name Display name of the route.
     * @param description Optional description text.
     * @param coordinates Ordered list of route polyline coordinates.
     * @param elevationProfile Optional elevation data indexed by distance.
     *        When provided, each route point's elevation is interpolated from
     *        the profile using cumulative Haversine distance.
     * @return Complete GPX 1.1 XML string.
     */
    fun serializeRoute(
        name: String,
        description: String = "",
        coordinates: List<Coordinate>,
        elevationProfile: List<ElevationPoint>? = null
    ): String {
        val sb = StringBuilder()
        sb.append(GPX_HEADER)
        sb.append("\n  <metadata>")
        sb.append("\n    <name>").append(escapeXml(name)).append("</name>")
        if (description.isNotBlank()) {
            sb.append("\n    <desc>").append(escapeXml(description)).append("</desc>")
        }
        sb.append("\n  </metadata>")
        sb.append("\n  <rte>")
        sb.append("\n    <name>").append(escapeXml(name)).append("</name>")

        var cumulativeDistance = 0.0

        for (i in coordinates.indices) {
            val coord = coordinates[i]

            if (i > 0) {
                cumulativeDistance += com.openhiker.core.geo.Haversine.distance(
                    coordinates[i - 1], coord
                )
            }

            sb.append("\n    <rtept lat=\"")
            sb.append(String.format(Locale.US, "%.7f", coord.latitude))
            sb.append("\" lon=\"")
            sb.append(String.format(Locale.US, "%.7f", coord.longitude))
            sb.append("\">")

            val elevation = elevationProfile?.let {
                com.openhiker.core.elevation.ElevationProfile.elevationAtDistance(
                    it, cumulativeDistance
                )
            }
            if (elevation != null) {
                sb.append(String.format(Locale.US, "\n      <ele>%.1f</ele>", elevation))
            }

            sb.append("\n    </rtept>")
        }

        sb.append("\n  </rte>")
        sb.append(GPX_FOOTER)
        return sb.toString()
    }

    /**
     * Escapes special XML characters in a string.
     *
     * Handles the five predefined XML entities: &, <, >, ", '.
     *
     * @param text Raw text to escape.
     * @return XML-safe string.
     */
    fun escapeXml(text: String): String {
        return text
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&apos;")
    }
}
