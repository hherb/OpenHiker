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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Unit tests for [GpxSerializer]. */
class GpxSerializerTest {

    /** Simple timestamp converter for tests: returns "2024-01-01T00:00:00Z" plus offset. */
    private val testTimestampToIso: (Double) -> String = { seconds ->
        "2024-01-01T%02d:%02d:%02dZ".format(
            (seconds / 3600).toInt() % 24,
            (seconds / 60).toInt() % 60,
            seconds.toInt() % 60
        )
    }

    // ─── escapeXml ──────────────────────────────────────────────────────

    @Test
    fun `escapeXml replaces ampersand`() {
        assertEquals("Tom &amp; Jerry", GpxSerializer.escapeXml("Tom & Jerry"))
    }

    @Test
    fun `escapeXml replaces less-than`() {
        assertEquals("a &lt; b", GpxSerializer.escapeXml("a < b"))
    }

    @Test
    fun `escapeXml replaces greater-than`() {
        assertEquals("a &gt; b", GpxSerializer.escapeXml("a > b"))
    }

    @Test
    fun `escapeXml replaces double quote`() {
        assertEquals("say &quot;hello&quot;", GpxSerializer.escapeXml("say \"hello\""))
    }

    @Test
    fun `escapeXml replaces apostrophe`() {
        assertEquals("it&apos;s", GpxSerializer.escapeXml("it's"))
    }

    @Test
    fun `escapeXml handles all five entities together`() {
        val input = "A & B < C > D \"E\" F'G"
        val expected = "A &amp; B &lt; C &gt; D &quot;E&quot; F&apos;G"
        assertEquals(expected, GpxSerializer.escapeXml(input))
    }

    @Test
    fun `escapeXml passes through clean strings unchanged`() {
        val clean = "Simple hike name 123"
        assertEquals(clean, GpxSerializer.escapeXml(clean))
    }

    @Test
    fun `escapeXml handles empty string`() {
        assertEquals("", GpxSerializer.escapeXml(""))
    }

    // ─── serializeTrack ─────────────────────────────────────────────────

    @Test
    fun `serializeTrack produces valid GPX 1_1 structure`() {
        val points = listOf(
            TrackPoint(47.2654, 11.3935, 1200.0, 0.0),
            TrackPoint(47.2660, 11.3940, 1210.0, 60.0)
        )

        val gpx = GpxSerializer.serializeTrack(
            name = "Morning Hike",
            trackPoints = points,
            timestampToIso = testTimestampToIso
        )

        assertTrue(gpx.startsWith("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        assertTrue(gpx.contains("xmlns=\"http://www.topografix.com/GPX/1/1\""))
        assertTrue(gpx.contains("version=\"1.1\""))
        assertTrue(gpx.contains("creator=\"OpenHiker\""))
        assertTrue(gpx.endsWith("</gpx>"))
    }

    @Test
    fun `serializeTrack includes metadata with name`() {
        val gpx = GpxSerializer.serializeTrack(
            name = "Test Hike",
            trackPoints = emptyList(),
            timestampToIso = testTimestampToIso
        )

        assertTrue(gpx.contains("<metadata>"))
        assertTrue(gpx.contains("<name>Test Hike</name>"))
        assertTrue(gpx.contains("</metadata>"))
    }

    @Test
    fun `serializeTrack includes description when provided`() {
        val gpx = GpxSerializer.serializeTrack(
            name = "Test",
            description = "A lovely trail",
            trackPoints = emptyList(),
            timestampToIso = testTimestampToIso
        )

        assertTrue(gpx.contains("<desc>A lovely trail</desc>"))
    }

    @Test
    fun `serializeTrack omits description when blank`() {
        val gpx = GpxSerializer.serializeTrack(
            name = "Test",
            description = "",
            trackPoints = emptyList(),
            timestampToIso = testTimestampToIso
        )

        assertFalse(gpx.contains("<desc>"))
    }

    @Test
    fun `serializeTrack omits description by default`() {
        val gpx = GpxSerializer.serializeTrack(
            name = "Test",
            trackPoints = emptyList(),
            timestampToIso = testTimestampToIso
        )

        assertFalse(gpx.contains("<desc>"))
    }

    @Test
    fun `serializeTrack produces trk with trkseg`() {
        val gpx = GpxSerializer.serializeTrack(
            name = "Test",
            trackPoints = listOf(TrackPoint(47.0, 11.0, 500.0, 0.0)),
            timestampToIso = testTimestampToIso
        )

        assertTrue(gpx.contains("<trk>"))
        assertTrue(gpx.contains("<trkseg>"))
        assertTrue(gpx.contains("</trkseg>"))
        assertTrue(gpx.contains("</trk>"))
    }

