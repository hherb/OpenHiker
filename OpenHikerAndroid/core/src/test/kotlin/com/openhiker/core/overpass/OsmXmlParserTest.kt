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

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [OsmXmlParser].
 */
class OsmXmlParserTest {

    // ── Node parsing ─────────────────────────────────────────────────

    @Test
    fun `parse extracts single node`() {
        val xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <osm version="0.6">
              <node id="123" lat="47.267" lon="11.393"/>
            </osm>
        """.trimIndent()

        val data = OsmXmlParser.parse(xml)
        assertEquals(1, data.nodes.size)

        val node = data.nodes[123L]
        assertNotNull(node)
        assertEquals(123L, node!!.id)
        assertEquals(47.267, node.latitude, 0.001)
        assertEquals(11.393, node.longitude, 0.001)
    }

    @Test
    fun `parse extracts multiple nodes`() {
        val xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <osm version="0.6">
              <node id="1" lat="47.0" lon="11.0"/>
              <node id="2" lat="47.1" lon="11.1"/>
              <node id="3" lat="47.2" lon="11.2"/>
            </osm>
        """.trimIndent()

        val data = OsmXmlParser.parse(xml)
        assertEquals(3, data.nodes.size)
        assertTrue(data.nodes.containsKey(1L))
        assertTrue(data.nodes.containsKey(2L))
        assertTrue(data.nodes.containsKey(3L))
    }

    @Test
    fun `parse skips node with missing coordinates`() {
        val xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <osm version="0.6">
              <node id="1"/>
              <node id="2" lat="47.0" lon="11.0"/>
            </osm>
        """.trimIndent()

        val data = OsmXmlParser.parse(xml)
        assertEquals(1, data.nodes.size)
        assertTrue(data.nodes.containsKey(2L))
    }

    // ── Way parsing ──────────────────────────────────────────────────

    @Test
    fun `parse extracts way with node refs`() {
        val xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <osm version="0.6">
              <node id="1" lat="47.0" lon="11.0"/>
              <node id="2" lat="47.1" lon="11.1"/>
              <way id="100">
                <nd ref="1"/>
                <nd ref="2"/>
                <tag k="highway" v="path"/>
              </way>
            </osm>
        """.trimIndent()

        val data = OsmXmlParser.parse(xml)
        assertEquals(1, data.ways.size)

        val way = data.ways[0]
        assertEquals(100L, way.id)
        assertEquals(listOf(1L, 2L), way.nodeRefs)
        assertEquals("path", way.highway)
    }

    @Test
    fun `parse extracts way tags`() {
        val xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <osm version="0.6">
              <node id="1" lat="47.0" lon="11.0"/>
              <node id="2" lat="47.1" lon="11.1"/>
              <way id="100">
                <nd ref="1"/>
                <nd ref="2"/>
                <tag k="highway" v="footway"/>
                <tag k="surface" v="gravel"/>
                <tag k="sac_scale" v="mountain_hiking"/>
                <tag k="trail_visibility" v="good"/>
                <tag k="name" v="Blue Ridge Trail"/>
                <tag k="oneway" v="yes"/>
              </way>
            </osm>
        """.trimIndent()

        val data = OsmXmlParser.parse(xml)
        val way = data.ways[0]

        assertEquals("footway", way.highway)
        assertEquals("gravel", way.surface)
        assertEquals("mountain_hiking", way.sacScale)
        assertEquals("good", way.trailVisibility)
        assertEquals("Blue Ridge Trail", way.name)
        assertTrue(way.isOneway)
    }

    @Test
    fun `parse filters out irrelevant tags`() {
        val xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <osm version="0.6">
              <node id="1" lat="47.0" lon="11.0"/>
              <node id="2" lat="47.1" lon="11.1"/>
              <way id="100">
                <nd ref="1"/>
                <nd ref="2"/>
                <tag k="highway" v="path"/>
                <tag k="created_by" v="iD"/>
                <tag k="source" v="survey"/>
                <tag k="fixme" v="check surface"/>
              </way>
            </osm>
        """.trimIndent()

        val data = OsmXmlParser.parse(xml)
        val way = data.ways[0]

        // Only "highway" should be stored
        assertEquals(1, way.tags.size)
        assertEquals("path", way.tags["highway"])
    }

