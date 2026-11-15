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

package com.openhiker.core.elevation

import com.openhiker.core.compression.TrackPoint
import com.openhiker.core.geo.Haversine
import com.openhiker.core.model.Coordinate
import com.openhiker.core.model.ElevationPoint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ElevationProfileTest {

    // ── Profile generation ───────────────────────────────────────────

    @Test
    fun `generate returns empty list for empty coordinates`() {
        val result = ElevationProfile.generate(emptyList()) { _, _ -> 100.0 }
        assertTrue(result.isEmpty())
    }

    @Test
    fun `generate returns single point for single coordinate`() {
        val coords = listOf(Coordinate(47.0, 11.0))
        val result = ElevationProfile.generate(coords) { _, _ -> 1000.0 }
        assertEquals(1, result.size)
        assertEquals(0.0, result[0].distance, 0.01)
        assertEquals(1000.0, result[0].elevation, 0.01)
    }

    @Test
    fun `generate computes cumulative distance`() {
        val coords = listOf(
            Coordinate(47.0, 11.0),
            Coordinate(47.001, 11.0), // ~111 metres north
            Coordinate(47.002, 11.0)  // ~222 metres from start
        )
        val result = ElevationProfile.generate(coords) { _, _ -> 500.0 }
        assertEquals(3, result.size)
        assertEquals(0.0, result[0].distance, 0.01)
        assertTrue(result[1].distance > 100.0) // ~111m
        assertTrue(result[2].distance > 200.0) // ~222m
        assertTrue(result[2].distance > result[1].distance)
    }

    @Test
    fun `generate skips points with null elevation`() {
        val coords = listOf(
            Coordinate(47.0, 11.0),
            Coordinate(47.001, 11.0),
            Coordinate(47.002, 11.0)
        )
        // Middle point returns null
        val result = ElevationProfile.generate(coords) { lat, _ ->
            if (lat > 47.0005 && lat < 47.0015) null else 500.0
        }
        assertEquals(2, result.size)
    }

    @Test
    fun `generate uses actual elevation lookup values`() {
        val coords = listOf(
            Coordinate(47.0, 11.0),
            Coordinate(47.001, 11.0)
        )
        val result = ElevationProfile.generate(coords) { lat, _ ->
            if (lat < 47.0005) 1000.0 else 1100.0
        }
        assertEquals(1000.0, result[0].elevation, 0.01)
        assertEquals(1100.0, result[1].elevation, 0.01)
    }

    // ── Gain/loss computation ────────────────────────────────────────

    @Test
    fun `computeGainLoss returns zeros for empty profile`() {
        val result = ElevationProfile.computeGainLoss(emptyList())
        assertEquals(0.0, result.gain, 0.01)
        assertEquals(0.0, result.loss, 0.01)
    }

    @Test
    fun `computeGainLoss returns zeros for single point`() {
        val profile = listOf(ElevationPoint(0.0, 1000.0))
        val result = ElevationProfile.computeGainLoss(profile)
        assertEquals(0.0, result.gain, 0.01)
        assertEquals(0.0, result.loss, 0.01)
    }

    @Test
    fun `computeGainLoss computes uphill gain`() {
        val profile = listOf(
            ElevationPoint(0.0, 1000.0),
            ElevationPoint(100.0, 1050.0),
            ElevationPoint(200.0, 1100.0)
        )
        val result = ElevationProfile.computeGainLoss(profile)
        assertEquals(100.0, result.gain, 0.01)
        assertEquals(0.0, result.loss, 0.01)
    }

    @Test
    fun `computeGainLoss computes downhill loss`() {
        val profile = listOf(
            ElevationPoint(0.0, 1100.0),
            ElevationPoint(100.0, 1050.0),
            ElevationPoint(200.0, 1000.0)
        )
        val result = ElevationProfile.computeGainLoss(profile)
        assertEquals(0.0, result.gain, 0.01)
        assertEquals(100.0, result.loss, 0.01)
    }

    @Test
    fun `computeGainLoss handles mixed elevation changes`() {
        val profile = listOf(
            ElevationPoint(0.0, 1000.0),
            ElevationPoint(100.0, 1050.0),  // +50
            ElevationPoint(200.0, 1020.0),  // -30 (above threshold)
            ElevationPoint(300.0, 1080.0)   // +60
        )
        val result = ElevationProfile.computeGainLoss(profile)
        assertTrue(result.gain > 0)
        assertTrue(result.loss > 0)
    }

    @Test
    fun `computeGainLoss filters noise below threshold`() {
        val profile = listOf(
            ElevationPoint(0.0, 1000.0),
            ElevationPoint(50.0, 1001.0),   // +1m (noise, below 3m threshold)
            ElevationPoint(100.0, 1000.5),  // -0.5m (noise)
            ElevationPoint(150.0, 1002.0)   // +1m (noise)
        )
        val result = ElevationProfile.computeGainLoss(profile)
        assertEquals(0.0, result.gain, 0.01)
        assertEquals(0.0, result.loss, 0.01)
    }

    @Test
    fun `computeGainLoss accumulates gain above threshold`() {
        val profile = listOf(
            ElevationPoint(0.0, 1000.0),
            ElevationPoint(100.0, 1010.0),  // +10m (above 3m threshold)
            ElevationPoint(200.0, 1020.0)   // +10m
        )
        val result = ElevationProfile.computeGainLoss(profile)
        assertEquals(20.0, result.gain, 0.01)
        assertEquals(0.0, result.loss, 0.01)
    }

    @Test
    fun `computeGainLoss respects custom noise threshold`() {
        val profile = listOf(
            ElevationPoint(0.0, 1000.0),
            ElevationPoint(100.0, 1005.0)  // +5m
        )
        // With threshold=10, this should be filtered
        val result = ElevationProfile.computeGainLoss(profile, noiseThreshold = 10.0)
        assertEquals(0.0, result.gain, 0.01)
    }

    // ── Elevation at distance ────────────────────────────────────────

    @Test
    fun `elevationAtDistance returns null for empty profile`() {
        assertNull(ElevationProfile.elevationAtDistance(emptyList(), 100.0))
    }

    @Test
    fun `elevationAtDistance returns first elevation before start`() {
        val profile = listOf(
            ElevationPoint(100.0, 1000.0),
            ElevationPoint(200.0, 1100.0)
        )
        assertEquals(1000.0, ElevationProfile.elevationAtDistance(profile, 50.0)!!, 0.01)
    }

    @Test
    fun `elevationAtDistance returns last elevation after end`() {
        val profile = listOf(
            ElevationPoint(100.0, 1000.0),
            ElevationPoint(200.0, 1100.0)
        )
        assertEquals(1100.0, ElevationProfile.elevationAtDistance(profile, 300.0)!!, 0.01)
    }

    @Test
    fun `elevationAtDistance interpolates between points`() {
        val profile = listOf(
            ElevationPoint(0.0, 1000.0),
            ElevationPoint(100.0, 1100.0)
        )
        // At 50m, should be 1050m (linear interpolation)
        assertEquals(1050.0, ElevationProfile.elevationAtDistance(profile, 50.0)!!, 0.01)
    }

    @Test
    fun `elevationAtDistance interpolates in multi-segment profile`() {
        val profile = listOf(
            ElevationPoint(0.0, 1000.0),
            ElevationPoint(100.0, 1100.0),
            ElevationPoint(200.0, 1200.0),
            ElevationPoint(300.0, 1000.0)
        )
        // At 250m: between 1200 and 1000, so 1100
        assertEquals(1100.0, ElevationProfile.elevationAtDistance(profile, 250.0)!!, 0.01)
    }

    @Test
    fun `elevationAtDistance returns exact value at profile point`() {
        val profile = listOf(
            ElevationPoint(0.0, 1000.0),
            ElevationPoint(100.0, 1100.0),
            ElevationPoint(200.0, 1200.0)
        )
        assertEquals(1100.0, ElevationProfile.elevationAtDistance(profile, 100.0)!!, 0.01)
    }

    // ── Incremental accumulator ──────────────────────────────────────

    @Test
    fun `accumulator first sample only sets the reference`() {
        val acc = ElevationAccumulator().add(1000.0)
        assertEquals(0.0, acc.gain, 0.0)
        assertEquals(0.0, acc.loss, 0.0)
        assertEquals(1000.0, acc.lastSignificantElevation!!, 0.0)
    }

    @Test
    fun `accumulator ignores a change just below the threshold`() {
        val acc = ElevationAccumulator().add(1000.0).add(1002.99)
        assertEquals(0.0, acc.gain, 0.0)
        assertEquals(1000.0, acc.lastSignificantElevation!!, 0.0)
    }

    @Test
    fun `accumulator counts a change of exactly the threshold`() {
        val acc = ElevationAccumulator().add(1000.0).add(1003.0)
        assertEquals(3.0, acc.gain, 1e-9)
        assertEquals(1003.0, acc.lastSignificantElevation!!, 0.0)
    }

    @Test
    fun `accumulator adds up slow drift once it crosses the threshold`() {
        // Each 1 m step is noise, but the total from the reference reaches 3 m.
        val acc = listOf(1000.0, 1001.0, 1002.0, 1003.0)
            .fold(ElevationAccumulator()) { a, alt -> a.add(alt) }
        assertEquals(3.0, acc.gain, 1e-9)
    }

    @Test
    fun `accumulator does not count GPS jitter around one altitude`() {
        val acc = listOf(1000.0, 1002.0, 998.0, 1002.5, 997.5, 1000.0)
            .fold(ElevationAccumulator()) { a, alt -> a.add(alt) }
        assertEquals(0.0, acc.gain, 0.0)
        assertEquals(0.0, acc.loss, 0.0)
    }

    @Test
    fun `accumulator tracks gain and loss separately as positive values`() {
        val acc = ElevationAccumulator().add(1000.0).add(1050.0).add(1020.0)
        assertEquals(50.0, acc.gain, 1e-9)
        assertEquals(30.0, acc.loss, 1e-9)
    }

    @Test
    fun `accumulator matches computeGainLoss on the same samples`() {
        val altitudes = listOf(500.0, 502.0, 507.0, 505.0, 499.0, 520.0, 518.0)
        val incremental = altitudes.fold(ElevationAccumulator()) { a, alt -> a.add(alt) }
        val batch = ElevationProfile.computeGainLoss(
            altitudes.mapIndexed { i, alt -> ElevationPoint(i * 10.0, alt) }
        )
        assertEquals(batch.gain, incremental.gain, 1e-9)
        assertEquals(batch.loss, incremental.loss, 1e-9)
    }

    // ── Profile from recorded track ──────────────────────────────────

    @Test
    fun `fromTrackPoints returns empty list for no points`() {
        assertTrue(ElevationProfile.fromTrackPoints(emptyList()).isEmpty())
    }

    @Test
    fun `fromTrackPoints keeps altitudes and accumulates distance`() {
        val points = listOf(
            TrackPoint(47.0, 11.0, 1000.0, 0.0),
            TrackPoint(47.001, 11.0, 1010.0, 10.0),
            TrackPoint(47.002, 11.0, 1005.0, 20.0)
        )
        val profile = ElevationProfile.fromTrackPoints(points)
        assertEquals(3, profile.size)
        assertEquals(0.0, profile[0].distance, 0.0)
        val leg = Haversine.distance(47.0, 11.0, 47.001, 11.0)
        assertEquals(leg, profile[1].distance, 1e-6)
        assertEquals(
            leg + Haversine.distance(47.001, 11.0, 47.002, 11.0),
            profile[2].distance,
            1e-6
        )
        assertEquals(listOf(1000.0, 1010.0, 1005.0), profile.map { it.elevation })
    }

    @Test
    fun `fromTrackPoints adds no distance for a stationary point`() {
        val points = listOf(
            TrackPoint(47.0, 11.0, 1000.0, 0.0),
            TrackPoint(47.0, 11.0, 1001.0, 5.0)
        )
        val profile = ElevationProfile.fromTrackPoints(points)
        assertEquals(0.0, profile[1].distance, 1e-9)
    }

    // ── Constants ────────────────────────────────────────────────────

    @Test
    fun `noise filter threshold is 3 metres`() {
        assertEquals(3.0, ElevationProfile.NOISE_FILTER_METRES, 0.01)
    }
}
