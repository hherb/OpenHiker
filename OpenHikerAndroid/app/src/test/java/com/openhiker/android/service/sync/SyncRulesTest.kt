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

import com.openhiker.core.formats.Tombstone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** Unit tests for the pure sync decisions in `SyncRules.kt`. */
class SyncRulesTest {

    private val t0 = "2026-11-15T10:00:00Z"
    private val t0Millis = Instant.parse(t0).toEpochMilli()

    // ── shouldUpload ─────────────────────────────────────────────

    @Test
    fun `first sync uploads everything`() {
        assertTrue(shouldUpload(t0, 0L))
    }

    @Test
    fun `uploads only entities changed after the last sync`() {
        assertTrue(shouldUpload(t0, t0Millis - 1))
        assertFalse(shouldUpload(t0, t0Millis))
        assertFalse(shouldUpload(t0, t0Millis + 1))
    }

    @Test
    fun `missing or unparseable change time uploads`() {
        assertTrue(shouldUpload(null, t0Millis))
        assertTrue(shouldUpload("yesterday", t0Millis))
    }

    // ── shouldDownload ───────────────────────────────────────────

    @Test
    fun `downloads when there is no local copy or it has no time`() {
        assertTrue(shouldDownload(null, null, existsLocally = false))
        assertTrue(shouldDownload(t0, null, existsLocally = true))
    }

    @Test
    fun `does not download a cloud copy without a time over a timed local copy`() {
        assertFalse(shouldDownload(null, t0, existsLocally = true))
    }

    @Test
    fun `downloads only a strictly newer cloud copy`() {
        assertTrue(shouldDownload("2026-11-15T10:00:01Z", t0, existsLocally = true))
        assertFalse(shouldDownload(t0, t0, existsLocally = true))
        assertFalse(shouldDownload("2026-11-15T09:59:59Z", t0, existsLocally = true))
    }

    @Test
    fun `compares times as instants, not text`() {
        // As text, "…00.500Z" sorts before "…00Z"; as instants it is half a second later.
        assertTrue(shouldDownload("2026-11-15T10:00:00.500Z", t0, existsLocally = true))
        assertFalse(shouldDownload("2026-11-15T10:00:00.000Z", t0, existsLocally = true))
    }

    // ── mergeTombstones ──────────────────────────────────────────

    @Test
    fun `merge keeps one tombstone per uuid with the earliest time`() {
        val merged = mergeTombstones(
            manifest = listOf(Tombstone("a", 200), Tombstone("b", 100)),
            pending = listOf(Tombstone("a", 150), Tombstone("c", 300))
        )
        assertEquals(
            setOf(Tombstone("a", 150), Tombstone("b", 100), Tombstone("c", 300)),
            merged.toSet()
        )
        assertEquals(3, merged.size)
    }

    @Test
    fun `merge of empty lists is empty`() {
        assertEquals(emptyList<Tombstone>(), mergeTombstones(emptyList(), emptyList()))
    }
}