    @Test
    fun `serializeTrack formats trkpt with lat lon ele time`() {
        val points = listOf(TrackPoint(47.2654321, 11.3935678, 1234.5, 3661.0))

        val gpx = GpxSerializer.serializeTrack(
            name = "Test",
            trackPoints = points,
            timestampToIso = testTimestampToIso
        )

        assertTrue(gpx.contains("lat=\"47.2654321\""))
        assertTrue(gpx.contains("lon=\"11.3935678\""))
        assertTrue(gpx.contains("<ele>1234.5</ele>"))
        assertTrue(gpx.contains("<time>2024-01-01T01:01:01Z</time>"))
    }

    @Test
    fun `serializeTrack handles multiple track points`() {
        val points = listOf(
            TrackPoint(47.0, 11.0, 500.0, 0.0),
            TrackPoint(47.1, 11.1, 600.0, 60.0),
            TrackPoint(47.2, 11.2, 700.0, 120.0)
        )

        val gpx = GpxSerializer.serializeTrack(
            name = "Multi",
            trackPoints = points,
            timestampToIso = testTimestampToIso
        )

        val trkptCount = "<trkpt ".toRegex().findAll(gpx).count()
        assertEquals(3, trkptCount)
    }

    @Test
    fun `serializeTrack handles empty track points`() {
        val gpx = GpxSerializer.serializeTrack(
            name = "Empty",
            trackPoints = emptyList(),
            timestampToIso = testTimestampToIso
        )

        assertTrue(gpx.contains("<trkseg>"))
        assertTrue(gpx.contains("</trkseg>"))
        assertFalse(gpx.contains("<trkpt"))
    }

    @Test
    fun `serializeTrack escapes special characters in name`() {
        val gpx = GpxSerializer.serializeTrack(
            name = "Tom & Jerry's <Trail>",
            trackPoints = emptyList(),
            timestampToIso = testTimestampToIso
        )

        assertTrue(gpx.contains("Tom &amp; Jerry&apos;s &lt;Trail&gt;"))
    }

    @Test
    fun `serializeTrack escapes special characters in description`() {
        val gpx = GpxSerializer.serializeTrack(
            name = "Test",
            description = "Elevation > 2000m & steep",
            trackPoints = emptyList(),
            timestampToIso = testTimestampToIso
        )

        assertTrue(gpx.contains("Elevation &gt; 2000m &amp; steep"))
    }

    @Test
    fun `serializeTrack formats negative coordinates`() {
        val points = listOf(TrackPoint(-33.8688197, 151.2092955, 10.0, 0.0))

        val gpx = GpxSerializer.serializeTrack(
            name = "Sydney",
            trackPoints = points,
            timestampToIso = testTimestampToIso
        )

        assertTrue(gpx.contains("lat=\"-33.8688197\""))
        assertTrue(gpx.contains("lon=\"151.2092955\""))
    }

    @Test
    fun `serializeTrack name appears in both metadata and trk`() {
        val gpx = GpxSerializer.serializeTrack(
            name = "Dual Name",
            trackPoints = emptyList(),
            timestampToIso = testTimestampToIso
        )

        val nameCount = "<name>Dual Name</name>".toRegex().findAll(gpx).count()
        assertEquals(2, nameCount)
    }

    // ─── serializeRoute ─────────────────────────────────────────────────

    @Test
    fun `serializeRoute produces valid GPX 1_1 structure`() {
        val coords = listOf(
            Coordinate(47.0, 11.0),
            Coordinate(47.1, 11.1)
        )

        val gpx = GpxSerializer.serializeRoute(
            name = "Planned Route",
            coordinates = coords
        )

        assertTrue(gpx.startsWith("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        assertTrue(gpx.contains("version=\"1.1\""))
        assertTrue(gpx.contains("creator=\"OpenHiker\""))
        assertTrue(gpx.endsWith("</gpx>"))
    }

    @Test
    fun `serializeRoute produces rte with rtept`() {
        val coords = listOf(Coordinate(47.0, 11.0))

        val gpx = GpxSerializer.serializeRoute(
            name = "Test",
            coordinates = coords
        )

        assertTrue(gpx.contains("<rte>"))
        assertTrue(gpx.contains("<rtept"))
        assertTrue(gpx.contains("</rtept>"))
        assertTrue(gpx.contains("</rte>"))
    }

    @Test
    fun `serializeRoute includes metadata with name`() {
        val gpx = GpxSerializer.serializeRoute(
            name = "Route Alpha",
            coordinates = emptyList()
        )

        assertTrue(gpx.contains("<metadata>"))
        assertTrue(gpx.contains("<name>Route Alpha</name>"))
    }

