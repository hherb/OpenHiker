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

package com.openhiker.android.service.sync

import com.openhiker.android.data.db.routes.SavedRouteEntity
import com.openhiker.android.data.db.waypoints.WaypointEntity
import com.openhiker.core.model.WaypointCategory
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Unit tests for the cloud sync records and their entity mappers. */
class SyncRecordsTest {

    private val route = SavedRouteEntity(
        id = "r1", name = "Ridge", startLatitude = 47.1, startLongitude = 11.1,
        endLatitude = 47.2, endLongitude = 11.2, startTime = "2026-11-15T08:00:00Z",
        endTime = "2026-11-15T12:00:00Z", totalDistance = 12_345.6, elevationGain = 800.0,
        elevationLoss = 790.0, walkingTime = 12_000.0, restingTime = 2_400.0,
        averageHeartRate = 120.0, maxHeartRate = null, estimatedCalories = 950.0,
        comment = "windy", regionId = "reg", trackData = byteArrayOf(0, 1, -1, 127, -128),
        modifiedAt = "2026-11-15T12:05:00Z"
    )

    private val waypoint = WaypointEntity(
        id = "w1", latitude = 47.3, longitude = 11.3, altitude = 1_820.0,
        timestamp = "2026-11-15T09:00:00Z", label = "Spring", category = "waterSource",
        note = "cold", hasPhoto = true, hikeId = "r1", photo = byteArrayOf(9, 8, 7),
        thumbnail = byteArrayOf(1), modifiedAt = "2026-11-15T09:01:00Z"
    )

    // Entities compare by id only, so the tests compare the core models plus the BLOBs.

    @Test
    fun `saved route survives a JSON round trip`() {
        val text = Json.encodeToString(route.toSyncRecord())
        val back = Json.decodeFromString<SavedRouteRecord>(text).toEntity()
        assertEquals(route.toSyncRecord().route, back.toSyncRecord().route)
        assertArrayEquals(route.trackData, back.trackData)
    }

    @Test
    fun `waypoint survives a JSON round trip with photo and thumbnail`() {
        val text = Json.encodeToString(waypoint.toSyncRecord())
        val back = Json.decodeFromString<WaypointRecord>(text).toEntity()
        assertEquals(waypoint.toSyncRecord().waypoint, back.toSyncRecord().waypoint)
        assertArrayEquals(waypoint.photo, back.photo)
        assertArrayEquals(waypoint.thumbnail, back.thumbnail)
    }

    @Test
    fun `waypoint category is written as the shared raw value`() {
        val text = Json.encodeToString(waypoint.toSyncRecord())
        assertTrue(text, "\"category\":\"waterSource\"" in text)
    }

    @Test
    fun `legacy enum-name category maps to the raw value`() {
        val legacy = waypoint.copy(category = "TRAIL_MARKER")
        assertEquals(WaypointCategory.TRAIL_MARKER, legacy.toSyncRecord().waypoint.category)
        assertEquals("trailMarker", legacy.toSyncRecord().toEntity().category)
    }

    @Test
    fun `unknown category falls back to custom`() {
        val odd = waypoint.copy(category = "not_a_category")
        assertEquals(WaypointCategory.CUSTOM, odd.toSyncRecord().waypoint.category)
    }

    @Test
    fun `waypoint without photo has null blobs both ways`() {
        val plain = waypoint.copy(hasPhoto = false, photo = null, thumbnail = null)
        val record = plain.toSyncRecord()
        assertNull(record.photo)
        assertNull(record.thumbnail)
        assertNull(record.toEntity().photo)
        assertNull(record.toEntity().thumbnail)
    }
}
