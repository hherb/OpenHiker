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

import java.io.InputStream
import javax.xml.parsers.SAXParserFactory
import org.xml.sax.Attributes
import org.xml.sax.helpers.DefaultHandler

/**
 * Streaming SAX parser for Overpass API XML responses.
 *
 * Parses the XML into [OsmNode] and [OsmWay] collections suitable for
 * building a routing graph. Uses SAX (not DOM) to handle large responses
 * without loading the entire XML tree into memory.
 *
 * The expected XML format is the default Overpass `[out:xml]` output:
 * ```xml
 * <osm>
 *   <node id="..." lat="..." lon="...">
 *     <tag k="..." v="..."/>
 *   </node>
 *   <way id="...">
 *     <nd ref="..."/>
 *     <tag k="..." v="..."/>
 *   </way>
 * </osm>
 * ```
 *
 * Pure function API — no state, no side effects.
 */
object OsmXmlParser {

    /** Tags extracted from ways that are relevant for routing cost computation. */
    val RELEVANT_WAY_TAGS = setOf(
        "highway", "surface", "sac_scale", "trail_visibility",
        "name", "oneway", "access", "bicycle", "foot"
    )

    /**
     * Parses an Overpass XML response from an input stream.
     *
     * Extracts all `<node>` and `<way>` elements. Node tags are ignored
     * (we only need coordinates). Way tags are filtered to [RELEVANT_WAY_TAGS].
     *
     * @param inputStream The XML input stream (Overpass API response).
     * @return An [OsmData] containing the parsed nodes and ways.
     * @throws javax.xml.parsers.ParserConfigurationException if the SAX parser cannot be created.
     * @throws org.xml.sax.SAXException if the XML is malformed.
     * @throws java.io.IOException on I/O errors reading the stream.
     */
    fun parse(inputStream: InputStream): OsmData {
        val handler = OsmSaxHandler()
        val factory = SAXParserFactory.newInstance()
        val parser = factory.newSAXParser()
        parser.parse(inputStream, handler)
        return OsmData(nodes = handler.nodes, ways = handler.ways)
    }

    /**
     * Parses an Overpass XML response from a string.
     *
     * Convenience overload for testing and small responses.
     *
     * @param xml The XML string.
     * @return An [OsmData] containing the parsed nodes and ways.
     */
    fun parse(xml: String): OsmData =
        parse(xml.byteInputStream())
}

/**
 * SAX event handler for Overpass OSM XML.
 *
 * Collects nodes and ways as the parser fires element events.
 * Thread-safe only if used by a single parser instance.
 */
private class OsmSaxHandler : DefaultHandler() {

    val nodes = mutableMapOf<Long, OsmNode>()
    val ways = mutableListOf<OsmWay>()

    // Current element being parsed
    private var currentWayId: Long? = null
    private var currentWayNodeRefs = mutableListOf<Long>()
    private var currentWayTags = mutableMapOf<String, String>()

    override fun startElement(
        uri: String,
        localName: String,
        qName: String,
        attributes: Attributes
    ) {
        when (qName) {
            "node" -> parseNode(attributes)
            "way" -> startWay(attributes)
            "nd" -> parseNodeRef(attributes)
            "tag" -> parseTag(attributes)
        }
    }

    override fun endElement(uri: String, localName: String, qName: String) {
        if (qName == "way") {
            endWay()
        }
    }

    /**
     * Parses a `<node>` element and adds it to the nodes map.
     */
    private fun parseNode(attrs: Attributes) {
        val id = attrs.getValue("id")?.toLongOrNull() ?: return
        val lat = attrs.getValue("lat")?.toDoubleOrNull() ?: return
        val lon = attrs.getValue("lon")?.toDoubleOrNull() ?: return
        nodes[id] = OsmNode(id = id, latitude = lat, longitude = lon)
    }

    /**
     * Starts parsing a `<way>` element.
     */
    private fun startWay(attrs: Attributes) {
        currentWayId = attrs.getValue("id")?.toLongOrNull()
        currentWayNodeRefs = mutableListOf()
        currentWayTags = mutableMapOf()
    }

    /**
     * Parses a `<nd>` (node reference) within a `<way>`.
     */
    private fun parseNodeRef(attrs: Attributes) {
        if (currentWayId == null) return
        val ref = attrs.getValue("ref")?.toLongOrNull() ?: return
        currentWayNodeRefs.add(ref)
    }

    /**
     * Parses a `<tag>` element within a `<way>`.
     *
     * Only stores tags in [OsmXmlParser.RELEVANT_WAY_TAGS] to reduce memory.
     */
    private fun parseTag(attrs: Attributes) {
        if (currentWayId == null) return
        val key = attrs.getValue("k") ?: return
        val value = attrs.getValue("v") ?: return
        if (key in OsmXmlParser.RELEVANT_WAY_TAGS) {
            currentWayTags[key] = value
        }
    }

    /**
     * Finalises the current `<way>` element and adds it to the ways list.
     */
    private fun endWay() {
        val wayId = currentWayId ?: return
        if (currentWayNodeRefs.size >= 2) {
            ways.add(
                OsmWay(
                    id = wayId,
                    nodeRefs = currentWayNodeRefs.toList(),
                    tags = currentWayTags.toMap()
                )
            )
        }
        currentWayId = null
    }
}

/**
 * Parsed OSM data from an Overpass API response.
 *
 * @property nodes Map of OSM node ID to [OsmNode] (coordinates only).
 * @property ways List of [OsmWay] with node references and tags.
 */
data class OsmData(
    val nodes: Map<Long, OsmNode>,
    val ways: List<OsmWay>
)

/**
 * An OSM node with coordinates.
 *
 * @property id OSM node ID.
 * @property latitude WGS84 latitude in degrees.
 * @property longitude WGS84 longitude in degrees.
 */
data class OsmNode(
    val id: Long,
    val latitude: Double,
    val longitude: Double
)

/**
 * An OSM way with ordered node references and tags.
 *
 * @property id OSM way ID.
 * @property nodeRefs Ordered list of OSM node IDs forming the way's geometry.
 * @property tags Map of relevant OSM tags (highway, surface, name, etc.).
 */
data class OsmWay(
    val id: Long,
    val nodeRefs: List<Long>,
    val tags: Map<String, String>
) {
    /** The highway tag value, or null if not tagged. */
    val highway: String? get() = tags["highway"]

    /** The surface tag value, or null. */
    val surface: String? get() = tags["surface"]

    /** The SAC scale tag value, or null. */
    val sacScale: String? get() = tags["sac_scale"]

    /** The trail visibility tag value, or null. */
    val trailVisibility: String? get() = tags["trail_visibility"]

    /** The way name from the OSM name tag, or null. */
    val name: String? get() = tags["name"]

    /** Whether the way is tagged as one-way. */
    val isOneway: Boolean get() = tags["oneway"] == "yes"
}