    @Test
    fun `parse skips way with fewer than 2 node refs`() {
        val xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <osm version="0.6">
              <node id="1" lat="47.0" lon="11.0"/>
              <way id="100">
                <nd ref="1"/>
                <tag k="highway" v="path"/>
              </way>
            </osm>
        """.trimIndent()

        val data = OsmXmlParser.parse(xml)
        assertTrue(data.ways.isEmpty())
    }

    @Test
    fun `parse handles multiple ways`() {
        val xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <osm version="0.6">
              <node id="1" lat="47.0" lon="11.0"/>
              <node id="2" lat="47.1" lon="11.1"/>
              <node id="3" lat="47.2" lon="11.2"/>
              <way id="100">
                <nd ref="1"/>
                <nd ref="2"/>
                <tag k="highway" v="path"/>
              </way>
              <way id="101">
                <nd ref="2"/>
                <nd ref="3"/>
                <tag k="highway" v="footway"/>
                <tag k="surface" v="asphalt"/>
              </way>
            </osm>
        """.trimIndent()

        val data = OsmXmlParser.parse(xml)
        assertEquals(3, data.nodes.size)
        assertEquals(2, data.ways.size)
        assertEquals(100L, data.ways[0].id)
        assertEquals(101L, data.ways[1].id)
    }

    // ── Way convenience properties ───────────────────────────────────

    @Test
    fun `OsmWay isOneway returns false by default`() {
        val way = OsmWay(1, listOf(1, 2), mapOf("highway" to "path"))
        assertFalse(way.isOneway)
    }

    @Test
    fun `OsmWay properties return null for missing tags`() {
        val way = OsmWay(1, listOf(1, 2), emptyMap())
        assertNull(way.highway)
        assertNull(way.surface)
        assertNull(way.sacScale)
        assertNull(way.name)
    }

    // ── Edge cases ───────────────────────────────────────────────────

    @Test
    fun `parse handles empty OSM response`() {
        val xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <osm version="0.6">
            </osm>
        """.trimIndent()

        val data = OsmXmlParser.parse(xml)
        assertTrue(data.nodes.isEmpty())
        assertTrue(data.ways.isEmpty())
    }

    @Test
    fun `parse handles long way with many nodes`() {
        val nodeElements = (1..100).joinToString("\n") {
            """<node id="$it" lat="${47.0 + it * 0.001}" lon="11.0"/>"""
        }
        val ndRefs = (1..100).joinToString("\n") { """<nd ref="$it"/>""" }

        val xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <osm version="0.6">
              $nodeElements
              <way id="1000">
                $ndRefs
                <tag k="highway" v="track"/>
              </way>
            </osm>
        """.trimIndent()

        val data = OsmXmlParser.parse(xml)
        assertEquals(100, data.nodes.size)
        assertEquals(1, data.ways.size)
        assertEquals(100, data.ways[0].nodeRefs.size)
    }

    // ── InputStream overload ─────────────────────────────────────────

    @Test
    fun `parse from InputStream produces same result as String`() {
        val xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <osm version="0.6">
              <node id="1" lat="47.0" lon="11.0"/>
              <way id="100">
                <nd ref="1"/>
                <nd ref="1"/>
                <tag k="highway" v="path"/>
              </way>
            </osm>
        """.trimIndent()

        val fromString = OsmXmlParser.parse(xml)
        val fromStream = OsmXmlParser.parse(xml.byteInputStream())

        assertEquals(fromString.nodes.size, fromStream.nodes.size)
        assertEquals(fromString.ways.size, fromStream.ways.size)
    }
}
