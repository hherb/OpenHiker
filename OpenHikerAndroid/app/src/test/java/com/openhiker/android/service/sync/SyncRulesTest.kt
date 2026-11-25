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
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
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

    // ── cloudEntityAction ────────────────────────────────────────

    @Test
    fun `an unreadable local file is never overwritten by the cloud copy`() {
        assertEquals(SyncAction.NONE, cloudEntityAction(null, false, true, "2026-11-25T00:00:00Z"))
    }

    @Test
    fun `a cloud-only entity is downloaded and one in both places is reconciled`() {
        val t0 = "2026-11-25T00:00:00Z"
        val later = "2026-11-25T01:00:00Z"
        assertEquals(SyncAction.DOWNLOAD, cloudEntityAction(null, false, false, t0))
        assertEquals(SyncAction.UPLOAD, cloudEntityAction(later, true, false, t0))
        assertEquals(SyncAction.DOWNLOAD, cloudEntityAction(t0, true, false, later))
    }

    // ── reconcile ────────────────────────────────────────────────

    private val later = "2026-11-15T10:00:01Z"
    private val earlier = "2026-11-15T09:59:59Z"

    @Test
    fun `the strictly newer copy wins in either direction`() {
        assertEquals(SyncAction.UPLOAD, reconcile(later, t0))
        assertEquals(SyncAction.DOWNLOAD, reconcile(earlier, t0))
        assertEquals(SyncAction.NONE, reconcile(t0, t0))
    }

    @Test
    fun `an old local copy never overwrites a newer cloud copy`() {
        // The device's last sync is irrelevant: only the two copies' times decide.
        assertEquals(SyncAction.DOWNLOAD, reconcile(t0, later))
    }

    @Test
    fun `a copy with a time beats one without`() {
        assertEquals(SyncAction.DOWNLOAD, reconcile(null, t0))
        assertEquals(SyncAction.UPLOAD, reconcile(t0, null))
        assertEquals(SyncAction.NONE, reconcile(null, null))
    }

    @Test
    fun `compares times as instants, not text`() {
        // As text, "…00.500Z" sorts before "…00Z"; as instants it is half a second later.
        assertEquals(SyncAction.DOWNLOAD, reconcile(t0, "2026-11-15T10:00:00.500Z"))
        assertEquals(SyncAction.NONE, reconcile(t0, "2026-11-15T10:00:00.000Z"))
    }

    @Test
    fun `unparseable times fall back to text comparison`() {
        assertEquals(SyncAction.UPLOAD, reconcile("b", "a"))
        // One unparseable time is enough to compare as text: "n" sorts after "2".
        assertEquals(SyncAction.UPLOAD, reconcile("not-a-time", t0))
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

    // ── isTransient ─────────────────────────────────────────────

    /** The exception kotlinx.serialization throws for a file that does not parse. */
    private fun parseError(): Throwable =
        runCatching { Json.parseToJsonElement("{ not json") }.exceptionOrNull()!!

    @Test
    fun `an IO failure is transient`() {
        assertTrue(isTransient(IOException("provider offline")))
    }

    @Test
    fun `a file that does not parse is not transient`() {
        assertFalse(isTransient(parseError()))
    }

    @Test
    fun `an IO failure caused by a parse error is not transient`() {
        // readManifest wraps the parse error this way.
        assertFalse(isTransient(IOException("Cannot read manifest.json", parseError())))
    }

    @Test
    fun `an IO failure wrapping another IO failure is transient`() {
        // readManifest also wraps a provider that is offline.
        assertTrue(isTransient(IOException("Cannot read manifest.json", IOException("offline"))))
    }

    @Test
    fun `other exceptions are not transient`() {
        assertFalse(isTransient(IllegalStateException("database closed")))
    }

    // ── folderErrorResult ───────────────────────────────────────

    @Test
    fun `a revoked permission reports the folder unavailable and is not retried`() {
        val result = folderErrorResult(hasPermission = false)
        assertEquals(listOf(CloudDriveSyncEngine.FOLDER_UNAVAILABLE), result.errors)
        assertFalse(result.retryable)
    }

    @Test
    fun `a missing folder with the permission held is unreachable and is not retried`() {
        val result = folderErrorResult(hasPermission = true)
        assertEquals(listOf(CloudDriveSyncEngine.FOLDER_UNREACHABLE), result.errors)
        assertFalse(result.retryable)
    }
}