    @Test
    fun `serializeRoute includes description when provided`() {
        val gpx = GpxSerializer.serializeRoute(
            name = "Test",
            description = "Via mountain pass",
            coordinates = emptyList()
        )

        assertTrue(gpx.contains("<desc>Via mountain pass</desc>"))
    }

    @Test
    fun `serializeRoute omits description when empty`() {
        val gpx = GpxSerializer.serializeRoute(
            name = "Test",
            coordinates = emptyList()
        )

        assertFalse(gpx.contains("<desc>"))
    }

    @Test
    fun `serializeRoute formats rtept with lat and lon`() {
        val coords = listOf(Coordinate(47.2654321, 11.3935678))

        val gpx = GpxSerializer.serializeRoute(
            name = "Test",
            coordinates = coords
        )

        assertTrue(gpx.contains("lat=\"47.2654321\""))
        assertTrue(gpx.contains("lon=\"11.3935678\""))
    }

    @Test
    fun `serializeRoute includes elevation when profile provided`() {
        val coords = listOf(
            Coordinate(47.0, 11.0),
            Coordinate(47.0001, 11.0001)
        )
        val profile = listOf(
            ElevationPoint(0.0, 800.0),
            ElevationPoint(100.0, 850.0),
            ElevationPoint(1000.0, 900.0)
        )

        val gpx = GpxSerializer.serializeRoute(
            name = "With Elevation",
            coordinates = coords,
            elevationProfile = profile
        )

        assertTrue(gpx.contains("<ele>"))
    }

    @Test
    fun `serializeRoute omits elevation when no profile`() {
        val coords = listOf(Coordinate(47.0, 11.0))

        val gpx = GpxSerializer.serializeRoute(
            name = "No Elevation",
            coordinates = coords,
            elevationProfile = null
        )

        assertFalse(gpx.contains("<ele>"))
    }

    @Test
    fun `serializeRoute handles empty coordinates`() {
        val gpx = GpxSerializer.serializeRoute(
            name = "Empty",
            coordinates = emptyList()
        )

        assertTrue(gpx.contains("<rte>"))
        assertTrue(gpx.contains("</rte>"))
        assertFalse(gpx.contains("<rtept"))
    }

    @Test
    fun `serializeRoute handles multiple coordinates`() {
        val coords = listOf(
            Coordinate(47.0, 11.0),
            Coordinate(47.1, 11.1),
            Coordinate(47.2, 11.2),
            Coordinate(47.3, 11.3)
        )

        val gpx = GpxSerializer.serializeRoute(
            name = "Multi",
            coordinates = coords
        )

        val rteptCount = "<rtept ".toRegex().findAll(gpx).count()
        assertEquals(4, rteptCount)
    }

    @Test
    fun `serializeRoute escapes special characters in name`() {
        val gpx = GpxSerializer.serializeRoute(
            name = "A & B \"route\"",
            coordinates = emptyList()
        )

        assertTrue(gpx.contains("A &amp; B &quot;route&quot;"))
    }

    @Test
    fun `serializeRoute first point elevation is at distance zero`() {
        val coords = listOf(Coordinate(47.0, 11.0))
        val profile = listOf(
            ElevationPoint(0.0, 1500.0),
            ElevationPoint(1000.0, 1600.0)
        )

        val gpx = GpxSerializer.serializeRoute(
            name = "Start Elevation",
            coordinates = coords,
            elevationProfile = profile
        )

        assertTrue(gpx.contains("<ele>1500.0</ele>"))
    }

    @Test
    fun `serializeRoute name appears in both metadata and rte`() {
        val gpx = GpxSerializer.serializeRoute(
            name = "Dual",
            coordinates = emptyList()
        )

        val nameCount = "<name>Dual</name>".toRegex().findAll(gpx).count()
        assertEquals(2, nameCount)
    }

    // ─── GPX schema location ────────────────────────────────────────────

    @Test
    fun `both serializers include GPX schema location`() {
        val trackGpx = GpxSerializer.serializeTrack(
            name = "T",
            trackPoints = emptyList(),
            timestampToIso = testTimestampToIso
        )
        val routeGpx = GpxSerializer.serializeRoute(
            name = "R",
            coordinates = emptyList()
        )

        val schemaUrl = "http://www.topografix.com/GPX/1/1/gpx.xsd"
        assertTrue(trackGpx.contains(schemaUrl))
        assertTrue(routeGpx.contains(schemaUrl))
    }
}
