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

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Unit tests for [SyncManifest] serialization and tombstone management. */
class SyncManifestTest {

    private val json = Json { prettyPrint = false }

    @Test
    fun `serialization roundtrip preserves data`() {
        val manifest = SyncManifest(
            version = 1,
            lastSyncTimestamp = 1700000000000L,
            tombstones = listOf(
                Tombstone("abc-123", 1700000000000L),
                Tombstone("def-456", 1699999000000L)
            )
        )

        val jsonStr = json.encodeToString(manifest)
        val decoded = json.decodeFromString<SyncManifest>(jsonStr)

        assertEquals(manifest, decoded)
    }

    @Test
    fun `empty manifest serializes correctly`() {
        val manifest = SyncManifest()
        val jsonStr = json.encodeToString(manifest)
        val decoded = json.decodeFromString<SyncManifest>(jsonStr)

        assertEquals(1, decoded.version)
        assertEquals(0L, decoded.lastSyncTimestamp)
        assertTrue(decoded.tombstones.isEmpty())
    }

    @Test
    fun `pruneExpiredTombstones removes old tombstones`() {
        val now = 1700000000000L
        val thirtyOneDaysAgo = now - (31L * 24 * 60 * 60 * 1000)
        val oneDayAgo = now - (1L * 24 * 60 * 60 * 1000)

        val manifest = SyncManifest(
            tombstones = listOf(
                Tombstone("old", thirtyOneDaysAgo),
                Tombstone("recent", oneDayAgo)
            )
        )

        val pruned = manifest.pruneExpiredTombstones(now)

        assertEquals(1, pruned.tombstones.size)
        assertEquals("recent", pruned.tombstones[0].uuid)
    }

    @Test
    fun `pruneExpiredTombstones keeps all if none expired`() {
        val now = 1700000000000L
        val manifest = SyncManifest(
            tombstones = listOf(
                Tombstone("a", now - 1000),
                Tombstone("b", now - 2000)
            )
        )

        val pruned = manifest.pruneExpiredTombstones(now)
        assertEquals(2, pruned.tombstones.size)
    }

    @Test
    fun `tombstone expiry is 30 days in milliseconds`() {
        val thirtyDaysMs = 30L * 24 * 60 * 60 * 1000
        assertEquals(thirtyDaysMs, SyncManifest.TOMBSTONE_EXPIRY_MILLIS)
    }
}
